defmodule PscWeb.Components.Accent do
  @moduledoc """
  Renders row/column accent colors in the template designer and canvas editor.

  Tokens come from `Psc.Canvas.Accent` (domain) and are mapped here to static
  Tailwind classes. Never build these classes at runtime — Tailwind only emits
  classes it can see in the source.
  """

  use Phoenix.Component

  @swatch %{
    "sky" => "bg-sky-400",
    "violet" => "bg-violet-400",
    "emerald" => "bg-emerald-400",
    "amber" => "bg-amber-400",
    "rose" => "bg-rose-400",
    "teal" => "bg-teal-400",
    "indigo" => "bg-indigo-400",
    "slate" => "bg-slate-400"
  }

  # An empty swatch relies on the button's own ring for its outline; a dashed
  # border at 14px reads as a gear rather than a circle.
  @no_accent "bg-transparent"

  @doc "Class for a small round swatch of the given token."
  def swatch_class(nil), do: @no_accent

  def swatch_class(token), do: Map.get(@swatch, token, @no_accent)

  @doc """
  A thin bar carrying the accent color.

  `:top` spans the width of a column header. `:left` is absolutely positioned to
  fill the height of its row header cell — the only reliable way to stretch an
  element to a table row's full height, since a percentage height cannot resolve
  against an auto-height cell. The owning `<td>` must be `relative`.
  """
  attr :id, :string, default: nil
  attr :token, :string, default: nil
  attr :orientation, :atom, values: [:top, :left], default: :top
  attr :class, :string, default: nil

  def accent_bar(assigns) do
    assigns = assign(assigns, :color, assigns[:token] && Map.get(@swatch, assigns[:token]))

    ~H"""
    <div
      :if={@color}
      id={@id}
      aria-hidden="true"
      class={[
        @orientation == :top && "h-1 w-full",
        @orientation == :left && "absolute inset-y-0 left-0 w-1",
        @color,
        @class
      ]}
    />
    """
  end
end
