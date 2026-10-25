defmodule Psc.Canvas.Structure do
  @moduledoc """
  How a canvas (or a bento template) arranges its cells.

  There are two modes:

    * `:table` — the classic rows × columns matrix (`"rows"`, `"columns"` and
      the `"layout"` cell-key matrix). A canvas keeps its cells flat
      (`cells[key][field]`); a template keeps them nested under `"cells"`.
    * `:bento` — free-form cards on a fixed column grid. Every cell carries a
      `"placement"` (`x`, `y`, `w`, `h`) and an optional `"accent"`, and the
      map itself carries `"layout_mode" => "bento"` and `"bento_columns"`.
      Canvas and template share the same flat shape, so one set of helpers
      serves the runtime, the designer and the previews.

  Every mutation here is pure and deterministic: the same cells and the same
  operation always produce the same result. The CRDT reducer calls these
  functions so a replay in another client cannot diverge.

  Geometry is clamped in one place (`clamp_placement/2`). Callers must never
  clamp on their own: an event is applied by every open client, and a value
  clamped differently in two places would break convergence.
  """

  alias Psc.Canvas.Accent

  # A card's width and height move in half columns/rows, so a resize is fine
  # grained without changing the column grid a template is designed on. The
  # board is rendered with two CSS tracks per column (`tracks_per_unit/0`), and
  # a stored `w` of 1.5 spans three tracks.
  @tracks_per_unit 2
  @unit_px 72
  @row_gap_px 8

  @default_columns 12
  @min_columns 4
  @max_columns 16
  @default_card_width 6
  @default_card_height 2
  @max_card_height 40

  # Table metadata is present on both a canvas and a template. `notes_mode`
  # and `notes` only exist on a template's layout map, and a bento template is
  # flat, so they sit beside the cards there.
  @table_metadata ["rows", "columns", "layout"]

  @bento_metadata @table_metadata ++
                    ["layout_mode", "bento_columns", "cells", "notes_mode", "notes"]

  @metadata_keys @bento_metadata

  # Cell keys that are metadata, not content, in both modes. `placement` and
  # `accent` are how a bento card is drawn; they are never editable fields.
  @reserved_cell_keys [
    "row",
    "column",
    "label",
    "name",
    "semantics",
    "titles",
    "placement",
    "accent"
  ]

  @doc "The metadata keys of a structure map: never cells."
  def metadata_keys, do: @metadata_keys

  @doc "The cell keys that can never be added, removed or rendered as fields."
  def reserved_cell_keys, do: @reserved_cell_keys

  @doc "The layout mode of a cells map (or a template layout map)."
  def mode(map) when is_map(map) do
    if map["layout_mode"] == "bento", do: :bento, else: :table
  end

  def bento?(map), do: mode(map) == :bento

  @doc "The number of grid columns of a bento map."
  def columns(map) do
    map
    |> Map.get("bento_columns", @default_columns)
    |> normalize_int(@default_columns)
    |> min(@max_columns)
    |> max(@min_columns)
  end

  @doc "The smallest and largest column counts a bento may have."
  def column_range, do: @min_columns..@max_columns

  @doc "How many CSS grid tracks one column (or row unit) spans."
  def tracks_per_unit, do: @tracks_per_unit

  @doc "The height of one row unit, in pixels, including one gap."
  def unit_px, do: @unit_px

  @doc "The gap between two cards, in pixels."
  def gap_px, do: @row_gap_px

  @doc "The smallest width or height a card may have, in columns/rows."
  def min_size, do: 1 / @tracks_per_unit

  @doc """
  The CSS grid style of a board.

  Two tracks per unit keep the template's column grid intact while letting a
  card be resized by half a column.
  """
  def board_style(columns) do
    tracks = round(columns * @tracks_per_unit)

    # A card of `h` units spans `2h` tracks and the gaps between them, so the
    # track height subtracts one gap to keep one unit exactly 72px:
    #   2 * 32 + 8 = 72. Half a unit is then 32 + 8 = 40px, half a step.
    gap = @row_gap_px
    row_height = div(@unit_px - gap, @tracks_per_unit)

    # `minmax` rather than a fixed height: a card's `h` is a minimum, so a card
    # holding a long note grows and takes its grid rows with it.
    "--bento-columns: #{columns}; " <>
      "grid-template-columns: repeat(#{tracks}, minmax(0, 1fr)); " <>
      "grid-auto-rows: minmax(#{row_height}px, auto); " <>
      "gap: #{gap}px;"
  end

  @doc "The CSS grid placement of one card."
  def placement_style(card) do
    "grid-column: #{track(card.x) + 1} / span #{track(card.w)}; " <>
      "grid-row: #{track(card.y) + 1} / span #{track(card.h)};"
  end

  @doc "A placement value converted to CSS tracks."
  def track(value), do: round(value * @tracks_per_unit)

  @doc """
  The cells of a map.

  A bento map is flat, exactly like a canvas. A table template nests its cells
  under `"cells"`; a table canvas is flat.
  """
  def cells(map) when is_map(map) do
    case mode(map) do
      :bento ->
        Map.drop(map, @bento_metadata)

      :table ->
        case map["cells"] do
          %{} = nested -> nested
          _other -> Map.drop(map, @table_metadata)
        end
    end
  end

  @doc "The cells of a map, by key."
  def cell(map, key) when is_map(map), do: cells(map)[key]

  @doc "The cell keys, in insertion-independent (sorted) order."
  def cell_keys(map), do: map |> cells() |> Map.keys() |> Enum.sort()

  @doc """
  Every card, in reading order.

  A table derives one card per matrix position (`w` and `h` are 1, `x` and `y`
  are the matrix indices). A bento reads each cell's placement. Either way the
  list is `%{key, label, x, y, w, h, accent}`, sorted by `{y, x, key}`.
  """
  def cards(map) when is_map(map) do
    map
    |> raw_cards()
    |> Enum.sort_by(&{&1.y, &1.x, &1.key})
  end

  defp raw_cards(map) do
    case mode(map) do
      :bento ->
        for {key, cell} <- cells(map) do
          placement = placement(cell)

          %{
            key: key,
            label: label(cell, key),
            x: placement.x,
            y: placement.y,
            w: placement.w,
            h: placement.h,
            accent: cell["accent"]
          }
        end

      :table ->
        layout = map["layout"] || []
        columns = map["columns"] || []
        table_cells = cells(map)

        for {row_keys, y} <- Enum.with_index(layout),
            {key, x} <- Enum.with_index(row_keys),
            is_binary(key) do
          cell = Map.get(table_cells, key, %{})

          %{
            key: key,
            label: label(cell, key),
            x: x,
            y: y,
            w: 1,
            h: 1,
            accent: accent_at(columns, x)
          }
        end
    end
  end

  defp accent_at(columns, index) do
    case Enum.at(columns, index) do
      %{"accent" => accent} -> accent
      _other -> nil
    end
  end

  defp label(cell, key) do
    case cell["label"] do
      label when is_binary(label) and label != "" -> label
      _other -> key
    end
  end

  @doc "One card, by key."
  def card(map, key) do
    Enum.find(cards(map), &(&1.key == key))
  end

  @doc "Whether the structure has nothing to render yet."
  def empty?(map) do
    case mode(map) do
      :bento -> cells(map) == %{}
      :table -> map["rows"] in [nil, []] or map["columns"] in [nil, []]
    end
  end

  @doc """
  The extent of the board: columns and the last used row.

  A table reports its matrix size; a bento reports its column count and the
  deepest card edge.
  """
  def bounds(map) do
    case mode(map) do
      :bento ->
        bottom = map |> cards() |> Enum.map(&(&1.y + &1.h)) |> Enum.max(fn -> 0 end)
        %{columns: columns(map), rows: bottom}

      :table ->
        %{columns: length(map["columns"] || []), rows: length(map["layout"] || [])}
    end
  end

  @doc "A cell's normalized placement. Table cells are one unit at their index."
  def placement(cell) do
    case cell["placement"] do
      %{} = placement ->
        %{
          x: normalize_number(placement["x"], 0),
          y: normalize_number(placement["y"], 0),
          w: placement |> get_number("w", 1) |> snap() |> max(min_size()),
          h: placement |> get_number("h", 1) |> snap() |> max(min_size())
        }

      _other ->
        %{x: 0, y: 0, w: 1, h: 1}
    end
  end

  @doc """
  Clamp a placement to the board.

  The single place geometry is bounded: `w`/`h` are at least one unit, a card
  never extends past the right edge, and `y` never goes negative.
  """
  def clamp_placement(map, placement) do
    board_columns = columns(map)

    w =
      placement
      |> get_number("w", @default_card_width)
      |> snap()
      |> min(board_columns)
      |> max(min_size())

    h =
      placement
      |> get_number("h", @default_card_height)
      |> snap()
      |> min(@max_card_height)
      |> max(min_size())

    # A card starts on a whole column: only its size is half-stepped, so the
    # board keeps a tidy left edge and the neighbours stay easy to read.
    x =
      placement
      |> get_number("x", 0)
      |> round()
      |> max(0)
      |> min(trunc(board_columns - w))

    y = placement |> get_number("y", 0) |> round() |> max(0)

    %{x: x, y: y, w: w, h: h}
  end

  defp get_number(map, key, default) do
    Map.get(map, key) || Map.get(map, String.to_existing_atom(key)) || default
  end

  # Half steps, exactly: 0.5 is representable, so clamping the same value twice
  # always lands on the same number.
  defp snap(value) do
    snapped =
      value
      |> normalize_number(0)
      |> Kernel.*(@tracks_per_unit)
      |> round()
      |> Kernel./(@tracks_per_unit)

    # Store whole sizes as integers: the JSON stays readable, and a replayed
    # event compares equal to the one that produced it.
    if snapped == trunc(snapped), do: trunc(snapped), else: snapped
  end

  defp normalize_number(value, _default) when is_integer(value), do: value
  defp normalize_number(value, _default) when is_float(value), do: value

  defp normalize_number(value, default) when is_binary(value) do
    case Float.parse(value) do
      {number, _rest} -> number
      :error -> default
    end
  end

  defp normalize_number(_value, default), do: default

  defp normalize_int(value, _default) when is_integer(value), do: value
  defp normalize_int(value, _default) when is_float(value), do: trunc(value)

  defp normalize_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _rest} -> int
      :error -> default
    end
  end

  defp normalize_int(_value, default), do: default

  @doc """
  The first free rectangle for a new card.

  Scans row by row from the top, left to right, for a `w` × `h` area that no
  existing card covers. The scan order is deterministic, so two clients that
  add a card concurrently still compute the same slot for the same board.
  """
  def next_slot(map) do
    board_columns = columns(map)
    w = min(@default_card_width, board_columns)
    h = @default_card_height
    occupied = occupied_rects(map)

    Enum.find_value(0..200, %{x: 0, y: 0, w: w, h: h}, fn y ->
      Enum.find_value(0..(board_columns - w), fn x ->
        rect = %{x: x, y: y, w: w, h: h}
        if free?(rect, occupied), do: rect, else: nil
      end)
    end)
  end

  @doc "Whether a rectangle is covered by any other card."
  def overlaps?(map, %{x: x, y: y, w: w, h: h}, except_key \\ nil) do
    rect = %{x: x, y: y, w: w, h: h}

    map
    |> occupied_rects()
    |> Enum.reject(fn {key, _rect} -> key == except_key end)
    |> Enum.any?(fn {_key, other} -> intersects?(rect, other) end)
  end

  defp occupied_rects(map) do
    map
    |> cards()
    |> Enum.map(fn card -> {card.key, %{x: card.x, y: card.y, w: card.w, h: card.h}} end)
  end

  defp free?(rect, occupied), do: not Enum.any?(occupied, &intersects?(rect, elem(&1, 1)))

  defp intersects?(a, b) do
    a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
  end

  ## Mutations (bento only)

  @doc "Add a card. Idempotent: an existing key is left untouched."
  def add_card(map, key, placement \\ nil, label \\ nil, accent \\ nil) when is_map(map) do
    if not bento?(map) or Map.has_key?(cells(map), key) do
      map
    else
      placement = clamp_placement(map, placement || next_slot(map))

      cell =
        %{
          "label" => label || key,
          "content" => "",
          "placement" => stringify(placement)
        }
        |> maybe_put("accent", nilify(accent))

      Map.put(map, key, cell)
    end
  end

  @doc "Remove a card, with its placement and content."
  def remove_card(map, key) when is_map(map) do
    if bento?(map), do: Map.delete(map, key), else: map
  end

  @doc "Move a card. Missing cards are a no-op."
  def move(map, key, x, y) do
    update_card(map, key, fn cell ->
      current = placement(cell)
      put_placement(cell, clamp_placement(map, %{current | x: x, y: y}))
    end)
  end

  @doc """
  Resize a card. Missing cards are a no-op.

  The left edge stays put: a card that is dragged wider than the board shrinks
  to the space left of it rather than jumping to a new column.
  """
  def resize(map, key, w, h) do
    update_card(map, key, fn cell ->
      current = placement(cell)

      width =
        w
        |> normalize_number(current.w)
        |> snap()
        |> min(columns(map) - current.x)
        |> max(min_size())

      put_placement(cell, clamp_placement(map, %{current | w: width, h: h}))
    end)
  end

  @doc "Set a card's accent (`nil` or `\"\"` clears it)."
  def set_accent(map, key, accent) do
    if Accent.valid?(accent) do
      update_card(map, key, &maybe_put(&1, "accent", nilify(accent)))
    else
      map
    end
  end

  @doc "Change the grid width, clamping every card into the new bounds."
  def set_columns(map, count) do
    if bento?(map) do
      count = count |> normalize_int(@default_columns) |> min(@max_columns) |> max(@min_columns)
      map = Map.put(map, "bento_columns", count)

      Enum.reduce(cells(map), map, fn {key, _cell}, acc ->
        update_card(acc, key, fn cell ->
          put_placement(cell, clamp_placement(acc, placement(cell)))
        end)
      end)
    else
      map
    end
  end

  defp update_card(map, key, fun) do
    if bento?(map) do
      case Map.fetch(cells(map), key) do
        {:ok, cell} -> Map.put(map, key, fun.(cell))
        :error -> map
      end
    else
      map
    end
  end

  defp put_placement(cell, placement), do: Map.put(cell, "placement", stringify(placement))

  defp stringify(%{x: x, y: y, w: w, h: h}) do
    %{"x" => x, "y" => y, "w" => w, "h" => h}
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp nilify(value) when value in [nil, ""], do: nil
  defp nilify(value), do: value

  ## Navigation

  @doc """
  The cards reachable from `key` with a swipe or an arrow key.

  The rule is geometric and deterministic: a neighbour on an axis must be on
  that side of the card and share some span on the other axis. When nothing
  qualifies, `right` and `down` fall back to reading order (and `left`/`up` to
  reverse reading order), so navigation never gets stuck at a ragged edge.
  """
  def neighbours(map, key) do
    case mode(map) do
      :table -> table_neighbours(map, key)
      :bento -> bento_neighbours(map, key)
    end
  end

  # A table never wraps: the last cell of a row has nothing to its right, the
  # way the DOM-based swipe always behaved.
  defp table_neighbours(map, key) do
    at =
      map
      |> cards()
      |> Map.new(fn card -> {{card.x, card.y}, card.key} end)

    case Enum.find(cards(map), &(&1.key == key)) do
      nil ->
        %{left: nil, right: nil, up: nil, down: nil}

      card ->
        %{
          left: Map.get(at, {card.x - 1, card.y}),
          right: Map.get(at, {card.x + 1, card.y}),
          up: Map.get(at, {card.x, card.y - 1}),
          down: Map.get(at, {card.x, card.y + 1})
        }
    end
  end

  # A ragged bento can have no card directly beside another. Horizontal swipes
  # fall back to reading order so they never get stuck; vertical swipes stay
  # geometric, because wrapping a swipe down at the bottom would be confusing.
  defp bento_neighbours(map, key) do
    list = cards(map)
    index = Enum.find_index(list, &(&1.key == key))

    case index do
      nil ->
        %{left: nil, right: nil, up: nil, down: nil}

      index ->
        card = Enum.at(list, index)

        %{
          left: axis_neighbour(list, card, :left) || previous_key(list, index),
          right: axis_neighbour(list, card, :right) || next_key(list, index),
          up: axis_neighbour(list, card, :up),
          down: axis_neighbour(list, card, :down)
        }
    end
  end

  defp previous_key(list, index) when index > 0 do
    list |> Enum.at(index - 1) |> Map.get(:key)
  end

  defp previous_key(_list, _index), do: nil

  defp next_key(list, index) do
    case Enum.at(list, index + 1) do
      nil -> nil
      card -> card.key
    end
  end

  defp axis_neighbour(list, card, direction) do
    list
    |> Enum.reject(&(&1.key == card.key))
    |> Enum.filter(&on_side?(&1, card, direction))
    |> Enum.min_by(&distance(&1, card, direction), fn -> nil end)
    |> case do
      nil -> nil
      neighbour -> neighbour.key
    end
  end

  defp on_side?(other, card, :left),
    do: other.x + other.w <= card.x and band_overlaps?(other, card)

  defp on_side?(other, card, :right),
    do: other.x >= card.x + card.w and band_overlaps?(other, card)

  defp on_side?(other, card, :up),
    do: other.y + other.h <= card.y and column_overlaps?(other, card)

  defp on_side?(other, card, :down),
    do: other.y >= card.y + card.h and column_overlaps?(other, card)

  defp band_overlaps?(a, b), do: a.y < b.y + b.h and b.y < a.y + a.h
  defp column_overlaps?(a, b), do: a.x < b.x + b.w and b.x < a.x + a.w

  defp distance(other, card, :left), do: card.x - (other.x + other.w)
  defp distance(other, card, :right), do: other.x - (card.x + card.w)
  defp distance(other, card, :up), do: card.y - (other.y + other.h)
  defp distance(other, card, :down), do: other.y - (card.y + card.h)

  ## Validation

  @doc """
  Validate a canvas's cells or a template's layout map.

  Returns `:ok` or `{:error, field, message}`.
  """
  def validate(map) do
    case mode(map) do
      :bento -> validate_bento(map)
      :table -> validate_table(map)
    end
  end

  @doc """
  Validate a template layout map.

  Table templates must be a complete matrix; bento templates must have valid
  placements and at least one card. Both require unique fields per card and
  reject unknown accents.
  """
  def validate_template(map) do
    with :ok <- validate_not_empty(map),
         :ok <- validate(map),
         :ok <- validate_fields(map),
         :ok <- validate_accents(map) do
      :ok
    end
  end

  defp validate_not_empty(map) do
    case mode(map) do
      :bento ->
        if cells(map) == %{},
          do: {:error, :layout_map, "template must have at least one card"},
          else: :ok

      :table ->
        cond do
          (map["rows"] || []) == [] ->
            {:error, :layout_map, "template must have at least one row"}

          (map["columns"] || []) == [] ->
            {:error, :layout_map, "template must have at least one column"}

          true ->
            :ok
        end
    end
  end

  defp validate_bento(map) do
    board_columns = columns(map)

    if valid_columns?(map) do
      map
      |> cells()
      |> Enum.reduce_while(:ok, fn {key, cell}, _acc ->
        case validate_bento_cell(key, cell, board_columns) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)
    else
      {:error, :layout_map, "bento must have between #{@min_columns} and #{@max_columns} columns"}
    end
  end

  defp valid_columns?(map) do
    case map["bento_columns"] do
      nil -> true
      count when is_integer(count) -> count in @min_columns..@max_columns
      _other -> false
    end
  end

  defp validate_bento_cell(key, cell, board_columns) do
    placement = cell["placement"]

    cond do
      not is_map(placement) ->
        {:error, :layout_map, "card #{key} has no placement"}

      not valid_placement_units?(placement) ->
        {:error, :layout_map,
         "card #{key} must start on a column and be a whole number of half columns wide"}

      placement["w"] < min_size() or placement["h"] < min_size() ->
        {:error, :layout_map, "card #{key} must be at least half a unit wide and tall"}

      placement["x"] < 0 or placement["y"] < 0 ->
        {:error, :layout_map, "card #{key} is placed outside the board"}

      placement["x"] + placement["w"] > board_columns ->
        {:error, :layout_map, "card #{key} extends past the board's #{board_columns} columns"}

      not valid_label?(cell["label"]) ->
        {:error, :layout_map, "card #{key} has an invalid label"}

      true ->
        :ok
    end
  end

  # A card starts on a whole column, and its size is a multiple of half a
  # column - the granularity a resize moves in.
  defp valid_placement_units?(placement) do
    Enum.all?(["x", "y"], &is_number(placement[&1])) and
      Enum.all?(["x", "y"], &(placement[&1] == round(placement[&1]))) and
      Enum.all?(["w", "h"], &is_number(placement[&1])) and
      Enum.all?(
        ["w", "h"],
        &(abs(placement[&1] * @tracks_per_unit - round(placement[&1] * @tracks_per_unit)) < 1.0e-9)
      )
  end

  defp valid_label?(nil), do: true
  defp valid_label?(label), do: is_binary(label)

  defp validate_table(map) do
    rows = map["rows"] || []
    columns = map["columns"] || []
    layout = map["layout"] || []

    cond do
      not is_list(layout) or not Enum.all?(layout, &is_list/1) ->
        {:error, :layout_map, "Layout must be a 2D array of cell keys"}

      layout != [] and
          (length(layout) != length(rows) or
             Enum.any?(layout, fn row -> length(row) != length(columns) end)) ->
        {:error, :layout_map, "every grid position must have a cell key"}

      Enum.any?(layout, fn row -> Enum.any?(row, &is_nil/1) end) ->
        {:error, :layout_map, "every grid position must have a cell key"}

      true ->
        validate_table_cells(layout, map)
    end
  end

  defp validate_table_cells(layout, map) do
    keys = layout |> List.flatten() |> Enum.uniq()
    known = cells(map)
    missing = Enum.reject(keys, &Map.has_key?(known, &1))

    if missing == [] do
      :ok
    else
      {:error, :cells, "Missing cell data for keys: #{Enum.join(missing, ", ")}"}
    end
  end

  defp validate_fields(map) do
    map
    |> cells()
    |> Enum.find_value(:ok, fn {_key, cell} ->
      fields = cell["fields"] || []

      if length(fields) != length(Enum.uniq(fields)) do
        {:error, :layout_map, "field keys must be unique within a cell"}
      end
    end)
  end

  defp validate_accents(map) do
    rows = map["rows"] || []
    columns = map["columns"] || []
    structure_accents = Enum.map(rows ++ columns, & &1["accent"])

    card_accents =
      map
      |> cells()
      |> Enum.map(fn {_key, cell} -> cell["accent"] end)

    cond do
      not Enum.all?(structure_accents ++ card_accents, &Accent.valid?/1) ->
        {:error, :layout_map, "accents must be known color tokens"}

      invalid_notes_mode?(map["notes_mode"]) ->
        {:error, :layout_map, "notes mode must be known"}

      true ->
        :ok
    end
  end

  defp invalid_notes_mode?(nil), do: false
  defp invalid_notes_mode?(mode), do: mode not in Psc.Canvas.NotesMode.modes()
end
