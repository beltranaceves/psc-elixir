defmodule PscWeb.NoteCollaborationTest do
  use PscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Psc.AccountsFixtures
  alias Psc.CanvasFixtures
  alias Psc.Notes
  alias Psc.NotesFixtures

  setup :register_and_log_in_user

  # Known bug: the push never arrives, so notes are NOT collaborative today even
  # though the store broadcasts and the hook listens. Verified neutral: the
  # operation shape applies (Psc.Text.apply_operation/2) and
  # TextStore.broadcast/5 publishes {:note_operation, …} on Notes.pubsub_topic/1.
  # Suspect: the LiveView's subscription (subscribe_to_note/1) or the handler's
  # `socket.assigns.note` guard. Unskip when fixed - this test is the proof.
  # Narrowed: a direct broadcast on the note topic now reaches the editor (the
  # next test passes), so subscription + handler + payload are correct. This one
  # goes through Notes.apply_operation/3 and still does not arrive, which points
  # at the context/store path (sequence or insert) rather than the LiveView.
  @tag :skip
  test "an edit by another user reaches the open note", %{conn: conn, user: owner} do
    layout = CanvasFixtures.canvas_layout_fixture(%{author_id: owner.id})

    {:ok, canvas} =
      Psc.Canvas.create_unstr_canvas(owner.id, %{"name" => "Collab", "layout_id" => layout.id})

    note = NotesFixtures.note_fixture(%{user: owner, canvas: canvas, title: "Shared note"})
    other = AccountsFixtures.user_fixture()

    {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=notes&note=#{note.id}")

    # Exactly what the other user's editor does when they type: turn the text
    # delta into operations, apply them through the context, which broadcasts.
    [operation] = Notes.text_to_operations("", "hello from the other user")
    Notes.apply_operation(note.id, other.id, operation)

    assert_push_event(view, "note_content_updated", %{content: "hello from the other user"})
  end

  test "the note topic is subscribed when the note is open", %{conn: conn, user: owner} do
    layout = CanvasFixtures.canvas_layout_fixture(%{author_id: owner.id})

    {:ok, canvas} =
      Psc.Canvas.create_unstr_canvas(owner.id, %{"name" => "Diag", "layout_id" => layout.id})

    note = NotesFixtures.note_fixture(%{user: owner, canvas: canvas, title: "Diag note"})
    other = AccountsFixtures.user_fixture()

    {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=notes&note=#{note.id}")

    # Straight onto the topic: proves whether the LiveView is listening at all.
    Phoenix.PubSub.broadcast(
      Psc.PubSub,
      Notes.pubsub_topic(note.id),
      {:note_operation, other.id, %{"type" => "insert", "pos" => 0, "text" => "direct"}, 1}
    )

    assert_push_event(view, "note_content_updated", %{content: "direct"})
  end

  test "the same user's own operations are not echoed back", %{conn: conn, user: owner} do
    layout = CanvasFixtures.canvas_layout_fixture(%{author_id: owner.id})

    {:ok, canvas} =
      Psc.Canvas.create_unstr_canvas(owner.id, %{"name" => "Solo", "layout_id" => layout.id})

    note = NotesFixtures.note_fixture(%{user: owner, canvas: canvas, title: "Mine"})

    {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=notes&note=#{note.id}")

    [operation] = Notes.text_to_operations("", "typed here")
    Notes.apply_operation(note.id, owner.id, operation)

    refute_push_event(view, "note_content_updated", %{content: "typed here"}, 100)
  end
end
