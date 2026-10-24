defmodule PscWeb.UnstrCanvasEditorRegressionTest do
  use PscWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Psc.AccountsFixtures
  alias Psc.Canvas
  alias Psc.CanvasFixtures
  alias Psc.Notes
  alias Psc.NotesFixtures
  alias Psc.Repo

  setup :register_and_log_in_user

  # PubSub delivery is asynchronous; a cold VM can take over 100 ms.
  @push_timeout 2_000

  defp canvas_fixture(user, attrs \\ %{}) do
    layout = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id})
    {:ok, canvas} = Canvas.instantiate_template(layout, user.id, attrs)
    canvas
  end

  defp failure_count(html) do
    [_, count] = Regex.run(~r/Failed writes.*?>(\d+)</s, html)
    String.to_integer(count)
  end

  defp canvas_event_count(canvas_id) do
    Repo.aggregate(
      from(e in Psc.Canvas.UnstrCanvasEvent, where: e.unstr_canvas_id == ^canvas_id),
      :count
    )
  end

  describe "save state" do
    test "a failed canvas save stays unsaved and is retried", %{conn: conn, user: user} do
      canvas = canvas_fixture(user)
      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      render_change(view, "update_name", %{"value" => "Changed while deleted"})

      # The row disappears underneath the socket: the next save cannot land.
      {:ok, _canvas} = Canvas.delete_unstr_canvas(canvas)

      send(view.pid, :idle_save)
      html = render(view)

      assert html =~ "Unsaved"
      failures_after_idle = failure_count(html)
      assert failures_after_idle >= 1

      # The dirty fingerprint must not have advanced: the periodic save tries
      # again even though no new edit arrived.
      send(view.pid, :periodic_save)
      html = render(view)

      assert html =~ "Unsaved"
      assert failure_count(html) > failures_after_idle
    end

    test "a failed note save stays unsaved", %{conn: conn, user: user} do
      canvas = canvas_fixture(user)
      note = NotesFixtures.note_fixture(%{user: user, canvas: canvas, title: "Fragile note"})

      {:ok, view, _html} =
        live(conn, ~p"/canvas/#{canvas.id}?tab=notes&note=#{note.id}")

      render_change(view, "update_note_content", %{"content" => "typed before deletion"})
      {:ok, _note} = Notes.delete_note(note)

      send(view.pid, :note_idle_save)
      html = render(view)

      assert html =~ "Unsaved"
      assert failure_count(html) >= 1
    end
  end

  describe "no-op edits" do
    test "blurring a cell without changing it stays saved and records no event", %{
      conn: conn,
      user: user
    } do
      canvas = canvas_fixture(user)
      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      assert canvas_event_count(canvas.id) == 0

      # Exactly what the cell hook sends when the user clicks in and out
      # without typing: the value it already had.
      render_change(view, "update_cell", %{
        "cell_key" => "r1_c1",
        "values" => %{"content" => ""}
      })

      assert has_element?(view, "#canvas-save-state-pill", "Saved")
      assert canvas_event_count(canvas.id) == 0

      # A real change still records and marks the canvas unsaved.
      render_change(view, "update_cell", %{
        "cell_key" => "r1_c1",
        "values" => %{"content" => "real change"}
      })

      assert has_element?(view, "#canvas-save-state-pill", "Unsaved")
      assert canvas_event_count(canvas.id) == 1
    end
  end

  describe "canvas collaboration" do
    test "a second tab of the same user receives the edit", %{conn: conn, user: user} do
      canvas = canvas_fixture(user)
      user_id = user.id
      path = ~p"/canvas/#{canvas.id}"

      {:ok, view_a, _html_a} = live(conn, path)
      {:ok, view_b, _html_b} = live(conn, path)

      render_change(view_a, "update_cell", %{
        "cell_key" => "r1_c1",
        "values" => %{"content" => "from the first tab"}
      })

      assert_push_event(
        view_b,
        "cell_updated",
        %{
          cell_key: "r1_c1",
          field: "content",
          new_value: "from the first tab",
          from_user_id: ^user_id
        },
        @push_timeout
      )

      # The writing tab already has the value locally; it must not see an echo.
      refute_push_event(
        view_a,
        "cell_updated",
        %{cell_key: "r1_c1", field: "content", new_value: "from the first tab"},
        100
      )
    end

    test "a legacy operation without a client id still reaches another client", %{
      conn: conn,
      user: owner
    } do
      canvas = canvas_fixture(owner)
      other = AccountsFixtures.user_fixture()
      other_id = other.id

      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      Phoenix.PubSub.broadcast(
        Psc.PubSub,
        Canvas.pubsub_topic_unstr(canvas.id),
        {:operation, other.id,
         %{
           "type" => "update_cell",
           "cell_key" => "r1_c1",
           "field" => "content",
           "value" => "legacy broadcast"
         }, 1}
      )

      assert_push_event(
        view,
        "cell_updated",
        %{
          cell_key: "r1_c1",
          field: "content",
          new_value: "legacy broadcast",
          from_user_id: ^other_id
        },
        @push_timeout
      )
    end
  end

  describe "notes" do
    test "switching notes flushes the note being left", %{conn: conn, user: user} do
      canvas = canvas_fixture(user)
      first = NotesFixtures.note_fixture(%{user: user, canvas: canvas, title: "First"})
      second = NotesFixtures.note_fixture(%{user: user, canvas: canvas, title: "Second"})

      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=notes&note=#{first.id}")

      render_change(view, "update_note_content", %{"content" => "typed before switching"})
      assert Notes.pending_event_count(first.id) > 0

      view |> element("#canvas-note-#{second.id} button") |> render_click()

      assert Notes.pending_event_count(first.id) == 0
      assert Notes.get_note_content(first.id) == "typed before switching"
      assert Notes.get_note_content(second.id) == ""
    end

    test "deleting a note asks for confirmation", %{conn: conn, user: user} do
      canvas = canvas_fixture(user)
      note = NotesFixtures.note_fixture(%{user: user, canvas: canvas, title: "Delete me"})

      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=notes&note=#{note.id}")

      assert has_element?(view, "#canvas-note-delete[data-confirm]")
    end
  end

  describe "structure editing" do
    test "cell labels and field titles debounce their change events", %{
      conn: conn,
      user: user
    } do
      canvas = canvas_fixture(user)
      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      render_click(view, "toggle_structure", %{})

      assert has_element?(view, ~s|#cell-r1_c1-label[phx-debounce="300"]|)
      assert has_element?(view, ~s|#cell-r1_c1-field-content-title[phx-debounce="300"]|)
    end
  end

  describe "routing" do
    test "a malformed canvas id redirects instead of crashing", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/canvas"}}} = live(conn, "/canvas/not-a-uuid")
    end
  end
end
