defmodule PscWeb.PageController do
  use PscWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
