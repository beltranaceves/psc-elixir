defmodule PscWeb.Components.Hint do
  @moduledoc """
  Tooltips that explain a cell, a row or a column: the concept it stands for,
  or how to fill it in.

  The text is the item's `"hint"` (`Psc.Canvas.Structure.hint/1`). A template
  author writes it in the designer, a canvas copies it, and the canvas's
  structure mode can change it. Two pieces share one look everywhere:

    * `hint/1` — a small ⓘ button with a tooltip, rendered only when there is
      a hint. Hover or focus opens it; on a touch screen a tap toggles it. The
      button carries `data-hint-trigger`, so the cell hooks do not treat the
      tap as "start editing" or "go full screen".
    * `hint_input/1` — the textarea that edits a hint. It sends `phx-change`
      with a `"hint"` param plus the given hidden params.
  """

  use Phoenix.Component

  import PscWeb.CoreComponents, only: [icon: 1]

  alias Psc.Canvas.Structure
  alias PscWeb.Components.UI.Tooltip, as: UITooltip

  @doc """
  The tooltip trigger for an item's hint, or nothing when it has none.

  The `id` must be unique on the page: the tooltip hook is bound to it. A
  read-only preview (the History tab) passes its own prefix.
  """
  attr :id, :string, required: true
  attr :item, :any, required: true, doc: "the cell, row or column map"
  attr :label, :string, default: nil, doc: "what the hint is about, for screen readers"
  attr :side, :string, default: "top", values: ~w(top right bottom left)
  attr :class, :string, default: nil

  def hint(assigns) do
    assigns = assign(assigns, :text, hint_text(assigns.item))

    ~H"""
    <UITooltip.tooltip
      :if={@text}
      id={@id}
      class={Enum.join(["inline-flex shrink-0 align-middle", @class], " ")}
    >
      <UITooltip.tooltip_trigger class="inline-flex">
        <button
          type="button"
          id={@id <> "-trigger"}
          data-hint-trigger
          class="inline-flex size-5 items-center justify-center rounded-full text-base-content/45 transition-colors hover:text-base-content focus:outline-none focus-visible:ring-2 focus-visible:ring-primary"
          aria-label={if @label, do: "About #{@label}", else: "About this"}
        >
          <.icon name="hero-information-circle" class="size-[18px]" />
        </button>
      </UITooltip.tooltip_trigger>
      <%!-- The text sits on one line with its tags: `whitespace-pre-line` keeps the
      author's line breaks, and would also keep the template's own indentation. --%>
      <UITooltip.tooltip_content
        side={@side}
        class="w-max max-w-64 px-2.5 py-1.5 text-left text-xs font-normal normal-case leading-snug tracking-normal"
      >
        <p class="whitespace-pre-line">{@text}</p>
      </UITooltip.tooltip_content>
    </UITooltip.tooltip>
    """
  end

  @doc """
  The textarea that edits a hint. Every change sends `event` with `"hint"`
  and the `params` as hidden fields.
  """
  attr :id, :string, required: true
  attr :event, :string, required: true
  attr :value, :string, default: nil
  attr :params, :map, default: %{}
  attr :disabled, :boolean, default: false
  attr :class, :any, default: nil

  attr :placeholder, :string, default: "Tooltip: what this means or how to fill it in"

  def hint_input(assigns) do
    assigns = assign(assigns, :max, Structure.max_hint())

    ~H"""
    <.form for={%{}} id={@id} phx-change={@event} class={["min-w-0", @class]}>
      <input :for={{name, value} <- @params} type="hidden" name={name} value={value} />
      <label class="flex items-start gap-1 text-base-content/45">
        <.icon name="hero-information-circle" class="mt-1 size-3.5 shrink-0" />
        <textarea
          id={@id <> "-input"}
          name="hint"
          rows="1"
          maxlength={@max}
          phx-debounce="300"
          disabled={@disabled}
          placeholder={@placeholder}
          aria-label="Tooltip text"
          class="field-sizing-content max-h-32 min-w-0 flex-1 resize-none rounded border border-transparent bg-transparent px-1 py-0.5 text-xs font-normal normal-case leading-snug tracking-normal text-base-content/80 placeholder-base-content/35 hover:border-base-content/10 focus:border-primary focus:outline-none"
        >{@value}</textarea>
      </label>
    </.form>
    """
  end

  defp hint_text(item) when is_map(item), do: Structure.hint(item)
  defp hint_text(_item), do: nil
end
