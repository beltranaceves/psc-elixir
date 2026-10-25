defmodule PscWeb.UnstrCanvasLive.CellColors do
  @moduledoc """
  The colour picker for a cell: its outline (the accent) and its background
  surface, in one labelled panel.

  The two-colour panel replaces a pair of unlabelled swatches: the outline and
  the background use the same token palette, so the labels are what tells them
  apart. The table has no per-cell outline (its accents belong to the row and
  column headers), so it opens the same panel with only the background row.
  """

  use Phoenix.Component

  import PscWeb.Components.Accent,
    only: [background_class: 1, outline_class: 1, swatch_class: 1]

  import PscWeb.CoreComponents, only: [icon: 1]

  attr :cell_key, :string, required: true
  attr :background, :string, default: nil
  attr :outline, :string, default: nil
  attr :outline?, :boolean, default: true
  attr :open?, :boolean, default: false
  attr :label, :string, default: "Outline and background colors"
  attr :class, :any, default: nil

  def colors_button(assigns) do
    ~H"""
    <button
      type="button"
      id={"cell-colors-" <> @cell_key}
      phx-click="toggle_cell_colors"
      phx-value-cell_key={@cell_key}
      aria-pressed={to_string(@open?)}
      aria-label={@label}
      title={@label}
      class={[
        "inline-flex size-7 shrink-0 items-center justify-center rounded-full border border-base-content/25 bg-base-100/90 transition-colors hover:border-base-content/40 focus:outline-none focus-visible:ring-2 focus-visible:ring-primary sm:size-6",
        @class
      ]}
    >
      <span
        :if={@background || (@outline? && @outline)}
        class={[
          "size-4 rounded-full",
          background_class(@background) || "bg-base-300",
          if(@outline? and @outline,
            do: outline_class(@outline),
            else: "ring-1 ring-inset ring-base-content/30"
          )
        ]}
      ></span>
      <.icon
        :if={is_nil(@background) and (not @outline? or is_nil(@outline))}
        name="hero-swatch"
        class="size-3.5 text-base-content/50"
      />
    </button>
    """
  end

  attr :cell_key, :string, required: true
  attr :background, :string, default: nil
  attr :outline, :string, default: nil
  attr :outline?, :boolean, default: true

  def colors_panel(assigns) do
    ~H"""
    <div class="w-56 space-y-2">
      <div :if={@outline?}>
        <div class="mb-1 flex items-center justify-between">
          <span class="text-[0.65rem] font-medium uppercase tracking-wide text-base-content/50">
            Outline
          </span>

          <button
            type="button"
            id={"cell-colors-#{@cell_key}-outline-none"}
            phx-click="set_card_accent"
            phx-value-cell_key={@cell_key}
            phx-value-accent=""
            class="text-[0.65rem] text-base-content/50 hover:text-base-content"
          >
            None
          </button>
        </div>

        <div class="flex flex-wrap gap-1">
          <button
            :for={token <- Psc.Canvas.Accent.tokens()}
            type="button"
            id={"cell-colors-#{@cell_key}-outline-#{token}"}
            phx-click="set_card_accent"
            phx-value-cell_key={@cell_key}
            phx-value-accent={token}
            class={[
              "size-5 rounded-full ring-1 ring-base-content/25 transition hover:scale-110",
              swatch_class(token),
              @outline == token && "ring-2 ring-primary"
            ]}
            title={"Outline #{token}"}
            aria-label={"Set outline #{token}"}
          ></button>
        </div>
      </div>

      <div>
        <div class="mb-1 flex items-center justify-between">
          <span class="text-[0.65rem] font-medium uppercase tracking-wide text-base-content/50">
            Background
          </span>

          <button
            type="button"
            id={"cell-colors-#{@cell_key}-background-none"}
            phx-click="set_cell_background"
            phx-value-cell_key={@cell_key}
            phx-value-background=""
            class="text-[0.65rem] text-base-content/50 hover:text-base-content"
          >
            None
          </button>
        </div>

        <div class="flex flex-wrap gap-1">
          <button
            :for={token <- Psc.Canvas.Accent.tokens()}
            type="button"
            id={"cell-colors-#{@cell_key}-background-#{token}"}
            phx-click="set_cell_background"
            phx-value-cell_key={@cell_key}
            phx-value-background={token}
            class={[
              "size-5 rounded-full ring-1 ring-base-content/25 transition hover:scale-110",
              swatch_class(token),
              @background == token && "ring-2 ring-primary"
            ]}
            title={"Background #{token}"}
            aria-label={"Set background #{token}"}
          ></button>
        </div>
      </div>
    </div>
    """
  end
end
