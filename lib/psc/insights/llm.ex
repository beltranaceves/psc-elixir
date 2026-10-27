defmodule Psc.Insights.LLM do
  @moduledoc """
  Optional AI review of a canvas.

  This is a single, non-streaming completion through the user's own provider
  connection - not the ReAct loop in `Psc.Agent.Turn`, which exists for
  conversations with tools. The model is asked for one JSON object, every
  finding is validated against `Psc.Insights.Finding`, and anything that does
  not fit is dropped. Heuristic analysis never depends on this module.

  Tests replace the call with `config :psc, :insights_llm` (a function or an
  `{module, function}` pair); no test reaches the network.
  """

  alias Psc.Agent.Connection
  alias Psc.Agent.Connections
  alias Psc.Canvas.Structure
  alias Psc.Insights.{Cells, Finding}

  @timeout_ms 60_000
  @max_findings 8
  @max_cells 60
  @max_field_chars 800
  @max_prompt_chars 24_000
  @max_note_chars 2_000
  @max_notes_chars 8_000

  @doc "Whether the user has a provider connection the pass could use."
  def available?(user), do: Connections.enabled?(user)

  @doc "The connection the review would use, or nil."
  def connection(user) do
    case Connections.for_session(nil, user) do
      %Connection{} = connection -> connection
      _other -> nil
    end
  end

  @doc "A display label for the connection, e.g. \"Work · Anthropic · claude-haiku\"."
  def connection_label(%Connection{} = connection) do
    "#{connection.name} · #{Connection.provider_label(connection.provider)} · #{connection.model_id}"
  end

  def connection_label(_connection), do: nil

  @doc """
  Reviews the canvas and returns the AI findings plus the provider/model that
  produced them.
  """
  def review(context, user) do
    case connection(user) do
      nil ->
        {:error, :no_connection}

      connection ->
        with {:ok, text, provider, model} <- complete(prompt(context), connection),
             {:ok, findings} <- parse(text, attribution(connection, provider, model)) do
          valid = context.cells |> Structure.cell_keys() |> MapSet.new()

          findings =
            findings
            |> Enum.filter(fn finding ->
              Enum.all?(finding["cell_keys"], &MapSet.member?(valid, &1))
            end)
            |> Enum.take(@max_findings)

          Connections.mark_used(connection)
          {:ok, %{findings: findings, provider: provider, model: model}}
        end
    end
  end

  @doc "The prompt sent to the provider. Public so tests can assert its shape."
  def prompt(context) do
    cells =
      context
      |> Cells.cards()
      |> Enum.take(@max_cells)
      |> Enum.map_join("\n", fn card ->
        fields =
          card.fields
          |> Enum.map(fn field ->
            value = Cells.value(card.cell[field])

            "    #{Cells.field_label(card.cell, field)}: #{String.slice(value, 0, @max_field_chars)}"
          end)
          |> Enum.join("\n")

        "- [#{card.key}] #{card.label}\n#{fields}"
      end)
      |> String.slice(0, @max_prompt_chars)

    title = String.slice(context.name || "", 0, 200)
    description = String.slice(context.description || "", 0, 1_000)
    notes = notes_text(context.notes)

    """
    You are reviewing a structured visual canvas. Find content problems only;
    do not rewrite the canvas and do not comment on empty fields.

    Canvas title: #{title}
    Canvas description: #{description}

    Cells:
    #{cells}

    Notes (supplemental; may be empty):
    #{notes}

    Return only a JSON object with this shape:
    {"findings":[{"kind":"contradiction|relevance|coverage|duplicate","severity":"info|warning|critical","cell_keys":["cell_key"],"field":"field_name_or_null","title":"short title","detail":"one or two sentences","confidence":0.0}]}

    Rules:
    - Use only cell keys that appear above.
    - Report contradictions between cells, content that drifts from the canvas
      framing, coverage gaps, and duplicated statements.
    - Use the notes only as context; every finding must be about the cells.
    - At most #{@max_findings} findings.
    - If there is nothing worth reporting, return {"findings":[]}.
    """
  end

  defp notes_text([]), do: "(none)"

  defp notes_text(notes) do
    notes
    |> Enum.map_join("\n", fn note ->
      title = String.slice(note["title"] || "Untitled", 0, 120)
      content = String.slice(note["content"] || "", 0, @max_note_chars)
      "- #{title}\n  #{content}"
    end)
    |> String.slice(0, @max_notes_chars)
  end

  defp attribution(connection, provider, model) do
    %{
      "provider" => provider,
      "model" => model,
      "connection" => connection.name
    }
  end

  defp complete(prompt, %Connection{} = connection) do
    case Application.get_env(:psc, :insights_llm) do
      nil ->
        request(prompt, connection)

      fun when is_function(fun, 1) ->
        hook(fun.(prompt), connection)

      fun when is_function(fun, 2) ->
        hook(fun.(prompt, connection), connection)

      {module, function} ->
        hook(apply(module, function, [prompt, connection]), connection)

      other ->
        hook(other, connection)
    end
  end

  defp hook({:ok, text}, connection) when is_binary(text) do
    {:ok, text, connection.provider, connection.model_id}
  end

  defp hook({:ok, text, provider, model}, _connection) when is_binary(text) do
    {:ok, text, provider, model}
  end

  defp hook({:error, reason}, _connection), do: {:error, reason}
  defp hook(other, _connection), do: {:error, {:invalid_test_hook, other}}

  defp request(prompt, %Connection{} = connection) do
    base_url = connection.base_url || Connection.default_base_url(connection.provider)

    case Connection.adapter(connection.provider) do
      :anthropic ->
        connection
        |> request_anthropic(prompt, base_url)
        |> wrap(connection)

      :google ->
        connection
        |> request_google(prompt, base_url)
        |> wrap(connection)

      _openai ->
        connection
        |> request_openai(prompt, base_url)
        |> wrap(connection)
    end
  end

  defp request_openai(connection, prompt, base_url) do
    headers =
      if blank?(connection.api_key),
        do: [],
        else: [{"authorization", "Bearer " <> connection.api_key}]

    Req.post(base_url <> "/chat/completions",
      headers: headers,
      json: %{
        model: connection.model_id,
        messages: [%{role: "user", content: prompt}],
        temperature: 0.1
      },
      receive_timeout: @timeout_ms,
      retry: false
    )
    |> normalize(fn body ->
      body = as_map(body)
      get_in(body, ["choices", Access.at(0), "message", "content"])
    end)
  end

  defp request_anthropic(connection, prompt, base_url) do
    Req.post(base_url <> "/messages",
      headers: [
        {"x-api-key", connection.api_key || ""},
        {"anthropic-version", "2023-06-01"}
      ],
      json: %{
        model: connection.model_id,
        max_tokens: 2048,
        messages: [%{role: "user", content: prompt}]
      },
      receive_timeout: @timeout_ms,
      retry: false
    )
    |> normalize(fn body ->
      body
      |> as_map()
      |> Map.get("content", [])
      |> List.wrap()
      |> Enum.find_value(fn
        %{"type" => "text", "text" => text} -> text
        _other -> nil
      end)
    end)
  end

  defp request_google(connection, prompt, base_url) do
    Req.post(base_url <> "/models/#{connection.model_id}:generateContent",
      params: [key: connection.api_key],
      json: %{
        contents: [%{parts: [%{text: prompt}]}],
        generationConfig: %{responseMimeType: "application/json"}
      },
      receive_timeout: @timeout_ms,
      retry: false
    )
    |> normalize(fn body ->
      body
      |> as_map()
      |> get_in(["candidates", Access.at(0), "content", "parts", Access.at(0), "text"])
    end)
  end

  defp normalize({:ok, %Req.Response{status: status, body: body}}, extract)
       when status in 200..299 do
    case extract.(body) do
      text when is_binary(text) and text != "" -> {:ok, text}
      _other -> {:error, "The provider returned an empty answer."}
    end
  end

  defp normalize({:ok, %Req.Response{status: status, body: body}}, _extract) do
    {:error, "The provider answered with HTTP #{status}: #{Cells.snippet(inspect(body), 160)}"}
  end

  defp normalize({:error, %Req.TransportError{reason: :timeout}}, _extract) do
    {:error, "The provider did not answer in time."}
  end

  defp normalize({:error, %Req.TransportError{reason: :econnrefused}}, _extract) do
    {:error, "Nothing is listening at that base URL."}
  end

  defp normalize({:error, %Req.TransportError{reason: reason}}, _extract) do
    {:error, "Could not reach the provider (#{reason})."}
  end

  defp normalize({:error, reason}, _extract) do
    {:error, "Could not reach the provider (#{inspect(reason)})."}
  end

  defp wrap({:ok, text}, connection) do
    {:ok, text, connection.provider, connection.model_id}
  end

  defp wrap({:error, _reason} = error, _connection), do: error

  @doc "Parses the model answer into normalised AI findings."
  def parse(text, attribution) when is_binary(text) do
    text = strip_fence(text)

    with {:ok, decoded} <- Jason.decode(text),
         {:ok, list} <- findings_list(decoded) do
      findings =
        list
        |> Enum.map(&Finding.from_ai(&1, attribution))
        |> Enum.reject(&is_nil/1)
        |> Enum.take(@max_findings)

      {:ok, findings}
    else
      _other -> {:error, "The model did not return usable JSON."}
    end
  end

  defp findings_list(%{"findings" => list}) when is_list(list), do: {:ok, list}
  defp findings_list(list) when is_list(list), do: {:ok, list}
  defp findings_list(_other), do: :error

  defp strip_fence(text) do
    text
    |> String.trim()
    |> String.replace(~r/^```(?:json)?\s*/i, "")
    |> String.replace(~r/\s*```$/, "")
  end

  defp as_map(%{} = body), do: body
  defp as_map(_body), do: %{}

  defp blank?(value), do: value in [nil, ""]
end
