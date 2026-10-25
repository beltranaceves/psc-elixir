defmodule PscWeb.UnstrCanvasLive.Bento do
  @moduledoc """
  The bento view of a canvas: free-form cards on a fixed column grid.

  The cards are the same cells the table grid renders, so the shared
  `PscWeb.UnstrCanvasLive.Cell` body supplies the label, the fields and the
  Markdown editors. A card differs only in its placement: `grid-column` and
  `grid-row` come from the cell's `"placement"` and are clamped by
  `Psc.Canvas.Structure`.

  Geometry lives in the event log like any other edit. A drag sends one
  `move_card` on release; the arrow keys (while Edit layout is on) send one
  `nudge_card` per press. Both are applied through the parent LiveView, so
  every open client converges.
  """

  use Phoenix.Component

  import PscWeb.CoreComponents, only: [icon: 1]
  import PscWeb.UnstrCanvasLive.CellColors, only: [colors_button: 1, colors_panel: 1]
  import PscWeb.UnstrCanvasLive.Header, only: [canvas_status: 1, title_field: 1]

  alias Psc.Canvas.Structure
  alias PscWeb.Components.UI.Button, as: UIButton
  alias PscWeb.UnstrCanvasLive.Cell

  attr :cells, :map, required: true
  attr :c_name, :string, required: true
  attr :edit_structure?, :boolean, required: true
  attr :structure_accent_picker, :any, default: nil
  attr :colors_picker, :string, default: nil
  attr :presence, :map, required: true
  attr :status, :map, required: true
  attr :can_share?, :boolean, required: true
  attr :status_row?, :boolean, default: false
  attr :focus_cell, :string, default: nil
  attr :user_id, :integer, required: true

  def board(assigns) do
    bounds = Structure.bounds(assigns.cells)

    assigns =
      assigns
      |> assign(:cards, Structure.cards(assigns.cells))
      |> assign(:columns, bounds.columns)
      |> assign(:rows, bounds.rows)
      |> assign(:min_rows, Structure.content_rows(assigns.cells))
      |> assign(:column_range, Structure.column_range())
      |> assign(:row_range, Structure.row_range())

    ~H"""
    <div
      id="canvas-bento"
      class={
        [
          "flex min-h-0 w-full flex-1 flex-col overflow-hidden rounded-xl border border-base-content/20 bg-base-200",
          # A phone keeps the board inside a scroll area of its own; a desktop
          # lets it grow and scrolls the page, so a tall board is not trapped in
          # a nested scrollbar.
          "lg:flex-none lg:overflow-visible"
        ]
      }
    >
      <div class="flex shrink-0 flex-wrap items-center gap-2 border-b border-base-content/10 px-3 py-2">
        <div class="min-w-[8rem] flex-1">
          <.title_field c_name={@c_name} />
        </div>

        <div :if={@status_row?} class="hidden sm:flex">
          <.canvas_status presence={@presence} status={@status} can_share?={@can_share?} />
        </div>

        <div class="ml-auto flex items-center gap-2">
          <button
            type="button"
            id="edit-layout-toggle"
            phx-click="toggle_structure"
            aria-pressed={to_string(@edit_structure?)}
            class={[
              "inline-flex items-center gap-1.5 rounded-lg border px-2.5 py-1 text-xs font-medium transition-colors",
              @edit_structure? && "border-primary/50 bg-primary/10 text-base-content",
              not @edit_structure? &&
                "border-base-content/10 text-base-content/70 hover:bg-base-content/5 hover:text-base-content"
            ]}
          >
            <.icon name="hero-pencil-square" class="size-4" /> Edit layout
          </button>

          <%!-- The board's real grid. In Edit layout it is the control itself:
          columns on the left of the ×, rows on the right. Outside it the same
          value is a read-only badge, so reading a canvas cannot restructure
          it by accident. --%>
          <%= if @edit_structure? do %>
            <div
              id="bento-size"
              class="inline-flex h-8 items-center gap-1 text-xs tabular-nums text-base-content/60"
            >
              <.icon name="hero-table-cells" class="size-4 shrink-0" />
              <form id="bento-columns-form" phx-change="set_bento_columns">
                <input
                  type="number"
                  id="bento-columns-input"
                  name="value"
                  value={@columns}
                  min={@column_range.first}
                  max={@column_range.last}
                  step="1"
                  inputmode="numeric"
                  phx-debounce="400"
                  aria-label="Board columns"
                  title={"Board columns (#{@column_range.first}–#{@column_range.last})"}
                  class="h-8 w-12 rounded-md border border-base-content/15 bg-base-100 px-1 text-center text-xs tabular-nums text-base-content focus:border-primary focus:outline-none"
                />
              </form>
              <span aria-hidden="true" class="text-sm text-base-content/50">×</span>
              <form id="bento-rows-form" phx-change="set_bento_rows">
                <input
                  type="number"
                  id="bento-rows-input"
                  name="value"
                  value={@rows}
                  min={@min_rows}
                  max={@row_range.last}
                  step="1"
                  inputmode="numeric"
                  phx-debounce="400"
                  aria-label="Board rows"
                  title={"Board rows (#{@min_rows}–#{@row_range.last}); cards set the minimum"}
                  class="h-8 w-12 rounded-md border border-base-content/15 bg-base-100 px-1 text-center text-xs tabular-nums text-base-content focus:border-primary focus:outline-none"
                />
              </form>
            </div>
          <% else %>
            <span
              id="bento-size"
              class="inline-flex h-8 items-center gap-1.5 rounded-md border border-base-content/10 px-2.5 text-xs tabular-nums text-base-content/50"
              title={"Board grid: #{@columns} × #{@rows} (columns × rows)"}
              aria-label={"Board grid: #{@columns} by #{@rows} rows"}
            >
              <.icon name="hero-table-cells" class="size-4" /> {@columns} × {@rows}
            </span>
          <% end %>

          <UIButton.button
            :if={@edit_structure?}
            type="button"
            id="add-card-button"
            variant="outline"
            size="sm"
            phx-click="add_card"
          >
            <.icon name="hero-plus" class="size-4" /> Add card
          </UIButton.button>
        </div>
      </div>

      <div class="canvas-bento-scroll min-h-0 flex-1 overflow-auto p-3 lg:flex-none lg:overflow-visible">
        <%= if @cards == [] do %>
          <div
            id="bento-empty"
            class="flex min-h-0 h-full flex-col items-center justify-center gap-3 rounded-xl border border-dashed border-base-content/20 p-8 text-center"
          >
            <.icon name="hero-squares-plus" class="size-8 text-base-content/30" />
            <p class="text-sm text-base-content/60">This board has no cards yet.</p>

            <UIButton.button
              type="button"
              id="empty-add-card"
              variant="outline"
              size="sm"
              phx-click="add_card"
            >
              Add the first card
            </UIButton.button>
          </div>
        <% else %>
          <div
            id="bento-board"
            phx-hook="BentoBoard"
            data-columns={Structure.columns(@cells)}
            data-max-columns={Structure.column_range().last}
            data-unit-x={bento_unit_x(Structure.columns(@cells))}
            data-unit-y={Structure.unit_px()}
            class="bento-board grid gap-2"
            style={Structure.board_style(@columns, @rows)}
          >
            <div
              :for={card <- @cards}
              id={"bento-card-#{card.key}"}
              class="bento-card relative min-h-0 rounded-lg"
              style={Structure.placement_style(card)}
              data-bento-size={Structure.size_label(card.w, card.h)}
              title={"Card grid: #{Structure.size_label(card.w, card.h)} (columns × rows)"}
            >
              <Cell.card
                cell_key={card.key}
                cell_data={Map.get(@cells, card.key, %{})}
                edit_structure?={@edit_structure?}
                user_id={@user_id}
                focus_cell={@focus_cell}
                accent_top={card.accent}
                class="h-full"
                body_class={@edit_structure? && "pt-10 sm:pt-8"}
                outline={card.accent}
                colors_control?={false}
                nav={Structure.neighbours(@cells, card.key)}
                colors_picker={@colors_picker}
              />

              <div
                :if={@colors_picker == card.key}
                id={"cell-colors-panel-" <> card.key}
                data-color-picker
                class="absolute left-1 top-11 z-40 rounded-md border border-base-content/10 bg-base-100 p-2 shadow-lg sm:left-auto sm:right-1 sm:top-9"
              >
                <.colors_panel
                  cell_key={card.key}
                  background={Map.get(@cells, card.key, %{})["background"]}
                  outline={card.accent}
                />
              </div>
              <%= if @edit_structure? do %>
                <%!-- On a phone a wide card starts off-screen to the right, so
                the controls sit at its left edge (the first part the pan
                reaches); a pointer device gets them at the top right. --%>
                <div class="absolute left-1 top-1 z-20 flex items-center gap-1 rounded-md bg-base-100/90 p-0.5 shadow-sm sm:left-auto sm:right-1">
                  <%!-- The card's real grid: width × height in columns and rows. --%>
                  <span
                    id={"bento-size-" <> card.key}
                    class="px-1 text-[0.65rem] tabular-nums text-base-content/50"
                    aria-label={
                      "Card grid: #{Structure.size_label(card.w, card.h)} columns by rows"
                    }
                  >
                    {Structure.size_label(card.w, card.h)}
                  </span>

                  <button
                    type="button"
                    data-bento-drag
                    id={"bento-move-" <> card.key}
                    phx-keydown="nudge_card"
                    phx-value-cell_key={card.key}
                    class="inline-flex size-8 cursor-move touch-none items-center justify-center rounded text-base-content/60 hover:bg-base-content/10 focus:outline-none focus-visible:ring-2 focus-visible:ring-primary sm:size-6"
                    title="Drag to move, or use the arrow keys (Shift to resize)"
                    aria-label={"Move #{card.label}. Use the arrow keys, with shift to resize."}
                  >
                    <.icon name="hero-arrows-pointing-out" class="size-3.5" />
                  </button>

                  <.colors_button
                    cell_key={card.key}
                    background={Map.get(@cells, card.key, %{})["background"]}
                    outline={card.accent}
                    open?={@colors_picker == card.key}
                  />

                  <button
                    type="button"
                    id={"remove-card-" <> card.key}
                    phx-click="request_remove_card"
                    phx-value-cell_key={card.key}
                    class="inline-flex size-8 items-center justify-center rounded border border-error/40 text-error transition-colors hover:bg-error/10 sm:size-6"
                    title="Remove card"
                    aria-label={"Remove #{card.label}"}
                  >
                    <.icon name="hero-x-mark" class="size-3" />
                  </button>
                </div>

                <button
                  type="button"
                  data-bento-resize
                  class="absolute -bottom-1 -right-1 z-20 size-6 cursor-nwse-resize touch-none rounded-sm border border-primary/50 bg-base-100 sm:size-4"
                  title="Resize"
                  aria-label={"Resize #{card.label}"}
                ></button>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # The nominal width of one grid column, for the drag hook. The real width is
  # measured in the browser; this keeps the initial conversion sane before the
  # first measurement.
  defp bento_unit_x(columns) when columns > 0, do: div(960, columns)
end
