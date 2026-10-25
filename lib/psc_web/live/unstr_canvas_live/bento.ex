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

  import PscWeb.Components.Accent
  import PscWeb.CoreComponents, only: [icon: 1]

  alias Psc.Canvas.Structure
  alias PscWeb.Components.UI.Button, as: UIButton
  alias PscWeb.UnstrCanvasLive.Cell

  attr :cells, :map, required: true
  attr :edit_structure?, :boolean, required: true
  attr :structure_accent_picker, :any, default: nil
  attr :focus_cell, :string, default: nil
  attr :user_id, :integer, required: true

  def board(assigns) do
    assigns = assign(assigns, :cards, Structure.cards(assigns.cells))

    ~H"""
    <div
      id="canvas-bento"
      class="flex min-h-0 w-full flex-1 flex-col overflow-hidden rounded-xl border border-base-content/20 bg-base-200"
    >
      <div class="flex shrink-0 items-center justify-between gap-2 border-b border-base-content/10 px-3 py-2">
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

      <div class="canvas-bento-scroll min-h-0 flex-1 overflow-auto p-3">
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
            data-unit-x={bento_unit_x(Structure.columns(@cells))}
            data-unit-y={Structure.unit_px()}
            class="bento-board grid gap-2"
            style={Structure.board_style(Structure.columns(@cells))}
          >
            <div
              :for={card <- @cards}
              id={"bento-card-#{card.key}"}
              class="bento-card relative min-h-0 rounded-lg"
              style={Structure.placement_style(card)}
            >
              <Cell.card
                cell_key={card.key}
                cell_data={Map.get(@cells, card.key, %{})}
                edit_structure?={@edit_structure?}
                user_id={@user_id}
                focus_cell={@focus_cell}
                accent_top={card.accent}
                class="h-full"
                nav={Structure.neighbours(@cells, card.key)}
              />
              <%= if @edit_structure? do %>
                <div class="absolute right-1 top-1 z-20 flex items-center gap-1 rounded-md bg-base-100/90 p-0.5 shadow-sm">
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

                  <button
                    type="button"
                    id={"card-accent-" <> card.key}
                    phx-click="toggle_structure_accent"
                    phx-value-group="card"
                    phx-value-id={card.key}
                    class={[
                      "size-8 rounded-full ring-2 ring-base-content/20 transition hover:ring-primary sm:size-6",
                      swatch_class(card.accent)
                    ]}
                    title="Card colour"
                    aria-label={"Colour for #{card.label}"}
                  ></button>
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

                <div
                  :if={@structure_accent_picker == {:card, card.key}}
                  class="absolute right-1 top-9 z-30 flex flex-wrap items-center gap-1 rounded-md border border-base-content/10 bg-base-100 p-1 shadow-lg"
                >
                  <%= for token <- Psc.Canvas.Accent.tokens() do %>
                    <button
                      type="button"
                      phx-click="set_card_accent"
                      phx-value-cell_key={card.key}
                      phx-value-accent={token}
                      class={[
                        "size-5 rounded-full ring-1 ring-base-content/25 transition hover:scale-110",
                        swatch_class(token),
                        card.accent == token && "ring-2 ring-primary"
                      ]}
                      title={token}
                      aria-label={"Set card accent #{token}"}
                    ></button>
                  <% end %>

                  <button
                    type="button"
                    phx-click="set_card_accent"
                    phx-value-cell_key={card.key}
                    phx-value-accent=""
                    class="px-1 text-[0.65rem] text-base-content/50 hover:text-base-content"
                  >
                    None
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
