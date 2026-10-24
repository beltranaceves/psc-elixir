defmodule PscWeb.UnstrCanvasLive.AgentPanel do
  @moduledoc false

  use Phoenix.Component
  use PscWeb, :verified_routes

  import PscWeb.CoreComponents, only: [icon: 1, input: 1]

  attr :agent_session, :map, default: nil
  attr :agent_messages, :list, required: true
  attr :agent_turn_pid, :any, default: nil
  attr :agent_sessions, :list, required: true
  attr :agent_list_open, :boolean, default: false
  attr :agent_menu_session, :any, default: nil
  attr :agent_phase, :any, default: nil
  attr :agent_enabled?, :boolean, required: true
  attr :agent_missing, :any, default: nil
  attr :agent_composer, :any, required: true

  def panel(assigns) do
    ~H"""
    <div
      id="canvas-agent-panel"
      class="flex min-h-0 w-full flex-1 flex-col rounded-xl border border-base-content/10 bg-base-200/40 p-4"
    >
      <div :if={is_nil(@agent_session)} class="m-auto max-w-md text-center">
        <h2 class="text-lg font-medium text-base-content">Agent</h2>

        <p class="mt-1 text-sm text-base-content/60">
          Ask about this canvas. The agent reads only what you can read and cannot change anything.
        </p>

        <p :if={@agent_missing == :key} class="mt-3 text-sm text-base-content/60">
          The agent needs a model provider key.
          <.link navigate={~p"/users/settings"} class="link link-primary">
            Add your API key in settings
          </.link>
        </p>

        <p :if={@agent_missing == :model} class="mt-3 text-sm text-base-content/60">
          Your key is saved; the agent still needs a model.
          <.link navigate={~p"/users/settings"} class="link link-primary">
            Choose a model in settings
          </.link>
        </p>

        <button
          type="button"
          phx-click="agent_new"
          disabled={not @agent_enabled?}
          class="mt-4 rounded-lg bg-primary px-4 py-2 text-sm font-medium text-primary-content disabled:opacity-50"
        >
          Start a chat
        </button>
      </div>

      <div :if={@agent_session} class="flex min-h-0 flex-1 flex-col">
        <div class="flex items-center justify-between gap-3 border-b border-base-content/10 pb-2">
          <h2 id="canvas-agent-title" class="truncate text-sm font-medium text-base-content">
            {@agent_session.title}
          </h2>

          <div class="flex shrink-0 items-center gap-2">
            <div class="relative" phx-click-away="agent_close_lists">
              <button
                type="button"
                id="canvas-agent-chats"
                phx-click="agent_toggle_list"
                class="flex max-w-[12rem] items-center gap-1 rounded-lg border border-base-content/15 px-2 py-1 text-xs text-base-content/70 hover:bg-base-100"
              >
                <.icon name="hero-chat-bubble-left-right" class="size-3.5 shrink-0" />
                <span class="truncate">{length(@agent_sessions)} chats</span>
                <.icon name="hero-chevron-down" class="size-3 shrink-0" />
              </button>

              <div
                :if={@agent_list_open}
                id="canvas-agent-chat-list"
                class="absolute right-0 z-30 mt-1 w-72 rounded-xl border border-base-content/10 bg-base-100 p-1 shadow-lg"
              >
                <p class="px-2 py-1 text-[11px] uppercase tracking-wide text-base-content/40">
                  Chats on this canvas
                </p>

                <div :for={session <- @agent_sessions} class="group relative">
                  <button
                    type="button"
                    phx-click="agent_select"
                    phx-value-session={session.id}
                    class={[
                      "block w-full rounded-lg px-2 py-1.5 pr-8 text-left hover:bg-base-200",
                      agent_session_selected?(@agent_session, session) && "bg-base-200"
                    ]}
                  >
                    <p class="truncate text-xs font-medium text-base-content">
                      {session.title}
                    </p>

                    <p class="mt-0.5 text-[11px] text-base-content/50">
                      {turn_count(session)} turns · started {agent_date(session.inserted_at)} · {agent_relative_time(
                        session.last_message_at || session.inserted_at
                      )}
                    </p>
                  </button>

                  <button
                    type="button"
                    phx-click="agent_chat_menu"
                    phx-value-session={session.id}
                    aria-label="Chat options"
                    class={[
                      "absolute right-1 top-1.5 rounded p-1 text-base-content/50 hover:bg-base-300",
                      "opacity-0 transition-opacity group-hover:opacity-100",
                      @agent_menu_session == session.id && "opacity-100"
                    ]}
                  >
                    <.icon name="hero-ellipsis-vertical" class="size-4" />
                  </button>

                  <div
                    :if={@agent_menu_session == session.id}
                    class="absolute right-1 top-8 z-40 w-44 rounded-lg border border-base-content/10 bg-base-100 p-1 shadow-lg"
                  >
                    <.form
                      for={to_form(%{"title" => session.title}, as: :rename)}
                      id={"agent-rename-#{session.id}"}
                      phx-submit="agent_rename"
                      phx-value-session={session.id}
                      class="px-1 pb-1"
                    >
                      <input
                        type="text"
                        name="title"
                        value={session.title}
                        maxlength="120"
                        class="w-full rounded border border-base-content/15 bg-base-100 px-1.5 py-1 text-xs text-base-content"
                      />
                      <button
                        type="submit"
                        class="mt-1 w-full rounded bg-primary px-2 py-1 text-xs text-primary-content"
                      >
                        Rename
                      </button>
                    </.form>

                    <button
                      type="button"
                      phx-click="agent_duplicate"
                      phx-value-session={session.id}
                      class="w-full rounded px-2 py-1 text-left text-xs text-base-content/80 hover:bg-base-200"
                    >
                      Duplicate
                    </button>

                    <button
                      type="button"
                      phx-click="agent_delete"
                      phx-value-session={session.id}
                      data-confirm="Delete this chat and its transcript?"
                      class="w-full rounded px-2 py-1 text-left text-xs text-error hover:bg-error/10"
                    >
                      Delete
                    </button>
                  </div>
                </div>
              </div>
            </div>

            <button
              :if={@agent_turn_pid}
              type="button"
              phx-click="agent_stop"
              class="rounded-lg border border-base-content/20 px-2 py-1 text-xs hover:bg-base-100"
            >
              Stop
            </button>

            <button
              type="button"
              phx-click="agent_new"
              class="rounded-lg border border-base-content/20 px-2 py-1 text-xs hover:bg-base-100"
            >
              New chat
            </button>
          </div>
        </div>

        <div
          :if={@agent_phase}
          id="canvas-agent-status"
          class="mt-2 flex items-center gap-2 text-xs text-base-content/60"
        >
          <span class="size-1.5 animate-pulse rounded-full bg-primary"></span> {@agent_phase}
        </div>

        <div id="canvas-agent-messages" class="mt-3 flex-1 space-y-3 overflow-y-auto pr-1">
          <p :if={@agent_messages == []} class="text-sm text-base-content/60">
            Ask about this canvas: its cells, its notes, what changed.
          </p>

          <div
            :for={message <- @agent_messages}
            id={"agent-message-#{message.id}"}
            class={[
              "rounded-xl border p-3 text-sm",
              message.role == :user && "border-primary/20 bg-primary/5",
              message.role == :assistant && "border-base-content/10 bg-base-100",
              message.status == :error && "border-error/40"
            ]}
          >
            <p class="mb-1 text-xs uppercase tracking-wide text-base-content/50">
              {if message.role == :user, do: "You", else: "Assistant"}
            </p>

            <div :if={message.tool_calls != []} class="mb-2 space-y-1">
              <p class="text-xs uppercase tracking-wide text-base-content/40">
                Tools called
              </p>

              <details
                :for={call <- message.tool_calls}
                class="rounded-lg border border-base-content/10 px-2 py-1 text-xs"
              >
                <summary class="cursor-pointer list-none">
                  <span class="font-mono">{call["name"]}</span>
                  <span class="ml-2 text-base-content/50">{call["status"]}</span>
                </summary>
                <pre class="mt-1 overflow-x-auto whitespace-pre-wrap text-base-content/70">{Jason.encode!(
                          call["result"] || call["arguments"] || %{},
                          pretty: true
                        )}</pre>
              </details>
            </div>

            <div
              :if={agent_refs(message) != []}
              id={"agent-refs-#{message.id}"}
              class="mb-2 space-y-2"
            >
              <div
                :for={ref <- agent_cell_refs(message)}
                class="rounded-lg border border-base-content/10 bg-base-200/60 px-2.5 py-2"
              >
                <div class="flex items-start justify-between gap-2">
                  <p class="text-xs font-medium text-base-content/80">{ref["label"]}</p>

                  <.link
                    navigate={ref["url"]}
                    class="shrink-0 rounded-md border border-base-content/15 px-2 py-0.5 text-xs text-base-content/70 hover:bg-base-100"
                  >
                    Open cell
                  </.link>
                </div>

                <p
                  :if={ref["excerpt"]}
                  class="mt-1 line-clamp-3 whitespace-pre-wrap text-xs leading-relaxed text-base-content/60"
                >
                  {ref["excerpt"]}
                </p>
              </div>

              <div :if={agent_other_refs(message) != []} class="flex flex-wrap gap-1.5">
                <.link
                  :for={ref <- agent_other_refs(message)}
                  navigate={ref["url"]}
                  class={[
                    "inline-flex max-w-[20rem] items-center gap-1.5 rounded-md border px-2 py-1 text-xs transition-colors hover:bg-base-200",
                    ref["kind"] == "note" && "border-primary/30 text-primary",
                    ref["kind"] != "note" && "border-base-content/15 text-base-content/70"
                  ]}
                >
                  <.icon
                    name={
                      case ref["kind"] do
                        "note" -> "hero-document-text"
                        "template" -> "hero-rectangle-stack"
                        _other -> "hero-square-2-stack"
                      end
                    }
                    class="size-3.5 shrink-0"
                  /> <span class="truncate">{ref["label"]}</span>
                </.link>
              </div>
            </div>

            <div class="whitespace-pre-wrap break-words text-base-content">
              {message.content}<span :if={message.status == :streaming}>▍</span>
            </div>

            <p :if={message.status == :cancelled} class="mt-1 text-xs text-base-content/50">
              Stopped.
            </p>

            <p :if={message.error} class="mt-1 text-xs text-error">{message.error}</p>
          </div>
        </div>

        <.form
          for={@agent_composer}
          id="canvas-agent-composer"
          phx-submit="agent_send"
          class="mt-3 rounded-xl border border-base-content/10 bg-base-100 p-2 focus-within:border-primary/50 focus-within:ring-2 focus-within:ring-primary/20"
        >
          <.input
            field={@agent_composer[:content]}
            type="textarea"
            rows="2"
            placeholder="Ask about this canvas…"
            disabled={not @agent_enabled? or @agent_turn_pid != nil}
            class="border-0 bg-transparent px-1 py-1 focus:ring-0"
          />
          <div class="mt-2 flex items-center justify-between gap-3">
            <p class="text-xs text-base-content/50">
              <%= if @agent_enabled? do %>
                Read-only. Nothing is created or changed.
              <% else %>
                <.link navigate={~p"/users/settings"} class="link link-primary">
                  {if @agent_missing == :key,
                    do: "Add your API key in settings",
                    else: "Choose a model in settings"}
                </.link>
              <% end %>
            </p>

            <button
              type="submit"
              disabled={not @agent_enabled? or @agent_turn_pid != nil}
              class="rounded-lg bg-primary px-3 py-1.5 text-sm font-medium text-primary-content disabled:opacity-50"
            >
              Send
            </button>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  defp agent_refs(message) do
    message.tool_calls
    |> Enum.flat_map(fn call ->
      case call["result"] do
        %{"refs" => refs} when is_list(refs) -> Enum.filter(refs, &is_map_key(&1, "url"))
        _other -> []
      end
    end)
    |> Enum.uniq_by(& &1["url"])
  end

  defp agent_cell_refs(message), do: Enum.filter(agent_refs(message), &(&1["kind"] == "cell"))

  defp agent_other_refs(message),
    do: Enum.reject(agent_refs(message), &(&1["kind"] == "cell"))

  defp agent_session_selected?(current, session), do: current.id == session.id

  # A turn is a user message plus the answer it produced; the counter stores both.
  defp turn_count(session), do: max(div(session.message_count + 1, 2), 0)

  defp agent_date(nil), do: "—"

  defp agent_date(%NaiveDateTime{} = at), do: Calendar.strftime(at, "%d %b")
  defp agent_date(%DateTime{} = at), do: Calendar.strftime(at, "%d %b")

  defp agent_relative_time(nil), do: "never used"

  defp agent_relative_time(%_{} = at) do
    seconds = DateTime.diff(DateTime.utc_now(), to_utc(at))

    cond do
      seconds < 60 -> "just now"
      seconds < 3_600 -> "#{div(seconds, 60)}m ago"
      seconds < 86_400 -> "#{div(seconds, 3_600)}h ago"
      seconds < 2_592_000 -> "#{div(seconds, 86_400)}d ago"
      true -> "on #{agent_date(at)}"
    end
  end

  defp to_utc(%DateTime{} = at), do: at
  defp to_utc(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")
end
