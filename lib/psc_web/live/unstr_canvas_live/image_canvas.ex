defmodule PscWeb.UnstrCanvasLive.ImageCanvas do
  @moduledoc """
  The image view of a canvas: floating cells over a backdrop picture.

  A cell is the same cell the table and the bento render - a label, fields and
  Markdown editors - pinned at a percentage of the picture. An image cell can
  also be a bare `text` input: a one-line label placed directly on the picture,
  without a card frame.

  Geometry lives in the event log like any other edit. A drag or resize sends
  one operation when the gesture ends; the arrow keys on the move grip send one
  `nudge_card` per press. `Psc.Canvas.Structure` clamps every rectangle, so all
  open clients converge on the same board.
  """

  use Phoenix.Component

  import PscWeb.CoreComponents, only: [icon: 1]
  import PscWeb.UnstrCanvasLive.CellColors, only: [colors_button: 1, colors_panel: 1]
  import PscWeb.UnstrCanvasLive.Header, only: [canvas_status: 1, title_field: 1]

  alias Psc.Canvas.Structure
  alias PscWeb.Components.ImageBoard, as: ImageFrame
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
    assigns = assign(assigns, :cards, Structure.cards(assigns.cells))

    ~H"""
    <div
      id="canvas-image"
      class="flex min-h-0 w-full flex-1 flex-col overflow-hidden rounded-xl border border-base-content/20 bg-base-200"
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

          <span
            id="image-size"
            class="inline-flex h-8 items-center gap-1.5 rounded-md border border-base-content/10 px-2.5 text-xs tabular-nums text-base-content/50"
            title="Cells placed on the picture"
          >
            <.icon name="hero-photo" class="size-4" /> {@cards |> length() |> cell_count()}
          </span>

          <UIButton.button
            :if={@edit_structure?}
            type="button"
            id="add-image-cell"
            variant="outline"
            size="sm"
            phx-click="add_card"
          >
            <.icon name="hero-plus" class="size-4" /> Add cell
          </UIButton.button>

          <UIButton.button
            :if={@edit_structure?}
            type="button"
            id="add-image-text"
            variant="outline"
            size="sm"
            phx-click="add_text"
          >
            <.icon name="hero-language" class="size-4" /> Add text
          </UIButton.button>
        </div>
      </div>

      <div
        :if={@edit_structure?}
        class="shrink-0 border-b border-base-content/10 bg-base-200/60 px-3 py-2"
      >
        <ImageFrame.backdrop_controls cells={@cells} id_prefix="image-backdrop" />
      </div>

      <div class="canvas-image-scroll min-h-0 flex-1 overflow-auto p-3">
        <ImageFrame.board cells={@cells} board_id="image-board">
          <:cell :let={card}>
            <div class="relative h-full">
              <%= if card.kind == "text" do %>
                <Cell.text
                  cell_key={card.key}
                  cell_data={Map.get(@cells, card.key, %{})}
                  edit_structure?={@edit_structure?}
                  class="h-full"
                />
              <% else %>
                <Cell.card
                  cell_key={card.key}
                  cell_data={Map.get(@cells, card.key, %{})}
                  edit_structure?={@edit_structure?}
                  user_id={@user_id}
                  focus_cell={@focus_cell}
                  accent_top={card.accent}
                  class="h-full rounded-lg shadow-lg"
                  body_class={@edit_structure? && "pt-10 sm:pt-8"}
                  outline={card.accent}
                  colors_control?={false}
                  nav={Structure.neighbours(@cells, card.key)}
                  colors_picker={@colors_picker}
                />
              <% end %>

              <div
                :if={@edit_structure?}
                class="absolute right-0.5 top-0.5 z-30 flex items-center gap-0.5 rounded-md bg-base-100/95 p-0.5 shadow-sm"
              >
                <span
                  id={"image-size-" <> card.key}
                  class="px-1 text-[0.65rem] tabular-nums text-base-content/50"
                  aria-label={"Cell placement: #{Structure.image_size_label(card.w, card.h)}"}
                >
                  {Structure.image_size_label(card.w, card.h)}
                </span>

                <button
                  type="button"
                  data-image-drag
                  id={"image-move-" <> card.key}
                  phx-keydown="nudge_card"
                  phx-value-cell_key={card.key}
                  class="inline-flex size-7 cursor-move touch-none items-center justify-center rounded text-base-content/60 hover:bg-base-content/10 focus:outline-none focus-visible:ring-2 focus-visible:ring-primary"
                  title="Drag to move, or use the arrow keys (Shift to resize)"
                  aria-label={"Move #{card.label}. Use the arrow keys, with shift to resize."}
                >
                  <.icon name="hero-arrows-pointing-out" class="size-3.5" />
                </button>

                <button
                  type="button"
                  id={"image-kind-" <> card.key}
                  phx-click="set_cell_kind"
                  phx-value-cell_key={card.key}
                  phx-value-kind={if card.kind == "text", do: "card", else: "text"}
                  class="rounded px-1 text-[0.65rem] font-medium text-base-content/60 hover:bg-base-content/10 hover:text-base-content"
                  title={
                    if card.kind == "text",
                      do: "Turn this text into a card with fields",
                      else: "Turn this card into a plain text label"
                  }
                >
                  {if card.kind == "text", do: "Card", else: "Text"}
                </button>

                <.colors_button
                  cell_key={card.key}
                  background={Map.get(@cells, card.key, %{})["background"]}
                  outline={card.accent}
                  open?={@colors_picker == card.key}
                />

                <button
                  type="button"
                  id={"remove-image-cell-" <> card.key}
                  phx-click="request_remove_card"
                  phx-value-cell_key={card.key}
                  class="inline-flex size-6 items-center justify-center rounded border border-error/40 text-error transition-colors hover:bg-error/10"
                  title="Remove cell"
                  aria-label={"Remove #{card.label}"}
                >
                  <.icon name="hero-x-mark" class="size-3" />
                </button>
              </div>

              <div
                :if={@colors_picker == card.key}
                id={"cell-colors-panel-" <> card.key}
                data-color-picker
                class="absolute right-0 top-8 z-40 rounded-md border border-base-content/10 bg-base-100 p-2 shadow-lg"
              >
                <.colors_panel
                  cell_key={card.key}
                  background={Map.get(@cells, card.key, %{})["background"]}
                  outline={card.accent}
                />
              </div>

              <button
                :if={@edit_structure?}
                type="button"
                data-image-resize
                id={"image-resize-" <> card.key}
                class="absolute -bottom-1 -right-1 z-30 size-5 cursor-nwse-resize touch-none rounded-sm border border-primary/50 bg-base-100"
                title="Resize"
                aria-label={"Resize #{card.label}"}
              ></button>
            </div>
          </:cell>
        </ImageFrame.board>
      </div>
    </div>
    """
  end

  defp cell_count(1), do: "1 cell"
  defp cell_count(count), do: "#{count} cells"
end
