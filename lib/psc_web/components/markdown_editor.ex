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
  """
  attr :id, :string, required: true
  attr :input_id, :string, required: true
  attr :form_id, :string, required: true
  attr :preview_id, :string, required: true
  attr :content, :string, default: ""
  attr :html, :string, default: ""
  attr :current_user_id, :integer, default: nil
  attr :change_event, :string, required: true
  attr :preview_event, :string, default: "render_document"
  attr :render_event, :string, default: "document_rendered"
  attr :update_event, :string, default: "content_updated"
  attr :empty_message, :string, default: "Start writing in the editor."
  attr :preview_label, :string, default: "Edit content"
  attr :placeholder, :string, default: "Start writing in Markdown..."
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
      class={["flex min-h-0 flex-1 flex-col", @class]}
    >
      <div class="relative min-h-0 flex-1">
        <.form
          for={%{}}
          id={@form_id}
          phx-change={@change_event}
          phx-debounce="300"
          class="absolute inset-0 hidden h-full"
          data-editor-form
        >
          <textarea
            name="content"
            id={@input_id}
            data-editor-input
            data-current-user-id={@current_user_id}
            class="h-full w-full resize-none border-0 bg-base-100 p-6 font-mono text-sm leading-6 text-base-content placeholder-base-content/40 focus:outline-none focus:ring-2 focus:ring-primary focus:ring-inset"
            placeholder={@placeholder}
            value={@content}
          ></textarea>
        </.form>

        <div
          id={@preview_id}
          role="button"
          tabindex="0"
          aria-label={@preview_label}
          class="absolute inset-0 cursor-text overflow-y-auto bg-base-100 p-6 transition-colors hover:bg-base-200/30"
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
end
