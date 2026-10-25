defmodule PscWeb.Components.TemplatePreview do
  @moduledoc """
  Read-only pictures of a template's grid, built from its `layout_map`.

  Two sizes, one job: show a template's structure without opening anything.

  * `mini_preview/1` — a schematic grid of squares for a picker card. The shape
    is the information; the template's row and column accents are drawn as thin
    bars on the first row and column, the same way the designer and the canvas
    editor draw them.
  * `grid_preview/1` — the detailed table with the row, column and cell labels,
    for a detail view (the catalog's template modal).

  Both read the map defensively: a template saved before a key existed renders
  an empty picture rather than crashing.
  """

  use Phoenix.Component

  import PscWeb.Components.Accent

  alias Psc.Canvas.Structure

  @doc """
  The schematic grid. `:layout_map` is the template's `layout_map` (or a
  canvas's `cells` — the same shape).
  """
  attr :layout_map, :map, required: true
  attr :class, :string, default: nil

  def mini_preview(assigns) do
    assigns =
      assign(assigns, :lm, assigns.layout_map || %{})

    ~H"""
    <div class={["min-w-0", @class]}>
      <%= if bento?(@lm) do %>
        <%!-- A fixed slot: the picture takes the board's proportions inside it,
        so every card in a row starts its name at the same height. --%>
        <div class="flex h-16 w-full items-center">
          <.bento_mini lm={@lm} />
        </div>
      <% else %>
        <%= if rows(@lm) == [] or columns(@lm) == [] do %>
          <div class="flex h-16 items-center justify-center rounded-[3px] border border-dashed border-base-content/20 text-xs text-base-content/40">
            Empty grid
          </div>
        <% else %>
          <div
            class="grid h-16 w-full gap-1"
            style={
            "grid-template-columns: repeat(#{length(columns(@lm))}, minmax(0, 1fr));" <>
              "grid-template-rows: repeat(#{length(rows(@lm))}, minmax(0, 1fr));"
          }
          >
            <%!-- The first row carries the columns' accents, the first column the
          rows': the same bars the designer authors and the editor renders. --%>
            <%= for {row, ri} <- Enum.with_index(rows(@lm)) do %>
              <%= for {column, ci} <- Enum.with_index(columns(@lm)) do %>
                <div class="relative rounded-[3px] bg-base-content/10">
                  <.accent_bar
                    :if={ri == 0}
                    token={column["accent"]}
                    orientation={:top}
                    class="rounded-t-[3px]"
                  />
                  <.accent_bar
                    :if={ci == 0}
                    token={row["accent"]}
                    orientation={:left}
                    class="rounded-l-[3px]"
                  />
                </div>
              <% end %>
            <% end %>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  @doc """
  A schematic of a bento board: one box per card, at its placement.

  The whole board is drawn: every card keeps its own row, so a card near the
  bottom is not folded back over the ones above it. The picture takes the
  board's proportions, with a floor and a ceiling so a very flat or very tall
  board still reads as a thumbnail.
  """
  attr :lm, :map, required: true

  def bento_mini(assigns) do
    cards = Structure.cards(assigns.lm)
    columns = max(Structure.columns(assigns.lm), 1)
    rows = max(Structure.bounds(assigns.lm).rows, 1)
    tracks = Structure.tracks_per_unit()

    assigns =
      assigns
      |> assign(:cards, cards)
      |> assign(:tracks_x, columns * tracks)
      |> assign(:tracks_y, rows * tracks)
      |> assign(:aspect, "#{columns} / #{rows}")

    ~H"""
    <div
      :if={@cards == []}
      class="flex h-full w-full items-center justify-center rounded-[3px] border border-dashed border-base-content/20 text-[0.65rem] text-base-content/40"
      aria-hidden="true"
    >
      Empty board
    </div>

    <div
      :if={@cards != []}
      class="grid max-h-full min-h-6 w-full gap-px overflow-hidden rounded-[3px] bg-base-content/5"
      style={
        "aspect-ratio: #{@aspect};" <>
          "grid-template-columns: repeat(#{@tracks_x}, minmax(0, 1fr));" <>
          "grid-template-rows: repeat(#{@tracks_y}, minmax(0, 1fr));"
      }
      aria-hidden="true"
    >
      <div
        :for={card <- @cards}
        data-card-key={card.key}
        class={
          [
            "min-h-0 rounded-[2px]",
            # One background only: two utilities for the same property would let
            # the stylesheet order, not the accent, decide the colour.
            if(card.accent, do: swatch_class(card.accent), else: "bg-base-content/20")
          ]
        }
        style={Structure.placement_style(card)}
      >
      </div>
    </div>
    """
  end

  @doc """
  The caption a picker shows under a template's name.

  A table is described by its matrix (rows × columns, the numbers it is
  authored with); a bento by its board (columns × rows, the order the editor's
  column and row inputs use).
  """
  def dimensions(lm) do
    lm = lm || %{}

    if Structure.bento?(lm) do
      bounds = Structure.bounds(lm)
      "#{bounds.columns} × #{bounds.rows}"
    else
      "#{length(lm["rows"] || [])} × #{length(lm["columns"] || [])}"
    end
  end

  @doc """
  The detailed table: row and column labels, and each cell's label (its key
  when it has none).
  """
  attr :layout_map, :map, required: true

  def grid_preview(assigns) do
    assigns = assign(assigns, :lm, assigns.layout_map || %{})

    ~H"""
    <div class="min-w-0 overflow-auto rounded-lg border border-base-content/10 bg-base-200/60">
      <%= if bento?(@lm) do %>
        <.bento_grid lm={@lm} />
      <% else %>
        <table class="w-full table-fixed border-collapse text-xs sm:text-sm">
          <thead>
            <tr>
              <th class="w-16 border border-base-content/10 p-1 sm:w-24 sm:p-2"></th>

              <th
                :for={column <- columns(@lm)}
                class="border border-base-content/10 bg-base-content/5 p-1 font-medium text-base-content/70 sm:p-2"
              >
                {column["label"]}
              </th>
            </tr>
          </thead>

          <tbody>
            <tr :for={{row, ri} <- Enum.with_index(rows(@lm))}>
              <th class="border border-base-content/10 bg-base-content/5 p-1 text-left font-medium text-base-content/70 sm:p-2">
                {row["label"]}
              </th>

              <td
                :for={cell_key <- cell_keys(@lm, ri)}
                class="border border-base-content/10 p-1 align-top text-base-content/80 sm:p-2"
              >
                {cell_label(@lm, cell_key)}
              </td>
            </tr>
          </tbody>
        </table>
      <% end %>
    </div>
    """
  end

  @doc "The detailed bento board: one labelled box per card."
  attr :lm, :map, required: true

  def bento_grid(assigns) do
    cards = Structure.cards(assigns.lm)
    columns = Structure.columns(assigns.lm)
    rows = max(Structure.bounds(assigns.lm).rows, 1)

    assigns =
      assigns
      |> assign(:cards, cards)
      |> assign(:columns, columns)
      |> assign(:rows, rows)

    ~H"""
    <div
      class="grid gap-1 p-2"
      style={
        "grid-template-columns: repeat(#{@columns * Structure.tracks_per_unit()}, minmax(0, 1fr));" <>
          "grid-template-rows: repeat(#{@rows * Structure.tracks_per_unit()}, minmax(1.5rem, auto));"
      }
    >
      <div
        :for={card <- @cards}
        class={[
          "relative min-h-0 overflow-hidden rounded-md border border-base-content/15 bg-base-100 p-1.5 text-xs text-base-content/80",
          card.accent && swatch_class(card.accent)
        ]}
        style={Structure.placement_style(card)}
      >
        <span class="relative z-10 line-clamp-2 font-medium">{card.label}</span>
      </div>
    </div>
    """
  end

  @doc """
  A one-line description of a structure: a matrix's size, or a board's cards.
  """
  def structure_size(lm) do
    lm = lm || %{}

    if Structure.bento?(lm) do
      cards = length(Structure.cards(lm))
      "#{plural(cards, "card")} on #{plural(Structure.columns(lm), "column")}"
    else
      "#{plural(length(lm["rows"] || []), "row")} × " <>
        "#{plural(length(lm["columns"] || []), "column")}"
    end
  end

  defp plural(1, word), do: "1 #{word}"
  defp plural(count, word), do: "#{count} #{word}s"

  defp bento?(lm), do: Structure.bento?(lm || %{})

  defp rows(lm), do: Map.get(lm, "rows", [])
  defp columns(lm), do: Map.get(lm, "columns", [])

  defp cell_keys(lm, row_index) do
    lm |> Map.get("layout", []) |> Enum.at(row_index, [])
  end

  defp cell_label(lm, cell_key) do
    label =
      lm
      |> Map.get("cells", %{})
      |> Map.get(cell_key, %{})
      |> Map.get("label", "")

    if label in [nil, ""], do: cell_key, else: label
  end
end
