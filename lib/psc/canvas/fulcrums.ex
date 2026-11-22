defmodule Psc.Canvas.Fulcrums do
  @moduledoc """
  Fulcrums: named, coloured sets of cells that a canvas can highlight.

  A template defines them, and its canvases get a copy, like the cells. They
  live in the cells map beside the structure, so they are part of every
  version and travel through the event log:

    * `"fulcrums"` — the list of `%{"id", "name", "color", "cells"}`, where
      `"color"` is an accent token and `"cells"` the highlighted cell keys.
    * `"fulcrum_mode"` — `"single"` (one active fulcrum at a time),
      `"multiple"`, or `"off"` (no picker, no highlights, no editing on the
      canvas; the list is kept), a template setting the canvas inherits.
    * `"$active_fulcrums"` — the ids currently highlighted, shared by everyone
      on the canvas. Like `"$name"` it is a view choice, not content: changing
      it does not start a version, and loading a version keeps it.

  This module only transforms maps; the designer edits a template's list with
  it and the canvas sends the result as a `set_fulcrums` operation.
  """

  alias Psc.Canvas.Accent
  alias Psc.Canvas.Structure

  @modes ["off", "single", "multiple"]
  @max_name 60

  def modes, do: @modes
  def default_mode, do: "single"

  def mode(map), do: normalize_mode(map["fulcrum_mode"])

  def normalize_mode(mode) when mode in @modes, do: mode
  def normalize_mode(_mode), do: default_mode()

  @doc "Whether the canvas (or template) uses fulcrums at all."
  def enabled?(map), do: mode(map) != "off"

  def label("off"), do: "Off"
  def label("single"), do: "One at a time"
  def label("multiple"), do: "Several at once"

  def blurb("off"), do: "Fulcrums are turned off: canvases show no fulcrums and cannot add them."
  def blurb("single"), do: "Picking a fulcrum replaces the one that is highlighted."
  def blurb(_mode), do: "Fulcrums add up: several can be highlighted at once."

  @doc "The fulcrums of a canvas or template map."
  def list(map), do: Map.get(map, "fulcrums") || []

  @doc """
  The ids that are highlighted, limited to fulcrums that still exist. Nothing
  is highlighted while fulcrums are off.
  """
  def active_ids(map) do
    if enabled?(map) do
      ids = MapSet.new(list(map), & &1["id"])

      map
      |> Map.get("$active_fulcrums", [])
      |> List.wrap()
      |> Enum.filter(&MapSet.member?(ids, &1))
    else
      []
    end
  end

  @doc """
  The highlights to draw: cell key to the colours of the active fulcrums that
  include it, in the fulcrums' order.
  """
  def highlights(map) do
    active = MapSet.new(active_ids(map))

    for fulcrum <- list(map),
        MapSet.member?(active, fulcrum["id"]),
        key <- fulcrum["cells"] || [],
        reduce: %{} do
      acc -> Map.update(acc, key, [fulcrum["color"]], &(&1 ++ [fulcrum["color"]]))
    end
  end

  @doc """
  The active ids after clicking a fulcrum: in single mode it replaces the
  current one (or clears it when it was the one); in multiple mode it toggles.
  """
  def toggle_active(map, id) do
    active = active_ids(map)

    cond do
      id in active -> List.delete(active, id)
      mode(map) == "single" -> [id]
      true -> active ++ [id]
    end
  end

  @doc "What a template passes on to the canvases made from it."
  def template_attrs(lm) do
    %{"fulcrums" => normalize(list(lm), lm), "fulcrum_mode" => mode(lm)}
  end

  ## Editing the list (used by the designer and the canvas dialog)

  def add(fulcrums) do
    used = MapSet.new(fulcrums, & &1["color"])
    color = Enum.find(Accent.tokens(), hd(Accent.tokens()), &(not MapSet.member?(used, &1)))

    fulcrums ++
      [
        %{
          "id" => next_id(fulcrums),
          "name" => "Fulcrum #{length(fulcrums) + 1}",
          "color" => color,
          "cells" => []
        }
      ]
  end

  def remove(fulcrums, id), do: Enum.reject(fulcrums, &(&1["id"] == id))

  def rename(fulcrums, id, name) do
    update(fulcrums, id, &Map.put(&1, "name", String.slice(name || "", 0, @max_name)))
  end

  def set_color(fulcrums, id, color) do
    if color in Accent.tokens(),
      do: update(fulcrums, id, &Map.put(&1, "color", color)),
      else: fulcrums
  end

  def toggle_cell(fulcrums, id, key) do
    update(fulcrums, id, fn fulcrum ->
      cells = fulcrum["cells"] || []

      Map.put(
        fulcrum,
        "cells",
        if(key in cells, do: List.delete(cells, key), else: cells ++ [key])
      )
    end)
  end

  @doc """
  Cleans a list against a map: drops malformed entries and cell keys the map
  no longer has, and gives every fulcrum an id, a name and a known colour.
  """
  def normalize(fulcrums, map) when is_list(fulcrums) do
    keys = map |> Structure.cells() |> Map.keys() |> MapSet.new()

    fulcrums
    |> Enum.filter(&is_map/1)
    |> Enum.with_index(1)
    |> Enum.map(fn {fulcrum, index} ->
      %{
        "id" => to_string(fulcrum["id"] || "f#{index}"),
        "name" => fulcrum["name"] |> to_string() |> String.slice(0, @max_name),
        "color" => if(fulcrum["color"] in Accent.tokens(), do: fulcrum["color"], else: "amber"),
        "cells" =>
          fulcrum
          |> Map.get("cells", [])
          |> List.wrap()
          |> Enum.filter(&MapSet.member?(keys, &1))
          |> Enum.uniq()
      }
    end)
  end

  def normalize(_fulcrums, _map), do: []

  defp update(fulcrums, id, fun) do
    Enum.map(fulcrums, fn
      %{"id" => ^id} = fulcrum -> fun.(fulcrum)
      fulcrum -> fulcrum
    end)
  end

  defp next_id(fulcrums) do
    max =
      fulcrums
      |> Enum.map(fn f ->
        f["id"] |> to_string() |> String.trim_leading("f") |> Integer.parse()
      end)
      |> Enum.flat_map(fn
        {n, ""} -> [n]
        _other -> []
      end)
      |> Enum.max(fn -> 0 end)

    "f#{max + 1}"
  end
end
