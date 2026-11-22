defmodule PscWeb.Components.FulcrumEditor do
  @moduledoc """
  Edits a list of fulcrums (`Psc.Canvas.Fulcrums`): a name, a colour and the
  cells each one highlights.

  Used by the template designer, which edits the list through `editor/1`
  (it emits `fulcrum_add`, `fulcrum_remove`, `fulcrum_rename` (`fulcrum_id`,
  `name`), `fulcrum_color` and `fulcrum_toggle_cell`; the caller applies them
  with the functions in `Psc.Canvas.Fulcrums`). The canvas only picks from the
  list, through `selector/1` and `picker/1`, which emit `toggle_fulcrum`.
  """

  use Phoenix.Component

  import PscWeb.Components.Accent
  import PscWeb.CoreComponents, only: [icon: 1]

  alias Psc.Canvas.Accent, as: Tokens
  alias Psc.Canvas.Structure
  alias PscWeb.Components.UI.Button, as: UIButton
  alias PscWeb.Components.UI.Input, as: UIInput

  attr :id, :string, required: true
  attr :fulcrums, :list, required: true
  attr :cells, :map, required: true, doc: "the canvas cells or template layout map"
  attr :can_edit?, :boolean, default: true

  def editor(assigns) do
    assigns = assign(assigns, :cards, Structure.cards(assigns.cells))

    ~H"""
    <div id={@id} class="space-y-3">
      <p :if={@fulcrums == []} class="text-sm text-base-content/50">
        No fulcrums yet. A fulcrum is a named set of cells that can be highlighted together.
      </p>

      <div
        :for={fulcrum <- @fulcrums}
        id={"#{@id}-#{fulcrum["id"]}"}
        class="space-y-2.5 rounded-xl border border-base-content/10 bg-base-100 p-3"
      >
        <div class="flex items-center gap-2">
          <span class={["size-3 shrink-0 rounded-full", swatch_class(fulcrum["color"])]}></span>
          <form
            id={"#{@id}-#{fulcrum["id"]}-form"}
            phx-change="fulcrum_rename"
            phx-submit="fulcrum_rename"
            class="min-w-0 flex-1"
          >
            <input type="hidden" name="fulcrum_id" value={fulcrum["id"]} />
            <UIInput.input
              type="text"
              id={"#{@id}-#{fulcrum["id"]}-name"}
              name="name"
              value={fulcrum["name"]}
              placeholder="Fulcrum name"
              maxlength="60"
              phx-debounce="300"
              disabled={not @can_edit?}
              aria-label="Fulcrum name"
            />
          </form>
          <button
            :if={@can_edit?}
            type="button"
            phx-click="fulcrum_remove"
            phx-value-id={fulcrum["id"]}
            title="Remove this fulcrum"
            aria-label={"Remove #{fulcrum["name"]}"}
            class="inline-flex size-8 shrink-0 items-center justify-center rounded-md text-base-content/50 transition-colors hover:bg-error/10 hover:text-error"
          >
            <.icon name="hero-trash" class="size-4" />
          </button>
        </div>

        <div class="flex flex-wrap items-center gap-1.5" role="group" aria-label="Colour">
          <button
            :for={token <- Tokens.tokens()}
            type="button"
            phx-click="fulcrum_color"
            phx-value-id={fulcrum["id"]}
            phx-value-color={token}
            disabled={not @can_edit?}
            aria-pressed={to_string(fulcrum["color"] == token)}
            aria-label={token}
            title={token}
            class={[
              "size-5 rounded-full transition focus:outline-none focus-visible:ring-2 focus-visible:ring-primary",
              swatch_class(token),
              fulcrum["color"] == token &&
                "ring-2 ring-base-content ring-offset-2 ring-offset-base-100"
            ]}
          ></button>
        </div>

        <div>
          <p class="mb-1.5 text-xs font-medium text-base-content/50">
            Cells · {length(fulcrum["cells"] || [])} selected
          </p>
          <div class="flex flex-wrap gap-1.5">
            <button
              :for={card <- @cards}
              type="button"
              phx-click="fulcrum_toggle_cell"
              phx-value-id={fulcrum["id"]}
              phx-value-key={card.key}
              disabled={not @can_edit?}
              aria-pressed={to_string(card.key in (fulcrum["cells"] || []))}
              class={[
                "rounded-md border px-2 py-1 text-xs transition-colors disabled:opacity-60",
                card.key in (fulcrum["cells"] || []) &&
                  "border-primary/50 bg-primary/10 font-medium text-base-content",
                card.key not in (fulcrum["cells"] || []) &&
                  "border-base-content/15 text-base-content/60 hover:border-base-content/30 hover:text-base-content"
              ]}
            >
              {card.label}
            </button>
            <span :if={@cards == []} class="text-xs text-base-content/40">
              Add cells first.
            </span>
          </div>
        </div>
      </div>

      <UIButton.button
        :if={@can_edit?}
        type="button"
        id={"#{@id}-add"}
        variant="outline"
        size="sm"
        phx-click="fulcrum_add"
        class="gap-1.5"
      >
        <.icon name="hero-plus" class="size-4" /> Add fulcrum
      </UIButton.button>
    </div>
    """
  end

  @doc """
  The canvas's fulcrum picker: one chip per fulcrum. Clicking a chip sends
  `toggle_fulcrum`; the highlight is shared by everyone on the canvas.
  """
  attr :fulcrums, :list, required: true
  attr :active_ids, :list, required: true
  attr :mode, :string, required: true

  def picker(assigns) do
    ~H"""
    <div
      :if={@fulcrums != [] and @mode != "off"}
      id="fulcrum-picker"
      class="flex shrink-0 flex-wrap items-center gap-1.5 px-2 pb-2 sm:px-0"
      role="group"
      aria-label="Fulcrums"
    >
      <span class="mr-1 text-xs font-medium uppercase tracking-wide text-base-content/50">
        Fulcrums
      </span>
      <button
        :for={fulcrum <- @fulcrums}
        type="button"
        id={"fulcrum-chip-" <> fulcrum["id"]}
        phx-click="toggle_fulcrum"
        phx-value-id={fulcrum["id"]}
        aria-pressed={to_string(fulcrum["id"] in @active_ids)}
        title={
          if @mode == "single", do: "Highlight only this fulcrum", else: "Highlight this fulcrum too"
        }
        class={[
          "inline-flex h-7 items-center gap-1.5 rounded-full border px-2.5 text-xs font-medium transition-colors",
          "focus:outline-none focus-visible:ring-2 focus-visible:ring-primary",
          fulcrum["id"] in @active_ids &&
            [
              "border-transparent text-base-content",
              selected_class(fulcrum["color"])
            ],
          fulcrum["id"] not in @active_ids &&
            "border-base-content/10 text-base-content/60 hover:border-base-content/25 hover:text-base-content"
        ]}
      >
        <span class={["size-2.5 rounded-full", swatch_class(fulcrum["color"])]}></span>
        {fulcrum["name"]}
      </button>
    </div>
    """
  end

  @doc """
  The canvas's fulcrum dialog: one row per fulcrum to pick from. Choosing a row
  sends `toggle_fulcrum`, the same event as its picker chip. Nothing is edited
  here; the fulcrums themselves are defined in the template designer.
  """
  attr :fulcrums, :list, required: true
  attr :active_ids, :list, required: true

  def selector(assigns) do
    ~H"""
    <p :if={@fulcrums == []} class="text-sm text-base-content/60">
      This template has no fulcrums.
    </p>

    <ul
      :if={@fulcrums != []}
      id="fulcrum-selector"
      class="space-y-2"
      role="group"
      aria-label="Fulcrums"
    >
      <li :for={fulcrum <- @fulcrums}>
        <button
          type="button"
          id={"fulcrum-select-" <> fulcrum["id"]}
          phx-click="toggle_fulcrum"
          phx-value-id={fulcrum["id"]}
          aria-pressed={to_string(fulcrum["id"] in @active_ids)}
          class={[
            "flex w-full items-center gap-3 rounded-xl border px-3 py-2.5 text-left transition-colors",
            "focus:outline-none focus-visible:ring-2 focus-visible:ring-primary",
            fulcrum["id"] in @active_ids && ["border-transparent", selected_class(fulcrum["color"])],
            fulcrum["id"] not in @active_ids &&
              "border-base-content/10 hover:border-base-content/25"
          ]}
        >
          <span class={["size-3 shrink-0 rounded-full", swatch_class(fulcrum["color"])]}></span>
          <span class="min-w-0 flex-1 truncate text-sm font-medium text-base-content">
            {fulcrum["name"]}
          </span>
          <span class="shrink-0 text-xs text-base-content/50">
            {length(fulcrum["cells"] || [])} {if length(fulcrum["cells"] || []) == 1,
              do: "cell",
              else: "cells"}
          </span>
          <.icon
            name="hero-check"
            class={[
              "size-4 shrink-0 text-primary",
              fulcrum["id"] not in @active_ids && "invisible"
            ]}
          />
        </button>
      </li>
    </ul>
    """
  end
end
