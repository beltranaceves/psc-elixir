defmodule PscWeb.Components.MarkdownEditor do
  @moduledoc """
  A Markdown editor with an inline preview.

  The editor starts as a preview: a click on the rendered Markdown opens the
  textarea, and blurring it asks the server to re-render the preview. The
  parts are wired through data attributes, so more than one editor can live on
  the same page.

  The three events it exchanges with the owning LiveView are configurable,
  because they belong to that LiveView:

  * `:change_event` — the form's `phx-change` handler, which receives the
    new text.
  * `:preview_event` — the client asks for a re-render when the textarea
    loses focus.
  * `:render_event` / `:update_event` — the server pushes a re-rendered
    preview, and a remote edit, respectively.

  The document editor and the note editor are the two users of it.
  """

  use Phoenix.Component

  import Phoenix.HTML, only: [raw: 1]

  @doc """
  The Markdown editor.

  * `:id` — the id of the wrapper.
  * `:input_id` / `:form_id` / `:preview_id` — the ids of the parts.
  * `:content` — the current text.
  * `:html` — the rendered Markdown, shown in the preview.
  * `:current_user_id` — the editing user, so the editor can ignore its own
    remote updates.
  * `:change_event` / `:preview_event` / `:render_event` / `:update_event` —
    the events exchanged with the owning LiveView.
  * `:empty_message` — what the preview shows when there is no content.
  * `:preview_label` — the accessible label of the preview.
  * `:auto_grow` — grow with the content instead of filling the container.
    The canvas editor fills its pane; a note inside a card grows instead, so
    the card never shows a scrollbar for text that was just written.
  * `:body_class` — the padding and typography shared by the textarea and the
    preview, so a compact editor can be smaller than the canvas one.
  * `:hidden_fields` — extra hidden inputs inside the editor's form, so the
    `phx-change` payload can carry context the form does not know about (the
    index of the note being edited, for instance).
  """
  attr :id, :string, required: true
  attr :input_id, :string, required: true
  attr :form_id, :string, required: true
  attr :preview_id, :string, required: true
  attr :content, :string, default: ""
  attr :html, :string, default: ""
  attr :current_user_id, :integer, default: nil
  attr :change_event, :string, required: true
  attr :input_name, :string, default: "content"

  attr :embedded, :boolean,
    default: false,
    doc: "render inside an existing form. The change_event is then handled by the outer form."

  attr :preview_event, :string, default: "render_document"
  attr :render_event, :string, default: "document_rendered"
  attr :update_event, :string, default: "content_updated"
  attr :empty_message, :string, default: "Start writing in the editor."
  attr :preview_label, :string, default: "Edit content"
  attr :placeholder, :string, default: "Start writing in Markdown..."
  attr :auto_grow, :boolean, default: false
  attr :body_class, :string, default: "p-6 font-mono text-sm leading-6"
  attr :hidden_fields, :list, default: []
  attr :class, :string, default: nil

  def markdown_editor(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="MarkdownEditorHook"
      phx-update="ignore"
      data-render-event={@render_event}
      data-update-event={@update_event}
      data-preview-event={@preview_event}
      data-auto-grow={to_string(@auto_grow)}
      class={
        [
          "flex flex-col overflow-hidden rounded-xl border border-base-content/20 bg-base-200",
          # The focus indication belongs to the frame, not to the textarea: a
          # ring on the textarea is square, and it would cut across the frame's
          # rounded corners.
          "focus-within:ring-2 focus-within:ring-primary/35 focus-within:ring-inset",
          not @auto_grow && "min-h-0 flex-1",
          @class
        ]
      }
    >
      <div class={not @auto_grow && "relative min-h-0 flex-1"}>
        <%= if @embedded do %>
          <div
            id={@form_id}
            data-editor-form
            class={[not @auto_grow && "absolute inset-0 h-full", "hidden"]}
          >
            <.editor_fields
              input_id={@input_id}
              input_name={@input_name}
              content={@content}
              current_user_id={@current_user_id}
              hidden_fields={@hidden_fields}
              body_class={@body_class}
              placeholder={@placeholder}
              fill={not @auto_grow}
            />
          </div>
        <% else %>
          <.form
            for={%{}}
            id={@form_id}
            phx-change={@change_event}
            phx-debounce="300"
            class={[not @auto_grow && "absolute inset-0 h-full", "hidden"]}
            data-editor-form
          >
            <.editor_fields
              input_id={@input_id}
              input_name={@input_name}
              content={@content}
              current_user_id={@current_user_id}
              hidden_fields={@hidden_fields}
              body_class={@body_class}
              placeholder={@placeholder}
              fill={not @auto_grow}
            />
          </.form>
        <% end %>

        <div
          id={@preview_id}
          role="button"
          tabindex="0"
          aria-label={@preview_label}
          class={[
            "cursor-text bg-base-100 transition-colors hover:bg-base-200/30",
            not @auto_grow && "absolute inset-0 overflow-y-auto",
            @body_class
          ]}
          data-editor-preview
        >
          <article
            class="markdown-preview prose dark:prose-invert max-w-none break-words"
            data-editor-content
          >
            {raw(@html)}
          </article>
        </div>
      </div>
    </div>
    """
  end

  attr :input_id, :string, required: true
  attr :input_name, :string, required: true
  attr :content, :string, default: ""
  attr :current_user_id, :integer, default: nil
  attr :hidden_fields, :list, default: []
  attr :body_class, :string, required: true
  attr :placeholder, :string, default: ""
  attr :fill, :boolean, default: false

  defp editor_fields(assigns) do
    ~H"""
    <input :for={{name, value} <- @hidden_fields} type="hidden" name={name} value={value} /> <textarea
      name={@input_name}
      id={@input_id}
      data-editor-input
      data-current-user-id={@current_user_id}
      phx-debounce={if @fill, do: "300", else: nil}
      class={[
        "w-full resize-none border-0 bg-base-100 text-base-content placeholder-base-content/40 focus:outline-none focus:ring-0",
        @fill && "h-full",
        @body_class
      ]}
      placeholder={@placeholder}
      value={@content}
    ></textarea>
    """
  end
end
