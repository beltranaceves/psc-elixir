defmodule PscWeb.Admin.Filters.CanvasNotesMode do
  @moduledoc """
  Filters the canvases index by how many notes a canvas accepts.
  """

  use Backpex.Filters.Select

  @impl Backpex.Filter
  def label, do: "Notes mode"

  @impl Backpex.Filters.Select
  def prompt, do: "Any mode"

  @impl Backpex.Filters.Select
  def options(_assigns), do: [{"Multi", "multi"}, {"Single", "single"}]
end
