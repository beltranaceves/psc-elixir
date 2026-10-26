defmodule PscWeb.UnstrCanvasLive.AgentPanel do
  @moduledoc false

  use Phoenix.Component
  use PscWeb, :verified_routes

  import Phoenix.HTML, only: [raw: 1]
  import PscWeb.CoreComponents, only: [icon: 1, input: 1]

  alias PscWeb.Markdown

  # Opening prompts for an empty transcript. Clicking one fills the composer;
  # the user still decides when to send it.
  @suggestions [
    "Summarize this canvas",
    "Which cells are still empty?",
    "Summarize the notes"
  ]

  attr :agent_session, :map, default: nil
  attr :agent_messages, :list, required: true
  attr :agent_turn_pid, :any, default: nil
  attr :agent_sessions, :list, required: true
  attr :agent_list_open, :boolean, default: false
  attr :agent_menu_session, :any, default: nil
  attr :agent_phase, :any, default: nil
  attr :agent_enabled?, :boolean, required: true
  attr :agent_roles, :list, default: []
  attr :agent_role, :string, default: nil
  attr :agent_missing, :any, default: nil
  attr :agent_composer, :any, required: true
  attr :agent_connections, :list, required: true
  attr :agent_connection, :map, default: nil
  attr :agent_connection_list_open, :boolean, default: false

  def panel(assigns) do
    assigns = assign(assigns, :suggestions, @suggestions)

    ~H"""
    <div
      id="canvas-agent-panel"
      phx-hook="CanvasAgent"
      class="flex min-h-0 w-full flex-1 flex-col overflow-hidden rounded-2xl border border-base-content/10 bg-base-100 shadow-sm"
    >
      <div
        :if={is_nil(@agent_session)}
        class="flex min-h-0 flex-1 items-center justify-center overflow-y-auto p-6"
      >
        <div class="w-full max-w-sm text-center">
          <span class="mx-auto flex size-14 items-center justify-center rounded-2xl bg-gradient-to-br from-primary/25 to-accent/20 text-primary ring-1 ring-primary/20 ring-inset">
            <.icon name="hero-sparkles" class="size-7" />
          </span>

          <h2 class="mt-4 text-base font-semibold text-base-content">Canvas agent</h2>

          <p class="mx-auto mt-1.5 max-w-[18rem] text-sm leading-relaxed text-base-content/55">
            Ask about this canvas. The agent reads only what you can read and cannot change anything.
          </p>

          <div
            :if={@agent_missing == :connection}
            class="mt-4 flex items-start gap-2 rounded-xl border border-warning/25 bg-warning/10 px-3 py-2 text-left text-xs leading-relaxed text-base-content/70"
          >
            <.icon name="hero-link" class="mt-0.5 size-4 shrink-0 text-warning" />
            <p>
              Add a provider connection to use the agent.
              <.link navigate={~p"/users/settings#agent-connections"} class="link link-primary">
                Add a connection in settings
              </.link>
            </p>
          </div>

          <p :if={@agent_connection} class="mt-3 truncate text-xs text-base-content/45">
            Using {@agent_connection.name} · {@agent_connection.provider_label} · {@agent_connection.model_id}
          </p>

          <button
            type="button"
            phx-click="agent_new"
            disabled={not @agent_enabled?}
            class="mt-5 inline-flex items-center gap-2 rounded-xl bg-primary px-4 py-2 text-sm font-medium text-primary-content shadow-sm transition hover:bg-primary/90 focus:outline-none focus-visible:ring-2 focus-visible:ring-primary/40 disabled:cursor-not-allowed disabled:opacity-50"
          >
            <.icon name="hero-chat-bubble-left-right" class="size-4" /> Start a chat
          </button>
        </div>
      </div>

      <div :if={@agent_session} class="flex min-h-0 flex-1 flex-col">
        <div class="shrink-0 border-b border-base-content/10">
          <div class="mx-auto flex w-full max-w-3xl items-center gap-2 px-3 py-2.5 sm:px-4">
            <span class="hidden size-7 shrink-0 items-center justify-center rounded-lg bg-primary/10 text-primary sm:flex">
              <.icon name="hero-sparkles" class="size-4" />
            </span>

            <div class="min-w-0 flex-1">
              <h2 id="canvas-agent-title" class="truncate text-sm font-semibold text-base-content">
                {@agent_session.title}
              </h2>

              <p class="truncate text-[11px] leading-4 text-base-content/45">
                {plural(turn_count(@agent_session), "turn")} · {agent_relative_time(
                  @agent_session.last_message_at || @agent_session.inserted_at
                )}
              </p>
            </div>

            <div class="flex shrink-0 items-center gap-1.5">
              <select
                :if={@agent_roles != []}
                id="canvas-agent-role"
                name="role"
                phx-change="agent_select_role"
                disabled={@agent_session.message_count not in [nil, 0] or not is_nil(@agent_turn_pid)}
                title="Agent role"
                class="max-w-[10rem] rounded-lg border border-base-content/10 bg-base-100 px-2 py-1.5 text-xs font-medium text-base-content/70 transition hover:bg-base-200 focus:outline-none focus-visible:ring-2 focus-visible:ring-primary/40 disabled:cursor-not-allowed disabled:opacity-50"
              >
                <option
                  :for={role <- @agent_roles}
                  value={role["key"]}
                  selected={role["key"] == @agent_role}
                >
                  {role["name"]}
                </option>
              </select>

              <div class="relative" phx-click-away="agent_close_lists">
                <button
                  type="button"
                  id="canvas-agent-connection"
                  phx-click="agent_toggle_connections"
                  disabled={not is_nil(@agent_turn_pid)}
                  title="Model connection"
                  class="flex max-w-[11rem] items-center gap-1.5 rounded-lg border border-base-content/10 bg-base-100 px-2 py-1.5 text-xs font-medium text-base-content/70 transition hover:bg-base-200 focus:outline-none focus-visible:ring-2 focus-visible:ring-primary/40 disabled:cursor-not-allowed disabled:opacity-50"
                >
                  <.icon name="hero-bolt" class="size-3.5 shrink-0" />
                  <span class="truncate">{connection_label(@agent_connection)}</span>
                  <.icon name="hero-chevron-down" class="size-3 shrink-0 opacity-60" />
                </button>

                <div
                  :if={@agent_connection_list_open}
                  id="canvas-agent-connection-list"
                  class="absolute right-0 z-30 mt-2 w-72 rounded-xl border border-base-content/10 bg-base-100 p-1.5 shadow-xl"
                >
                  <p class="px-2 pb-1 pt-1 text-[11px] font-medium uppercase tracking-wider text-base-content/40">
                    Model connection
                  </p>

                  <button
                    :for={connection <- @agent_connections}
                    type="button"
                    phx-click="agent_select_connection"
                    phx-value-connection={connection.id}
                    class={[
                      "flex w-full items-start gap-2 rounded-lg px-2 py-2 text-left transition-colors",
                      if(selected_connection?(@agent_connection, connection),
                        do: "bg-primary/10",
                        else: "hover:bg-base-200"
                      )
                    ]}
                  >
                    <.icon
                      name="hero-check"
                      class={[
                        "mt-0.5 size-4 shrink-0",
                        if(selected_connection?(@agent_connection, connection),
                          do: "text-primary",
                          else: "text-transparent"
                        )
                      ]}
                    />

                    <span class="min-w-0 flex-1">
                      <span class="block truncate text-xs font-medium text-base-content">
                        {connection.name}
                      </span>
                      <span class="mt-0.5 block truncate text-[11px] text-base-content/45">
                        {connection.provider_label} · {connection.model_id}
                      </span>
                    </span>
                  </button>

                  <p
                    :if={@agent_connections == []}
                    class="px-2 py-3 text-center text-xs text-base-content/50"
                  >
                    No connections yet.
                  </p>

                  <div class="mt-1 border-t border-base-content/10 pt-1">
                    <.link
                      navigate={~p"/users/settings#agent-connections"}
                      class="flex items-center gap-2 rounded-lg px-2 py-1.5 text-xs text-base-content/70 transition hover:bg-base-200"
                    >
                      <.icon
                        name="hero-cog-6-tooth"
                        class="size-3.5 shrink-0 text-base-content/50"
                      /> Manage connections
                    </.link>
                  </div>
                </div>
              </div>

              <div class="relative" phx-click-away="agent_close_lists">
                <button
                  type="button"
                  id="canvas-agent-chats"
                  phx-click="agent_toggle_list"
                  class="flex max-w-[10rem] items-center gap-1.5 rounded-lg border border-base-content/10 bg-base-100 px-2 py-1.5 text-xs font-medium text-base-content/70 transition hover:bg-base-200 focus:outline-none focus-visible:ring-2 focus-visible:ring-primary/40"
                >
                  <.icon name="hero-chat-bubble-left-right" class="size-3.5 shrink-0" />
                  <span class="truncate">{plural(length(@agent_sessions), "chat")}</span>
                  <.icon name="hero-chevron-down" class="size-3 shrink-0 opacity-60" />
                </button>

                <div
                  :if={@agent_list_open}
                  id="canvas-agent-chat-list"
                  class="absolute right-0 z-30 mt-2 w-80 max-w-[calc(100vw-2rem)] rounded-xl border border-base-content/10 bg-base-100 p-1.5 shadow-xl"
                >
                  <p class="px-2 pb-1 pt-1 text-[11px] font-medium uppercase tracking-wider text-base-content/40">
                    Chats on this canvas
                  </p>

                  <div class={[
                    "max-h-72 space-y-0.5",
                    if(@agent_menu_session, do: "overflow-visible", else: "overflow-y-auto")
                  ]}>
                    <div :for={session <- @agent_sessions} class="group relative">
                      <button
                        type="button"
                        phx-click="agent_select"
                        phx-value-session={session.id}
                        class={[
                          "flex w-full items-center gap-2 rounded-lg px-2 py-2 pr-9 text-left transition-colors",
                          if(agent_session_selected?(@agent_session, session),
                            do: "bg-primary/10",
                            else: "hover:bg-base-200"
                          )
                        ]}
                      >
                        <.icon
                          name="hero-chat-bubble-oval-left"
                          class="size-4 shrink-0 text-base-content/40"
                        />
                        <span class="min-w-0 flex-1">
                          <span class="block truncate text-xs font-medium text-base-content">
                            {session.title}
                          </span>

                          <span class="mt-0.5 block truncate text-[11px] text-base-content/45">
                            {plural(turn_count(session), "turn")} · {agent_relative_time(
                              session.last_message_at || session.inserted_at
                            )}
                          </span>
                        </span>
                      </button>

                      <button
                        type="button"
                        phx-click="agent_chat_menu"
                        phx-value-session={session.id}
                        aria-label="Chat options"
                        class={[
                          "absolute right-1.5 top-1.5 rounded-md p-1 text-base-content/50 transition hover:bg-base-300 hover:text-base-content focus:opacity-100 group-hover:opacity-100",
                          "opacity-0",
                          @agent_menu_session == session.id && "opacity-100"
                        ]}
                      >
                        <.icon name="hero-ellipsis-vertical" class="size-4" />
                      </button>

                      <div
                        :if={@agent_menu_session == session.id}
                        class="absolute right-1.5 top-9 z-40 w-48 rounded-xl border border-base-content/10 bg-base-100 p-1.5 shadow-xl"
                      >
                        <.form
                          for={to_form(%{"title" => session.title}, as: :rename)}
                          id={"agent-rename-#{session.id}"}
                          phx-submit="agent_rename"
                          phx-value-session={session.id}
                          class="pb-1.5"
                        >
                          <input
                            type="text"
                            name="title"
                            value={session.title}
                            maxlength="120"
                            aria-label="Chat title"
                            class="w-full rounded-lg border border-base-content/15 bg-base-100 px-2 py-1.5 text-xs text-base-content focus:border-primary/50 focus:outline-none focus:ring-2 focus:ring-primary/20"
                          />
                          <button
                            type="submit"
                            class="mt-1.5 w-full rounded-lg bg-primary px-2 py-1.5 text-xs font-medium text-primary-content transition hover:bg-primary/90"
                          >
                            Rename
                          </button>
                        </.form>

                        <button
                          type="button"
                          phx-click="agent_duplicate"
                          phx-value-session={session.id}
                          class="flex w-full items-center gap-2 rounded-lg px-2 py-1.5 text-left text-xs text-base-content/80 transition hover:bg-base-200"
                        >
                          <.icon
                            name="hero-document-duplicate"
                            class="size-3.5 shrink-0 text-base-content/50"
                          /> Duplicate
                        </button>

                        <button
                          type="button"
                          phx-click="agent_delete"
                          phx-value-session={session.id}
                          data-confirm="Delete this chat and its transcript?"
                          class="flex w-full items-center gap-2 rounded-lg px-2 py-1.5 text-left text-xs text-error transition hover:bg-error/10"
                        >
                          <.icon name="hero-trash" class="size-3.5 shrink-0" /> Delete
                        </button>
                      </div>
                    </div>
                  </div>
                </div>
              </div>

              <button
                type="button"
                phx-click="agent_new"
                class="flex items-center gap-1.5 rounded-lg border border-primary/30 px-2 py-1.5 text-xs font-medium text-primary transition hover:bg-primary/10 focus:outline-none focus-visible:ring-2 focus-visible:ring-primary/40"
              >
                <.icon name="hero-plus" class="size-3.5" /> New chat
              </button>
            </div>
          </div>
        </div>

        <div
          id="canvas-agent-messages"
          role="log"
          aria-live="polite"
          class="min-h-0 flex-1 overflow-y-auto overscroll-contain px-3 py-4 sm:px-4"
        >
          <div class="mx-auto flex min-h-full w-full max-w-3xl flex-col">
            <div
              :if={@agent_messages == [] and is_nil(@agent_phase)}
              class="my-auto py-6 text-center"
            >
              <span class="mx-auto flex size-12 items-center justify-center rounded-2xl bg-primary/10 text-primary">
                <.icon name="hero-sparkles" class="size-6" />
              </span>

              <h3 class="mt-3 text-sm font-semibold text-base-content">Ask about this canvas</h3>

              <p class="mt-1 text-xs leading-relaxed text-base-content/50">
                Its cells, its notes, or what changed recently.
              </p>

              <div
                :if={@agent_enabled? and is_nil(@agent_turn_pid)}
                class="mt-4 flex flex-wrap justify-center gap-1.5"
              >
                <button
                  :for={prompt <- @suggestions}
                  type="button"
                  phx-click="agent_suggest"
                  phx-value-prompt={prompt}
                  class="rounded-full border border-base-content/15 bg-base-200/50 px-3 py-1.5 text-xs text-base-content/70 transition hover:border-primary/40 hover:bg-primary/10 hover:text-primary"
                >
                  {prompt}
                </button>
              </div>
            </div>

            <div :if={@agent_messages != [] or @agent_phase} class="flex flex-col gap-4">
              <div :for={message <- @agent_messages} id={"agent-message-#{message.id}"}>
                <div :if={message.role == :user} class="flex justify-end">
                  <div
                    phx-no-format
                    class="max-w-[85%] whitespace-pre-wrap break-words rounded-2xl rounded-br-md bg-primary px-3.5 py-2 text-sm leading-relaxed text-primary-content shadow-sm"
                  >{message.content}</div>
                </div>

                <div :if={message.role == :assistant} class="flex gap-2.5">
                  <span class="mt-1 flex size-7 shrink-0 items-center justify-center rounded-lg bg-gradient-to-br from-primary/25 to-accent/20 text-primary ring-1 ring-primary/20 ring-inset">
                    <.icon name="hero-sparkles" class="size-4" />
                  </span>

                  <div class="min-w-0 flex-1">
                    <div class={[
                      "rounded-2xl rounded-tl-md border px-3.5 py-2.5 text-sm leading-relaxed",
                      if(message.status == :error,
                        do: "border-error/30 bg-error/5",
                        else: "border-base-content/10 bg-base-200/40"
                      )
                    ]}>
                      <div :if={message.tool_calls != []} class="mb-2 flex flex-col gap-1">
                        <details
                          :for={call <- message.tool_calls}
                          class="group/tool overflow-hidden rounded-lg border border-base-content/10 bg-base-100/60"
                        >
                          <summary class="flex cursor-pointer select-none list-none items-center gap-2 px-2.5 py-1.5 text-[11px] [&::-webkit-details-marker]:hidden">
                            <.icon
                              name="hero-wrench-screwdriver"
                              class="size-3.5 shrink-0 text-base-content/40"
                            />
                            <span class="truncate font-mono text-base-content/70">{tool_label(
                              call["name"]
                            )}</span>

                            <span class={[
                              "ml-auto shrink-0 rounded-full px-1.5 py-0.5 text-[10px] font-medium",
                              tool_status_class(call["status"])
                            ]}>{call["status"]}</span>

                            <.icon
                              name="hero-chevron-down"
                              class="size-3.5 shrink-0 text-base-content/35 transition-transform group-open/tool:rotate-180"
                            />
                          </summary>
                          <pre
                            phx-no-format
                            class="max-h-64 overflow-auto border-t border-base-content/10 bg-base-200/40 px-2.5 py-2 text-[11px] leading-relaxed text-base-content/60"
                          >{pretty_json(call)}</pre>
                        </details>
                      </div>

                      <div
                        :if={agent_refs(message) != []}
                        id={"agent-refs-#{message.id}"}
                        class="mb-2 space-y-1.5"
                      >
                        <div
                          :for={ref <- agent_cell_refs(message)}
                          class="rounded-xl border border-base-content/10 bg-base-100/50 px-2.5 py-2"
                        >
                          <div class="flex items-start justify-between gap-2">
                            <p class="text-xs font-medium text-base-content/80">{ref["label"]}</p>

                            <.link
                              navigate={ref["url"]}
                              class="shrink-0 rounded-md px-1.5 py-0.5 text-[11px] font-medium text-primary transition hover:bg-primary/10"
                            >
                              Open cell
                            </.link>
                          </div>

                          <p
                            :if={ref["excerpt"]}
                            phx-no-format
                            class="mt-1 line-clamp-3 whitespace-pre-wrap text-xs leading-relaxed text-base-content/55"
                          >{ref["excerpt"]}</p>
                        </div>

                        <div :if={agent_other_refs(message) != []} class="flex flex-wrap gap-1.5">
                          <.link
                            :for={ref <- agent_other_refs(message)}
                            navigate={ref["url"]}
                            class={[
                              "inline-flex max-w-[20rem] items-center gap-1.5 rounded-full border px-2.5 py-1 text-[11px] transition-colors",
                              if(ref["kind"] == "note",
                                do: "border-primary/30 bg-primary/5 text-primary hover:bg-primary/10",
                                else: "border-base-content/15 text-base-content/70 hover:bg-base-200"
                              )
                            ]}
                          >
                            <.icon name={ref_icon(ref["kind"])} class="size-3.5 shrink-0" />
                            <span class="truncate">{ref["label"]}</span>
                          </.link>
                        </div>
                      </div>

                      <div
                        :if={message.status == :streaming}
                        phx-no-format
                        class="whitespace-pre-wrap break-words"
                      >{message.content}<span class="ml-0.5 inline-block h-4 w-0.5 translate-y-0.5 animate-pulse rounded-full bg-primary/70"></span></div>

                      <div
                        :if={message.status != :streaming and message.content not in [nil, ""]}
                        class="prose prose-sm dark:prose-invert max-w-none break-words prose-headings:mb-1.5 prose-headings:mt-3 prose-headings:font-semibold prose-p:my-1.5 prose-pre:my-2 prose-pre:rounded-lg prose-pre:bg-base-300 prose-pre:text-xs prose-code:text-[0.8em] prose-code:before:content-none prose-code:after:content-none prose-li:my-0.5 prose-a:text-primary"
                      >
                        {raw(markdown_html(message.content))}
                      </div>
                    </div>

                    <p
                      :if={message.status == :cancelled}
                      class="mt-1.5 pl-1 text-[11px] text-base-content/45"
                    >
                      Stopped.
                    </p>

                    <p
                      :if={message.error}
                      class="mt-1.5 flex items-start gap-1.5 pl-1 text-[11px] text-error"
                    >
                      <.icon name="hero-exclamation-triangle" class="mt-0.5 size-3.5 shrink-0" />
                      <span class="break-words">{message.error}</span>
                    </p>
                  </div>
                </div>
              </div>

              <div :if={@agent_phase} id="canvas-agent-status" class="flex gap-2.5">
                <span class="mt-1 flex size-7 shrink-0 items-center justify-center rounded-lg bg-gradient-to-br from-primary/25 to-accent/20 text-primary ring-1 ring-primary/20 ring-inset">
                  <.icon name="hero-sparkles" class="size-4" />
                </span>

                <div class="flex items-center gap-2.5 rounded-2xl rounded-tl-md border border-base-content/10 bg-base-200/40 px-3.5 py-2.5">
                  <span class="flex gap-1">
                    <span class="size-1.5 animate-bounce rounded-full bg-primary/70"></span>
                    <span class="size-1.5 animate-bounce rounded-full bg-primary/70 [animation-delay:150ms]"></span>
                    <span class="size-1.5 animate-bounce rounded-full bg-primary/70 [animation-delay:300ms]"></span>
                  </span>
                  <span class="text-xs text-base-content/60">{@agent_phase}</span>
                </div>
              </div>
            </div>
          </div>
        </div>

        <.form
          for={@agent_composer}
          id="canvas-agent-composer"
          phx-submit="agent_send"
          class="shrink-0 border-t border-base-content/10 px-3 py-3 sm:px-4"
        >
          <div class="mx-auto w-full max-w-3xl">
            <div class="flex items-end gap-2 rounded-2xl border border-base-content/15 bg-base-200/40 p-1.5 transition focus-within:border-primary/50 focus-within:bg-base-100 focus-within:ring-4 focus-within:ring-primary/10 [&>div]:mb-0 [&>div]:min-w-0 [&>div]:flex-1">
              <.input
                field={@agent_composer[:content]}
                type="textarea"
                rows="1"
                placeholder="Ask about this canvas…"
                disabled={not @agent_enabled? or @agent_turn_pid != nil}
                class="max-h-48 min-h-9 w-full resize-none border-0 bg-transparent px-2 py-1.5 text-sm leading-relaxed text-base-content placeholder:text-base-content/35 focus:outline-none focus:ring-0"
              />
              <button
                :if={is_nil(@agent_turn_pid)}
                type="submit"
                disabled={not @agent_enabled?}
                aria-label="Send"
                title="Send"
                class="mb-1 flex size-9 shrink-0 items-center justify-center rounded-xl bg-primary text-primary-content shadow-sm transition hover:bg-primary/90 focus:outline-none focus-visible:ring-2 focus-visible:ring-primary/40 disabled:cursor-not-allowed disabled:opacity-40"
              >
                <.icon name="hero-arrow-up" class="size-4" />
              </button>

              <button
                :if={@agent_turn_pid}
                type="button"
                phx-click="agent_stop"
                aria-label="Stop"
                title="Stop"
                class="mb-1 flex size-9 shrink-0 items-center justify-center rounded-xl border border-base-content/15 bg-base-100 text-base-content/70 transition hover:bg-base-200 focus:outline-none focus-visible:ring-2 focus-visible:ring-primary/40"
              >
                <.icon name="hero-stop" class="size-4" />
              </button>
            </div>

            <div class="mt-2 flex items-center justify-between gap-3 px-1 text-[11px] text-base-content/45">
              <p class="flex min-w-0 items-center gap-1.5">
                <.icon name="hero-lock-closed" class="size-3.5 shrink-0" />
                <span :if={@agent_enabled?} class="truncate">
                  Read-only. Nothing is created or changed.
                </span>

                <.link
                  :if={not @agent_enabled?}
                  navigate={~p"/users/settings#agent-connections"}
                  class="link link-primary truncate"
                >
                  Add a connection in settings
                </.link>
              </p>

              <p :if={@agent_enabled? and is_nil(@agent_turn_pid)} class="hidden shrink-0 sm:block">
                Enter to send · Shift+Enter for a new line
              </p>
            </div>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  defp markdown_html(content) when is_binary(content),
    do: Markdown.render(content, empty_message: "")

  defp markdown_html(_content), do: ""

  defp ref_icon("note"), do: "hero-document-text"
  defp ref_icon("template"), do: "hero-rectangle-stack"
  defp ref_icon("file"), do: "hero-folder-open"
  defp ref_icon(_kind), do: "hero-square-2-stack"

  defp tool_label(name) when is_binary(name),
    do: name |> String.replace("_", " ") |> String.capitalize()

  defp tool_label(_name), do: "tool"

  defp tool_status_class("ok"), do: "bg-success/10 text-success"
  defp tool_status_class("error"), do: "bg-error/10 text-error"
  defp tool_status_class(_status), do: "bg-base-content/10 text-base-content/60"

  defp pretty_json(call) do
    value = call["result"] || call["arguments"] || %{}

    case Jason.encode(value, pretty: true) do
      {:ok, json} -> json
      {:error, _reason} -> inspect(value, pretty: true, limit: 40)
    end
  end

  defp plural(1, word), do: "1 #{word}"
  defp plural(count, word), do: "#{count} #{word}s"

  defp connection_label(nil), do: "Choose model"
  defp connection_label(%{name: name}), do: name

  defp selected_connection?(nil, _connection), do: false
  defp selected_connection?(%{id: id}, %{id: id}), do: true
  defp selected_connection?(_current, _connection), do: false

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
