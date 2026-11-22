defmodule PscWeb.CanvasHintsLiveTest do
  use PscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Psc.Canvas
  alias Psc.CanvasFixtures

  setup :register_and_log_in_user

  defp table_template(user) do
    lm =
      CanvasFixtures.template_layout_map_fixture()
      |> put_in(["cells", "r1_c1", "hint"], "Who feels the problem?")
      |> Map.update!("columns", fn [first | rest] ->
        [Map.put(first, "hint", "Before anything is built") | rest]
      end)
      |> Map.update!("rows", fn [first | rest] -> [Map.put(first, "hint", "The why") | rest] end)

    CanvasFixtures.canvas_layout_fixture(%{author_id: user.id, layout_map: lm})
  end

  defp cells(canvas), do: Canvas.get_unstr_canvas_content(canvas.id)

  describe "canvas" do
    test "cells, rows and columns with a hint show a tooltip", %{conn: conn, user: user} do
      {:ok, canvas} = Canvas.instantiate_template(table_template(user), user.id)
      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      assert has_element?(lv, "#hint-cell-r1_c1 [data-part='content']", "Who feels the problem?")
      assert has_element?(lv, "#hint-cell-r1_c1-trigger[data-hint-trigger]")
      assert has_element?(lv, "#hint-column-c1", "Before anything is built")
      assert has_element?(lv, "#hint-row-r1", "The why")

      # No hint, no ⓘ.
      refute has_element?(lv, "#hint-cell-r1_c2")
      refute has_element?(lv, "#hint-column-c2")
    end

    test "structure mode edits and clears the hints", %{conn: conn, user: user} do
      {:ok, canvas} = Canvas.instantiate_template(table_template(user), user.id)
      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      lv |> element("#edit-structure-toggle") |> render_click()

      lv
      |> form("#cell-r1_c2-hint-form", %{"cell_key" => "r1_c2", "hint" => "What did you try?"})
      |> render_change()

      lv
      |> form("#column-c2-hint-form", %{"structure_id" => "c2", "hint" => "After launch"})
      |> render_change()

      lv
      |> form("#row-r1-hint-form", %{"structure_id" => "r1", "hint" => ""})
      |> render_change()

      saved = cells(canvas)
      assert saved["r1_c2"]["hint"] == "What did you try?"
      assert Enum.at(saved["columns"], 1)["hint"] == "After launch"
      refute Map.has_key?(hd(saved["rows"]), "hint")

      lv |> element("#edit-structure-toggle") |> render_click()

      assert has_element?(lv, "#hint-cell-r1_c2", "What did you try?")
      assert has_element?(lv, "#hint-column-c2", "After launch")
      refute has_element?(lv, "#hint-row-r1")
    end

    test "an image text label shows its hint and edits it in a panel", %{
      conn: conn,
      user: user
    } do
      lm = put_in(Canvas.image_layout_map(), ["next_step", "hint"], "One concrete action")
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id, layout_map: lm})
      {:ok, canvas} = Canvas.instantiate_template(template, user.id)

      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      assert has_element?(lv, "#hint-cell-next_step", "One concrete action")

      lv |> element("#edit-layout-toggle") |> render_click()
      refute has_element?(lv, "#image-hint-panel-next_step")

      lv |> element("#image-hint-next_step") |> render_click()
      assert has_element?(lv, "#image-hint-panel-next_step")

      lv
      |> form("#cell-next_step-hint-form", %{"cell_key" => "next_step", "hint" => "Owner + date"})
      |> render_change()

      assert cells(canvas)["next_step"]["hint"] == "Owner + date"

      # A click elsewhere closes the panel, like the colour pickers.
      render_hook(lv, "dismiss_color_pickers", %{})
      refute has_element?(lv, "#image-hint-panel-next_step")
    end
  end

  describe "designer" do
    test "a table template edits cell, row and column hints", %{conn: conn, user: user} do
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id})
      {:ok, lv, _html} = live(conn, ~p"/templates/#{template.id}")

      lv
      |> form("#cell-r1_c1-hint-form", %{"cell_key" => "r1_c1", "hint" => "Describe the pain"})
      |> render_change()

      lv |> form("#row-r2-hint-form", %{"index" => "1", "hint" => "How"}) |> render_change()
      lv |> form("#column-c1-hint-form", %{"index" => "0", "hint" => "First"}) |> render_change()

      lv
      |> form("#template-form", %{"name" => template.name, "description" => ""})
      |> render_submit()

      lm = Canvas.get_canvas_layout(template.id).layout_map
      assert lm["cells"]["r1_c1"]["hint"] == "Describe the pain"
      assert Enum.at(lm["rows"], 1)["hint"] == "How"
      assert hd(lm["columns"])["hint"] == "First"
    end

    test "bento and image templates edit a card's hint", %{conn: conn, user: user} do
      for {lm, form_id, key} <- [
            {Canvas.bento_layout_map(), "#card-decision-hint-form", "decision"},
            {Canvas.image_layout_map(), "#image-next_step-hint-form", "next_step"}
          ] do
        template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id, layout_map: lm})
        {:ok, lv, _html} = live(conn, ~p"/templates/#{template.id}")

        lv |> form(form_id, %{"cell_key" => key, "hint" => "Explain it"}) |> render_change()

        lv
        |> form("#template-form", %{"name" => template.name, "description" => ""})
        |> render_submit()

        assert Canvas.get_canvas_layout(template.id).layout_map[key]["hint"] == "Explain it"
      end
    end
  end
end
