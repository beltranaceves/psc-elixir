defmodule Psc.EventsSweeperTest do
  # async: false so the sandbox is shared and the sweeper process (which runs
  # outside the test process) sees the rows the test writes.
  use Psc.DataCase, async: false

  import Ecto.Query

  alias Psc.Canvas
  alias Psc.EventsSweeper
  alias Psc.Notes
  alias Psc.NotesFixtures

  describe "sweep/0" do
    test "prunes folded rows from every event table" do
      user = Psc.AccountsFixtures.user_fixture()

      {:ok, canvas} = Canvas.create_unstr_canvas(user.id, %{"name" => "Sweep canvas"})

      {:ok, 1} =
        Canvas.apply_unstr_canvas_operation(canvas.id, user.id, %{
          "type" => "update_name",
          "value" => "Renamed"
        })

      cells = Canvas.get_unstr_canvas_content(canvas.id)
      {:ok, _} = Canvas.save_unstr_canvas_content_to_db(canvas.id, cells)

      note = NotesFixtures.note_fixture(%{user: user})

      {:ok, 1} =
        Notes.apply_operation(note.id, user.id, %{
          "type" => "insert",
          "pos" => 0,
          "text" => "ab"
        })

      {:ok, _} = Notes.save_content_to_db(note.id, "ab")

      # Re-create the rows that escaped pruning, so the marker covers them and
      # the saved content already includes them.
      insert_legacy_canvas_event(canvas, user, 1)
      insert_legacy_note_event(note, user, 1)

      assert {1, 1} = EventsSweeper.sweep()

      assert Repo.aggregate(from(e in Canvas.UnstrCanvasEvent), :count) == 0
      assert Repo.aggregate(from(e in Notes.NoteEvent), :count) == 0

      # Folded state is still loadable after the sweep
      assert Canvas.get_unstr_canvas_content(canvas.id)["$name"] == "Renamed"
      assert Notes.get_note_content(note.id) == "ab"
    end

    test "returns zeros when there is nothing to prune" do
      user = Psc.AccountsFixtures.user_fixture()
      note = NotesFixtures.note_fixture(%{user: user})

      {:ok, _} =
        Notes.apply_operation(note.id, user.id, %{
          "type" => "insert",
          "pos" => 0,
          "text" => "pending"
        })

      assert {0, 0} = EventsSweeper.sweep()
      assert Notes.pending_event_count(note.id) == 1
    end
  end

  describe "process" do
    test "prunes folded rows when it handles a sweep message" do
      user = Psc.AccountsFixtures.user_fixture()
      note = NotesFixtures.note_fixture(%{user: user})

      {:ok, 1} =
        Notes.apply_operation(note.id, user.id, %{
          "type" => "insert",
          "pos" => 0,
          "text" => "x"
        })

      {:ok, _} = Notes.save_content_to_db(note.id, "x")
      insert_legacy_note_event(note, user, 1)

      assert Repo.aggregate(from(e in Notes.NoteEvent), :count) == 1

      start_supervised!({EventsSweeper, enabled: true, initial_delay: 60_000, interval: 60_000})
      send(Process.whereis(EventsSweeper), :sweep)
      # :sys.get_state/1 blocks until the already-queued :sweep is handled
      _ = :sys.get_state(EventsSweeper)

      assert Repo.aggregate(from(e in Notes.NoteEvent), :count) == 0
    end
  end

  # Events that escaped pruning (written before pruning shipped, or left by an
  # abandoned session) are re-created here with a seq the marker already covers.
  defp insert_legacy_canvas_event(canvas, user, seq) do
    %Canvas.UnstrCanvasEvent{}
    |> Canvas.UnstrCanvasEvent.changeset(%{
      unstr_canvas_id: canvas.id,
      user_id: user.id,
      seq: seq,
      operation: %{"type" => "update_name", "value" => "Renamed"}
    })
    |> Repo.insert!()
  end

  defp insert_legacy_note_event(note, user, seq) do
    %Notes.NoteEvent{}
    |> Notes.NoteEvent.changeset(%{
      note_id: note.id,
      user_id: user.id,
      seq: seq,
      operation: %{"type" => "insert", "pos" => 0, "text" => "ab"}
    })
    |> Repo.insert!()
  end
end
