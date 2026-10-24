defmodule PscWeb.UnstrCanvasLive.NotesPanel do
  @moduledoc false

  use Phoenix.Component

  import PscWeb.Components.MarkdownEditor
  import PscWeb.CoreComponents, only: [icon: 1]

  alias PscWeb.Components.UI.Button, as: UIButton
  alias PscWeb.Markdown

  # The Notes view: the canvas's notes, and the one that is open.
  #
  # On a wide screen the list sits beside the editor. On a phone they are one
  # pane at a time: the list, and — once a note is open — the editor with a
  # back action.
  #
  # A scratchpad canvas has one note and no list: the editor takes the whole
  # view, with no way to pick another note.
  attr :notes, :list, required: true
  attr :note, :map, default: nil
  attr :note_content, :string, default: ""
  attr :note_html, :string, default: ""
  attr :note_save_state, :atom, required: true
  attr :note_save_stats, :map, required: true
  attr :note_presence, :map, default: %{}
  attr :user_id, :integer, required: true
  attr :is_owner, :boolean, required: true
  attr :scratchpad?, :boolean, default: false

  def panel(assigns) do
    ~H"""
    <div id="canvas-notes" class="flex min-h-0 w-full flex-1 flex-col lg:flex-row lg:gap-4">
      <%!-- The list. On a phone it is hidden while a note is open. A
      scratchpad has no list at all: it is not rendered. --%>
      <%= if not @scratchpad? do %>
        <div
          id="canvas-notes-list"
          class={[
            "flex min-h-0 w-full flex-col lg:w-64 lg:shrink-0",
            @note && "hidden lg:flex"
          ]}
        >
          <div class="mb-3 flex items-center justify-between gap-3">
            <h2 class="text-sm font-medium uppercase tracking-wide text-base-content/50">
              Notes
            </h2>

            <UIButton.button type="button" id="new-note-button" phx-click="create_note" size="sm">
              <.icon name="hero-plus" class="size-4" /> New note
            </UIButton.button>
          </div>

          <%= if @notes == [] do %>
            <div
              id="canvas-notes-empty"
              class="rounded-xl border border-dashed border-base-content/20 bg-base-200/40 p-6 text-center"
            >
              <p class="text-sm text-base-content/60">No notes yet.</p>

              <p class="mt-1 text-xs text-base-content/45">
                Notes are shared Markdown attached to this canvas.
              </p>
            </div>
          <% else %>
            <ul id="canvas-notes-items" class="min-h-0 flex-1 space-y-2 overflow-y-auto">
              <li :for={note <- @notes} id={"canvas-note-" <> note.id}>
                <button
                  type="button"
                  phx-click="select_note"
                  phx-value-note={note.id}
                  aria-current={to_string(@note && @note.id == note.id)}
                  class={[
                    "w-full rounded-lg border p-3 text-left transition-colors",
                    @note && @note.id == note.id && "border-primary/40 bg-primary/10",
                    !(@note && @note.id == note.id) &&
                      "border-base-content/10 bg-base-200 hover:border-base-content/25"
                  ]}
                >
                  <span class="block truncate text-sm font-medium text-base-content">
                    {note.title || "Untitled note"}
                  </span>

                  <span class="mt-1 block truncate text-xs text-base-content/50">
                    {note.snippet}
                  </span>
                </button>
              </li>
            </ul>
          <% end %>
        </div>
      <% end %>
      <%!-- The editor. On a phone it takes over the pane. --%>
      <div
        id="canvas-note-editor"
        class={[
          "flex min-h-0 w-full flex-1 flex-col",
          !@note && "hidden lg:flex"
        ]}
      >
        <%= if @note do %>
          <div class="mb-3 flex flex-wrap items-center gap-3">
            <%!-- There is no list to go back to in a scratchpad. --%>
            <button
              :if={!@scratchpad?}
              type="button"
              id="canvas-notes-back"
              phx-click="select_note"
              phx-value-note=""
              class="inline-flex size-8 shrink-0 items-center justify-center rounded-lg text-base-content/60 transition-colors hover:bg-base-content/5 hover:text-base-content lg:hidden"
              aria-label="Back to the notes"
            >
              <.icon name="hero-arrow-left" class="size-5" />
            </button>

            <.form
              for={%{}}
              id="canvas-note-title-form"
              phx-change="update_note_title"
              class="min-w-0 flex-1"
            >
              <input
                name="title"
                type="text"
                value={@note.title}
                phx-debounce="500"
                placeholder="Untitled note"
                class="w-full min-w-0 border-b-2 border-transparent bg-transparent text-lg font-semibold text-base-content transition-colors placeholder-base-content/40 hover:border-base-content/20 focus:border-primary focus:outline-none"
              />
            </.form>

            <%!-- Who else has this note open. The canvas's Active Users says
            who is on the canvas; this says who is in the same note. --%>
            <span
              :if={note_editors(@note_presence, @user_id) != []}
              id="canvas-note-presence"
              title={note_editors_label(note_editors(@note_presence, @user_id))}
              class="inline-flex max-w-48 items-center gap-1.5 rounded-full border border-base-content/10 bg-base-content/5 px-2.5 py-1 text-xs text-base-content/70"
            >
              <span class="relative flex size-2 shrink-0">
                <span class="absolute inline-flex size-full rounded-full bg-success/50"></span>
                <span class="relative inline-flex size-2 rounded-full bg-success"></span>
              </span>

              <span class="truncate">
                {note_editors_label(note_editors(@note_presence, @user_id))}
              </span>
            </span>

            <%= if @is_owner and not @scratchpad? do %>
              <UIButton.button
                type="button"
                id="canvas-note-delete"
                phx-click="delete_note"
                phx-value-note={@note.id}
                data-confirm="Delete this note? This cannot be undone."
                variant="outline"
                size="sm"
                class="text-error hover:text-error"
              >
                Delete
              </UIButton.button>
            <% end %>
          </div>

          <.markdown_editor
            id="canvas-note-markdown"
            input_id="canvas-note-input"
            form_id="canvas-note-form"
            preview_id="canvas-note-preview"
            content={@note_content}
            html={@note_html}
            current_user_id={@user_id}
            change_event="update_note_content"
            preview_event="render_note"
            render_event="note_rendered"
            update_event="note_content_updated"
            empty_message="Start writing in the editor."
            preview_label="Edit note content"
          />
        <% else %>
          <div class="flex min-h-0 flex-1 items-center justify-center rounded-xl border border-dashed border-base-content/20 bg-base-200/40 p-8 text-center">
            <p class="max-w-sm text-sm text-base-content/50">
              <%= if @scratchpad? do %>
                The scratchpad is on its way. Reload the view to write in it.
              <% else %>
                Select a note, or create one, to start writing.
              <% end %>
            </p>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  def with_snippets(notes) do
    Enum.map(notes, &Map.put(&1, :snippet, note_snippet(&1.content)))
  end

  def render_html(content),
    do: Markdown.render(content, empty_message: "Start writing in the editor.")

  # A one-line preview of a note's content for the list.
  defp note_snippet(nil), do: "Empty"

  defp note_snippet(content) when content in ["", nil], do: "Empty"

  defp note_snippet(content) do
    content
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, 90)
  end

  # The other people who have this note open. Presence keys come back from the
  # CRDT as strings, so the id is compared as one.
  defp note_editors(presence, user_id) do
    for {id, %{metas: [meta | _]}} <- presence, to_string(id) != to_string(user_id) do
      meta[:username]
    end
  end

  defp note_editors_label([username]), do: "#{username} is editing"
  defp note_editors_label(usernames), do: "#{length(usernames)} others are editing"
end
