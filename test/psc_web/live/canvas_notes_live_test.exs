defmodule PscWeb.CanvasNotesLiveTest do
  @moduledoc """
  The Notes view of the canvas editor.

  A note is a child of its canvas: it inherits the canvas's access rules, and
  only the canvas's owner can delete one (ADR-027).
  """

  use PscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Psc.Canvas
  alias Psc.CanvasFixtures
  alias Psc.Notes
  alias Psc.NotesFixtures

  setup :register_and_log_in_user

  defp canvas_for(user) do
    template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id})
    {:ok, canvas} = Canvas.instantiate_template(template, user.id)
    canvas
  end

  defp canvas_with_mode(user, mode) do
    template =
      CanvasFixtures.canvas_layout_fixture(%{
        author_id: user.id,
        layout_map: Map.put(CanvasFixtures.template_layout_map_fixture(), "notes_mode", mode)
      })

    {:ok, canvas} = Canvas.instantiate_template(template, user.id)
    canvas
  end

  describe "the notes view" do
    test "shows an empty state when the canvas has no notes", %{conn: conn, user: user} do
      canvas = canvas_for(user)

      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=notes")

      assert has_element?(lv, "#canvas-notes-empty")
      refute has_element?(lv, "#canvas-notes-items")
      # The editor waits for a note to be chosen.
      assert has_element?(lv, "#canvas-note-editor")
    end

    test "lists the notes of the canvas", %{conn: conn, user: user} do
      canvas = canvas_for(user)
      note = NotesFixtures.note_fixture(%{canvas: canvas, user: user, title: "First note"})

      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=notes")

      assert has_element?(lv, "#canvas-notes-items li#canvas-note-#{note.id}")
      assert has_element?(lv, "#canvas-notes-items", "First note")
      refute has_element?(lv, "#canvas-notes-empty")
    end

    test "does not list the notes of another canvas", %{conn: conn, user: user} do
      canvas = canvas_for(user)
      other = canvas_for(user)
      _theirs = NotesFixtures.note_fixture(%{canvas: other, user: user, title: "Not mine"})

      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=notes")

      refute has_element?(lv, "#canvas-notes-items", "Not mine")
    end

    test "opens a note from the URL", %{conn: conn, user: user} do
      canvas = canvas_for(user)
      note = NotesFixtures.note_fixture(%{canvas: canvas, user: user, title: "Open me"})

      {:ok, lv, html} = live(conn, ~p"/canvas/#{canvas.id}?tab=notes&note=#{note.id}")

      assert has_element?(lv, "#canvas-note-title-form input[value='Open me']")
      assert html =~ "canvas-note-preview"
    end

    test "ignores a note that belongs to another canvas", %{conn: conn, user: user} do
      canvas = canvas_for(user)
      other = canvas_for(user)
      theirs = NotesFixtures.note_fixture(%{canvas: other, user: user, title: "Not mine"})

      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=notes&note=#{theirs.id}")

      refute has_element?(lv, "#canvas-note-title-form input[value='Not mine']")
    end
  end

  describe "creating a note" do
    test "creates it on the canvas and opens it", %{conn: conn, user: user} do
      canvas = canvas_for(user)

      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=notes")

      lv |> element("#new-note-button") |> render_click()

      assert [note] = Notes.list_notes(canvas.id)
      assert note.canvas_id == canvas.id
      assert note.created_by_id == user.id
      # The note is opened, and its id is in the URL.
      assert has_element?(lv, "#canvas-note-title-form")
      assert_patch(lv, ~p"/canvas/#{canvas.id}?tab=notes&note=#{note.id}")
    end
  end

  describe "editing a note" do
    test "writes the content and keeps it after a reload", %{conn: conn, user: user} do
      canvas = canvas_for(user)
      note = NotesFixtures.note_fixture(%{canvas: canvas, user: user})

      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=notes&note=#{note.id}")

      lv
      |> form("#canvas-note-form", %{"content" => "A note in the test"})
      |> render_change()

      assert Notes.get_note_content(note.id) == "A note in the test"

      # The content survives a reload.
      {:ok, _lv, html} = live(conn, ~p"/canvas/#{canvas.id}?tab=notes&note=#{note.id}")
      assert html =~ "A note in the test"
    end

    test "renames the note", %{conn: conn, user: user} do
      canvas = canvas_for(user)
      note = NotesFixtures.note_fixture(%{canvas: canvas, user: user})

      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=notes&note=#{note.id}")

      lv
      |> form("#canvas-note-title-form", %{"title" => "Renamed"})
      |> render_change()

      assert Notes.get_note(note.id).title == "Renamed"
    end
  end

  describe "deleting a note" do
    test "the canvas owner can delete it", %{conn: conn, user: user} do
      canvas = canvas_for(user)
      note = NotesFixtures.note_fixture(%{canvas: canvas, user: user})

      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=notes&note=#{note.id}")

      assert has_element?(lv, "#canvas-note-delete")

      lv |> element("#canvas-note-delete") |> render_click()

      assert Notes.get_note(note.id) == nil
    end

    test "a shared user cannot delete it", %{user: user} do
      canvas = canvas_for(user)
      note = NotesFixtures.note_fixture(%{canvas: canvas, user: user})

      # Share the canvas with somebody else.
      {:ok, _canvas} =
        Canvas.share_unstr_canvas_with(canvas, "shared@example.com")

      shared = Psc.AccountsFixtures.user_fixture(%{email: "shared@example.com"})

      conn =
        build_conn()
        |> log_in_user(shared)

      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=notes&note=#{note.id}")

      # The shared user can read and edit the note…
      assert has_element?(lv, "#canvas-note-title-form")
      # …but there is no delete action.
      refute has_element?(lv, "#canvas-note-delete")
    end
  end

  describe "the scratchpad mode" do
    test "a scratchpad canvas has one note and no list", %{conn: conn, user: user} do
      canvas = canvas_with_mode(user, "single")

      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=notes")

      # The note is created the first time the view is opened.
      assert [note] = Notes.list_notes(canvas.id)
      assert note.title == "Scratchpad"

      # There is no list, and no way to create a second note.
      refute has_element?(lv, "#canvas-notes-list")
      refute has_element?(lv, "#new-note-button")

      # There is no list to go back to either.
      refute has_element?(lv, "#canvas-notes-back")

      # The editor takes the whole view.
      assert has_element?(lv, "#canvas-note-title-form")
      assert has_element?(lv, "#canvas-note-preview")

      # And the scratchpad is not deletable: it would come straight back.
      refute has_element?(lv, "#canvas-note-delete")
    end

    test "opening the view again does not create a second note", %{conn: conn, user: user} do
      canvas = canvas_with_mode(user, "single")

      {:ok, _lv, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=notes")
      {:ok, _lv, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=notes")

      assert length(Notes.list_notes(canvas.id)) == 1
    end

    test "a scratchpad canvas keeps what is written in it", %{conn: conn, user: user} do
      canvas = canvas_with_mode(user, "single")

      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=notes")

      lv
      |> form("#canvas-note-form", %{"content" => "A thought"})
      |> render_change()

      assert [note] = Notes.list_notes(canvas.id)
      assert Notes.get_note_content(note.id) == "A thought"
    end

    test "a multi-note canvas still lists its notes", %{conn: conn, user: user} do
      canvas = canvas_for(user)
      NotesFixtures.note_fixture(%{canvas: canvas, user: user, title: "One"})

      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=notes")

      assert has_element?(lv, "#canvas-notes-list")
      assert has_element?(lv, "#new-note-button")
      assert has_element?(lv, "#canvas-notes-items", "One")
    end
  end

  describe "the status pill" do
    test "there is one pill, and the note editor has none of its own", %{conn: conn, user: user} do
      canvas = canvas_for(user)
      note = NotesFixtures.note_fixture(%{canvas: canvas, user: user})

      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=notes&note=#{note.id}")

      assert has_element?(lv, "#canvas-save-state-pill")
      refute has_element?(lv, "#canvas-note-status")
    end

    test "it reports the note and lists the canvas alongside it", %{conn: conn, user: user} do
      canvas = canvas_for(user)
      note = NotesFixtures.note_fixture(%{canvas: canvas, user: user})

      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=notes&note=#{note.id}")

      html = lv |> element("#canvas-save-state-pill-tooltip") |> render()

      assert html =~ "Note"
      assert html =~ "Canvas"
      assert html =~ "Writes this session"
    end

    test "it reports the canvas alone when no note is open", %{conn: conn, user: user} do
      canvas = canvas_for(user)

      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=editor")

      html = lv |> element("#canvas-save-state-pill-tooltip") |> render()

      # One surface, so no section heading.
      refute html =~ "Canvas"
      assert html =~ "Writes this session"
    end
  end

  describe "access" do
    test "a user who cannot open the canvas cannot open its notes", %{user: user} do
      canvas = canvas_for(user)
      note = NotesFixtures.note_fixture(%{canvas: canvas, user: user})

      stranger = Psc.AccountsFixtures.user_fixture()

      stranger_conn =
        build_conn()
        |> log_in_user(stranger)

      assert {:error, {:redirect, %{to: "/canvas"}}} =
               live(stranger_conn, ~p"/canvas/#{canvas.id}?tab=notes&note=#{note.id}")
    end
  end
end
