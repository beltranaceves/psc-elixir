defmodule PscWeb.RedirectControllerTest do
  use PscWeb.ConnCase, async: true

  setup :register_and_log_in_user

  test "redirects the old canvas list path", %{conn: conn} do
    conn = get(conn, "/canvases")
    assert redirected_to(conn) == ~p"/canvas"
  end

  test "redirects an old canvas path, keeping the id", %{conn: conn} do
    id = Ecto.UUID.generate()
    conn = get(conn, "/canvases/#{id}")
    assert redirected_to(conn) == ~p"/canvas/#{id}"
  end
end
