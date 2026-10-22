defmodule Psc.Agent.Turn do
  @moduledoc """
  One turn of a conversation.

  A turn starts a throwaway `Jido.AgentServer`, runs a single read-only ReAct
  loop, streams its events onto PubSub and writes the result to the message row
  it was given. It never outlives the turn: the server is linked to this process
  and stops with it, so a deploy mid-conversation loses at most the turn in
  flight - which `Psc.Agent.cancel_stale_streaming/1` then marks cancelled.

  Jido's `ask_stream/3` takes a string or content parts, and an ephemeral agent
  has no thread to seed, so the transcript is rendered into the prompt. The
  rendering is deterministic and append-only: the same conversation always
  produces the same prefix, which is what keeps the provider's prompt cache warm.

  ## The script seam

  `run/4` accepts `script: [...]` - a list of steps a test replays instead of
  calling a model. It exercises the parts this module owns (broadcasting,
  accumulating tool calls, persisting, failing) without a network round trip.
  The real Jido path stays the default.
  """

  require Logger

  alias Psc.Agent
  alias Psc.Agent.CanvasAgent

  @topic_prefix "agent_session:"
  @timeout 90_000
  @stream_timeout_ms 45_000

  @doc "The PubSub topic carrying this session's turn events."
  def topic(session_id), do: @topic_prefix <> session_id

  @doc "Runs a turn in a supervised task."
  def start(session, message, scope) do
    Task.Supervisor.start_child(Psc.Agent.TurnSupervisor, fn -> run(session, message, scope) end)
  end

  @doc """
  Runs a turn in the calling process.

  Options:

    * `:script` - a list of steps to replay instead of calling a model. Test-only.
  """
  def run(session, message, scope, opts \\ []) do
    topic = topic(session.id)

    try do
      case Keyword.get(opts, :script) do
        nil -> run_agent(session, message, scope, topic)
        script -> replay(script, message, topic)
      end
    rescue
      error ->
        Logger.error("agent turn crashed: " <> Exception.format(:error, error, __STACKTRACE__))
        fail(message, topic, "The agent hit an unexpected error: #{Exception.message(error)}")
    catch
      kind, reason ->
        Logger.error("agent turn exited: #{inspect({kind, reason})}")
        fail(message, topic, "The agent stopped unexpectedly: #{inspect(reason)}")
    end
  end

  ## The real path

  defp run_agent(session, message, scope, topic) do
    prompt = render_prompt(session)

    # The agent server is linked to this process, so a crash inside the ReAct
    # runtime would kill the turn before it could persist a failure - leaving a
    # message stuck in `:streaming` and the user staring at an empty bubble.
    # Trapping exits turns that into a normal error message.
    previous = Process.flag(:trap_exit, true)

    try do
      case start_agent() do
        {:ok, pid} ->
          try do
            execute(pid, prompt, message, topic, scope)
          after
            stop_agent(pid)
          end

        {:error, reason} ->
          fail(message, topic, "The agent could not start: #{inspect(reason)}")
      end
    after
      Process.flag(:trap_exit, previous)
    end
  end

  defp execute(pid, prompt, message, topic, scope) do
    request =
      [
        tool_context: %{scope: scope, model: Agent.model_for(scope.user)},
        request_transformer: Psc.Agent.UserModel,
        # A provider that accepts the request and then goes quiet would hold the
        # turn (and the "streaming" bubble) far too long. Bound it.
        stream_timeout_ms: @stream_timeout_ms
      ] ++ api_key_opts(scope)

    case CanvasAgent.ask_stream(pid, prompt, request) do
      {:ok, %{request: request, events: events}} ->
        trace = consume(events, topic, message)
        await(request, message, topic, trace)

      {:error, reason} ->
        fail(message, topic, "The agent refused the request: #{inspect(reason)}")
    end
  rescue
    error ->
      Logger.error("agent turn crashed: " <> Exception.format(:error, error, __STACKTRACE__))
      fail(message, topic, "The agent hit an unexpected error.")
  end

  # Streaming the events is best-effort: a broken subscriber must never take the
  # turn down, and the persisted message is the source of truth either way.
  defp consume(events, topic, message) do
    Enum.reduce(events, %{tool_calls: []}, fn event, trace ->
      case event.kind do
        :request_started ->
          status(topic, message, "starting…")
          trace

        :llm_started ->
          status(topic, message, "waiting for the model…")
          trace

        :llm_completed ->
          status(topic, message, "model answered, finishing…")
          trace

        :llm_delta ->
          case delta_text(event) do
            "" ->
              trace

            text ->
              broadcast(topic, {:delta, message.id, text})
              trace
          end

        :tool_started ->
          call = %{
            "name" => to_string(event.tool_name || "tool"),
            "arguments" => safe(field(event, :arguments) || %{}),
            "status" => "running"
          }

          status(topic, message, "running #{call["name"]}…")
          broadcast(topic, {:tool_started, message.id, call})
          Map.update!(trace, :tool_calls, &(&1 ++ [call]))

        :tool_completed ->
          result = %{
            "status" => tool_status(event),
            "result" => unwrap(field(event, :result)),
            "duration_ms" => safe(field(event, :duration_ms))
          }

          broadcast(
            topic,
            {:tool_finished, message.id,
             Map.merge(%{"name" => to_string(event.tool_name)}, result)}
          )

          Map.update!(trace, :tool_calls, &update_last(&1, result))

        _other ->
          trace
      end
    end)
  end

  defp await(request, message, topic, trace) do
    case CanvasAgent.await(request, timeout: @timeout) do
      {:ok, result} ->
        complete(message, topic, answer_text(result), trace.tool_calls, usage(result))

      {:error, reason} ->
        fail(message, topic, "The model did not finish: #{inspect(reason)}")
    end
  end

  defp start_agent do
    # `register_global: false`: an ephemeral turn is never looked up by name, so
    # it does not need a registry entry. The instance still supplies the
    # supervisor the ReAct runtime spawns its worker under.
    Jido.AgentServer.start_link(
      agent: CanvasAgent,
      jido: Psc.Agent.Jido,
      register_global: false
    )
  end

  # Users bring their own provider key (settings). Without one the tab is gated
  # off, so this list is normally the key; the deployment key remains the
  # fallback for MCP clients acting through a configured account.
  # The key travels as `api_key` in the per-request generation options.
  #
  # Known limitation, found by a live run: Jido's ReAct runtime injects a
  # `provider_options[:previous_response_id]` into every streaming request, and
  # ReqLLM validates that map against the provider's schema. OpenRouter rejects
  # the unknown key ("unknown options [:previous_response_id]"), so OpenRouter
  # models that ReqLLM resolves through a strict schema fail to build a request.
  # OpenAI accepts the option. The workaround is a provider whose schema allows
  # it, or an upstream fix.
  defp api_key_opts(scope) do
    with %{user: %Psc.Accounts.User{} = user} <- scope,
         key when is_binary(key) <- Agent.api_key(user) do
      [llm_opts: [api_key: key]]
    else
      _other -> []
    end
  end

  defp stop_agent(pid) do
    if Process.alive?(pid), do: GenServer.stop(pid, :normal, 5_000)
  catch
    _kind, _reason -> :ok
  end

  ## The script path

  # Steps:
  #   {:delta, text}                   - a streamed token chunk
  #   {:tool, name, arguments, result} - a completed tool call
  #   {:answer, text}                  - the final answer
  #   {:error, reason}                 - a failed turn
  defp replay(steps, message, topic) do
    steps
    |> Enum.reduce_while(%{content: "", tool_calls: []}, fn step, acc ->
      case step do
        {:delta, text} ->
          broadcast(topic, {:delta, message.id, text})
          {:cont, %{acc | content: acc.content <> text}}

        {:tool, name, arguments, result} ->
          call = %{"name" => to_string(name), "arguments" => arguments, "status" => "running"}
          status(topic, message, "running #{call["name"]}…")
          broadcast(topic, {:tool_started, message.id, call})
          finished = %{"status" => "ok", "result" => result, "duration_ms" => 0}

          broadcast(
            topic,
            {:tool_finished, message.id, Map.merge(%{"name" => to_string(name)}, finished)}
          )

          {:cont, %{acc | tool_calls: acc.tool_calls ++ [Map.merge(call, finished)]}}

        {:answer, text} ->
          {:halt, %{acc | content: text}}

        {:error, reason} ->
          {:halt, {:error, reason}}

        _other ->
          {:cont, acc}
      end
    end)
    |> case do
      {:error, reason} -> fail(message, topic, to_string(reason))
      %{content: content, tool_calls: calls} -> complete(message, topic, content, calls, nil)
    end
  end

  ## Shared

  defp complete(message, topic, content, tool_calls, usage) do
    attrs = %{content: content, tool_calls: tool_calls, usage: usage}

    case update(Agent, :finish_message, message, attrs) do
      {:ok, message} ->
        broadcast(topic, {:completed, message.id, %{content: content}})
        {:ok, message}

      {:error, message} ->
        {:error, message}
    end
  end

  defp fail(message, topic, reason) do
    case update(Agent, :fail_message, message, reason) do
      {:ok, message} ->
        broadcast(topic, {:failed, message.id, reason})
        {:error, message}

      {:error, message} ->
        {:error, message}
    end
  end

  # A session can be deleted while its turn is still running. The row is gone by
  # the time the turn finishes, and that is a normal outcome, not a crash.
  defp update(module, fun, message, arg) do
    apply(module, fun, [message, arg])
  rescue
    Ecto.StaleEntryError ->
      Logger.debug("agent turn finished after its message was deleted")
      {:error, message}
  end

  # Progress for the UI: without it a quiet provider looks like a broken app.
  defp status(topic, message, phase) do
    Logger.debug("agent turn #{message.id}: #{phase}")
    broadcast(topic, {:status, message.id, phase})
  end

  defp broadcast(topic, event) do
    Phoenix.PubSub.broadcast(Psc.PubSub, topic, event)
    :ok
  end

  @doc """
  Renders the conversation so far into the prompt.

  Append-only and deterministic: earlier turns are rendered the same way every
  time, so the prefix stays byte-identical between turns and stays cacheable. The
  current message is the last line, unwrapped, so the model sees it as the thing
  to answer.
  """
  def render_prompt(session) do
    case Agent.history(session) do
      [] ->
        ""

      [only] ->
        with_canvas(session, String.trim(only.content))

      messages ->
        {prior, [current]} = Enum.split(messages, -1)

        # Keep this a plain transcript. An earlier version wrapped it in a
        # "<<<CONVERSATION" block with instructions and the ReAct runtime emitted
        # no events at all for it (turn two hung forever while turn one worked),
        # so the shape is deliberately boring.
        transcript =
          Enum.map_join(prior, "\n", fn message ->
            role = if message.role == :user, do: "User", else: "Assistant"

            "#{role}: #{message.content |> to_string() |> String.replace(~r/\s+/, " ") |> String.trim()}"
          end)

        with_canvas(session, transcript <> "\nUser: " <> String.trim(current.content))
    end
  end

  # Without this the model has no idea which canvas the tab is showing, and
  # asks the user for an id it already has. The header is derived from the
  # session's canvas and is stable per conversation, so it does not disturb the
  # cacheable prefix.
  defp with_canvas(%{canvas_id: nil}, text), do: text

  defp with_canvas(%{canvas_id: canvas_id}, text) do
    case Psc.Canvas.get_unstr_canvas(canvas_id) do
      nil ->
        text

      canvas ->
        "You are in the canvas #{inspect(canvas.name)} (id: #{canvas.id}). " <>
          "When the user says \"this canvas\", they mean that one.\n\n" <> text
    end
  end

  # Tool payloads come from Jido, not JSON: a result can hold tuples, structs or
  # atom keys. Everything persisted has to survive a JSON encode.
  defp safe(value)
       when is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value),
       do: value

  defp safe(%_{} = struct), do: inspect(struct)
  defp safe(%{} = map), do: Map.new(map, fn {key, value} -> {to_string(key), safe(value)} end)
  defp safe(list) when is_list(list), do: Enum.map(list, &safe/1)
  defp safe(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> safe()
  defp safe(other), do: inspect(other)

  # Jido hands the result over as `{:ok, value}` or `{:ok, value, extra}`. Left
  # as a tuple it becomes `[":ok", value, []]` in the transcript - which also
  # hides `refs` from the chip renderer, since it looks for a map.
  defp unwrap({:ok, value}), do: safe(value)
  defp unwrap({:ok, value, _extra}), do: safe(value)
  defp unwrap({:error, reason}), do: %{"error" => safe(reason)}
  defp unwrap(other), do: safe(other)

  defp field(event, key) do
    data = event.data || %{}
    Map.get(data, key) || Map.get(data, to_string(key))
  end

  defp delta_text(event) do
    data = event.data || %{}

    [data[:text], data["text"], data[:delta], data["delta"], data[:content], data["content"]]
    |> Enum.find("", &is_binary/1)
  end

  defp tool_status(event) do
    case event.data do
      %{status: status} when is_atom(status) -> Atom.to_string(status)
      %{"status" => status} when is_binary(status) -> status
      %{error: error} when not is_nil(error) -> "error"
      _other -> "ok"
    end
  end

  defp update_last([], _result), do: []
  defp update_last(calls, result), do: List.update_at(calls, -1, &Map.merge(&1, result))

  defp answer_text(text) when is_binary(text), do: text

  defp answer_text(%{} = result) do
    Enum.find_value([:result, :text, :answer, :content], "", fn key ->
      case Map.get(result, key) do
        value when is_binary(value) -> value
        _other -> nil
      end
    end)
  end

  defp answer_text(_other), do: ""

  defp usage(%{} = result) do
    case Map.get(result, :usage) || Map.get(result, "usage") do
      %{} = usage ->
        %{
          "input_tokens" => usage[:input_tokens] || usage["input_tokens"],
          "output_tokens" => usage[:output_tokens] || usage["output_tokens"],
          "cached_tokens" => usage[:cached_tokens] || usage["cached_tokens"]
        }

      _other ->
        nil
    end
  end

  defp usage(_other), do: nil
end
