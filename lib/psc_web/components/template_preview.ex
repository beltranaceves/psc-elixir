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
    </div>
    """
  end

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
