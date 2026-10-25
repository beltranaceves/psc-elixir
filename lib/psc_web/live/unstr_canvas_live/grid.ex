defmodule PscWeb.UnstrCanvasLive.Grid do
  @moduledoc false

  use Phoenix.Component

  import PscWeb.Components.Accent
  import PscWeb.CoreComponents, only: [icon: 1]
  import PscWeb.UnstrCanvasLive.Header, only: [canvas_status: 1, title_field: 1]

  alias PscWeb.Components.UI.Button, as: UIButton
  alias PscWeb.UnstrCanvasLive.Cell

  # Every data column may shrink to this width before the table stops fitting
  # the viewport and scrolls horizontally.
  @min_column_width_rem 12

  # The row-label column hugs the longest label instead of taking a fixed
  # share of the table. Measuring the text in the 14px the labels use keeps
  # that tight without a canvas measurement: capitals and wide letters take
  # more room than lowercase, a space less. The padding covers the cell's
  # px-2 plus the borders. The width is recomputed when the debounced label
  # reaches the server, never on every keystroke.
  @row_label_padding_px 22
  @row_label_min_px 56
  # Edit structure puts the accent swatch and the remove button beside the
  # label input, so the column cannot shrink to the text alone or the input
  # would be unusable.
  @row_label_edit_min_px 128

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

  def grid(assigns) do
    ~H"""
    <div
      id="canvas-grid"
      class="flex min-h-0 w-full flex-1 flex-col overflow-hidden rounded-xl border border-base-content/20 bg-base-200"
    >
      <%!-- Structure editing is available to everyone with access to the
              canvas: the toggle, and — while it is on — the add actions. --%>
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
            id="edit-structure-toggle"
            phx-click="toggle_structure"
            aria-pressed={to_string(@edit_structure?)}
            class={[
              "inline-flex items-center gap-1.5 rounded-lg border px-2.5 py-1 text-xs font-medium transition-colors",
              @edit_structure? &&
                "border-primary/50 bg-primary/10 text-base-content",
              not @edit_structure? &&
                "border-base-content/10 text-base-content/70 hover:bg-base-content/5 hover:text-base-content"
            ]}
          >
            <.icon name="hero-pencil-square" class="size-4" /> Edit structure
          </button>

          <%= if @edit_structure? do %>
            <UIButton.button
              type="button"
              variant="outline"
              size="sm"
              phx-click="add_column"
            >
              Add Column
            </UIButton.button>

            <UIButton.button type="button" variant="outline" size="sm" phx-click="add_row">
              Add Row
            </UIButton.button>
          <% end %>
        </div>
      </div>

      <div class="canvas-grid-scroll flex min-h-0 flex-1 flex-col overflow-auto">
        <%= if structure_empty?(@cells) do %>
          <%!-- A blank canvas: nothing to render as a table yet. Anyone
                  with access can build the first row and column here. --%>
          <div class="flex min-h-0 flex-1 flex-col items-center justify-center gap-3 p-8 text-center">
            <.icon name="hero-squares-2x2" class="size-8 text-base-content/30" />
            <p class="text-sm text-base-content/60">This canvas has no structure yet.</p>

            <div class="flex gap-2">
              <UIButton.button
                type="button"
                id="empty-add-row"
                variant="outline"
                size="sm"
                phx-click="add_row"
              >
                Add row
              </UIButton.button>

              <UIButton.button
                type="button"
                id="empty-add-column"
                variant="outline"
                size="sm"
                phx-click="add_column"
              >
                Add column
              </UIButton.button>
            </div>
          </div>
        <% else %>
          <table
            class="h-full min-h-0 w-full flex-1 table-fixed border-collapse"
            style={"min-width: #{table_min_width(@cells, @edit_structure?)}"}
          >
            <colgroup>
              <col style={"width: #{row_label_width(@cells, @edit_structure?)}"} />
              <%= for _column <- @cells["columns"] || [] do %>
                <col />
              <% end %>
            </colgroup>

            <thead>
              <tr>
                <th class="px-2 py-1 border border-base-content/20 bg-base-content/5"></th>

                <%= for column <- @cells["columns"] || [] do %>
                  <th class="border border-base-content/20 bg-base-content/5 p-0 align-bottom font-medium text-base-content/70 text-sm">
                    <div class="flex flex-col">
                      <.accent_bar
                        id={"accent-bar-column-#{column["id"]}"}
                        token={column["accent"]}
                      />
                      <div class="px-2 py-1">
                        <%= if @edit_structure? do %>
                          <%!-- Same treatment as the row header: the input
                                  takes the full width, the controls sit beside it
                                  on a pointer and below it on a phone. --%>
                          <div class="flex flex-col gap-1 sm:flex-row sm:items-center sm:gap-1">
                            <.form
                              for={%{}}
                              id={"column-" <> column["id"] <> "-label-form"}
                              phx-change="update_column_label"
                              class="min-w-0 flex-1"
                            >
                              <input type="hidden" name="structure_id" value={column["id"]} />
                              <input
                                type="text"
                                id={"column-" <> column["id"] <> "-label"}
                                name="label"
                                value={column["label"]}
                                phx-debounce="300"
                                class="w-full min-w-0 rounded border border-transparent bg-transparent px-1.5 py-1.5 text-inherit hover:border-base-content/10 focus:border-primary focus:outline-none sm:py-0.5"
                              />
                            </.form>

                            <div class="flex shrink-0 items-center gap-1.5 sm:gap-1">
                              <button
                                type="button"
                                data-color-picker
                                id={"accent-swatch-column-" <> column["id"]}
                                phx-click="toggle_structure_accent"
                                phx-value-group="column"
                                phx-value-id={column["id"]}
                                class={[
                                  "size-7 shrink-0 rounded-full ring-2 ring-base-content/25 hover:ring-primary transition sm:size-3.5",
                                  swatch_class(column["accent"])
                                ]}
                                title="Accent color"
                                aria-label={"Accent color for column #{column["label"]}"}
                              ></button>
                              <button
                                type="button"
                                phx-click="request_remove_column"
                                phx-value-id={column["id"]}
                                class="inline-flex size-7 shrink-0 items-center justify-center rounded-md border border-error/40 text-error transition-colors hover:border-error hover:bg-error/10 sm:size-5"
                                title="Remove column"
                                aria-label={"Remove column #{column["label"]}"}
                              >
                                <.icon name="hero-x-mark" class="size-3.5 sm:size-3" />
                              </button>
                            </div>
                          </div>

                          <div
                            :if={@structure_accent_picker == {:column, column["id"]}}
                            data-color-picker
                            class="mt-1 flex flex-wrap items-center gap-1 rounded-md bg-base-100/80 p-1"
                          >
                            <%= for token <- Psc.Canvas.Accent.tokens() do %>
                              <button
                                type="button"
                                phx-click="set_column_accent"
                                phx-value-id={column["id"]}
                                phx-value-accent={token}
                                class={[
                                  "size-6 rounded-full ring-1 ring-base-content/25 hover:scale-110 transition sm:size-3",
                                  swatch_class(token),
                                  column["accent"] == token &&
                                    "ring-2 ring-primary ring-offset-1 ring-offset-base-100"
                                ]}
                                title={token}
                                aria-label={"Set column accent #{token}"}
                              ></button>
                            <% end %>

                            <button
                              type="button"
                              phx-click="set_column_accent"
                              phx-value-id={column["id"]}
                              phx-value-accent=""
                              class="px-1 text-[0.65rem] text-base-content/50 hover:text-base-content"
                            >
                              None
                            </button>
                          </div>
                        <% else %>
                          {column["label"]}
                        <% end %>
                      </div>
                    </div>
                  </th>
                <% end %>
              </tr>
            </thead>

            <tbody>
              <%= for {row, row_index} <- Enum.with_index(@cells["rows"] || []) do %>
                <tr>
                  <td class="relative border border-base-content/20 bg-base-content/5 p-0 align-top">
                    <.accent_bar
                      id={"accent-bar-row-#{row["id"]}"}
                      token={row["accent"]}
                      orientation={:left}
                    />
                    <div class="px-2 py-1">
                      <%= if @edit_structure? do %>
                        <%!-- The input gets the full width of the column; the
                                swatch and the remove button sit beside it on a
                                pointer and below it on a phone, where a 14px
                                swatch is not a target anyone can hit. --%>
                        <div class="flex flex-col gap-1 sm:flex-row sm:items-center sm:gap-1">
                          <.form
                            for={%{}}
                            id={"row-" <> row["id"] <> "-label-form"}
                            phx-change="update_row_label"
                            class="min-w-0 flex-1"
                          >
                            <input type="hidden" name="structure_id" value={row["id"]} />
                            <input
                              type="text"
                              id={"row-" <> row["id"] <> "-label"}
                              name="label"
                              value={row["label"]}
                              phx-debounce="300"
                              class="w-full min-w-0 rounded border border-transparent bg-transparent px-1.5 py-1.5 text-inherit hover:border-base-content/10 focus:border-primary focus:outline-none sm:py-0.5"
                            />
                          </.form>

                          <div class="flex shrink-0 items-center gap-1.5 sm:gap-1">
                            <button
                              type="button"
                              data-color-picker
                              id={"accent-swatch-row-" <> row["id"]}
                              phx-click="toggle_structure_accent"
                              phx-value-group="row"
                              phx-value-id={row["id"]}
                              class={[
                                "size-7 shrink-0 rounded-full ring-2 ring-base-content/25 hover:ring-primary transition sm:size-3.5",
                                swatch_class(row["accent"])
                              ]}
                              title="Accent color"
                              aria-label={"Accent color for row #{row["label"]}"}
                            ></button>
                            <button
                              type="button"
                              phx-click="request_remove_row"
                              phx-value-id={row["id"]}
                              class="inline-flex size-7 shrink-0 items-center justify-center rounded-md border border-error/40 text-error transition-colors hover:border-error hover:bg-error/10 sm:size-5"
                              title="Remove row"
                              aria-label={"Remove row #{row["label"]}"}
                            >
                              <.icon name="hero-x-mark" class="size-3.5 sm:size-3" />
                            </button>
                          </div>
                        </div>

                        <div
                          :if={@structure_accent_picker == {:row, row["id"]}}
                          data-color-picker
                          class="mt-1 flex flex-wrap items-center gap-1 rounded-md bg-base-100/80 p-1"
                        >
                          <%= for token <- Psc.Canvas.Accent.tokens() do %>
                            <button
                              type="button"
                              phx-click="set_row_accent"
                              phx-value-id={row["id"]}
                              phx-value-accent={token}
                              class={[
                                "size-6 rounded-full ring-1 ring-base-content/25 hover:scale-110 transition sm:size-3",
                                swatch_class(token),
                                row["accent"] == token &&
                                  "ring-2 ring-primary ring-offset-1 ring-offset-base-100"
                              ]}
                              title={token}
                              aria-label={"Set row accent #{token}"}
                            ></button>
                          <% end %>

                          <button
                            type="button"
                            phx-click="set_row_accent"
                            phx-value-id={row["id"]}
                            phx-value-accent=""
                            class="px-1 text-[0.65rem] text-base-content/50 hover:text-base-content"
                          >
                            None
                          </button>
                        </div>
                      <% else %>
                        <div
                          class="truncate font-medium text-base-content/70 text-sm"
                          title={row["label"]}
                        >
                          {row["label"]}
                        </div>
                      <% end %>
                    </div>
                  </td>

                  <%= for {column, col_index} <- Enum.with_index(@cells["columns"] || []) do %>
                    <% layout = @cells["layout"] || [] %> <% cell_key =
                      Enum.at(Enum.at(layout, row_index, []), col_index) %>
                    <td class="relative border border-base-content/20 align-top">
                      <%= if cell_key do %>
                        <% cell_data =
                          get_in(@cells, ["cells", cell_key]) || @cells[cell_key] || %{} %>
                        <Cell.card
                          cell_key={cell_key}
                          cell_data={cell_data}
                          edit_structure?={@edit_structure?}
                          user_id={@user_id}
                          focus_cell={@focus_cell}
                          accent_top={column["accent"]}
                          accent_left={row["accent"]}
                          colors_picker={@colors_picker}
                          colors_palette?
                        />
                      <% end %>
                    </td>
                  <% end %>
                </tr>
              <% end %>
            </tbody>
          </table>
        <% end %>
      </div>
    </div>
    """
  end

  defp table_min_width(cells, edit_structure?) do
    columns = length(cells["columns"] || [])
    "calc(#{row_label_width(cells, edit_structure?)} + #{columns * @min_column_width_rem}rem)"
  end

  defp row_label_width(cells, edit_structure?) do
    width = cells |> longest_row_label() |> label_text_px() |> Kernel.+(@row_label_padding_px)
    width = max(width, if(edit_structure?, do: @row_label_edit_min_px, else: @row_label_min_px))
    "#{width}px"
  end

  defp longest_row_label(cells) do
    cells
    |> Map.get("rows", [])
    |> Enum.map(fn row -> row |> Map.get("label", "") |> to_string() end)
    |> Enum.max_by(&String.length/1, fn -> "" end)
  end

  defp label_text_px(label) do
    label
    |> String.graphemes()
    |> Enum.map(&glyph_px/1)
    |> Enum.sum()
  end

  defp glyph_px(" "), do: 4
  defp glyph_px(glyph) when glyph in ["m", "w", "M", "W"], do: 13

  defp glyph_px(glyph) do
    case String.to_charlist(glyph) do
      [codepoint] when codepoint > 0x2E80 -> 14
      _ -> if String.upcase(glyph) == glyph, do: 9, else: 7
    end
  end

  # A canvas with no rows or no columns has nothing to render as a table: the
  # empty state takes over, and anyone with access builds the structure in place.
  defp structure_empty?(cells) do
    Map.get(cells, "rows", []) == [] or Map.get(cells, "columns", []) == []
  end
end
