defmodule Psc.Canvas.UnstrCanvasCRDT do
  @moduledoc """
  CRDT-like state application for unstructured canvas `cells` maps.

  Operations are plain maps describing what to update:

    * `%{"type" => "update_cell", "cell_key" => key, "field" => field, "value" => value}`
    * `%{"type" => "update_name", "value" => value}`
    * `%{"type" => "update_description", "value" => value}`

  State shape notes (kept consistent across editor, templates and replay):

    * Cell data lives at **flat top-level keys** (`cells[cell_key][field]`),
      matching the default PSC structure created by `create_unstr_canvas/2`
      and the shape produced by `Canvas.instantiate_template/2`.
    * The canvas title/description edited in the editor live under the
      reserved `"$name"` / `"$description"` keys (the editor reads these
      into its `@c_name` / `@c_desc` assigns).
  """

  alias Psc.Canvas.UnstrCanvasEvent
  alias Psc.Repo
  import Ecto.Query

  def load_events(unstr_canvas_id) do
    from(e in UnstrCanvasEvent,
      where: e.unstr_canvas_id == ^unstr_canvas_id,
      order_by: [asc: e.seq]
    )
    |> Repo.all()
  end

  def apply_operation(event, cells) when is_struct(event) do
    apply_operation(event.operation, cells)
  end

  def apply_operation(
        %{"type" => "update_cell", "cell_key" => cell_key, "field" => field, "value" => value},
        cells
      ) do
    cell_data = cells[cell_key] || %{}
    updated_cell = Map.put(cell_data, field, value)
    Map.put(cells, cell_key, updated_cell)
  end

  def apply_operation(%{"type" => "update_name", "value" => value}, cells) do
    Map.put(cells, "$name", value)
  end

  def apply_operation(%{"type" => "update_description", "value" => value}, cells) do
    Map.put(cells, "$description", value)
  end

  def apply_operation(_op, cells), do: cells

  @doc """
  Rebuilds the cells map by folding a list of events (or event structs)
  over an initial state.
  """
  def rebuild_state(events, initial_state \\ %{}) do
    Enum.reduce(events, initial_state, &apply_operation/2)
  end
end
