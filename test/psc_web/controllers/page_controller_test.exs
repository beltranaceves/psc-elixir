defmodule PscWeb.PageControllerTest do
  use PscWeb.ConnCase

  test "GET / redirects anonymous visitors to log in", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/users/log-in"
  end

  test "GET / redirects logged-in users to their canvases", %{conn: conn} do
    user = Psc.AccountsFixtures.user_fixture()
    conn = conn |> log_in_user(user) |> get(~p"/")

    assert redirected_to(conn) == ~p"/canvases"
  end
end
