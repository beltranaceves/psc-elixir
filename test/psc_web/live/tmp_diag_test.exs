defmodule PscWeb.TmpDiagTest do
  use PscWeb.ConnCase, async: false

  alias Psc.AccountsFixtures
  alias Psc.CanvasFixtures
  alias Psc.Notes
  alias Psc.NotesFixtures

  setup :register_and_log_in_user

  test "diagnose apply_operation path", %{user: owner} do
    layout = CanvasFixtures.canvas_layout_fixture(%{author_id: owner.id})

    {:ok, canvas} =
      Psc.Canvas.create_unstr_canvas(owner.id, %{"name" => "Collab", "layout_id" => layout.id})

    note = NotesFixtures.note_fixture(%{user: owner, canvas: canvas, title: "Shared note"})
    other = AccountsFixtures.user_fixture()

    [operation] = Notes.text_to_operations("", "hello from the other user")
    IO.inspect(operation, label: "operation")

    result = Notes.apply_operation(note.id, other.id, operation)
    IO.inspect(result, label: "apply_operation result")

    IO.inspect(Notes.get_note_content(note.id), label: "content after")
    IO.inspect(Psc.TextStore.next_sequence(Psc.Notes.Store, note.id), label: "next_seq")
    IO.inspect(Psc.Repo.all(Psc.Notes.NoteEvent), label: "events")
  end
end
