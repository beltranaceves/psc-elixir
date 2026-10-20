defmodule Psc.NotesTest do
  use Psc.DataCase, async: true

  alias Psc.AccountsFixtures
  alias Psc.Notes
  alias Psc.NotesFixtures
  alias Psc.Repo

  describe "create_note/3" do
    test "creates a note on a canvas" do
      user = AccountsFixtures.user_fixture()
      canvas = NotesFixtures.canvas_fixture(%{user: user})

      assert {:ok, note} = Notes.create_note(canvas.id, user.id, %{title: "My note"})
      assert note.title == "My note"
      assert note.canvas_id == canvas.id
      assert note.created_by_id == user.id
    end

    test "a note carries no shared_with and no owner" do
      user = AccountsFixtures.user_fixture()
      canvas = NotesFixtures.canvas_fixture(%{user: user})

      assert {:ok, note} = Notes.create_note(canvas.id, user.id, %{title: "My note"})

      # The access rules live on the canvas; a note has none of its own.
      refute Map.has_key?(note, :shared_with)
      refute Map.has_key?(note, :user_id)
    end

    test "requires a canvas" do
      user = AccountsFixtures.user_fixture()

      assert {:error, changeset} = Notes.create_note(nil, user.id, %{title: "Orphan"})
      assert %{canvas_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "rejects a canvas that does not exist" do
      user = AccountsFixtures.user_fixture()

      assert {:error, changeset} =
               Notes.create_note(Ecto.UUID.generate(), user.id, %{title: "Nowhere"})

      assert %{canvas_id: ["does not exist"]} = errors_on(changeset)
    end
  end

  describe "list_notes/1" do
    test "returns only the notes of that canvas" do
      canvas = NotesFixtures.canvas_fixture()
      other = NotesFixtures.canvas_fixture()

      mine = NotesFixtures.note_fixture(%{canvas: canvas})
      _theirs = NotesFixtures.note_fixture(%{canvas: other})

      assert [note] = Notes.list_notes(canvas.id)
      assert note.id == mine.id
    end

    test "returns an empty list for a canvas without notes" do
      canvas = NotesFixtures.canvas_fixture()

      assert Notes.list_notes(canvas.id) == []
    end
  end

  describe "the canvas relationship" do
    test "a canvas has_many notes" do
      canvas = NotesFixtures.canvas_fixture()
      note = NotesFixtures.note_fixture(%{canvas: canvas})

      canvas = Repo.preload(canvas, :notes)

      assert [found] = canvas.notes
      assert found.id == note.id
    end

    test "deleting a canvas removes its notes and their events" do
      canvas = NotesFixtures.canvas_fixture()
      user = AccountsFixtures.user_fixture()
      note = NotesFixtures.note_fixture(%{canvas: canvas, user: user})

      {:ok, _} =
        Notes.apply_operation(note.id, user.id, %{
          "type" => "insert",
          "pos" => 0,
          "text" => "hello"
        })

      assert Repo.aggregate(Psc.Notes.NoteEvent, :count) == 1

      {:ok, _} = Psc.Canvas.delete_unstr_canvas(canvas)

      assert Repo.get(Psc.Notes.Note, note.id) == nil
      assert Repo.aggregate(Psc.Notes.NoteEvent, :count) == 0
    end

    test "deleting a note removes its events" do
      user = AccountsFixtures.user_fixture()
      note = NotesFixtures.note_fixture(%{user: user})

      {:ok, _} =
        Notes.apply_operation(note.id, user.id, %{
          "type" => "insert",
          "pos" => 0,
          "text" => "hello"
        })

      assert Repo.aggregate(Psc.Notes.NoteEvent, :count) == 1

      {:ok, _} = Notes.delete_note(note)

      assert Repo.aggregate(Psc.Notes.NoteEvent, :count) == 0
    end
  end

  describe "the event log" do
    test "an operation is stored and the content is replayed" do
      user = AccountsFixtures.user_fixture()
      note = NotesFixtures.note_fixture(%{user: user})

      assert {:ok, 1} =
               Notes.apply_operation(note.id, user.id, %{
                 "type" => "insert",
                 "pos" => 0,
                 "text" => "hello"
               })

      assert Notes.get_note_content(note.id) == "hello"
      assert Notes.pending_event_count(note.id) == 1
    end

    test "saving folds the content and prunes the events it covers" do
      user = AccountsFixtures.user_fixture()
      note = NotesFixtures.note_fixture(%{user: user})

      {:ok, _} =
        Notes.apply_operation(note.id, user.id, %{
          "type" => "insert",
          "pos" => 0,
          "text" => "hello"
        })

      assert {:ok, saved} = Notes.save_content_to_db(note.id, "hello")
      assert saved.snapshot_seq == 1
      assert saved.content == "hello"

      # The covered event is pruned; the content still loads.
      assert Repo.aggregate(Psc.Notes.NoteEvent, :count) == 0
      assert Notes.get_note_content(note.id) == "hello"
      assert Notes.pending_event_count(note.id) == 0
    end

    test "the sequence is floored at the snapshot marker, so pruned events are not re-used" do
      user = AccountsFixtures.user_fixture()
      note = NotesFixtures.note_fixture(%{user: user})

      {:ok, _} =
        Notes.apply_operation(note.id, user.id, %{
          "type" => "insert",
          "pos" => 0,
          "text" => "a"
        })

      {:ok, _} = Notes.save_content_to_db(note.id, "a")

      # The event is gone, so max(seq) would restart at 1. The marker keeps the
      # next event above the snapshot, where the loader will replay it.
      assert {:ok, 2} =
               Notes.apply_operation(note.id, user.id, %{
                 "type" => "insert",
                 "pos" => 1,
                 "text" => "b"
               })

      assert Notes.get_note_content(note.id) == "ab"
    end

    test "the sweeper leaves the events above the marker alone" do
      user = AccountsFixtures.user_fixture()
      note = NotesFixtures.note_fixture(%{user: user})

      {:ok, _} =
        Notes.apply_operation(note.id, user.id, %{
          "type" => "insert",
          "pos" => 0,
          "text" => "a"
        })

      # Fold it, then leave a new event above the marker.
      {:ok, _} = Notes.save_content_to_db(note.id, "a")

      {:ok, _} =
        Notes.apply_operation(note.id, user.id, %{
          "type" => "insert",
          "pos" => 1,
          "text" => "b"
        })

      # The event above the marker is kept; the covered one was already pruned.
      assert Repo.aggregate(Psc.Notes.NoteEvent, :count) == 1
      assert Notes.sweep_folded_events() == 0
    end
  end

  describe "text_to_operations/2" do
    test "an insertion becomes one operation" do
      assert [%{"type" => "insert", "pos" => 0, "text" => "ab"}] =
               Notes.text_to_operations("", "ab")
    end

    test "a deletion becomes one operation" do
      # The common prefix is kept, so the deletion starts after it.
      assert [%{"type" => "delete", "pos" => 2, "count" => 2}] =
               Notes.text_to_operations("abcd", "ab")
    end
  end
end
