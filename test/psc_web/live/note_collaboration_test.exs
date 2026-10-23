defmodule PscWeb.NoteCollaborationTest do
  use PscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Psc.AccountsFixtures
  alias Psc.CanvasFixtures
  alias Psc.Notes
  alias Psc.NotesFixtures

  setup :register_and_log_in_user

  # Delivery is a PubSub broadcast, so the push is asynchronous. ExUnit's
  # default 100 ms is not enough for the first push in a fresh VM (module
  # loading makes it ~105 ms cold, ~2 ms warm).
  @push_timeout 2_000

  # The acceptance test for collaboration: an operation applied through the
  # context by another user must reach the open note.
  test "an edit by another user reaches the open note", %{conn: conn, user: owner} do
    layout = CanvasFixtures.canvas_layout_fixture(%{author_id: owner.id})

    {:ok, canvas} =
      Psc.Canvas.create_unstr_canvas(owner.id, %{"name" => "Collab", "layout_id" => layout.id})

    note = NotesFixtures.note_fixture(%{user: owner, canvas: canvas, title: "Shared note"})
    other = AccountsFixtures.user_fixture()
    other_id = other.id

    {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=notes&note=#{note.id}")

    # Exactly what the other user's editor does when they type: turn the text
    # delta into operations, apply them through the context, which broadcasts.
    [operation] = Notes.text_to_operations("", "hello from the other user")
    Notes.apply_operation(note.id, other_id, operation)

    assert_push_event(
      view,
      "note_content_updated",
      %{content: "hello from the other user", from_user_id: ^other_id},
      @push_timeout
    )
  end

  # A scratchpad canvas has one note and no note list; opening the Notes view
  # creates and subscribes it. It used to open without subscribing at all, so
  # a remote edit went nowhere.
  test "an edit by another user reaches a scratchpad note", %{conn: conn, user: owner} do
    layout = CanvasFixtures.canvas_layout_fixture(%{author_id: owner.id})

    {:ok, canvas} =
      Psc.Canvas.create_unstr_canvas(owner.id, %{
        "name" => "Scratch",
        "layout_id" => layout.id,
        "notes_mode" => "single"
      })

    other = AccountsFixtures.user_fixture()
    other_id = other.id

    {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=notes")

    assert [note] = Notes.list_notes(canvas.id)

    [operation] = Notes.text_to_operations("", "scratch from afar")
    Notes.apply_operation(note.id, other_id, operation)

    assert_push_event(
      view,
      "note_content_updated",
      %{content: "scratch from afar", from_user_id: ^other_id},
      @push_timeout
    )
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

    assert_push_event(view, "note_content_updated", %{content: "direct"}, @push_timeout)
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

  # Two tabs of the same account are two clients. The echo is suppressed per
  # client, not per user, so the second tab still sees what the first typed.
  test "another tab of the same user receives the edit", %{conn: conn, user: owner} do
    layout = CanvasFixtures.canvas_layout_fixture(%{author_id: owner.id})

    {:ok, canvas} =
      Psc.Canvas.create_unstr_canvas(owner.id, %{"name" => "Two tabs", "layout_id" => layout.id})

    note = NotesFixtures.note_fixture(%{user: owner, canvas: canvas, title: "Mine"})
    owner_id = owner.id
    path = ~p"/canvas/#{canvas.id}?tab=notes&note=#{note.id}"

    {:ok, view_a, _html_a} = live(conn, path)
    {:ok, view_b, _html_b} = live(conn, path)

    # What typing in the first tab does: the form's change event, which applies
    # the delta with that view's client id.
    render_change(view_a, "update_note_content", %{"content" => "from the other tab"})

    assert_push_event(
      view_b,
      "note_content_updated",
      %{content: "from the other tab", from_user_id: ^owner_id},
      @push_timeout
    )

    # The tab that typed already has the text locally: no echo to it.
    refute_push_event(view_a, "note_content_updated", %{content: "from the other tab"}, 100)
  end

  test "the note header says who else has the note open", %{conn: conn, user: owner} do
    layout = CanvasFixtures.canvas_layout_fixture(%{author_id: owner.id})

    {:ok, canvas} =
      Psc.Canvas.create_unstr_canvas(owner.id, %{"name" => "Together", "layout_id" => layout.id})

    note = NotesFixtures.note_fixture(%{user: owner, canvas: canvas, title: "Shared"})
    other = AccountsFixtures.user_fixture()
    {:ok, _canvas} = Psc.Canvas.share_unstr_canvas_with(canvas, other.email)

    {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=notes&note=#{note.id}")
    refute render(view) =~ "is editing"

    # The other user opens the same note. Presence is tracked in the live
    # process, so the first view hears about it on its own note topic.
    conn_b = log_in_user(Phoenix.ConnTest.build_conn(), other)
    {:ok, _view_b, _html_b} = live(conn_b, ~p"/canvas/#{canvas.id}?tab=notes&note=#{note.id}")

    assert render(view) =~ "#{other.email} is editing"
  end

  # The textarea belongs to the client hook (`phx-update="ignore"`), so the
  # server cannot hand it content with a re-render. Opening a note that
  # already has text must push that text, marked as a resync (`-1`), or the
  # editor would come up empty until someone else typed.
  test "opening a note with content pushes it to the editor", %{conn: conn, user: owner} do
    layout = CanvasFixtures.canvas_layout_fixture(%{author_id: owner.id})

    {:ok, canvas} =
      Psc.Canvas.create_unstr_canvas(owner.id, %{"name" => "Filled", "layout_id" => layout.id})

    note =
      NotesFixtures.note_fixture(%{
        user: owner,
        canvas: canvas,
        title: "Written elsewhere",
        content: "already here"
      })

    {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=notes&note=#{note.id}")

    assert_push_event(
      view,
      "note_content_updated",
      %{content: "already here", from_user_id: -1},
      @push_timeout
    )
  end
end
