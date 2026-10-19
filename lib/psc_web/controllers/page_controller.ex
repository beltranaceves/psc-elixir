defmodule PscWeb.PageController do
  use PscWeb, :controller

  # The stock Phoenix welcome page is gone — "/" is an app entry point that
  # routes users to their workspace (or the login page when anonymous).
  def home(conn, _params) do
    case conn.assigns[:current_scope] do
      %{user: user} when not is_nil(user) -> redirect(conn, to: ~p"/canvas")
      _ -> redirect(conn, to: ~p"/users/log-in")
    end
  end
end
