defmodule Psc.Export.Data do
  @moduledoc """
  The machine-readable copy of a canvas inside a Markdown export.

  The readable Markdown is for people; this block is what an import reads.
  It is an HTML comment at the end of the file, so Markdown viewers do not
  show it, holding JSON:

      <!-- psc-canvas-data v1
      {"format":"psc-canvas","version":1,"canvas":{...},...}
      -->

  It carries exactly the sections the exporter ticked: `canvas` (name,
  description, note mode and cells), `notes`, `agent` (from Info and
  settings: the config and the reference files' contents) and `history`
  (every version, with the one the canvas holds marked). Analysis is
  recomputed on import and agent chats are personal, so neither is included.
  A file can be imported only when it has the `canvas` part.
  """

  alias Psc.{Canvas, Notes}
  alias Psc.Agent.Files, as: AgentFiles

  @format "psc-canvas"
  @version 1
  @open "<!-- psc-canvas-data v1\n"
  @close "\n-->"

  def format, do: @format
  def version, do: @version

  @doc """
  The data for the ticked sections, or nil when Canvas is not ticked (without
  the cells there is nothing to import).
  """
  def build(canvas, cells, sections) do
    if "canvas" in sections do
      %{
        "format" => @format,
        "version" => @version,
        "canvas" => %{
          "name" => canvas.name,
          "description" => canvas.description || "",
          "notes_mode" => canvas.notes_mode,
          "cells" => cells
        }
      }
      |> put_if("notes" in sections, "notes", fn -> notes(canvas) end)
      |> put_if("info" in sections, "agent", fn -> agent(canvas) end)
      |> put_if("history" in sections, "history", fn -> history(canvas, cells) end)
    end
  end

  @doc """
  The comment that holds the data. JSON never has `--` outside a string, so
  escaping it inside strings is enough to keep the comment closed only by its
  own `-->`.
  """
  def embed(data) do
    @open <> (data |> Jason.encode!() |> String.replace("--", "-\\u002d")) <> @close
  end

  @doc """
  Reads the data back out of a Markdown file.

  Returns `{:ok, data}` or `{:error, reason}`, where reason is `:missing`
  (no block: an older export, or one without the Canvas section),
  `:unsupported` (a newer or foreign format) or `:invalid` (a damaged block).
  """
  def extract(markdown) when is_binary(markdown) do
    # The block is the last one: a cell may quote the marker in its text, but
    # the block itself cannot contain it (its `--` are escaped).
    with {start, length} <- markdown |> :binary.matches(@open) |> List.last(),
         rest = binary_part(markdown, start + length, byte_size(markdown) - start - length),
         [json | _after] <- :binary.split(rest, @close),
         {:ok, %{} = data} <- Jason.decode(json) do
      case data do
        %{"format" => @format, "version" => @version} -> {:ok, data}
        %{"format" => @format} -> {:error, :unsupported}
        _other -> {:error, :invalid}
      end
    else
      nil -> {:error, :missing}
      _other -> {:error, :invalid}
    end
  end

  def extract(_markdown), do: {:error, :invalid}

  defp put_if(map, true, key, fun), do: Map.put(map, key, fun.())
  defp put_if(map, false, _key, _fun), do: map

  defp notes(canvas) do
    canvas.id
    |> Notes.list_notes()
    |> Enum.map(fn note ->
      %{"title" => note.title, "content" => to_string(Notes.get_note_content(note.id))}
    end)
  end

  defp agent(canvas) do
    %{
      "config" => canvas.agent_config || %{},
      "files" =>
        canvas.id
        |> AgentFiles.list_canvas()
        |> Enum.map(fn file ->
          %{
            "path" => file.path,
            "description" => file.description || "",
            "content" => file.content || ""
          }
        end)
    }
  end

  # Every version with its parent, oldest first. The version the canvas holds
  # is exported with the live content, which may be ahead of its stored
  # snapshot.
  defp history(canvas, cells) do
    pivots =
      canvas.id
      |> Canvas.list_pivots()
      |> Enum.map(fn pivot ->
        %{
          "id" => pivot.id,
          "parent_id" => pivot.parent_id,
          "name" => pivot.name,
          "rationale" => pivot.rationale,
          "kind" => pivot.kind,
          "inserted_at" => pivot.inserted_at && DateTime.to_iso8601(pivot.inserted_at),
          "cells" => if(pivot.id == canvas.head_pivot_id, do: cells, else: pivot.cells)
        }
      end)

    %{"head_id" => canvas.head_pivot_id, "pivots" => pivots}
  end
end
