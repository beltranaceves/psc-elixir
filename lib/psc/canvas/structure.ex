defmodule Psc.Canvas.Structure do
  @moduledoc """
  How a canvas (or a template) arranges its cells.

  There are three modes:

    * `:table` — the classic rows × columns matrix (`"rows"`, `"columns"` and
      the `"layout"` cell-key matrix). A canvas keeps its cells flat
      (`cells[key][field]`); a template keeps them nested under `"cells"`.
    * `:bento` — free-form cards on a fixed column grid. Every cell carries a
      `"placement"` (`x`, `y`, `w`, `h`) and an optional `"accent"`, and the
      map itself carries `"layout_mode" => "bento"` and `"bento_columns"`.
      Canvas and template share the same flat shape, so one set of helpers
      serves the runtime, the designer and the previews.
    * `:image` — floating cells over a backdrop image or SVG. A cell's
      `"placement"` is a percentage of the backdrop (`0`–`100`), and the map
      carries `"layout_mode" => "image"` plus a `"backdrop"` map (`url`,
      `fit`, `alt`, optional `aspect`). Percentages keep every cell registered
      with the picture at any size, which is the whole point of the mode.

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

  # The board's height is a container: a template can leave empty rows at the
  # bottom, and the stored value is a floor that the cards can outgrow.
  @default_rows 4
  @min_rows 1
  @max_rows 64
  @default_card_width 6
  @default_card_height 2
  @max_card_height 40

  # An image board's coordinates are percentages of the backdrop, so the board
  # has the same extent at every viewport size. A cell moves in the same half
  # unit a bento card does (0.5%), and must be at least 2% wide and tall to stay
  # usable.
  @image_extent 100
  @image_min_size 2
  @default_image_cell_width 24
  @default_image_cell_height 12

  @default_backdrop_fit "contain"
  @backdrop_fits ["contain", "cover", "stretch"]
  @default_backdrop_aspect 16 / 9
  @min_backdrop_aspect 0.1
  @max_backdrop_aspect 10.0
  @max_backdrop_url_length 4000

  # Table metadata is present on both a canvas and a template. `notes_mode`
  # and `notes` only exist on a template's layout map, and a bento or image
  # template is flat, so they sit beside the cells there.
  # `$name` and `$description` are the canvas header, stored in the cells map
  # by the CRDT. They are not cells, and a table template never writes them.
  @table_metadata ["rows", "columns", "layout", "$name", "$description"]

  @bento_metadata @table_metadata ++
                    ["layout_mode", "bento_columns", "bento_rows", "cells", "notes_mode", "notes"]

  @image_metadata @table_metadata ++
                    ["layout_mode", "backdrop", "cells", "notes_mode", "notes"]

  @metadata_keys Enum.uniq(@bento_metadata ++ @image_metadata)

  # Cell keys that are metadata, not content, in every mode. `placement` and
  # `accent` are how a free-form cell is drawn, and `kind` is whether an image
  # cell is a card or a bare text box; they are never editable fields.
  @reserved_cell_keys [
    "row",
    "column",
    "label",
    "name",
    "semantics",
    "titles",
    "placement",
    "accent",
    "kind"
  ]

  @doc "The metadata keys of a structure map: never cells."
  def metadata_keys, do: @metadata_keys

  @doc "The cell keys that can never be added, removed or rendered as fields."
  def reserved_cell_keys, do: @reserved_cell_keys

  @doc "The layout mode of a cells map (or a template layout map)."
  def mode(map) when is_map(map) do
    case map["layout_mode"] do
      "bento" -> :bento
      "image" -> :image
      _other -> :table
    end
  end

  def bento?(map), do: mode(map) == :bento

  @doc "Whether the map is an image board."
  def image?(map), do: mode(map) == :image

  @doc """
  Whether cells are placed freely (a bento or an image board) rather than in a
  matrix. Free-form cells carry a `"placement"` and can be added, moved and
  resized independently.
  """
  def freeform?(map), do: mode(map) in [:bento, :image]

  ## Backdrop (image boards)

  @doc """
  The backdrop of an image board, normalized.

  `aspect` is `nil` when the picture supplies its own shape; when it is set the
  board is that shape and the picture is fitted inside it.
  """
  def backdrop(map) when is_map(map) do
    stored =
      case Map.get(map, "backdrop") do
        %{} = backdrop -> backdrop
        _other -> %{}
      end

    %{
      url: normalize_backdrop_url(stored["url"]),
      fit: normalize_fit(stored["fit"]),
      alt: normalize_alt(stored["alt"]),
      aspect: normalize_aspect(stored["aspect"])
    }
  end

  @doc "Whether the map has a backdrop picture."
  def backdrop?(map), do: backdrop(map).url != nil

  @doc """
  The backdrop as it is stored (string keys, unset values omitted).

  Used when a template's backdrop is copied into a canvas.
  """
  def backdrop_map(map) do
    case backdrop(map) do
      %{url: nil} ->
        %{}

      backdrop ->
        %{"url" => backdrop.url, "fit" => backdrop.fit}
        |> maybe_put("alt", backdrop.alt)
        |> maybe_put("aspect", backdrop.aspect)
    end
  end

  @doc "The fits a pinned backdrop may use."
  def backdrop_fits, do: @backdrop_fits

  @doc "The default shape of a board without a pinned aspect."
  def default_backdrop_aspect, do: @default_backdrop_aspect

  @doc """
  A URL that can act as a backdrop: `http(s)`, a root-relative path, or an
  `image/*` data URI.

  Quotes and whitespace are refused: the value is written into an `src`
  attribute, and only image sources make sense there.
  """
  def valid_backdrop_url?(url) when is_binary(url) do
    url = String.trim(url)

    url != "" and String.length(url) <= @max_backdrop_url_length and
      not String.match?(url, ~r/[\s"'`\x00-\x1F\x7F]/) and
      (String.starts_with?(url, "https://") or String.starts_with?(url, "http://") or
         String.starts_with?(url, "/") or String.starts_with?(url, "data:image/"))
  end

  def valid_backdrop_url?(_url), do: false

  @doc """
  Update an image board's backdrop. Missing fields keep their current value.

  An invalid URL, fit or aspect is ignored rather than stored, and an empty URL
  removes the backdrop. The rules run here, not in a LiveView, so every client
  applying the same operation reaches the same backdrop.
  """
  def set_backdrop(map, attrs) when is_map(map) and is_map(attrs) do
    if image?(map) do
      current = backdrop(map)

      url =
        case Map.fetch(attrs, "url") do
          {:ok, url} when is_binary(url) ->
            if String.trim(url) == "", do: nil, else: normalize_backdrop_url(url) || current.url

          _other ->
            current.url
        end

      fit =
        case Map.fetch(attrs, "fit") do
          {:ok, fit} when is_binary(fit) and fit in @backdrop_fits -> fit
          _other -> current.fit
        end

      alt =
        case Map.fetch(attrs, "alt") do
          {:ok, alt} when is_binary(alt) -> normalize_alt(alt)
          _other -> current.alt
        end

      aspect =
        case Map.fetch(attrs, "aspect") do
          {:ok, nil} -> nil
          {:ok, aspect} when is_number(aspect) or is_binary(aspect) -> normalize_aspect(aspect)
          _other -> current.aspect
        end

      backdrop = %{url: url, fit: fit, alt: alt, aspect: aspect}

      if url do
        Map.put(map, "backdrop", store_backdrop(backdrop))
      else
        Map.delete(map, "backdrop")
      end
    else
      map
    end
  end

  defp store_backdrop(backdrop) do
    %{"url" => backdrop.url, "fit" => backdrop.fit}
    |> maybe_put("alt", backdrop.alt)
    |> maybe_put("aspect", backdrop.aspect)
  end

  defp normalize_backdrop_url(url) when is_binary(url) do
    url = String.trim(url)
    if valid_backdrop_url?(url), do: url, else: nil
  end

  defp normalize_backdrop_url(_url), do: nil

  defp normalize_fit(fit) when is_binary(fit) do
    if fit in @backdrop_fits, do: fit, else: @default_backdrop_fit
  end

  defp normalize_fit(_fit), do: @default_backdrop_fit

  defp normalize_alt(alt) when is_binary(alt) do
    case String.trim(alt) do
      "" -> nil
      alt -> String.slice(alt, 0, 200)
    end
  end

  defp normalize_alt(_alt), do: nil

  defp normalize_aspect(aspect) when is_number(aspect) do
    if aspect >= @min_backdrop_aspect and aspect <= @max_backdrop_aspect do
      Float.round(aspect / 1, 4)
    end
  end

  defp normalize_aspect(aspect) when is_binary(aspect) do
    case Float.parse(String.trim(aspect)) do
      {number, _rest} -> normalize_aspect(number)
      :error -> nil
    end
  end

  defp normalize_aspect(_aspect), do: nil

  @doc """
  The CSS of an image board's frame.

  A pinned aspect ratio gives the board a stable shape before the picture
  loads; without one the picture's own height establishes the board, so the
  stored percentages refer to exactly the space the picture occupies. An empty
  frame falls back to the default shape so it still has an area to drop cells
  onto.
  """
  def image_board_style(map) do
    case backdrop(map) do
      %{url: nil} ->
        "aspect-ratio: #{Float.round(@default_backdrop_aspect, 4)};"

      %{aspect: nil} ->
        ""

      %{aspect: aspect} ->
        "aspect-ratio: #{Float.round(aspect, 4)};"
    end
  end

  @doc "A cell's size on an image board, in percent."
  def image_size_label(w, h), do: "#{dimension(w)} × #{dimension(h)}%"

  @doc """
  The kind of an image cell: a `card` (a titled box with Markdown fields) or a
  bare `text` input. Everything else is a card.
  """
  def kind(cell) when is_map(cell) do
    if cell["kind"] == "text", do: "text", else: "card"
  end

  def kind(_cell), do: "card"

  @doc "The kinds an image cell may be."
  def kinds, do: ["card", "text"]

  @doc """
  Set an image cell's kind. Missing cells and unknown kinds are a no-op.
  """
  def set_kind(map, key, kind) do
    if image?(map) and kind in kinds() do
      update_card(map, key, fn cell -> Map.put(cell, "kind", kind) end)
    else
      map
    end
  end

  @doc """
  Clamp every image cell's placement into the backdrop.

  Used when a stored template is loaded: hand-edited or older data may carry a
  rectangle that leaves the picture, and the designer should show it where the
  editor will actually render it.
  """
  def normalize_image(map) do
    if image?(map) do
      map
      |> cells()
      |> Enum.reduce(map, fn
        {key, cell}, acc when is_map(cell) ->
          update_card(acc, key, fn cell ->
            put_placement(cell, clamp_image_placement(cell["placement"] || %{}))
          end)

        _other, acc ->
          acc
      end)
    else
      map
    end
  end

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

  @doc "The smallest and largest row counts a bento may have."
  def row_range, do: @min_rows..@max_rows

  @doc """
  The board's height in rows.

  The stored `"bento_rows"` is the container the template asked for; a card
  that reaches lower grows the board past it, so the value can never hide a
  card.
  """
  def rows(map) do
    stored =
      map
      |> Map.get("bento_rows", @default_rows)
      |> normalize_int(@default_rows)
      |> min(@max_rows)
      |> max(@min_rows)

    max(stored, content_rows(map))
  end

  @doc "The rows the cards actually reach (rounded up), at least one."
  def content_rows(map) do
    bottom =
      map
      |> cards()
      |> Enum.map(&(&1.y + &1.h))
      |> Enum.max(fn -> 0 end)

    bottom |> :math.ceil() |> trunc() |> max(@min_rows)
  end

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
  def board_style(columns, rows \\ @default_rows) do
    tracks = round(columns * @tracks_per_unit)

    # A card of `h` units spans `2h` tracks and the gaps between them, so the
    # track height subtracts one gap to keep one unit exactly 72px:
    #   2 * 32 + 8 = 72. Half a unit is then 32 + 8 = 40px, half a step.
    gap = @row_gap_px
    row_height = div(@unit_px - gap, @tracks_per_unit)

    # `minmax` rather than a fixed height: a card's `h` is a minimum, so a card
    # holding a long note grows and takes its grid rows with it. The `min-height`
    # is the requested container height, so empty rows are real space.
    "--bento-columns: #{columns}; " <>
      "grid-template-columns: repeat(#{tracks}, minmax(0, 1fr)); " <>
      "grid-auto-rows: minmax(#{row_height}px, auto); " <>
      "gap: #{gap}px; " <>
      "min-height: #{height_px(rows)}px;"
  end

  @doc "The pixel height of `rows` row units, including the gaps between them."
  def height_px(rows), do: round(rows * (@unit_px + @row_gap_px) - @row_gap_px)

  @doc "The CSS grid placement of one card."
  def placement_style(card) do
    "grid-column: #{track(card.x) + 1} / span #{track(card.w)}; " <>
      "grid-row: #{track(card.y) + 1} / span #{track(card.h)};"
  end

  @doc "A placement value converted to CSS tracks."
  def track(value), do: round(value * @tracks_per_unit)

  @doc """
  The CSS of one floating cell on an image board.

  Coordinates are percentages of the backdrop, so the cell keeps its place in
  the picture at any viewport size.
  """
  def image_placement_style(card) do
    "left: #{dimension(card.x)}%; top: #{dimension(card.y)}%; " <>
      "width: #{dimension(card.w)}%; height: #{dimension(card.h)}%;"
  end

  @doc "The smallest size of an image cell, in percent."
  def image_min_size, do: @image_min_size

  @doc "The step an image cell moves and resizes by, in percent."
  def image_step, do: 1 / @tracks_per_unit

  @doc """
  A compact `columns × rows` label.

  Whole numbers print without a decimal tail, so a card is `8 × 3` and a
  half-step resize is `8.5 × 3`.
  """
  def size_label(columns, rows), do: "#{dimension(columns)} × #{dimension(rows)}"

  defp dimension(value) when is_float(value) do
    if value == trunc(value),
      do: Integer.to_string(trunc(value)),
      else: :erlang.float_to_binary(value, decimals: 1)
  end

  defp dimension(value) when is_integer(value), do: Integer.to_string(value)
  defp dimension(value), do: to_string(value)

  @doc """
  The cells of a map.

  A bento or image map is flat, exactly like a canvas. A table template nests
  its cells under `"cells"`; a table canvas is flat.
  """
  def cells(map) when is_map(map) do
    case mode(map) do
      :bento ->
        Map.drop(map, @bento_metadata)

      :image ->
        Map.drop(map, @image_metadata)

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
  are the matrix indices). A bento reads each cell's placement in grid units;
  an image board reads it in percent of the backdrop. Either way the list is
  `%{key, label, x, y, w, h, accent, kind}`, sorted by `{y, x, key}`. `kind` is
  `"card"` unless the cell is an image board's `text` cell.
  """
  def cards(map) when is_map(map) do
    map
    |> raw_cards()
    |> Enum.sort_by(&{&1.y, &1.x, &1.key})
  end

  defp raw_cards(map) do
    case mode(map) do
      :bento ->
        # Only maps are cards: the map also holds the header strings and the
        # grid settings, and a canvas written before a key existed must still
        # render.
        for {key, cell} <- cells(map), is_map(cell) do
          placement = placement(cell)

          %{
            key: key,
            label: label(cell, key),
            x: placement.x,
            y: placement.y,
            w: placement.w,
            h: placement.h,
            accent: cell["accent"],
            kind: "card"
          }
        end

      :image ->
        for {key, cell} <- cells(map), is_map(cell) do
          placement = normalize_placement(cell, :image)

          %{
            key: key,
            label: label(cell, key),
            x: placement.x,
            y: placement.y,
            w: placement.w,
            h: placement.h,
            accent: cell["accent"],
            kind: kind(cell)
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
            accent: accent_at(columns, x),
            kind: "card"
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
    case is_map(cell) && cell["label"] do
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
      :image -> cells(map) == %{}
      :table -> map["rows"] in [nil, []] or map["columns"] in [nil, []]
    end
  end

  @doc """
  The extent of the board: columns and rows.

  A table reports its matrix size; a bento reports its column count and its
  height (the stored container floor, or the deepest card when that is lower);
  an image board reports `100 × 100` because its unit is a percentage of the
  backdrop.
  """
  def bounds(map) do
    case mode(map) do
      :bento ->
        %{columns: columns(map), rows: rows(map)}

      :image ->
        %{columns: @image_extent, rows: @image_extent}

      :table ->
        %{columns: length(map["columns"] || []), rows: length(map["layout"] || [])}
    end
  end

  @doc """
  The extent of an image board, in percent.
  """
  def image_extent, do: @image_extent

  @doc """
  A cell's normalized placement, in bento grid units.

  Table cells are one unit at their index; an image board uses
  `normalize_placement/2` with its own percent rules.
  """
  def placement(cell) when is_map(cell) do
    normalize_placement(cell, :bento)
  end

  # Defensive: a value that is not a cell map has no placement.
  def placement(_cell), do: %{x: 0, y: 0, w: 1, h: 1}

  defp normalize_placement(cell, :bento) when is_map(cell) do
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

  defp normalize_placement(cell, :image) when is_map(cell) do
    case cell["placement"] do
      %{} = placement -> clamp_image_placement(placement)
      _other -> clamp_image_placement(%{})
    end
  end

  defp normalize_placement(_cell, _mode), do: %{x: 0, y: 0, w: 1, h: 1}

  @doc """
  Clamp a placement to the board.

  The single place geometry is bounded. A bento card is at least one unit and
  never extends past the right edge; an image cell is at least `2%` wide and
  tall and stays inside the picture. `y` never goes negative.
  """
  def clamp_placement(map, placement) do
    case mode(map) do
      :image -> clamp_image_placement(placement)
      _other -> clamp_grid_placement(map, placement)
    end
  end

  defp clamp_grid_placement(map, placement) do
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

    # Position and size move in the same half units, so a card can be nudged
    # half a column without resizing it first.
    x =
      placement
      |> get_number("x", 0)
      |> snap()
      |> max(0)
      |> min(board_columns - w)

    y = placement |> get_number("y", 0) |> snap() |> max(0)

    %{x: x, y: y, w: w, h: h}
  end

  defp clamp_image_placement(placement) do
    w =
      placement
      |> get_number("w", @default_image_cell_width)
      |> snap()
      |> min(@image_extent)
      |> max(@image_min_size)

    h =
      placement
      |> get_number("h", @default_image_cell_height)
      |> snap()
      |> min(@image_extent)
      |> max(@image_min_size)

    x =
      placement
      |> get_number("x", 0)
      |> snap()
      |> max(0)
      |> min(@image_extent - w)

    y =
      placement
      |> get_number("y", 0)
      |> snap()
      |> max(0)
      |> min(@image_extent - h)

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
  The first free rectangle for a new free-form cell.

  A bento scans row by row for a `w` × `h` area that no card covers; an image
  board scans in 2% steps. The scan order is deterministic, so two clients that
  add a cell concurrently still compute the same slot for the same board.
  """
  def next_slot(map) do
    case mode(map) do
      :image -> next_image_slot(map)
      _other -> next_grid_slot(map)
    end
  end

  defp next_grid_slot(map) do
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

  defp next_image_slot(map) do
    w = @default_image_cell_width
    h = @default_image_cell_height
    occupied = occupied_rects(map)

    Enum.find_value(
      0..(div(@image_extent, 2) - div(h, 2)),
      %{
        x: div(@image_extent - w, 4),
        y: div(@image_extent - h, 2),
        w: w,
        h: h
      },
      fn step ->
        y = step * 2

        Enum.find_value(0..div(@image_extent - w, 2), fn x_step ->
          x = x_step * 2
          rect = %{x: x, y: y, w: w, h: h}
          if free?(rect, occupied), do: rect, else: nil
        end)
      end
    )
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

  ## Mutations (free-form cells)

  @doc """
  Add a cell to a free-form board. Idempotent: an existing key is left
  untouched.

  `placement` is in bento grid units or image percentages, depending on the
  map's mode; without one the board's first free slot is used. `kind` is only
  meaningful for an image board's cells and defaults to `"card"`.
  """
  def add_card(map, key, placement \\ nil, label \\ nil, accent \\ nil, kind \\ nil)
      when is_map(map) do
    if not freeform?(map) or Map.has_key?(cells(map), key) do
      map
    else
      placement = clamp_placement(map, placement || next_slot(map))

      cell =
        %{
          "label" => label || key,
          "content" => "",
          "placement" => stringify(placement)
        }
        |> maybe_put("kind", cell_kind(map, kind))
        |> maybe_put("accent", nilify(accent))

      Map.put(map, key, cell)
    end
  end

  defp cell_kind(map, kind) do
    cond do
      not image?(map) -> nil
      kind in kinds() -> kind
      true -> "card"
    end
  end

  @doc "Remove a free-form cell, with its placement and content."
  def remove_card(map, key) when is_map(map) do
    if freeform?(map), do: Map.delete(map, key), else: map
  end

  @doc """
  Move a free-form cell. Missing cells are a no-op.

  A bento card dragged past the right edge grows the board: the columns follow
  the card instead of clamping it. An explicit narrower grid (`set_columns/2`)
  still wins, because that is the user asking for a smaller board. An image
  cell is a percentage of the backdrop and cannot leave it.
  """
  def move(map, key, x, y) do
    if image?(map) do
      update_freeform_card(map, key, fn map, cell ->
        current = normalize_placement(cell, :image)
        x = x |> normalize_number(current.x) |> snap()
        y = y |> normalize_number(current.y) |> snap()

        {map, put_placement(cell, clamp_image_placement(%{current | x: x, y: y}))}
      end)
    else
      update_freeform_card(map, key, fn map, cell ->
        current = placement(cell)
        x = x |> normalize_number(current.x) |> snap()
        y = y |> normalize_number(current.y) |> snap()
        map = grow_columns(map, x + current.w)

        {map, put_placement(cell, clamp_placement(map, %{current | x: x, y: y}))}
      end)
    end
  end

  @doc """
  Resize a free-form cell. Missing cells are a no-op.

  The left edge stays put, and a bento card dragged wider than the board grows
  the board with it (up to the maximum column count). An image cell stays
  inside the backdrop.
  """
  def resize(map, key, w, h) do
    if image?(map) do
      update_freeform_card(map, key, fn map, cell ->
        current = normalize_placement(cell, :image)
        width = w |> normalize_number(current.w) |> snap()
        height = h |> normalize_number(current.h) |> snap()

        {map, put_placement(cell, clamp_image_placement(%{current | w: width, h: height}))}
      end)
    else
      update_freeform_card(map, key, fn map, cell ->
        current = placement(cell)

        width = w |> normalize_number(current.w) |> snap() |> max(min_size())
        map = grow_columns(map, current.x + width)

        # At the maximum width the card shrinks into the space left of it; its
        # left edge never jumps to a different column.
        width = width |> min(columns(map) - current.x) |> max(min_size())

        {map, put_placement(cell, clamp_placement(map, %{current | w: width, h: h}))}
      end)
    end
  end

  @doc "Set a cell's accent (`nil` or `\"\"` clears it)."
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

      cells(map)
      |> Enum.reduce(map, fn
        {key, cell}, acc when is_map(cell) ->
          update_card(acc, key, fn cell ->
            put_placement(cell, clamp_placement(acc, placement(cell)))
          end)

        _other, acc ->
          acc
      end)
    else
      map
    end
  end

  @doc """
  Change the board's height.

  The cards are the floor: a request shorter than the deepest card is clamped
  up, so shrinking the container can never hide work.
  """
  def set_rows(map, count) do
    if bento?(map) do
      count =
        count
        |> normalize_int(@default_rows)
        |> max(content_rows(map))
        |> min(@max_rows)
        |> max(@min_rows)

      Map.put(map, "bento_rows", count)
    else
      map
    end
  end

  defp update_card(map, key, fun) do
    if freeform?(map) do
      case Map.fetch(cells(map), key) do
        {:ok, cell} -> Map.put(map, key, fun.(cell))
        :error -> map
      end
    else
      map
    end
  end

  # A cell's geometry can change the board itself (the columns grow when a
  # bento card is dragged past the edge), so the updater gets the map back too.
  defp update_freeform_card(map, key, fun) do
    if freeform?(map) do
      case Map.fetch(cells(map), key) do
        {:ok, cell} ->
          {map, new_cell} = fun.(map, cell)
          Map.put(map, key, new_cell)

        :error ->
          map
      end
    else
      map
    end
  end

  # Grow the grid so a card fits, up to the maximum width. Never shrinks: a
  # narrower board is the explicit `set_columns/2`, never a side effect of a
  # drag that ends before the edge.
  defp grow_columns(map, needed) do
    needed = ceil(needed)

    if needed > columns(map) do
      # Saturate at the maximum: a card dragged past it is clamped into the
      # widest board the model allows rather than refusing to grow at all.
      Map.put(map, "bento_columns", min(needed, @max_columns))
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
      _freeform -> freeform_neighbours(map, key)
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

  # A ragged free-form board can have no card directly beside another.
  # Horizontal swipes fall back to reading order so they never get stuck;
  # vertical swipes stay geometric, because wrapping a swipe down at the bottom
  # would be confusing.
  defp freeform_neighbours(map, key) do
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
      :image -> validate_image(map)
      :table -> validate_table(map)
    end
  end

  @doc """
  Validate a template layout map.

  Table templates must be a complete matrix; bento templates must have valid
  placements and at least one card; image templates must have a backdrop and at
  least one placement. All three require unique fields per cell and reject
  unknown accents.
  """
  def validate_template(map) do
    with :ok <- validate_not_empty(map),
         :ok <- validate_backdrop(map),
         :ok <- validate(map),
         :ok <- validate_fields(map),
         :ok <- validate_accents(map) do
      :ok
    end
  end

  # A template is a starting point, so it must carry the picture its cell
  # coordinates refer to. A canvas may be blank and get one later.
  defp validate_backdrop(map) do
    if image?(map) and not backdrop?(map) do
      {:error, :layout_map, "template must have a backdrop"}
    else
      :ok
    end
  end

  defp validate_not_empty(map) do
    case mode(map) do
      :bento ->
        if cells(map) == %{},
          do: {:error, :layout_map, "template must have at least one card"},
          else: :ok

      :image ->
        if cells(map) == %{},
          do: {:error, :layout_map, "template must have at least one cell"},
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

    cond do
      not valid_rows?(map) ->
        {:error, :layout_map, "bento must have between #{@min_rows} and #{@max_rows} rows"}

      true ->
        validate_bento_cards(map, board_columns)
    end
  end

  defp validate_bento_cards(map, board_columns) do
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

  defp valid_rows?(map) do
    case map["bento_rows"] do
      nil -> true
      count when is_integer(count) -> count in @min_rows..@max_rows
      _other -> false
    end
  end

  defp validate_bento_cell(key, cell, board_columns) do
    placement = if is_map(cell), do: cell["placement"]

    cond do
      not is_map(cell) ->
        {:error, :layout_map, "card #{key} is not a card"}

      not is_map(placement) ->
        {:error, :layout_map, "card #{key} has no placement"}

      not valid_placement_units?(placement) ->
        {:error, :layout_map, "card #{key} must be placed and sized in half units"}

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

  # Position and size both sit on half-unit boundaries: that is the step a
  # move and a resize share.
  defp valid_placement_units?(placement) do
    fields = ["x", "y", "w", "h"]

    Enum.all?(fields, &is_number(placement[&1])) and
      Enum.all?(fields, fn field ->
        value = placement[field] * @tracks_per_unit
        abs(value - round(value)) < 1.0e-9
      end)
  end

  defp validate_image(map) do
    with :ok <- validate_image_backdrop(map) do
      map
      |> cells()
      |> Enum.reduce_while(:ok, fn {key, cell}, _acc ->
        case validate_image_cell(key, cell) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)
    end
  end

  defp validate_image_backdrop(map) do
    case map["backdrop"] do
      nil ->
        :ok

      %{} = backdrop ->
        cond do
          not valid_backdrop_url?(backdrop["url"]) ->
            {:error, :layout_map, "backdrop must be an image URL"}

          not valid_fit?(backdrop["fit"]) ->
            {:error, :layout_map, "backdrop fit must be #{Enum.join(@backdrop_fits, ", ")}"}

          not valid_aspect?(backdrop["aspect"]) ->
            {:error, :layout_map,
             "backdrop shape must be between #{@min_backdrop_aspect} and #{@max_backdrop_aspect}"}

          true ->
            :ok
        end

      _other ->
        {:error, :layout_map, "backdrop must be an image"}
    end
  end

  defp valid_fit?(nil), do: true
  defp valid_fit?(fit), do: fit in @backdrop_fits

  defp valid_aspect?(nil), do: true

  defp valid_aspect?(aspect) do
    is_number(aspect) and aspect >= @min_backdrop_aspect and aspect <= @max_backdrop_aspect
  end

  defp validate_image_cell(key, cell) do
    placement = if is_map(cell), do: cell["placement"]

    cond do
      not is_map(cell) ->
        {:error, :layout_map, "cell #{key} is not a cell"}

      not is_map(placement) ->
        {:error, :layout_map, "cell #{key} has no placement"}

      not valid_placement_units?(placement) ->
        {:error, :layout_map, "cell #{key} must be placed and sized in half units"}

      placement["w"] < @image_min_size or placement["h"] < @image_min_size ->
        {:error, :layout_map, "cell #{key} must be at least #{@image_min_size}% wide and tall"}

      placement["x"] < 0 or placement["y"] < 0 ->
        {:error, :layout_map, "cell #{key} is placed outside the backdrop"}

      placement["x"] + placement["w"] > @image_extent or
          placement["y"] + placement["h"] > @image_extent ->
        {:error, :layout_map, "cell #{key} extends past the backdrop"}

      not valid_label?(cell["label"]) ->
        {:error, :layout_map, "cell #{key} has an invalid label"}

      cell["kind"] not in [nil | kinds()] ->
        {:error, :layout_map, "cell #{key} has an unknown kind"}

      true ->
        :ok
    end
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
    |> Enum.find_value(:ok, fn
      {_key, cell} when is_map(cell) ->
        fields = cell["fields"] || []

        if length(fields) != length(Enum.uniq(fields)) do
          {:error, :layout_map, "field keys must be unique within a cell"}
        end

      _other ->
        nil
    end)
  end

  defp validate_accents(map) do
    rows = map["rows"] || []
    columns = map["columns"] || []
    structure_accents = Enum.map(rows ++ columns, & &1["accent"])

    card_accents =
      map
      |> cells()
      |> Enum.filter(fn {_key, cell} -> is_map(cell) end)
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
