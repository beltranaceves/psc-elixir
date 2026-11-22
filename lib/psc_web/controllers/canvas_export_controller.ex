defmodule PscWeb.CanvasExportController do
  @moduledoc """
  Downloads a canvas as Markdown (`Psc.Export.Markdown`).

  The editor's export dialog submits its checkboxes here as `sections[key]`.
  Someone who cannot open the canvas gets a 404, as for the canvas itself.
  """
  use PscWeb, :controller

  alias Psc.Export.Markdown

  def markdown(conn, %{"id" => id} = params) do
    case Markdown.build(conn.assigns.current_scope, id, selected(params)) do
      {:ok, %{filename: filename, markdown: markdown}} ->
        send_download(conn, {:binary, markdown},
          filename: filename,
          content_type: "text/markdown",
          charset: "utf-8"
        )

      {:error, :no_sections} ->
        send_resp(conn, 400, "Choose at least one section to export")

      {:error, :not_found} ->
        send_resp(conn, 404, "Not found")
    end
  end

  # Checkboxes arrive as `sections[canvas]=true`, with a hidden `false` for
  # the unticked ones.
  defp selected(%{"sections" => %{} = sections}) do
    for {key, "true"} <- sections, do: key
  end

  defp selected(_params), do: []
end
