defmodule PscWeb.CanvasBackdropController do
  @moduledoc """
  Serves an image board's backdrop from our own origin, for the PNG/SVG
  export (see `Psc.Canvas.BackdropFetch`).

  It only ever fetches the backdrop stored on the canvas in the URL, and only
  for someone who can open that canvas. A site path or a `data:` URI needs no
  proxy, so the route 404s for those.
  """
  use PscWeb, :controller

  alias Psc.Canvas
  alias Psc.Canvas.BackdropFetch
  alias Psc.Canvas.Structure

  def show(conn, %{"id" => id}) do
    canvas = Canvas.get_unstr_canvas_with_author(id)
    email = conn.assigns.current_scope.user.email

    with true <- canvas != nil and Canvas.can_access_unstr_canvas?(canvas, email),
         url when is_binary(url) <- Structure.backdrop(Canvas.get_unstr_canvas_content(id)).url,
         true <- BackdropFetch.external?(url) do
      serve(conn, BackdropFetch.fetch(url))
    else
      _other -> send_resp(conn, 404, "Not found")
    end
  end

  # The picture is served from our origin, so an SVG opened directly must not
  # run scripts: the sandbox CSP and nosniff keep it an inert image.
  defp serve(conn, {:ok, content_type, body}) do
    conn
    |> put_resp_content_type(content_type, nil)
    |> put_resp_header("cache-control", "private, max-age=300")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_header(
      "content-security-policy",
      "default-src 'none'; style-src 'unsafe-inline'; sandbox"
    )
    |> send_resp(200, body)
  end

  defp serve(conn, {:error, _reason}) do
    send_resp(conn, 502, "The backdrop picture could not be fetched")
  end
end
