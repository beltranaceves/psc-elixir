defmodule Psc.Canvas.UnstrCanvasCRDT do
  @moduledoc """
  CRDT-like state application for unstructured canvas `cells` maps.

  Operations are plain maps describing what to update:

    * `%{"type" => "update_cell", "cell_key" => key, "field" => field, "value" => value}`
    * `%{"type" => "update_name", "value" => value}`
    * `%{"type" => "update_description", "value" => value}`

  Structure operations (owner-authored, applied by every client) carry their ids and
  labels inside the payload, so applying the events in sequence order always reaches the
  same state:

    * `%{"type" => "add_row", "id" => id, "label" => label}` (and `add_column`)
    * `%{"type" => "remove_row", "id" => id}` (and `remove_column`) — idempotent
    * `%{"type" => "update_row_label", "id" => id, "label" => label}` (and `update_column_label`)
    * `%{"type" => "set_row_accent", "id" => id, "accent" => token}` (and `set_column_accent`)
    * `%{"type" => "update_cell_label", "cell_key" => key, "label" => label}`
    * `%{"type" => "add_cell_field", "cell_key" => key, "field" => field}`
    * `%{"type" => "remove_cell_field", "cell_key" => key, "field" => field}`
    * `%{"type" => "update_cell_field_title", "cell_key" => key, "field" => field, "title" => title}`

  State shape notes (kept consistent across editor, templates and replay):

    * Cell data lives at **flat top-level keys** (`cells[cell_key][field]`),
      matching the default PSC structure created by `create_unstr_canvas/2`
      and the shape produced by `Canvas.instantiate_template/2`.
    * The structure lives beside them: `cells["rows"]`, `cells["columns"]`
      and `cells["layout"]` (a matrix of cell keys, one row per entry).
    * The canvas title/description edited in the editor live under the
      reserved `"$name"` / `"$description"` keys (the editor reads these
      into its `@c_name` / `@c_desc` assigns).
  """

  alias Psc.Canvas.UnstrCanvasEvent
  alias Psc.Repo
  import Ecto.Query

  # Keys of a cell that are metadata, not content: never addable or removable
  # as fields. `name` is the legacy label alias, `semantics` the removed field
  # of ADR-012 — both kept reserved so old cells cannot gain them back.
  @reserved_cell_keys ["row", "column", "label", "name", "semantics", "titles"]

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

  ## Structure operations

  def apply_operation(%{"type" => "add_row", "id" => id} = op, cells) do
    rows = Map.get(cells, "rows", [])
    columns = Map.get(cells, "columns", [])
    layout = Map.get(cells, "layout", [])

    if Enum.any?(rows, &(&1["id"] == id)) do
      cells
    else
      ordered_keys = Enum.map(columns, &"#{id}_#{&1["id"]}")

      entries =
        ordered_keys
        |> Enum.zip(columns)
        |> Map.new(fn {key, col} ->
          {key, %{"row" => id, "column" => col["id"], "label" => key}}
        end)

      cells
      |> Map.put("rows", rows ++ [%{"id" => id, "label" => Map.get(op, "label", "")}])
      |> Map.put("layout", layout ++ [ordered_keys])
      |> put_new_cells(entries)
    end
  end

  def apply_operation(%{"type" => "add_column", "id" => id} = op, cells) do
    rows = Map.get(cells, "rows", [])
    columns = Map.get(cells, "columns", [])
    layout = Map.get(cells, "layout", [])

    if Enum.any?(columns, &(&1["id"] == id)) do
      cells
    else
      entries =
        rows
        |> Map.new(fn row ->
          key = "#{row["id"]}_#{id}"
          {key, %{"row" => row["id"], "column" => id, "label" => key}}
        end)

      # Every layout row gains the new key, in the row's own position at the end.
      new_layout =
        layout
        |> Enum.with_index()
        |> Enum.map(fn {row_keys, ri} ->
          case Enum.at(rows, ri) do
            %{"id" => row_id} -> row_keys ++ ["#{row_id}_#{id}"]
            _other -> row_keys
          end
        end)

      cells
      |> Map.put("columns", columns ++ [%{"id" => id, "label" => Map.get(op, "label", "")}])
      |> Map.put("layout", new_layout)
      |> put_new_cells(entries)
    end
  end

  def apply_operation(%{"type" => "remove_row", "id" => id}, cells) do
    rows = Map.get(cells, "rows", [])

    case Enum.find_index(rows, &(&1["id"] == id)) do
      nil ->
        cells

      ri ->
        cells
        |> Map.put("rows", List.delete_at(rows, ri))
        |> Map.put("layout", List.delete_at(Map.get(cells, "layout", []), ri))
        |> drop_cells_by("row", id)
    end
  end

  def apply_operation(%{"type" => "remove_column", "id" => id}, cells) do
    columns = Map.get(cells, "columns", [])

    case Enum.find_index(columns, &(&1["id"] == id)) do
      nil ->
        cells

      ci ->
        cells
        |> Map.put("columns", List.delete_at(columns, ci))
        |> Map.put("layout", Enum.map(Map.get(cells, "layout", []), &List.delete_at(&1, ci)))
        |> drop_cells_by("column", id)
    end
  end

  def apply_operation(%{"type" => "update_row_label", "id" => id, "label" => label}, cells) do
    update_structure_def(cells, "rows", id, fn row -> Map.put(row, "label", label) end)
  end

  def apply_operation(%{"type" => "update_column_label", "id" => id, "label" => label}, cells) do
    update_structure_def(cells, "columns", id, fn col -> Map.put(col, "label", label) end)
  end

  def apply_operation(%{"type" => "set_row_accent", "id" => id, "accent" => token}, cells) do
    if valid_accent?(token) do
      update_structure_def(cells, "rows", id, fn row -> Map.put(row, "accent", token) end)
    else
      cells
    end
  end

  def apply_operation(%{"type" => "set_column_accent", "id" => id, "accent" => token}, cells) do
    if valid_accent?(token) do
      update_structure_def(cells, "columns", id, fn col ->
        Map.put(col, "accent", token)
      end)
    else
      cells
    end
  end

  def apply_operation(
        %{"type" => "update_cell_label", "cell_key" => key, "label" => label},
        cells
      ) do
    update_cell_data(cells, key, fn cell -> Map.put(cell, "label", label) end)
  end

  def apply_operation(%{"type" => "add_cell_field", "cell_key" => key, "field" => field}, cells) do
    update_cell_data(cells, key, fn cell ->
      cond do
        field in @reserved_cell_keys ->
          cell

        Map.has_key?(cell, field) ->
          cell

        true ->
          cell
          |> Map.put(field, "")
          |> Map.put("titles", Map.put(cell["titles"] || %{}, field, ""))
      end
    end)
  end

  def apply_operation(
        %{"type" => "remove_cell_field", "cell_key" => key, "field" => field},
        cells
      ) do
    update_cell_data(cells, key, fn cell ->
      if field in @reserved_cell_keys do
        cell
      else
        titles = Map.delete(cell["titles"] || %{}, field)

        cell
        |> Map.delete(field)
        |> then(
          &if titles == %{}, do: Map.delete(&1, "titles"), else: Map.put(&1, "titles", titles)
        )
      end
    end)
  end

  def apply_operation(
        %{
          "type" => "update_cell_field_title",
          "cell_key" => key,
          "field" => field,
          "title" => title
        },
        cells
      ) do
    update_cell_data(cells, key, fn cell ->
      Map.put(cell, "titles", Map.put(cell["titles"] || %{}, field, title))
    end)
  end

  def apply_operation(_op, cells), do: cells

  defp valid_accent?(nil), do: true
  defp valid_accent?(token), do: Psc.Canvas.Accent.valid?(token)

  # A row's or a column's cells are found by their back-reference, not by their
  # key: the built-in PSC structure keys its cells semantically ("problem",
  # "manifestations"), while instantiated and added cells use "rowId_colId".
  # Both carry "row" and "column", and only cells are maps with them.
  defp drop_cells_by(cells, ref_key, ref_id) do
    Enum.reduce(cells, cells, fn
      {key, data}, acc when is_map(data) ->
        if Map.get(data, ref_key) == ref_id, do: Map.delete(acc, key), else: acc

      _pair, acc ->
        acc
    end)
  end

  # A structure def (a row or a column) is updated in place; an id that is not
  # there leaves the list untouched.
  defp update_structure_def(cells, list_key, id, fun) do
    defs =
      cells
      |> Map.get(list_key, [])
      |> Enum.map(fn
        %{"id" => ^id} = def -> fun.(def)
        def -> def
      end)

    Map.put(cells, list_key, defs)
  end

  defp put_new_cells(cells, entries) do
    Enum.reduce(entries, cells, fn {key, data}, acc -> Map.put_new(acc, key, data) end)
  end

  defp update_cell_data(cells, key, fun) do
    case cells[key] do
      nil -> cells
      cell -> Map.put(cells, key, fun.(cell))
    end
  end

  @doc """
  Rebuilds the cells map by folding a list of events (or event structs)
  over an initial state.
  """
  def rebuild_state(events, initial_state \\ %{}) do
    Enum.reduce(events, initial_state, &apply_operation/2)
  end
end
