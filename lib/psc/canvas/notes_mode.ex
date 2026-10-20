defmodule Psc.Canvas.NotesMode do
  @moduledoc """
  How a canvas's Notes view behaves.

  A template picks the mode and its canvases inherit it:

  * `"multi"` — a list of notes. The canvas can hold as many as the work needs.
  * `"single"` — one scratchpad. Deliberately restrictive: for a framework like
    the Problem–Solution Canvas, limiting how much can be written down is the
    point.
  """

  @modes ["multi", "single"]

  @doc """
  The known note modes.
  """
  def modes, do: @modes

  @doc """
  The default mode: a list of notes.
  """
  def default, do: "multi"

  @doc """
  Is this a single-note (scratchpad) canvas?
  """
  def single?(mode), do: mode == "single"

  @doc """
  The mode a template asks for, falling back to the default.

  An unknown or missing value is the default, so an old template keeps
  working.
  """
  def normalize(nil), do: default()
  def normalize(mode) when mode in @modes, do: mode
  def normalize(_other), do: default()

  @doc """
  The label shown in the template designer.
  """
  def label("single"), do: "Single note"
  def label(_multi), do: "Multiple notes"

  @doc """
  The one-line explanation shown in the template designer.
  """
  def blurb("single") do
    "One note for the whole canvas. Deliberately restrictive: a framework that " <>
      "limits what can be written down keeps the thinking sharp."
  end

  def blurb(_multi) do
    "A list of notes for the canvas. Each note is collaborative Markdown."
  end
end
