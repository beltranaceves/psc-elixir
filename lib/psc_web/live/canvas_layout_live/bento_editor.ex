defmodule PscWeb.CanvasLayoutLive.BentoEditor do
  @moduledoc """
  The designer's board for a bento template.

  A bento template is stored in the same flat shape as a bento canvas - one
  entry per card with a `"placement"` - so the geometry helpers are shared with
  the canvas through `Psc.Canvas.Structure`. The designer edits the definition
  (labels, fields, defaults, section titles); the canvas edits the values.

  The board is keyboard-first: the move grip takes arrow keys (shift to
  resize), which is both the accessible path and the one a browser test can
  drive deterministically. Pointing devices get the same drag/resize corners as
  the canvas through the `BentoBoard` hook.
  """

  use Phoenix.Component

  import PscWeb.Components.Accent
  import PscWeb.CoreComponents, only: [icon: 1]

  alias Psc.Canvas.Accent
  alias Psc.Canvas.Structure
  alias PscWeb.Components.UI.Button, as: UIButton

  attr :layout_map, :map, required: true
  attr :can_edit?, :boolean, required: true
  attr :accent_picker, :any, default: nil

  def editor(assigns) do
    bounds = Structure.bounds(assigns.layout_map)

    assigns =
      assigns
      |> assign(:cards, Structure.cards(assigns.layout_map))
      |> assign(:columns, bounds.columns)
      |> assign(:rows, bounds.rows)
      |> assign(:min_rows, Structure.content_rows(assigns.layout_map))
      |> assign(:column_range, Structure.column_range())
      |> assign(:row_range, Structure.row_range())

    ~H"""
    <div class="flex flex-col gap-3">
      <div class="flex flex-wrap items-center justify-between gap-2">
        <%!-- The board's own grid: the template's columns and its container
        height. Rows can exceed the cards, so a board can reserve space. --%>
        <div
          id="designer-bento-size"
          class="inline-flex h-8 items-center gap-1 text-xs tabular-nums text-base-content/60"
        >
          <.icon name="hero-table-cells" class="size-4 shrink-0" />
          <form id="designer-columns-form" phx-change="set_bento_columns">
            <input
              type="number"
              id="designer-bento-columns"
              name="value"
              value={@columns}
              min={@column_range.first}
              max={@column_range.last}
              step="1"
              inputmode="numeric"
              phx-debounce="400"
              disabled={!@can_edit?}
              aria-label="Board columns"
              title={"Board columns (#{@column_range.first}–#{@column_range.last})"}
              class="h-8 w-12 rounded-md border border-base-content/15 bg-base-100 px-1 text-center text-xs tabular-nums text-base-content focus:border-primary focus:outline-none disabled:opacity-60"
            />
          </form>
          <span aria-hidden="true" class="text-sm text-base-content/50">×</span>
          <form id="designer-rows-form" phx-change="set_bento_rows">
            <input
              type="number"
              id="designer-bento-rows"
              name="value"
              value={@rows}
              min={@min_rows}
              max={@row_range.last}
              step="1"
              inputmode="numeric"
              phx-debounce="400"
              disabled={!@can_edit?}
              aria-label="Board rows"
              title={"Board rows (#{@min_rows}–#{@row_range.last}); cards set the minimum"}
              class="h-8 w-12 rounded-md border border-base-content/15 bg-base-100 px-1 text-center text-xs tabular-nums text-base-content focus:border-primary focus:outline-none disabled:opacity-60"
            />
          </form>
        </div>

        <UIButton.button
          :if={@can_edit?}
          type="button"
          id="designer-add-card"
          variant="outline"
          size="sm"
          phx-click="add_card"
        >
          <.icon name="hero-plus" class="size-4" /> Add card
        </UIButton.button>
      </div>

      <div class="overflow-auto rounded-xl border border-base-content/10 bg-base-200/40 p-3">
        <%= if @cards == [] do %>
          <p class="p-6 text-center text-sm text-base-content/50">
            Add at least one card to start building your board.
          </p>
        <% else %>
          <div
            id="designer-bento"
            phx-hook="BentoBoard"
            data-columns={@columns}
            class="bento-board grid gap-2"
            style={Structure.board_style(@columns, @rows)}
          >
            <div
              :for={card <- @cards}
              id={"bento-card-#{card.key}"}
              class="relative min-h-0 rounded-lg border border-base-content/15 bg-base-100 p-2"
              style={Structure.placement_style(card)}
              data-bento-size={Structure.size_label(card.w, card.h)}
              title={"Card grid: #{Structure.size_label(card.w, card.h)} (columns × rows)"}
            >
              <div class="mb-1 flex items-center gap-1">
                <%!-- The card's real grid: width × height in columns and rows.
                It leads the row, so it is the first thing a narrow screen
                shows when a wide card starts off-screen. --%>
                <span
                  id={"designer-size-" <> card.key}
                  class="shrink-0 px-0.5 text-[0.65rem] tabular-nums text-base-content/50"
                  aria-label={
                    "Card grid: #{Structure.size_label(card.w, card.h)} columns by rows"
                  }
                >
                  {Structure.size_label(card.w, card.h)}
                </span>

                <button
                  :if={@can_edit?}
                  type="button"
                  data-bento-drag
                  id={"designer-move-#{card.key}"}
                  phx-keydown="nudge_card"
                  phx-value-cell_key={card.key}
                  class="inline-flex size-8 cursor-move touch-none items-center justify-center rounded text-base-content/60 hover:bg-base-content/10 focus:outline-none focus-visible:ring-2 focus-visible:ring-primary sm:size-6"
                  title="Drag to move, or use the arrow keys (Shift to resize)"
                  aria-label={"Move #{card.label}. Use the arrow keys, with shift to resize."}
                >
                  <.icon name="hero-arrows-pointing-out" class="size-3.5" />
                </button>

                <form
                  id={"card-label-#{card.key}"}
                  phx-change="update_cell_meta"
                  class="min-w-0 flex-1"
                >
                  <input type="hidden" name="cell_key" value={card.key} />
                  <input type="hidden" name="field" value="label" />
                  <input
                    type="text"
                    id={"card-#{card.key}-label"}
                    name="value"
                    value={card.label}
                    phx-debounce="300"
                    disabled={!@can_edit?}
                    class="w-full rounded border border-transparent bg-transparent px-1.5 py-0.5 text-sm font-medium text-base-content hover:border-base-content/10 focus:border-primary focus:outline-none"
                  />
                </form>

                <button
                  :if={@can_edit?}
                  type="button"
                  id={"card-accent-#{card.key}"}
                  phx-click="toggle_card_accent"
                  phx-value-cell_key={card.key}
                  class={[
                    "size-5 shrink-0 rounded-full ring-2 ring-base-content/25 transition hover:ring-primary",
                    swatch_class(card.accent)
                  ]}
                  title="Card colour"
                  aria-label={"Colour for #{card.label}"}
                ></button>
                <button
                  :if={@can_edit?}
                  type="button"
                  id={"designer-remove-#{card.key}"}
                  phx-click="remove_card"
                  phx-value-cell_key={card.key}
                  class="inline-flex size-5 shrink-0 items-center justify-center rounded border border-error/40 text-error transition-colors hover:bg-error/10"
                  title="Remove card"
                  aria-label={"Remove #{card.label}"}
                >
                  <.icon name="hero-x-mark" class="size-3" />
                </button>
              </div>

              <div
                :if={@accent_picker == {:card, card.key}}
                id={"accent-picker-card-#{card.key}"}
                class="mb-1 flex flex-wrap items-center gap-1 rounded-md bg-base-200 p-1"
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
                  aria-label={"Set card accent #{token}"}
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
                  class="min-w-0 flex-1 rounded border border-base-content/10 bg-base-200 px-1.5 py-0.5 text-xs text-base-content placeholder-base-content/35 focus:border-primary focus:outline-none"
                />
                <button
                  type="submit"
                  class="shrink-0 rounded border border-base-content/10 px-1.5 py-0.5 text-xs text-base-content/70 hover:bg-base-content/5"
                >
                  Add
                </button>
              </form>

              <button
                :if={@can_edit?}
                type="button"
                data-bento-resize
                class="absolute -bottom-1 -right-1 size-6 cursor-nwse-resize touch-none rounded-sm border border-primary/50 bg-base-100 sm:size-4"
                title="Resize"
                aria-label={"Resize #{card.label}"}
              ></button>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp card_fields(lm, key), do: (Structure.cell(lm, key) || %{})["fields"] || []

  defp field_title(lm, key, field),
    do: get_in(Structure.cell(lm, key) || %{}, ["titles", field]) || ""

  defp field_default(lm, key, field),
    do: get_in(Structure.cell(lm, key) || %{}, ["defaults", field]) || ""

  @doc false
  def empty_cell_meta do
    %{"label" => "", "fields" => ["content"], "defaults" => %{"content" => ""}}
  end
end
