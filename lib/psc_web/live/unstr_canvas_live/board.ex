defmodule PscWeb.UnstrCanvasLive.Board do
  @moduledoc """
  The canvas in its layout mode: the table grid, the bento board or the image
  board. The editor tab, the History preview and the image export all render
  it.
  """
  use PscWeb, :html

  alias Psc.Canvas.{Fulcrums, Structure}
  alias PscWeb.UnstrCanvasLive.{Bento, Grid, ImageCanvas}

  # The canvas in its layout mode. The Editor tab renders the live cells; the
  # History tab renders a pivot's snapshot with `read_only?`.
  attr :cells, :map, required: true
  attr :c_name, :string, required: true
  attr :edit_structure?, :boolean, required: true
  attr :structure_accent_picker, :any, default: nil
  attr :colors_picker, :string, default: nil
  attr :hint_editor, :string, default: nil
  attr :presence, :map, required: true
  attr :status, :map, required: true
  attr :can_share?, :boolean, required: true
  attr :status_row?, :boolean, default: false
  attr :focus_cell, :string, default: nil
  attr :user_id, :integer, required: true
  attr :read_only?, :boolean, default: false

  def canvas_board(assigns) do
    # Every version carries its fulcrums, so a preview highlights what was
    # highlighted then.
    assigns = assign(assigns, :highlights, Fulcrums.highlights(assigns.cells))

    ~H"""
    <%= cond do %>
      <% Structure.image?(@cells) -> %>
        <ImageCanvas.board {assigns_to_attributes(assigns)} />
      <% Structure.bento?(@cells) -> %>
        <Bento.board {assigns_to_attributes(assigns)} />
      <% true -> %>
        <Grid.grid {assigns_to_attributes(assigns)} />
    <% end %>
    """
  end
end
