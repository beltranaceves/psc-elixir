defmodule PscWeb.CanvasFulcrumsLiveTest do
  use PscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Psc.Canvas
  alias Psc.CanvasFixtures

  setup :register_and_log_in_user

  defp canvas_with_fulcrums(user, mode) do
    cells =
      Map.merge(Canvas.psc_cells(), %{
        "fulcrum_mode" => mode,
        "fulcrums" => [
          %{"id" => "f1", "name" => "Risk", "color" => "rose", "cells" => ["problem"]},
          %{"id" => "f2", "name" => "Bet", "color" => "sky", "cells" => ["problem", "mission"]}
        ]
      })

    {:ok, canvas} = Canvas.create_unstr_canvas(user.id, %{"name" => "Plan", "cells" => cells})
    canvas
  end

  describe "on a canvas" do
    test "picking a fulcrum highlights its cells for everyone, without a new version",
         %{conn: conn, user: user} do
      canvas = canvas_with_fulcrums(user, "single")
      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}")
      {:ok, other, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      refute has_element?(lv, "#cell-card-problem[data-fulcrum-highlight]")

      lv |> element("#fulcrum-chip-f1") |> render_click()

      assert has_element?(lv, "#fulcrum-chip-f1[aria-pressed='true']")
      assert has_element?(lv, "#cell-card-problem[data-fulcrum-highlight]")
      refute has_element?(lv, "#cell-card-mission[data-fulcrum-highlight]")
      assert has_element?(other, "#cell-card-problem[data-fulcrum-highlight]")

      # Single mode: the next pick replaces it.
      lv |> element("#fulcrum-chip-f2") |> render_click()
      assert has_element?(lv, "#fulcrum-chip-f1[aria-pressed='false']")
      assert has_element?(lv, "#cell-card-mission[data-fulcrum-highlight]")

      assert length(Canvas.list_pivots(canvas.id)) == 1
    end

    test "multiple mode highlights several at once", %{conn: conn, user: user} do
      canvas = canvas_with_fulcrums(user, "multiple")
      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      lv |> element("#fulcrum-chip-f1") |> render_click()
      lv |> element("#fulcrum-chip-f2") |> render_click()

      assert has_element?(lv, "#fulcrum-chip-f1[aria-pressed='true']")
      assert has_element?(lv, "#fulcrum-chip-f2[aria-pressed='true']")
    end

    test "the Info tab turns fulcrums off and back on, for everyone, without a version",
         %{conn: conn, user: user} do
      canvas = canvas_with_fulcrums(user, "single")
      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=info")
      {:ok, other, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      assert has_element?(lv, "#canvas-fulcrum-mode-single[aria-pressed='true']")
      assert has_element?(other, "#fulcrum-picker")

      lv |> element("#canvas-fulcrum-mode-off") |> render_click()

      assert has_element?(lv, "#canvas-fulcrum-mode-off[aria-pressed='true']")
      refute has_element?(lv, "#canvas-info-edit-fulcrums")
      refute has_element?(other, "#fulcrum-picker")
      refute has_element?(other, "#fulcrums-canvas-button")

      lv |> element("#canvas-fulcrum-mode-multiple") |> render_click()
      assert has_element?(other, "#fulcrum-chip-f2")
      assert Canvas.get_unstr_canvas_content(canvas.id)["fulcrum_mode"] == "multiple"
      assert length(Canvas.list_pivots(canvas.id)) == 1
    end

    test "off hides the picker and the Fulcrums button, and highlights nothing",
         %{conn: conn, user: user} do
      canvas = canvas_with_fulcrums(user, "off")
      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      refute has_element?(lv, "#fulcrum-picker")
      refute has_element?(lv, "#fulcrums-canvas-button")

      # A stray event changes nothing.
      render_click(lv, "toggle_fulcrum", %{"id" => "f1"})
      render_click(lv, "open_fulcrums", %{})
      render_click(lv, "edit_fulcrums", %{})
      refute has_element?(lv, "[data-fulcrum-highlight]")
      refute has_element?(lv, "#fulcrums-dialog")
      refute has_element?(lv, "#fulcrums-edit-dialog")
    end

    test "the Info tab edits the fulcrums, and saving is a versioned change",
         %{conn: conn, user: user} do
      {:ok, canvas} =
        Canvas.create_unstr_canvas(user.id, %{"name" => "Plan", "cells" => Canvas.psc_cells()})

      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=info")
      refute has_element?(lv, "#fulcrum-picker")

      lv |> element("#canvas-info-edit-fulcrums") |> render_click()
      assert has_element?(lv, "#fulcrums-edit-dialog")

      lv |> element("#canvas-fulcrums-add") |> render_click()

      lv
      |> element("#canvas-fulcrums-f1 button[phx-value-key='problem']")
      |> render_click()

      lv |> element("#fulcrums-save") |> render_click()
      refute has_element?(lv, "#fulcrums-edit-dialog")

      assert [%{"cells" => ["problem"]}] = Canvas.get_unstr_canvas_content(canvas.id)["fulcrums"]
      assert [_root, %{kind: "draft"}] = Canvas.list_pivots(canvas.id)
    end

    test "the Fulcrums dialog picks a fulcrum without a version and has no editing",
         %{conn: conn, user: user} do
      canvas = canvas_with_fulcrums(user, "single")
      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      lv |> element("#fulcrums-canvas-button") |> render_click()

      assert has_element?(lv, "#fulcrums-dialog")
      assert has_element?(lv, "#fulcrum-select-f1", "Risk")
      assert has_element?(lv, "#fulcrum-select-f2", "Bet")

      # Nothing to rename, recolour or re-cell from here.
      refute has_element?(lv, "#fulcrums-dialog input")
      refute has_element?(lv, "#fulcrums-dialog [phx-click='fulcrum_add']")
      refute has_element?(lv, "#fulcrums-dialog [phx-click='fulcrum_toggle_cell']")
      refute has_element?(lv, "#fulcrums-save")

      lv |> element("#fulcrum-select-f1") |> render_click()

      assert has_element?(lv, "#fulcrum-select-f1[aria-pressed='true']")
      assert has_element?(lv, "#cell-card-problem[data-fulcrum-highlight]")
      assert has_element?(lv, "#fulcrum-chip-f1[aria-pressed='true']")
      assert length(Canvas.list_pivots(canvas.id)) == 1

      lv |> element("#fulcrums-done") |> render_click()
      refute has_element?(lv, "#fulcrums-dialog")
      assert has_element?(lv, "#cell-card-problem[data-fulcrum-highlight]")
    end
  end

  describe "in the template designer" do
    test "fulcrums and their mode are saved with the template", %{conn: conn, user: user} do
      template =
        CanvasFixtures.canvas_layout_fixture(%{author_id: user.id, name: "With fulcrums"})

      [key | _] = Psc.Canvas.Structure.cell_keys(template.layout_map)

      {:ok, lv, _html} = live(conn, ~p"/templates/#{template.id}")

      lv |> element("#fulcrum-mode-multiple") |> render_click()
      lv |> element("#template-fulcrum-editor-add") |> render_click()

      lv
      |> element("#template-fulcrum-editor-f1 button[phx-value-key='#{key}']")
      |> render_click()

      lv |> form("#template-form", %{"name" => "With fulcrums"}) |> render_submit()

      template = Canvas.get_canvas_layout(template.id)
      assert template.layout_map["fulcrum_mode"] == "multiple"
      assert [%{"cells" => [^key]}] = template.layout_map["fulcrums"]
    end

    test "turning fulcrums off hides the editor but keeps the list", %{conn: conn, user: user} do
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id, name: "Off"})
      {:ok, lv, _html} = live(conn, ~p"/templates/#{template.id}")

      lv |> element("#template-fulcrum-editor-add") |> render_click()
      lv |> element("#fulcrum-mode-off") |> render_click()

      assert has_element?(lv, "#fulcrum-mode-off[aria-pressed='true']")
      refute has_element?(lv, "#template-fulcrum-editor")

      lv |> form("#template-form", %{"name" => "Off"}) |> render_submit()

      template = Canvas.get_canvas_layout(template.id)
      assert template.layout_map["fulcrum_mode"] == "off"
      assert [_kept] = template.layout_map["fulcrums"]
    end
  end
end
