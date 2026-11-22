defmodule Psc.Export.Import do
  @moduledoc """
  Creates a canvas from a Markdown export (`Psc.Export.Markdown`).

  Only the hidden data block is read (`Psc.Export.Data`); the readable text
  is for people and hand edits to it are ignored. The import is always a new
  canvas owned by the importer, like instantiating a template; it never
  touches an existing one.

  Everything in the block is untrusted input. The cells go through the same
  validation as any canvas, each version's snapshot is validated too, agent
  files go through `Psc.Agent.Files`' caps, and the counts are capped for the
  free tier's row limits. Either everything is created or nothing is.
  """

  alias Psc.{Canvas, Notes, Repo}
  alias Psc.Agent.Files, as: AgentFiles
  alias Psc.Canvas.{NotesMode, Structure}
  alias Psc.Export.Data

  @max_bytes 4 * 1024 * 1024
  @max_notes 100
  @max_versions 300
  @max_name 200
  @max_description 5_000
  @max_note_title 200
  @version_kinds ~w(pivot draft restore)

  @doc "The largest file accepted, in bytes."
  def max_bytes, do: @max_bytes

  @doc """
  Imports a Markdown export for the scope's user.

  Returns `{:ok, canvas}` or `{:error, reason}`; `error_message/1` turns a
  reason into a sentence for the person importing.
  """
  def import_markdown(%{user: %{id: user_id}}, markdown) when is_binary(markdown) do
    with :ok <- check_size(markdown),
         {:ok, data} <- Data.extract(markdown),
         {:ok, attrs} <- canvas_attrs(data),
         {:ok, notes} <- notes(data),
         {:ok, files} <- files(data),
         {:ok, versions, head_id} <- versions(data) do
      Repo.transaction(fn ->
        with {:ok, canvas} <- Canvas.import_unstr_canvas(user_id, attrs, versions, head_id),
             :ok <- create_notes(canvas, user_id, notes),
             {:ok, :ok} <- AgentFiles.replace(:canvas, canvas.id, files) do
          canvas
        else
          {:error, %Ecto.Changeset{}} -> Repo.rollback(:invalid)
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    end
  end

  def import_markdown(_scope, _markdown), do: {:error, :unauthorized}

  @doc "A sentence explaining why an import failed."
  def error_message(:missing),
    do:
      "This file has no canvas data. Export the canvas again with the Canvas section ticked, then import that file."

  def error_message(:unsupported),
    do: "This file comes from a newer version of the app and cannot be imported here."

  def error_message(:too_large),
    do: "This file is too large to import (the limit is #{div(@max_bytes, 1024 * 1024)} MB)."

  def error_message({:invalid_cells, message}),
    do: "The canvas in this file is not valid: #{message}."

  def error_message(:unauthorized), do: "You need to be logged in to import a canvas."
  def error_message(_reason), do: "This file could not be imported: its canvas data is damaged."

  defp check_size(markdown) when byte_size(markdown) > @max_bytes, do: {:error, :too_large}
  defp check_size(_markdown), do: :ok

  defp canvas_attrs(%{"canvas" => %{"cells" => %{} = cells} = canvas} = data) do
    with :ok <- valid_cells(cells) do
      attrs =
        %{
          "name" => text(canvas["name"], @max_name) || "Imported canvas",
          "description" => text(canvas["description"], @max_description) || "",
          "notes_mode" => NotesMode.normalize(canvas["notes_mode"]),
          "cells" => cells
        }

      case data["agent"] do
        %{"config" => %{} = config} -> {:ok, Map.put(attrs, "agent_config", config)}
        _other -> {:ok, attrs}
      end
    end
  end

  defp canvas_attrs(_data), do: {:error, :missing}

  defp valid_cells(cells) do
    case Structure.validate(cells) do
      :ok -> :ok
      {:error, _field, message} -> {:error, {:invalid_cells, message}}
    end
  end

  defp notes(%{"notes" => notes}) when is_list(notes) and length(notes) <= @max_notes do
    if Enum.all?(notes, &is_map/1) do
      {:ok,
       Enum.map(notes, fn note ->
         %{
           title: text(note["title"], @max_note_title) || "Untitled note",
           content: if(is_binary(note["content"]), do: note["content"], else: "")
         }
       end)}
    else
      {:error, :invalid}
    end
  end

  defp notes(%{"notes" => _notes}), do: {:error, :invalid}
  defp notes(_data), do: {:ok, []}

  defp files(%{"agent" => %{"files" => files}}) when is_list(files) do
    if Enum.all?(files, &is_map/1) do
      {:ok,
       Enum.map(files, fn file ->
         path = if is_binary(file["path"]), do: file["path"], else: ""
         content = if is_binary(file["content"]), do: file["content"], else: ""

         %{
           "id" => nil,
           "path" => path,
           "name" => Path.basename(path),
           "description" => if(is_binary(file["description"]), do: file["description"], else: ""),
           "content" => content,
           "byte_size" => byte_size(content)
         }
       end)}
    else
      {:error, :invalid}
    end
  end

  defp files(%{"agent" => _agent}), do: {:error, :invalid}
  defp files(_data), do: {:ok, []}

  defp versions(%{"history" => %{"pivots" => pivots} = history})
       when is_list(pivots) and length(pivots) <= @max_versions do
    pivots
    |> Enum.reduce_while({:ok, []}, fn pivot, {:ok, acc} ->
      case version(pivot) do
        {:ok, version} -> {:cont, {:ok, [version | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, versions} -> {:ok, ordered(Enum.reverse(versions)), history["head_id"]}
      error -> error
    end
  end

  defp versions(%{"history" => _history}), do: {:error, :invalid}
  defp versions(_data), do: {:ok, [], nil}

  defp version(%{"id" => id, "cells" => %{} = cells} = pivot) when is_binary(id) do
    # A snapshot may carry the canvas's name and description beside its cells.
    with :ok <- valid_cells(Map.drop(cells, ["$name", "$description"])) do
      {:ok,
       %{
         id: id,
         parent_id: if(is_binary(pivot["parent_id"]), do: pivot["parent_id"]),
         name: text(pivot["name"], 120),
         rationale: text(pivot["rationale"], 2_000),
         kind: if(pivot["kind"] in @version_kinds, do: pivot["kind"], else: "pivot"),
         cells: cells,
         inserted_at: timestamp(pivot["inserted_at"])
       }}
    end
  end

  defp version(_pivot), do: {:error, :invalid}

  # Parents before children, so every version's parent already has its new id
  # when it is inserted. The export is oldest first, which normally is that
  # order already; a version whose parent never appears hangs off the root.
  defp ordered(versions) do
    ids = MapSet.new(versions, & &1.id)
    {roots, children} = Enum.split_with(versions, &(not MapSet.member?(ids, &1.parent_id)))
    walk(roots, Enum.group_by(children, & &1.parent_id))
  end

  defp walk([], _children), do: []

  defp walk([version | rest], children) do
    [version | walk(Map.get(children, version.id, []), children)] ++ walk(rest, children)
  end

  defp create_notes(canvas, user_id, notes) do
    Enum.reduce_while(notes, :ok, fn note, :ok ->
      case Notes.create_note(canvas.id, user_id, note) do
        {:ok, _note} -> {:cont, :ok}
        {:error, _changeset} -> {:halt, {:error, :invalid}}
      end
    end)
  end

  defp text(value, max) when is_binary(value) do
    case value |> String.trim() |> String.slice(0, max) do
      "" -> nil
      text -> text
    end
  end

  defp text(_value, _max), do: nil

  defp timestamp(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _offset} -> %{at | microsecond: {elem(at.microsecond, 0), 6}}
      _error -> nil
    end
  end

  defp timestamp(_value), do: nil
end
