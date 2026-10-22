defmodule Psc.Agent.Tools.GetNote do
  @moduledoc """
  Reads one note's Markdown content.
  """

  use Jido.Action,
    name: "get_note",
    description:
      "Read a note by id, returning its title and Markdown content as the editor " <>
        "shows it. Notes inherit their canvas's access rules.",
    schema: [
      note_id: [type: :string, required: true, doc: "The note id (UUID)."]
    ]

  alias Psc.Agent.Tools.Ref
  alias Psc.Agent.Tools.Scope
  alias Psc.Canvas
  alias Psc.Notes

  # One message for "missing" and "not yours": two different ones would let a
  # client probe which note ids exist.
  @not_found "No canvas or note with that id that you can access."

  @impl true
  def run(%{note_id: note_id}, context) do
    with {:ok, user} <- Scope.user(context),
         {:ok, note_id} <- Scope.uuid(note_id, "Note id"),
         %{} = note <- fetch(note_id),
         {:ok, canvas} <- canvas_of(note),
         :ok <- authorize(canvas, user) do
      {:ok,
       %{
         id: note.id,
         canvas_id: canvas.id,
         title: note.title,
         content: Notes.get_note_content(note.id),
         updated_at: Scope.iso8601(note.updated_at),
         refs: [
           Ref.note(canvas.id, note.id, note.title, Ref.excerpt(Notes.get_note_content(note.id)))
         ]
       }}
    end
  end

  defp fetch(id), do: Notes.get_note(id) || {:error, @not_found}

  defp canvas_of(note) do
    case Canvas.get_unstr_canvas(note.canvas_id) do
      nil -> {:error, @not_found}
      canvas -> {:ok, canvas}
    end
  end

  defp authorize(canvas, user) do
    if Canvas.can_access_unstr_canvas?(canvas, user.email) do
      :ok
    else
      {:error, @not_found}
    end
  end
end
