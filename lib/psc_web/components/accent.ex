defmodule PscWeb.Components.Accent do
  @moduledoc """
  Renders accent colors and cell backgrounds in the template designer and
  canvas editor.

  Tokens come from `Psc.Canvas.Accent` (domain) and are mapped here to static
  Tailwind classes: the swatch and bar colours, and the cell surface tints.
  Never build these classes at runtime — Tailwind only emits classes it can see
  in the source.
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

  # Cell backgrounds reuse the accent tokens, so a colour chosen for a border
  # and one chosen for a surface come from the same palette. The tints are
  # light in the light theme and deep in the dark one; the text keeps using
  # `text-base-content`, which stays legible on both.
  @background %{
    "sky" => "bg-sky-100 dark:bg-sky-950/60",
    "violet" => "bg-violet-100 dark:bg-violet-950/60",
    "emerald" => "bg-emerald-100 dark:bg-emerald-950/60",
    "amber" => "bg-amber-100 dark:bg-amber-950/60",
    "rose" => "bg-rose-100 dark:bg-rose-950/60",
    "teal" => "bg-teal-100 dark:bg-teal-950/60",
    "indigo" => "bg-indigo-100 dark:bg-indigo-950/60",
    "slate" => "bg-slate-200 dark:bg-slate-800/70"
  }

  # An empty swatch relies on the button's own ring for its outline; a dashed
  # border at 14px reads as a gear rather than a circle.
  @no_accent "bg-transparent"

  @doc "Class for a small round swatch of the given token."
  def swatch_class(nil), do: @no_accent

  def swatch_class(token), do: Map.get(@swatch, token, @no_accent)

  @doc """
  The surface tint a cell takes from its `"background"` token.

  `nil` (or an unknown token) leaves the cell on the default surface.
  """
  def background_class(nil), do: nil
  def background_class(""), do: nil
  def background_class(token), do: Map.get(@background, token)

  # A free-form cell draws its accent as a ring around the card, so the colour
  # picked in the cluster is visible while editing (the edge bars only show in
  # the mobile fullscreen view). Static strings: Tailwind must see each class.
  @outline %{
    "sky" => "ring-2 ring-inset ring-sky-400",
    "violet" => "ring-2 ring-inset ring-violet-400",
    "emerald" => "ring-2 ring-inset ring-emerald-400",
    "amber" => "ring-2 ring-inset ring-amber-400",
    "rose" => "ring-2 ring-inset ring-rose-400",
    "teal" => "ring-2 ring-inset ring-teal-400",
    "indigo" => "ring-2 ring-inset ring-indigo-400",
    "slate" => "ring-2 ring-inset ring-slate-400"
  }

  @doc """
  The visible outline a free-form cell takes from its accent token.

  Bento cards and image cells show the accent as a ring around the card, so the
  colour picked in the cluster has a visible effect outside the mobile
  fullscreen view (where the edge bars are shown).
  """
  def outline_class(nil), do: nil
  def outline_class(""), do: nil
  def outline_class(token), do: Map.get(@outline, token)

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
