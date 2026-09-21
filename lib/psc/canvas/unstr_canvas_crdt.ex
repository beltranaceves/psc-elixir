defmodule Psc.Canvas.UnstrCanvasCRDT do
  @moduledoc """
  CRDT operations for unstr_canvas maps.
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
end

defmodule Psc.Canvas.UnstrCanvasCRDT do
  @moduledoc """
  CRDT-like state application for UnstrCanvas properties (name, description, cells).
  Operations are maps representing what to update.
  """

  alias Psc.Repo
  import Ecto.Query
  alias Psc.Canvas.UnstrCanvasEvent

  def load_events(canvas_id) do
    from(e in UnstrCanvasEvent,
      where: e.unstr_canvas_id == ^canvas_id,
      order_by: [asc: e.seq]
    )
    |> Repo.all()
  end

  def apply_operation(event, state) when is_struct(event) do
    apply_operation(event.operation, state)
  end

  # Name updates
  def apply_operation(%{"type" => "update_name", "value" => value}, state) do
    Map.put(state, "name", value)
  end

  # Description updates
  def apply_operation(%{"type" => "update_description", "value" => value}, state) do
    Map.put(state, "description", value)
  end

  # Cell updates
  def apply_operation(
        %{"type" => "update_cell", "cell_key" => cell_key, "field" => field, "value" => value},
        state
      ) do
    cells = Map.get(state, "cells") || %{}
    cell_data = Map.get(cells, cell_key) || %{}

    updated_cell = Map.put(cell_data, field, value)
    updated_cells = Map.put(cells, cell_key, updated_cell)

    Map.put(state, "cells", updated_cells)
  end

  # Fallback for unknown
  def apply_operation(_op, state), do: state

  # Rebuild state from events starting from a given initial state (or default empty map)
  def rebuild_state(events, initial_state \\ %{}) do
    Enum.reduce(events, initial_state, &apply_operation/2)
  end
end
