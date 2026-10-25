defmodule PscWeb.UnstrCanvasLive.Cell do
  @moduledoc false

  use Phoenix.Component

  import PscWeb.Components.Accent
  import PscWeb.CoreComponents, only: [icon: 1]

  import PscWeb.UnstrCanvasLive.CellColors,
    only: [colors_button: 1, colors_panel: 1]

  # One cell's body: the label, its fields and the Markdown editors. Shared by
  # the table grid and the bento board so the two layouts cannot drift - the
  # ids (`cell-card-<key>`, `cell-<key>-label`, `md-<key>-<field>`) are the
  # contract the hooks and the tests rely on.

  attr :cell_key, :string, required: true
  attr :cell_data, :map, required: true
  attr :edit_structure?, :boolean, required: true
  attr :user_id, :integer, required: true
  attr :focus_cell, :string, default: nil
  attr :accent_top, :string, default: nil
  attr :accent_left, :string, default: nil
  attr :class, :any, default: nil
  attr :nav, :map, default: nil
  attr :colors_picker, :string, default: nil
  attr :colors_palette?, :boolean, default: false
  attr :colors_control?, :boolean, default: true
  attr :body_class, :any, default: nil
  attr :outline, :string, default: nil

  def card(assigns) do
    background = normalize_background(Map.get(assigns.cell_data, "background"))

    assigns =
      assigns
      |> assign(:background, background)
      |> assign(:surface, if(background, do: "bg-transparent", else: "bg-base-300"))

    ~H"""
    <div
      id={"cell-card-" <> @cell_key}
      phx-hook="CellFocus"
      data-cell-key={@cell_key}
      data-cell-nav={@nav && Jason.encode!(@nav)}
      class={[
        "canvas-cell cursor-text transition-shadow focus-within:ring-2 focus-within:ring-primary/35 focus-within:ring-inset",
        background_class(@background) || "bg-base-300",
        outline_class(@outline),
        @focus_cell == @cell_key && "ring-2 ring-primary ring-inset",
        @class
      ]}
    >
      <%!-- The colour combination of this cell (column on top,
        row on the left) is only shown in the mobile fullscreen
        view, where there is room for it. --%>
      <.accent_bar
        id={"accent-bar-cell-#{@cell_key}-column"}
        token={@accent_top}
        class="cell-accent absolute inset-x-0 top-0 h-1 z-10"
      />
      <.accent_bar
        id={"accent-bar-cell-#{@cell_key}-row"}
        token={@accent_left}
        orientation={:left}
        class="cell-accent z-10"
      />
      <div class={["cell-body p-2", @body_class]}>
        <%= if @edit_structure? do %>
          <div class="mb-1 flex items-center gap-1">
            <.colors_button
              :if={@colors_control?}
              cell_key={@cell_key}
              background={@background}
              outline={@outline}
              open?={@colors_picker == @cell_key}
              label="Cell background"
            />

            <.form
              for={%{}}
              id={"cell-label-" <> @cell_key}
              phx-change="update_cell_label"
              class="min-w-0 flex-1"
            >
              <input type="hidden" name="cell_key" value={@cell_key} />
              <input
                type="text"
                id={"cell-" <> @cell_key <> "-label"}
                name="label"
                value={Map.get(@cell_data, "label", "")}
                phx-debounce="300"
                placeholder={@cell_key}
                class="w-full min-w-0 rounded border border-transparent bg-transparent px-1.5 py-1 text-sm font-medium text-base-content placeholder-base-content/40 hover:border-base-content/10 focus:border-primary focus:outline-none"
              />
            </.form>
          </div>

          <div
            :if={@colors_palette? and @colors_picker == @cell_key}
            id={"cell-colors-panel-" <> @cell_key}
            data-color-picker
            class="mb-1 rounded-md border border-base-content/10 bg-base-100/95 p-2 shadow-sm"
          >
            <.colors_panel cell_key={@cell_key} background={@background} outline?={false} />
          </div>
        <% else %>
          <div class="mb-1">
            <div class="text-sm font-medium text-base-content break-words">
              {cell_title(@cell_data, @cell_key)}
            </div>
          </div>
        <% end %>

        <%= for {field, value} <- @cell_data do %>
          <%!-- "semantics" is tolerated in older canvases but is
                no longer authored or shown; "titles" holds labels. --%>
          <%= if field not in Psc.Canvas.Structure.reserved_cell_keys() do %>
            <% field_title = Psc.Canvas.field_title(@cell_data, field) %>
            <div
              id={"cell-field-" <> @cell_key <> "-" <> field}
              class="mb-1 flex min-w-0 flex-col"
            >
              <%= if @edit_structure? do %>
                <.form
                  for={%{}}
                  id={"cell-title-" <> @cell_key <> "-" <> field}
                  phx-change="update_cell_field_title"
                  class="mb-0.5 flex items-center gap-1"
                >
                  <input type="hidden" name="cell_key" value={@cell_key} />
                  <input type="hidden" name="field" value={field} />
                  <input
                    type="text"
                    id={"cell-" <> @cell_key <> "-field-" <> field <> "-title"}
                    name="title"
                    value={field_title}
                    phx-debounce="300"
                    placeholder={field}
                    class="min-w-0 flex-1 rounded border border-base-content/10 bg-base-200 px-1.5 py-0.5 text-xs font-medium text-base-content placeholder-base-content/35 focus:border-primary focus:outline-none"
                  />
                  <button
                    type="button"
                    phx-click="remove_cell_field"
                    phx-value-cell_key={@cell_key}
                    phx-value-field={field}
                    class="inline-flex size-4 shrink-0 items-center justify-center rounded border border-error/40 text-error/90 transition-colors hover:border-error hover:bg-error/10 hover:text-error"
                    title={"Remove field #{field}"}
                    aria-label={"Remove field #{field}"}
                  >
                    <.icon name="hero-x-mark" class="size-2.5" />
                  </button>
                </.form>
              <% else %>
                <label
                  :if={field_title != ""}
                  class="text-xs font-medium text-base-content/50 uppercase tracking-wide mb-0.5 break-words"
                >
                  {field_title}
                </label>
              <% end %>

              <.form
                for={%{}}
                id={"cell-form-" <> @cell_key <> "-" <> field}
                phx-change="update_cell"
              >
                <input type="hidden" name="cell_key" value={@cell_key} />
                <.cell_field_editor
                  cell_key={@cell_key}
                  field={field}
                  value={value}
                  user_id={@user_id}
                  surface={@surface}
                />
              </.form>
            </div>
          <% end %>
        <% end %>

        <%= if @edit_structure? do %>
          <.form
            for={%{}}
            id={"cell-add-field-" <> @cell_key}
            phx-submit="add_cell_field"
            class="mt-1 flex gap-1"
          >
            <input type="hidden" name="cell_key" value={@cell_key} />
            <input
              type="text"
              id={"cell-" <> @cell_key <> "-new-field"}
              name="field"
              placeholder="New field"
              class="min-w-0 flex-1 rounded border border-base-content/10 bg-base-200 px-1.5 py-0.5 text-xs text-base-content placeholder-base-content/35 focus:border-primary focus:outline-none"
            />
            <button
              type="submit"
              class="shrink-0 rounded border border-base-content/10 px-1.5 py-0.5 text-xs text-base-content/70 transition-colors hover:bg-base-content/5 hover:text-base-content"
            >
              Add
            </button>
          </.form>
        <% end %>
      </div>

      <button
        type="button"
        data-cell-exit="true"
        class="cell-exit fixed bottom-5 right-5 z-[70] size-12 shrink-0 items-center justify-center rounded-full bg-primary text-primary-content shadow-lg transition-transform hover:scale-105 focus:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2 focus-visible:ring-offset-base-300"
        aria-label="Close full screen"
      >
        <.icon name="hero-x-mark" class="size-5" />
      </button>
    </div>
    """
  end

  # The heading of a cell: its label, the legacy name/title aliases, or the key
  # itself when it has none.
  defp cell_title(cell_data, key) do
    Map.get(cell_data, "label") || Map.get(cell_data, "name") || Map.get(cell_data, "title") ||
      key
  end

  attr :cell_key, :string, required: true
  attr :field, :string, required: true
  attr :value, :any, required: true
  attr :user_id, :integer, required: true
  attr :surface, :string, default: "bg-base-300"

  def cell_field_editor(assigns) do
    ~H"""
    <div
      id={"md-" <> @cell_key <> "-" <> @field}
      phx-hook="MarkdownField"
      phx-update="ignore"
      data-cell-key={@cell_key}
      data-field={@field}
      data-field-wrapper
      data-current-user-id={@user_id}
      class="w-full"
    >
      <div
        id={"md-render-" <> @cell_key <> "-" <> @field}
        class={[
          "md-render prose prose-sm dark:prose-invert break-words mb-0.5 text-base-content p-1",
          @surface
        ]}
        phx-update="ignore"
      >
        {@value}
      </div>
      <textarea
        name={"values[" <> @field <> "]"}
        phx-debounce="150"
        class={[
          "field-sizing-content hidden max-h-[60vh] w-full resize-none overflow-y-auto px-1.5 py-0.5 text-base-content placeholder-base-content/40 focus:outline-none",
          @surface
        ]}
        placeholder="Enter value..."
        rows="3"
      >{@value}</textarea>
    </div>
    """
  end

  # A bare text cell on an image board: one line, no title, no fields. It edits
  # the cell's `content` field with the same `update_cell` event a card's field
  # uses, so autosave, collaboration and the event log need no special case.
  attr :cell_key, :string, required: true
  attr :cell_data, :map, required: true
  attr :edit_structure?, :boolean, default: false
  attr :class, :any, default: nil
  attr :placeholder, :string, default: "Type a label…"

  def text(assigns) do
    ~H"""
    <.form
      for={%{}}
      id={"text-cell-form-" <> @cell_key}
      phx-change="update_cell"
      class={["h-full w-full", @class]}
    >
      <input type="hidden" name="cell_key" value={@cell_key} />
      <input
        type="text"
        id={"text-cell-" <> @cell_key}
        name="values[content]"
        value={Map.get(@cell_data, "content", "")}
        phx-debounce="200"
        placeholder={@placeholder}
        aria-label={Map.get(@cell_data, "label") || @cell_key}
        class={[
          "h-full w-full rounded-md border px-2 text-center text-sm font-semibold text-base-content shadow-sm outline-none transition placeholder:font-normal placeholder:text-base-content/40 focus:border-primary",
          background_class(Map.get(@cell_data, "background")) || "bg-base-100/90 focus:bg-base-100",
          outline_class(Map.get(@cell_data, "accent")),
          @edit_structure? && "border-primary/40",
          not @edit_structure? && "border-base-content/10 hover:border-base-content/25"
        ]}
      />
    </.form>
    """
  end

  defp normalize_background(""), do: nil
  defp normalize_background(token), do: token
end
