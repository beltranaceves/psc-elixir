defmodule PscWeb.RedirectController do
  @moduledoc """
  Keeps old URLs working after route renames.

  The canvas routes moved from `/canvas` to `/canvas`; bookmarks and links
  from an older release still resolve.
  """
  use PscWeb, :controller

  def canvases(conn, _params), do: redirect(conn, to: ~p"/canvas")
  def canvas(conn, %{"id" => id}), do: redirect(conn, to: ~p"/canvas/#{id}")
end
