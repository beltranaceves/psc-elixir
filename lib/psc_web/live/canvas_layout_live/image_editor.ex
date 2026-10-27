defmodule PscWeb.CanvasLayoutLive.ImageEditor do
  @moduledoc """
  The designer's board for an image template.

  An image template is stored in the same flat shape as an image canvas - one
  entry per cell with a `"placement"` in percent of the backdrop - so the frame,
  the geometry helpers and the backdrop controls are shared with the canvas
  through `PscWeb.Components.ImageBoard` and `Psc.Canvas.Structure`. The
  designer edits the definition (label, kind, fields, defaults, section titles);
  the canvas edits the values.

  Moving and resizing work exactly as on the canvas: the shared `ImageBoard`
  hook previews the gesture and pushes one `move_card` / `resize_card`. The
  arrow keys on the move grip are the keyboard path, and they are also what a
  browser test can drive deterministically.
  """

  use Phoenix.Component

  import PscWeb.Components.Accent
  import PscWeb.CoreComponents, only: [icon: 1]

  alias Psc.Canvas.Accent
  alias Psc.Canvas.Structure
  alias PscWeb.Components.ImageBoard, as: ImageFrame
  alias PscWeb.Components.UI.Button, as: UIButton

  attr :layout_map, :map, required: true
  attr :can_edit?, :boolean, required: true
  attr :accent_picker, :any, default: nil

  def editor(assigns) do
    assigns = assign(assigns, :cards, Structure.cards(assigns.layout_map))

    ~H"""
    <div class="flex flex-col gap-3">
      <div class="flex flex-wrap items-center justify-between gap-2">
        <span
          id="designer-image-size"
          class="inline-flex h-8 items-center gap-1.5 rounded-md border border-base-content/10 px-2.5 text-xs tabular-nums text-base-content/50"
          title="Cells placed on the picture"
        >
          <.icon name="hero-photo" class="size-4" /> {cell_count(length(@cards))} on a picture
        </span>

        <div :if={@can_edit?} class="flex flex-wrap gap-2">
          <UIButton.button
            type="button"
            id="designer-add-cell"
            variant="outline"
            size="sm"
            phx-click="add_card"
          >
            <.icon name="hero-plus" class="size-4" /> Add cell
          </UIButton.button>

          <UIButton.button
            type="button"
            id="designer-add-text"
            variant="outline"
            size="sm"
            phx-click="add_text"
          >
            <.icon name="hero-language" class="size-4" /> Add text
          </UIButton.button>
        </div>
      </div>

      <div class="rounded-lg border border-base-content/10 bg-base-200/40 p-2">
        <ImageFrame.backdrop_controls
          cells={@layout_map}
          can_edit?={@can_edit?}
          id_prefix="designer-backdrop"
        />
      </div>

      <%= if @cards == [] do %>
        <p class="rounded-lg border border-dashed border-base-content/20 p-6 text-center text-sm text-base-content/50">
          Add at least one cell to start building your image board.
        </p>
      <% else %>
        <ImageFrame.board cells={@layout_map} board_id="designer-image">
          <:cell :let={card}>
            <div class="relative h-full">
              <%!-- The dashed outline is the cell's real footprint; the editor
              box above it grows with its fields (like a bento card's height)
              so a small placement does not hide the definition. --%>
              <div
                class="pointer-events-none absolute inset-0 rounded-md border border-dashed border-primary/30"
                aria-hidden="true"
              >
              </div>

              <div class="absolute inset-x-0 top-0 z-10 flex min-h-full flex-col overflow-hidden rounded-md border border-base-content/15 bg-base-100 p-1.5 shadow-md">
                <div class="mb-1 flex shrink-0 flex-wrap items-center gap-1">
                  <span
                    id={"designer-image-size-" <> card.key}
                    class="shrink-0 px-0.5 text-[0.65rem] tabular-nums text-base-content/50"
                    aria-label={
                    "Cell placement: #{Structure.image_size_label(card.w, card.h)} of the picture"
                  }
                  >
                    {Structure.image_size_label(card.w, card.h)}
                  </span>

                  <button
                    :if={@can_edit?}
                    type="button"
                    data-image-drag
                    id={"designer-image-move-" <> card.key}
                    phx-keydown="nudge_card"
                    phx-value-cell_key={card.key}
                    class="inline-flex size-6 shrink-0 cursor-move touch-none items-center justify-center rounded text-base-content/60 hover:bg-base-content/10 focus:outline-none focus-visible:ring-2 focus-visible:ring-primary"
                    title="Drag to move, or use the arrow keys (Shift to resize)"
                    aria-label={"Move #{card.label}. Use the arrow keys, with shift to resize."}
                  >
                    <.icon name="hero-arrows-pointing-out" class="size-3.5" />
                  </button>

                  <form
                    id={"image-label-" <> card.key}
                    phx-change="update_cell_meta"
                    class="min-w-0 flex-1 basis-24"
                  >
                    <input type="hidden" name="cell_key" value={card.key} />
                    <input type="hidden" name="field" value="label" />
                    <input
                      type="text"
                      id={"image-" <> card.key <> "-label"}
                      name="value"
                      value={card.label}
                      phx-debounce="300"
                      disabled={!@can_edit?}
                      aria-label="Cell label"
                      class="w-full min-w-0 rounded border border-transparent bg-transparent px-1.5 py-0.5 text-sm font-medium text-base-content hover:border-base-content/10 focus:border-primary focus:outline-none"
                    />
                  </form>

                  <button
                    :if={@can_edit?}
                    type="button"
                    id={"designer-image-kind-" <> card.key}
                    phx-click="set_cell_kind"
                    phx-value-cell_key={card.key}
                    phx-value-kind={if card.kind == "text", do: "card", else: "text"}
                    class="shrink-0 rounded px-1 text-[0.65rem] font-medium text-base-content/60 hover:bg-base-content/10 hover:text-base-content"
                    title={
                      if card.kind == "text",
                        do: "Turn this text into a card with fields",
                        else: "Turn this card into a plain text label"
                    }
                  >
                    {if card.kind == "text", do: "Card", else: "Text"}
                  </button>

                  <button
                    :if={@can_edit?}
                    type="button"
                    id={"designer-image-accent-" <> card.key}
                    phx-click="toggle_card_accent"
                    phx-value-cell_key={card.key}
                    class={[
                      "size-5 shrink-0 rounded-full ring-2 ring-base-content/25 transition hover:ring-primary",
                      swatch_class(card.accent)
                    ]}
                    title="Cell colour"
                    aria-label={"Colour for #{card.label}"}
                  ></button>
                  <button
                    :if={@can_edit?}
                    type="button"
                    id={"designer-remove-image-" <> card.key}
                    phx-click="remove_card"
                    phx-value-cell_key={card.key}
                    class="inline-flex size-5 shrink-0 items-center justify-center rounded border border-error/40 text-error transition-colors hover:bg-error/10"
                    title="Remove cell"
                    aria-label={"Remove #{card.label}"}
                  >
                    <.icon name="hero-x-mark" class="size-3" />
                  </button>
                </div>

                <div
                  :if={@accent_picker == {:card, card.key}}
                  id={"accent-picker-image-" <> card.key}
                  class="mb-1 flex shrink-0 flex-wrap items-center gap-1 rounded-md bg-base-200 p-1"
                >
                  <button
                    :for={token <- Accent.tokens()}
                    type="button"
                    phx-click="set_card_accent"
                    phx-value-cell_key={card.key}
                    phx-value-accent={token}
                    class={[
                      "size-4 rounded-full ring-1 ring-base-content/25 transition hover:scale-110",
                      swatch_class(token),
                      card.accent == token && "ring-2 ring-primary"
                    ]}
                    title={token}
                    aria-label={"Set cell accent #{token}"}
                  ></button>
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

                <div class="min-h-0 flex-1">
                  <div
                    :if={card.kind == "text"}
                    id={"designer-image-text-preview-" <> card.key}
                    class="mb-1 truncate rounded border border-dashed border-base-content/20 bg-base-200/70 px-1.5 py-1 text-center text-xs font-semibold text-base-content/70"
                    title="On a canvas this cell is a plain text label"
                  >
                    {text_preview(@layout_map, card.key)}
                  </div>

                  <ul class="space-y-1">
                    <li
                      :for={field <- card_fields(@layout_map, card.key)}
                      class="flex items-center gap-1"
                    >
                      <form
                        id={"cell-#{card.key}-field-#{field}-title-form"}
                        phx-change="update_cell_field_title"
                        class="min-w-0 flex-1"
                      >
                        <input type="hidden" name="cell_key" value={card.key} />
                        <input type="hidden" name="field" value={field} />
                        <input
                          type="text"
                          id={"cell-#{card.key}-field-#{field}-title"}
                          name="value"
                          value={field_title(@layout_map, card.key, field)}
                          phx-debounce="300"
                          placeholder={field}
                          disabled={!@can_edit?}
                          aria-label={"Section title for #{field}"}
                          class="w-full min-w-0 rounded border border-base-content/10 bg-base-200 px-1.5 py-0.5 text-xs font-medium text-base-content placeholder-base-content/35 focus:border-primary focus:outline-none"
                        />
                      </form>

                      <form
                        id={"cell-#{card.key}-field-#{field}-form"}
                        phx-change="update_cell_field_default"
                        class="min-w-0 flex-1"
                      >
                        <input type="hidden" name="cell_key" value={card.key} />
                        <input type="hidden" name="field" value={field} />
                        <input
                          type="text"
                          id={"cell-#{card.key}-field-#{field}"}
                          name="value"
                          value={field_default(@layout_map, card.key, field)}
                          phx-debounce="300"
                          placeholder="Default"
                          disabled={!@can_edit?}
                          aria-label={"Default value for #{field}"}
                          class="w-full min-w-0 rounded border border-base-content/10 bg-base-200 px-1.5 py-0.5 text-xs text-base-content placeholder-base-content/35 focus:border-primary focus:outline-none"
                        />
                      </form>

                      <button
                        :if={@can_edit?}
                        type="button"
                        phx-click="remove_cell_field"
                        phx-value-cell_key={card.key}
                        phx-value-field={field}
                        class="inline-flex size-4 shrink-0 items-center justify-center rounded border border-error/40 text-error/90 hover:border-error hover:bg-error/10"
                        title={"Remove field #{field}"}
                        aria-label={"Remove field #{field}"}
                      >
                        <.icon name="hero-x-mark" class="size-2.5" />
                      </button>
                    </li>
                  </ul>

                  <form
                    :if={@can_edit?}
                    id={"cell-#{card.key}-add-field-form"}
                    phx-submit="add_cell_field"
                    class="mt-1 flex gap-1"
                  >
                    <input type="hidden" name="cell_key" value={card.key} />
                    <input
                      type="text"
                      id={"cell-#{card.key}-new-field"}
                      name="field"
                      placeholder="New field"
                      aria-label="New field name"
                      class="min-w-0 flex-1 rounded border border-base-content/10 bg-base-200 px-1.5 py-0.5 text-xs text-base-content placeholder-base-content/35 focus:border-primary focus:outline-none"
                    />
                    <button
                      type="submit"
                      class="shrink-0 rounded border border-base-content/10 px-1.5 py-0.5 text-xs text-base-content/70 transition-colors hover:bg-base-content/5"
                    >
                      Add
                    </button>
                  </form>
                </div>
              </div>

              <button
                :if={@can_edit?}
                type="button"
                data-image-resize
                id={"designer-image-resize-" <> card.key}
                class="absolute -bottom-1 -right-1 z-40 size-5 cursor-nwse-resize touch-none rounded-sm border border-primary/50 bg-base-100"
                title="Resize"
                aria-label={"Resize #{card.label}"}
              ></button>
            </div>
          </:cell>
        </ImageFrame.board>
      <% end %>
    </div>
    """
  end

  defp cell_count(1), do: "1 cell"
  defp cell_count(count), do: "#{count} cells"

  defp card_fields(lm, key), do: (Structure.cell(lm, key) || %{})["fields"] || []

  defp field_title(lm, key, field),
    do: get_in(Structure.cell(lm, key) || %{}, ["titles", field]) || ""

  defp field_default(lm, key, field),
    do: get_in(Structure.cell(lm, key) || %{}, ["defaults", field]) || ""

  defp text_preview(lm, key) do
    case field_default(lm, key, "content") do
      "" -> "Plain text label"
      content -> content |> to_string() |> String.slice(0, 80)
    end
  end
end
