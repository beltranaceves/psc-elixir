defmodule PscWeb.CanvasLiveTest do
  use PscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Psc.CanvasFixtures

  setup :register_and_log_in_user

  describe "index" do
    test "renders the canvases page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/psc-canvas")

      assert html =~ "Canvases"
      refute html =~ "Back to Documents"
    end

    test "lists the current user's canvases", %{conn: conn, user: user} do
      CanvasFixtures.canvas_fixture(%{user: user, name: "Strategy 2026"})

      {:ok, _lv, html} = live(conn, ~p"/psc-canvas")

      assert html =~ "Strategy 2026"
    end
  end

  describe "editor" do
    test "renders the canvas editor for the owner", %{conn: conn, user: user} do
      canvas = CanvasFixtures.canvas_fixture(%{user: user, name: "Strategy 2026"})

      {:ok, _lv, html} = live(conn, ~p"/psc-canvas/#{canvas.id}")

      assert html =~ "Strategy 2026"
    end

    test "exposes the share modal to the owner", %{conn: conn, user: user} do
      canvas = CanvasFixtures.canvas_fixture(%{user: user})

      {:ok, lv, _html} = live(conn, ~p"/psc-canvas/#{canvas.id}")

      assert has_element?(lv, "#share-canvas-button .hero-share")

      lv |> element("#share-canvas-button") |> render_click()
      assert has_element?(lv, "#share-canvas-dialog[data-open='true']")

      html =
        lv
        |> form("#share-canvas-dialog-form", %{"email" => "guest@example.com"})
        |> render_submit()

      assert html =~ "Canvas shared with guest@example.com"
    end
  end
end
