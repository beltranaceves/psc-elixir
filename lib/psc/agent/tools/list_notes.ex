defmodule Psc.Agent.Tools.ListNotes do
  @moduledoc """
  Lists the notes attached to a canvas.
  """

  use Jido.Action,
    name: "list_notes",
    description:
      "List the notes of a canvas by canvas id, most recently edited first. " <>
        "Returns titles and ids only; call get_note for the Markdown content.",
    schema: [
      canvas_id: [type: :string, required: true, doc: "The canvas id (UUID)."]
    ]

  alias Psc.Agent.Tools.Ref
  alias Psc.Agent.Tools.Scope
  alias Psc.Canvas
  alias Psc.Notes

  # One message for "missing" and "not yours": two different ones would let a
  # client probe which canvas ids exist.
  @not_found "No canvas or note with that id that you can access."

  @impl true
  def run(%{canvas_id: canvas_id}, context) do
    with {:ok, user} <- Scope.user(context),
         {:ok, canvas_id} <- Scope.uuid(canvas_id, "Canvas id"),
         %{} = canvas <- fetch(canvas_id),
         :ok <- authorize(canvas, user) do
      notes = Notes.list_notes(canvas.id)

      summaries =
        Enum.map(notes, fn note ->
          %{id: note.id, title: note.title, updated_at: Scope.iso8601(note.updated_at)}
        end)

      {:ok,
       %{
         canvas_id: canvas.id,
         notes: summaries,
         refs: Enum.map(notes, &Ref.note(canvas.id, &1.id, &1.title, Ref.excerpt(&1.content)))
       }}
    end
  end

  defp fetch(id), do: Canvas.get_unstr_canvas(id) || {:error, @not_found}

  defp authorize(canvas, user) do
    if Canvas.can_access_unstr_canvas?(canvas, user.email) do
      :ok
    else
      {:error, @not_found}
    end
  end
end
