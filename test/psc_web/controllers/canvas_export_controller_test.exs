defmodule PscWeb.CanvasExportControllerTest do
  use PscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Psc.AccountsFixtures
  alias Psc.Canvas
  alias Psc.InsightsFixtures

  setup :register_and_log_in_user

  defp canvas_for(user) do
    {:ok, canvas} =
      Canvas.create_unstr_canvas(user.id, %{
        "name" => "Export test",
        "cells" => InsightsFixtures.cells([{"Problem", "Slow onboarding"}])
      })

    canvas
  end

  test "downloads the ticked sections as a Markdown file", %{conn: conn, user: user} do
    canvas = canvas_for(user)

    # The form sends a hidden "false" before each ticked box's "true".
    conn =
      get(conn, ~p"/canvas/#{canvas.id}/export.md", %{
        "sections" => %{"canvas" => "true", "notes" => "false"}
      })

    assert response(conn, 200) =~ "### Problem\n\nSlow onboarding"
    refute response(conn, 200) =~ "## Notes"
    assert ["text/markdown; charset=utf-8"] = get_resp_header(conn, "content-type")

    assert get_resp_header(conn, "content-disposition") == [
             ~s(attachment; filename="export-test.md")
           ]
  end

  test "nothing ticked is a bad request", %{conn: conn, user: user} do
    canvas = canvas_for(user)

    conn = get(conn, ~p"/canvas/#{canvas.id}/export.md", %{"sections" => %{"canvas" => "false"}})

    assert response(conn, 400)
  end

  test "another account's canvas is not found", %{conn: conn} do
    canvas = canvas_for(AccountsFixtures.user_fixture())

    conn = get(conn, ~p"/canvas/#{canvas.id}/export.md", %{"sections" => %{"canvas" => "true"}})

    assert response(conn, 404)
  end

  test "the editor's Export menu opens the section picker", %{conn: conn, user: user} do
    canvas = canvas_for(user)
    {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}")

    refute has_element?(lv, "#markdown-export-dialog")
    lv |> element("#export-markdown") |> render_click()

    assert has_element?(
             lv,
             ~s(#markdown-export-form[action="/canvas/#{canvas.id}/export.md"][method="get"])
           )

    assert has_element?(lv, "#markdown-export-canvas[checked]")
    refute has_element?(lv, "#markdown-export-notes[checked]")

    # Unticking the last section disables Download.
    lv
    |> form("#markdown-export-form", sections: %{canvas: "false"})
    |> render_change()

    assert has_element?(lv, "#markdown-export-download[disabled]")

    lv
    |> form("#markdown-export-form", sections: %{canvas: "true", agent: "true"})
    |> render_change()

    refute has_element?(lv, "#markdown-export-download[disabled]")
    assert has_element?(lv, "#markdown-export-agent[checked]")

    lv |> element("#markdown-export-download") |> render_click()
    refute has_element?(lv, "#markdown-export-dialog")
  end
end
