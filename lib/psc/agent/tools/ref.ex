defmodule Psc.Agent.Tools.Ref do
  @moduledoc """
  Deep links a tool returns so the transcript can point at the real thing.

  The URLs are built here, from ids the access check already approved, never
  from model output. The chat renders them as chips; MCP clients get them in
  `structuredContent`.

  Cells have no deep link yet (`?cell=`), so canvas links land on the editor tab
  rather than a specific cell.
  """

  @excerpt_length 80

  @doc "A canvas, opened in the editor tab."
  def canvas(id, label, excerpt \\ nil) do
    ref("canvas", label, "/canvas/#{id}?tab=editor", excerpt)
  end

  @doc "A note, opened in the notes tab with that note selected."
  def note(canvas_id, note_id, label, excerpt \\ nil) do
    ref("note", label, "/canvas/#{canvas_id}?tab=notes&note=#{note_id}", excerpt)
  end

  @doc "A template, opened in the designer."
  def template(id, label, excerpt \\ nil) do
    ref("template", label, "/templates/#{id}", excerpt)
  end

  @doc """
  One cell of a canvas, opened on the editor tab with that cell ringed.

  `?cell=` was added for this: before it, a cell reference could only point at
  the whole canvas.
  """
  def cell(canvas_id, key, label, excerpt \\ nil) do
    ref("cell", label, "/canvas/#{canvas_id}?tab=editor&cell=#{key}", excerpt)
  end

  @doc "A short, single-line preview of a text body."
  def excerpt(nil), do: nil

  def excerpt(text) when is_binary(text) do
    case text |> String.replace(~r/\s+/, " ") |> String.trim() do
      "" -> nil
      text -> String.slice(text, 0, @excerpt_length)
    end
  end

  def excerpt(_other), do: nil

  defp ref(kind, label, url, excerpt) do
    base = %{"kind" => kind, "label" => to_string(label), "url" => url}

    case excerpt(excerpt) do
      nil -> base
      excerpt -> Map.put(base, "excerpt", excerpt)
    end
  end
end
