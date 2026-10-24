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
        <.bento_mini lm={@lm} />
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
  """
  attr :lm, :map, required: true

  def bento_mini(assigns) do
    cards = Structure.cards(assigns.lm)
    columns = Structure.columns(assigns.lm)
    rows = max(Structure.bounds(assigns.lm).rows, 1)

    clipped = clamp_int(rows, 1, 8)

    assigns =
      assigns
      |> assign(:cards, cards)
      |> assign(:columns, columns)
      |> assign(:cell_rows, clipped)
      |> assign(
        :boxes,
        Enum.map(cards, fn card ->
          {card, clamp_int(card.y + 1, 1, clipped), clamp_int(card.h, 1, clipped)}
        end)
      )

    ~H"""
    <div
      class="grid h-16 w-full gap-1"
      style={
        "grid-template-columns: repeat(#{@columns}, minmax(0, 1fr));" <>
          "grid-template-rows: repeat(#{@cell_rows}, minmax(0, 1fr));"
      }
    >
      <div
        :for={{card, row_start, row_span} <- @boxes}
        class={[
          "relative min-h-0 rounded-[3px] bg-base-content/10",
          card.accent && swatch_class(card.accent)
        ]}
        style={
          "grid-column: #{card.x + 1} / span #{card.w};" <>
            "grid-row: #{row_start} / span #{row_span};"
        }
        title={card.label}
      >
      </div>
    </div>
    """
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
      |> assign(:rows, min(rows, 12))

    ~H"""
    <div
      class="grid gap-1 p-2"
      style={
        "grid-template-columns: repeat(#{@columns}, minmax(0, 1fr));" <>
          "grid-template-rows: repeat(#{@rows}, minmax(3rem, auto));"
      }
    >
      <div
        :for={card <- @cards}
        class={[
          "relative min-h-0 overflow-hidden rounded-md border border-base-content/15 bg-base-100 p-1.5 text-xs text-base-content/80",
          card.accent && swatch_class(card.accent)
        ]}
        style={"grid-column: #{card.x + 1} / span #{card.w}; grid-row: #{card.y + 1} / span #{card.h};"}
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
      case length(Structure.cards(lm)) do
        1 -> "1 card on #{Structure.columns(lm)} columns"
        count -> "#{count} cards on #{Structure.columns(lm)} columns"
      end
    else
      "#{length(lm["rows"] || [])} rows × #{length(lm["columns"] || [])} columns"
    end
  end

  defp clamp_int(value, low, high) do
    value
    |> max(low)
    |> then(&if(&1 > high, do: high, else: &1))
  end

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
