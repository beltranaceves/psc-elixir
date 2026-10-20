defmodule PscWeb.MarkdownEditorTest do
  @moduledoc """
  The reusable Markdown editor.

  The parts are wired through data attributes, so more than one editor can
  live on the same page — a note inside the canvas editor, for instance.
  """

  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias PscWeb.Components.MarkdownEditor

  defp one_editor(assigns) do
    ~H"""
    <MarkdownEditor.markdown_editor
      id="first"
      input_id="first-input"
      form_id="first-form"
      preview_id="first-preview"
      content="One"
      html="<p>One</p>"
      current_user_id={1}
      change_event="update_content"
    />
    """
  end

  defp two_editors(assigns) do
    ~H"""
    <div>
      <MarkdownEditor.markdown_editor
        id="first"
        input_id="first-input"
        form_id="first-form"
        preview_id="first-preview"
        content="One"
        html="<p>One</p>"
        current_user_id={1}
        change_event="update_content"
      />
      <MarkdownEditor.markdown_editor
        id="second"
        input_id="second-input"
        form_id="second-form"
        preview_id="second-preview"
        content="Two"
        html="<p>Two</p>"
        current_user_id={1}
        change_event="update_content"
      />
    </div>
    """
  end

  test "renders the editor and its preview" do
    html = rendered_to_string(one_editor(%{}))

    assert html =~ ~s(id="first")
    assert html =~ ~s(id="first-input")
    assert html =~ ~s(id="first-form")
    assert html =~ ~s(id="first-preview")
    assert html =~ "One"
  end

  test "two editors can live on the same page, each with its own parts" do
    html = rendered_to_string(two_editors(%{}))

    # Every part is scoped to its own editor.
    assert html =~ ~s(id="first-input")
    assert html =~ ~s(id="second-input")
    assert html =~ ~s(id="first-preview")
    assert html =~ ~s(id="second-preview")
    assert html =~ "One"
    assert html =~ "Two"
  end

  test "the hook is wired with the events the LiveView owns" do
    html = rendered_to_string(one_editor(%{}))

    assert html =~ ~s(phx-hook="MarkdownEditorHook")
    assert html =~ ~s(data-render-event="document_rendered")
    assert html =~ ~s(data-update-event="content_updated")
    assert html =~ ~s(data-preview-event="render_document")
  end
end
