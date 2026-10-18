defmodule PscWeb.MarkdownTest do
  use ExUnit.Case, async: true

  alias PscWeb.Markdown

  test "renders Markdown as HTML" do
    html = Markdown.render("# Heading\n\n**Important**")

    assert html =~ "<h1>\nHeading</h1>"
    assert html =~ "<strong>Important</strong>"
  end

  test "renders a placeholder for empty content" do
    assert Markdown.render("") =~ "Click to edit"
    assert Markdown.render(nil, empty_message: "Start writing") =~ "Start writing"
  end

  test "escapes content when Markdown rendering reports an error" do
    assert Markdown.render("<script>alert('xss')</script>") =~ "&lt;script&gt;"
  end
end
