defmodule PscWeb.CanvasImportLiveTest do
  use PscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Psc.Accounts.Scope
  alias Psc.AccountsFixtures
  alias Psc.Canvas
  alias Psc.Export.Markdown
  alias Psc.InsightsFixtures

  setup :register_and_log_in_user

  defp exported_markdown(sections) do
    author = AccountsFixtures.user_fixture()

    {:ok, canvas} =
      Canvas.create_unstr_canvas(author.id, %{
        "name" => "From a file",
        "cells" => InsightsFixtures.cells([{"Problem", "Slow onboarding"}])
      })

    {:ok, %{markdown: markdown}} =
      Markdown.build(Scope.for_user(author), canvas.id, sections)

    markdown
  end

  defp upload(lv, name, content) do
    lv
    |> file_input("#import-canvas-form", :import, [%{name: name, content: content}])
    |> render_upload(name)
  end

  test "importing an export opens the new canvas", %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/canvas")
    assert has_element?(lv, "#import-canvas-button", ~r/^\s*Import\s*$/)

    assert {:error, {:redirect, %{to: "/canvas/" <> id}}} =
             upload(lv, "from-a-file.md", exported_markdown(["canvas"]))

    canvas = Canvas.get_unstr_canvas(id)
    assert canvas.author_id == user.id
    assert canvas.name == "From a file"
  end

  test "a file without canvas data says how to get one", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/canvas")

    html = upload(lv, "notes.md", exported_markdown(["notes"]))

    assert html =~ "Export the canvas again with the Canvas section ticked"
  end

  test "a file that is not Markdown is refused before it uploads", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/canvas")

    assert {:error, [[_ref, :not_accepted]]} =
             lv
             |> file_input("#import-canvas-form", :import, [%{name: "photo.png", content: "png"}])
             |> render_upload("photo.png")

    # In a browser picking the file also sends the form's change event, which
    # explains the refusal and clears the entry.
    assert lv |> form("#import-canvas-form") |> render_change() =~
             "Pick a Markdown (.md) file exported from a canvas."

    assert has_element?(lv, "#import-canvas-button", ~r/^\s*Import\s*$/)
  end
end
