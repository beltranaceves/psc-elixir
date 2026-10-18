defmodule Psc.Canvas.Accent do
  @moduledoc """
  Accent color tokens for template and canvas row/column headers.

  Rows and columns carry an optional `"accent"` key. It stores a *token* from
  this fixed palette rather than a raw hex value, so the web layer can map it
  to static Tailwind classes (Tailwind never sees a runtime-built class name)
  and both themes stay legible. `nil` means "no accent" and renders nothing.

  The tokens are copied from a template into each instantiated canvas together
  with the rest of the row/column metadata, so a canvas can be restyled
  independently of the template it came from.
  """

  @tokens ~w(sky violet emerald amber rose teal indigo slate)

  @doc "All accent tokens, in palette order."
  def tokens, do: @tokens

  @doc "Whether a stored accent value is acceptable (nil/empty means none)."
  def valid?(nil), do: true
  def valid?(""), do: true
  def valid?(token) when is_binary(token), do: token in @tokens
  def valid?(_token), do: false
end
