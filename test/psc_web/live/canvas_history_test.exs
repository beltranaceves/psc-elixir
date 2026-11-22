defmodule PscWeb.CanvasHistoryLiveTest do
  use PscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Psc.AccountsFixtures
  alias Psc.Canvas

  setup :register_and_log_in_user

  setup %{user: user} do
    {:ok, canvas} =
      Canvas.create_unstr_canvas(user.id, %{"name" => "Plan", "cells" => Canvas.psc_cells()})

    [root] = Canvas.list_pivots(canvas.id)
    %{canvas: canvas, root: root}
  end

  defp type(lv, value) do
    render_change(lv, "update_cell", %{"cell_key" => "problem", "values" => %{"content" => value}})
  end

  defp draft_with(canvas, user, value) do
    op = %{
      "type" => "update_cell",
      "cell_key" => "problem",
      "field" => "content",
      "value" => value
    }

    {:ok, _seq} = Canvas.apply_unstr_canvas_operation(canvas.id, user.id, op)
    {:ok, {:created, draft}} = Canvas.start_draft(canvas.id, user.id)
    draft
  end

  test "a new canvas shows its root as the current version", %{conn: conn, canvas: c, root: root} do
    {:ok, lv, _html} = live(conn, ~p"/canvas/#{c.id}?tab=history")

    assert has_element?(lv, "#pivot-node-#{root.id}", "Initial version")
    assert has_element?(lv, "#pivot-details", "Current")
    refute has_element?(lv, "#history-pivot-button")
    refute has_element?(lv, "#pivot-load")
  end

  test "an edit starts a draft and asks for a name after the first save",
       %{conn: conn, canvas: c, root: root} do
    {:ok, lv, _html} = live(conn, ~p"/canvas/#{c.id}")

    type(lv, "Teams lose hours")

    # The draft exists straight away, but the dialog waits for the save.
    assert [_root, draft] = Canvas.list_pivots(c.id)
    assert draft.kind == "draft" and draft.parent_id == root.id
    refute has_element?(lv, "#pivot-dialog")

    send(lv.pid, :idle_save)
    assert has_element?(lv, "#pivot-dialog")

    # Later keeps the draft unnamed; more typing does not ask again.
    lv |> element("#pivot-later") |> render_click()
    refute has_element?(lv, "#pivot-dialog")
    type(lv, "Teams lose whole days")
    send(lv.pid, :idle_save)
    refute has_element?(lv, "#pivot-dialog")
    assert length(Canvas.list_pivots(c.id)) == 2

    # The Pivot button names it whenever the user is ready.
    lv |> element("#pivot-canvas-button") |> render_click()

    lv
    |> form("#pivot-form", pivot: %{name: "Reporting pain", rationale: "Interviews"})
    |> render_submit()

    refute has_element?(lv, "#pivot-dialog")
    named = Enum.find(Canvas.list_pivots(c.id), &(&1.id == draft.id))
    assert named.name == "Reporting pain"
    assert named.cells["problem"]["content"] == "Teams lose whole days"
  end

  test "renaming the canvas does not start a version", %{conn: conn, canvas: c} do
    {:ok, lv, _html} = live(conn, ~p"/canvas/#{c.id}")

    render_change(lv, "update_name", %{"value" => "Renamed"})
    send(lv.pid, :idle_save)

    refute has_element?(lv, "#pivot-dialog")
    assert length(Canvas.list_pivots(c.id)) == 1
  end

  test "an unnamed draft is dashed and can be named later from History",
       %{conn: conn, canvas: c, user: user} do
    draft = draft_with(c, user, "Rough idea")

    {:ok, lv, _html} = live(conn, ~p"/canvas/#{c.id}?tab=history")

    assert has_element?(lv, "#pivot-node-#{draft.id}.border-dashed", "Unnamed changes")
    lv |> element("#pivot-name") |> render_click()

    assert lv |> form("#pivot-form", pivot: %{name: "", rationale: ""}) |> render_submit() =~
             "can&#39;t be blank"
  end

  test "shows the clicked version's canvas read-only",
       %{conn: conn, canvas: c, user: user, root: root} do
    draft_with(c, user, "New problem")

    {:ok, lv, _html} = live(conn, ~p"/canvas/#{c.id}?tab=history")

    # The current version (the draft) is selected and shows the live canvas.
    assert has_element?(lv, "#pivot-preview [data-cell-key=problem]", "New problem")

    lv |> element("#pivot-node-#{root.id}") |> render_click()
    refute has_element?(lv, "#pivot-preview [data-cell-key=problem]", "New problem")

    # Same renderer, but nothing to edit, and no ids that clash with the editor.
    refute has_element?(lv, "#pivot-preview form")
    refute has_element?(lv, "#pivot-preview [phx-hook]")
    refute has_element?(lv, "#pivot-preview [id]")
    assert has_element?(lv, "#canvas-panel-editor #cell-card-problem")
  end

  test "bento and image versions use their own renderer, read-only", %{conn: conn, user: user} do
    Canvas.seed_builtin_templates()

    for slug <- ["bento", "image"] do
      {:ok, canvas} =
        slug |> Canvas.get_template_by_slug() |> Canvas.instantiate_template(user.id)

      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=history")

      assert has_element?(lv, "#pivot-preview [data-cell-key]")
      refute has_element?(lv, "#pivot-preview [id]")
      refute has_element?(lv, "#pivot-preview form")
    end
  end

  test "loading a version swaps the canvas for everyone without a new version",
       %{conn: conn, canvas: c, user: user, root: root} do
    draft = draft_with(c, user, "Later text")

    {:ok, lv, _html} = live(conn, ~p"/canvas/#{c.id}?tab=history")
    {:ok, other, _html} = live(conn, ~p"/canvas/#{c.id}")

    lv |> element("#pivot-node-#{root.id}") |> render_click()
    lv |> element("#pivot-load") |> render_click()
    assert has_element?(lv, "#pivot-load-dialog")
    lv |> element("#pivot-confirm-load") |> render_click()

    assert_push_event(lv, "cell_updated", %{cell_key: "problem", new_value: "", from_user_id: -1})
    assert_push_event(other, "cell_updated", %{cell_key: "problem", from_user_id: -1})

    assert Canvas.head_pivot_id(c.id) == root.id
    assert length(Canvas.list_pivots(c.id)) == 2
    assert has_element?(lv, "#pivot-node-#{draft.id}", "Unnamed changes")
    refute has_element?(lv, "#pivot-dialog")
  end

  test "everyone with access can load and fork", %{canvas: c, user: user, root: root} do
    draft_with(c, user, "x")
    guest = AccountsFixtures.user_fixture()
    {:ok, c} = Canvas.share_unstr_canvas_with(c, guest.email)

    {:ok, lv, _html} = build_conn() |> log_in_user(guest) |> live(~p"/canvas/#{c.id}?tab=history")

    lv |> element("#pivot-node-#{root.id}") |> render_click()
    assert has_element?(lv, "#pivot-load")
    assert has_element?(lv, "#pivot-fork")
  end

  test "fork into a new canvas, keeping the history", %{conn: conn, canvas: c, user: user} do
    draft = draft_with(c, user, "idea")
    {:ok, _named} = Canvas.name_pivot(c.id, draft.id, %{name: "Idea", rationale: "Why"})

    {:ok, lv, _html} = live(conn, ~p"/canvas/#{c.id}?tab=history")

    lv |> element("#pivot-fork") |> render_click()
    assert has_element?(lv, "#pivot-fork-dialog #fork-keep-history")

    assert {:error, {:live_redirect, %{to: "/canvas/" <> path}}} =
             lv
             |> form("#pivot-fork-form", fork: %{mode: "canvas", keep_history: "true"})
             |> render_submit()

    [fork_id | _] = String.split(path, "?")
    assert Canvas.get_unstr_canvas(fork_id).name == "Plan (fork)"
    assert Enum.map(Canvas.list_pivots(fork_id), & &1.name) == ["Initial version", "Idea"]
  end

  test "fork in place starts a version under the selected one and asks for its name",
       %{conn: conn, canvas: c, user: user, root: root} do
    draft_with(c, user, "idea")

    {:ok, lv, _html} = live(conn, ~p"/canvas/#{c.id}?tab=history")

    lv |> element("#pivot-node-#{root.id}") |> render_click()
    lv |> element("#pivot-fork") |> render_click()

    # Choosing "here" hides the history checkbox, which only applies to a new canvas.
    lv |> form("#pivot-fork-form", fork: %{mode: "here"}) |> render_change()
    refute has_element?(lv, "#fork-keep-history")

    lv |> form("#pivot-fork-form", fork: %{mode: "here"}) |> render_submit()

    [_root, _old, fork] = Canvas.list_pivots(c.id)
    assert fork.parent_id == root.id
    assert Canvas.head_pivot_id(c.id) == fork.id
    assert has_element?(lv, "#pivot-dialog")
    assert has_element?(lv, "#pivot-node-#{fork.id}.border-dashed")
  end
end
