defmodule PscWeb.CanvasLiveTest do
  use PscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Psc.CanvasFixtures

  setup :register_and_log_in_user

  describe "index" do
    test "renders the canvases page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/canvases")

      assert html =~ "Canvases"
    end

    test "lists the current user's canvases", %{conn: conn, user: user} do
      CanvasFixtures.canvas_fixture(%{user: user, name: "Strategy 2026"})

      {:ok, _lv, html} = live(conn, ~p"/canvases")

      assert html =~ "Strategy 2026"
    end
  end

  describe "editor" do
    test "renders the canvas editor for the owner", %{conn: conn, user: user} do
      canvas = CanvasFixtures.canvas_fixture(%{user: user, name: "Strategy 2026"})

      {:ok, _lv, html} = live(conn, ~p"/canvases/#{canvas.id}")

      assert html =~ "Strategy 2026"
    end

    test "exposes the share form to the owner", %{conn: conn, user: user} do
      canvas = CanvasFixtures.canvas_fixture(%{user: user})

      {:ok, lv, _html} = live(conn, ~p"/canvases/#{canvas.id}")

      assert has_element?(lv, "#share-form")
    end
  end
end