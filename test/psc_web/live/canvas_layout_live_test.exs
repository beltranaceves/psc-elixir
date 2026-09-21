defmodule PscWeb.CanvasLayoutLiveTest do
  use PscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Psc.CanvasFixtures

  setup :register_and_log_in_user

  describe "index" do
    test "renders the canvas layouts page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/canvas-layouts")

      assert html =~ "Canvas Layouts"
    end
  end

  describe "editor" do
    test "renders the layout editor", %{conn: conn} do
      layout = CanvasFixtures.canvas_layout_fixture(%{name: "Grid layout"})

      {:ok, _lv, html} = live(conn, ~p"/canvas-layouts/#{layout.id}")

      assert html =~ "Graphical Layout Editor"
    end

    test "adds a column", %{conn: conn} do
      layout = CanvasFixtures.canvas_layout_fixture(%{name: "Grid layout"})

      {:ok, lv, _html} = live(conn, ~p"/canvas-layouts/#{layout.id}")

      html = lv |> element("button[phx-click='add_column']") |> render_click()

      assert html =~ "Column 1"
    end
  end
end