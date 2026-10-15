defmodule PscWeb.CanvasLayoutLiveTest do
  use PscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Psc.Canvas
  alias Psc.CanvasFixtures

  setup :register_and_log_in_user

  describe "index (template library)" do
    test "renders the template library page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/canvas-layouts")

      assert html =~ "Templates"
      assert html =~ "Create New Template"
    end

    test "creates a template from the index form", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/canvas-layouts")

      html =
        lv
        |> form("#new-template-form", %{
          "name" => "My VIT",
          "description" => "Visual inquiry template"
        })
        |> render_submit()

      assert html =~ "Template created"
      assert html =~ "My VIT"
      assert Canvas.list_templates(user) |> Enum.any?(&(&1.name == "My VIT"))
    end

    test "own templates show the Owner badge", %{conn: conn, user: user} do
      CanvasFixtures.canvas_layout_fixture(%{author_id: user.id, name: "Owned Tpl"})

      {:ok, _lv, html} = live(conn, ~p"/canvas-layouts")

      assert html =~ "Owned Tpl"
      assert html =~ "Owner"
    end

    test "shared templates show the Shared badge and no owner actions", %{conn: conn, user: user} do
      owner = Psc.AccountsFixtures.user_fixture()
      CanvasFixtures.canvas_layout_fixture(%{author_id: owner.id, name: "Shared Tpl"})
      template = Canvas.list_templates(owner) |> List.first()
      {:ok, _} = Canvas.share_template_with(template, user.email)

      {:ok, _lv, html} = live(conn, ~p"/canvas-layouts")

      assert html =~ "Shared Tpl"
      assert html =~ "Shared"
      refute html =~ "Delete"
    end

    test "deleting requires two-step confirmation", %{conn: conn, user: user} do
      CanvasFixtures.canvas_layout_fixture(%{author_id: user.id, name: "Doomed Tpl"})
      [template] = Canvas.list_templates(user)

      {:ok, lv, _html} = live(conn, ~p"/canvas-layouts")

      lv
      |> element("button[phx-click='confirm_delete'][phx-value-id='#{template.id}']")
      |> render_click()

      html =
        lv
        |> element("button[phx-click='delete_template'][phx-value-id='#{template.id}']")
        |> render_click()

      assert html =~ "Template deleted"
      refute html =~ "Doomed Tpl"
      assert Canvas.get_canvas_layout(template.id) == nil
    end

    test "instantiate creates a canvas and redirects to the editor", %{conn: conn, user: user} do
      CanvasFixtures.canvas_layout_fixture(%{author_id: user.id, name: "Instantiable"})
      [template] = Canvas.list_templates(user)

      {:ok, lv, _html} = live(conn, ~p"/canvas-layouts")

      assert {:error, {:redirect, %{to: "/canvas-designer/" <> canvas_id}}} =
               lv
               |> element("button[phx-click='instantiate'][phx-value-id='#{template.id}']")
               |> render_click()

      assert Canvas.list_user_unstr_canvases(user.id)
             |> Enum.any?(&(&1.id == canvas_id))
    end
  end

  describe "editor (designer)" do
    test "renders the new template page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/canvas-layouts/new")

      assert html =~ "New Template"
      assert html =~ "Add Column"
      assert html =~ "Add Row"
    end

    test "adds a column and a row to the grid", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/canvas-layouts/new")

      lv |> element("button[phx-click='add_column']") |> render_click()
      html = lv |> element("button[phx-click='add_row']") |> render_click()

      assert html =~ "Column 1"
      assert html =~ "Row 1"
    end

    test "selecting a cell opens the metadata panel with fields", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/canvas-layouts/new")

      lv |> element("button[phx-click='add_column']") |> render_click()
      lv |> element("button[phx-click='add_row']") |> render_click()

      html =
        lv
        |> element("button[phx-click='select_cell'][phx-value-cell_key='r1_c1']")
        |> render_click()

      # fresh cells have no label yet — the panel falls back to the cell key
      assert html =~ "Cell: r1_c1"
      assert html =~ "Semantics"
      assert html =~ "Fields"
      assert html =~ "content"
    end

    test "adds a field to the selected cell", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/canvas-layouts/new")

      lv |> element("button[phx-click='add_column']") |> render_click()
      lv |> element("button[phx-click='add_row']") |> render_click()

      lv
      |> element("button[phx-click='select_cell'][phx-value-cell_key='r1_c1']")
      |> render_click()

      html =
        lv
        |> form("form[phx-submit='add_cell_field']", %{"field" => "notes"})
        |> render_submit()

      assert html =~ "notes"
    end

    test "adds a relation between cells", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/canvas-layouts/new")

      lv |> element("button[phx-click='add_column']") |> render_click()
      lv |> element("button[phx-click='add_column']") |> render_click()
      lv |> element("button[phx-click='add_row']") |> render_click()

      html =
        lv
        |> form("form[phx-submit='add_relation']", %{
          "from" => "r1_c1",
          "to" => "r1_c2",
          "label" => "leads to"
        })
        |> render_submit()

      assert html =~ "leads to"
    end

    test "saves a new template and redirects to the library", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/canvas-layouts/new")

      lv |> element("button[phx-click='add_column']") |> render_click()
      lv |> element("button[phx-click='add_row']") |> render_click()

      assert {:error, {:redirect, %{to: "/canvas-layouts"}}} =
               lv
               |> form("#template-form", %{"name" => "Saved Tpl", "description" => "desc"})
               |> render_submit()

      {:ok, _lv, html} = live(conn, ~p"/canvas-layouts")
      assert html =~ "Saved Tpl"
      assert Canvas.list_templates(user) |> Enum.any?(&(&1.name == "Saved Tpl"))
    end

    test "editing an existing template loads its structure", %{conn: conn, user: user} do
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id, name: "Loaded Tpl"})

      {:ok, _lv, html} = live(conn, ~p"/canvas-layouts/#{template.id}")

      assert html =~ "Edit Template"
      assert html =~ "Loaded Tpl"
      assert html =~ "Row 1"
      assert html =~ "Column 1"
    end

    test "non-owner without access is redirected", %{conn: conn} do
      stranger = Psc.AccountsFixtures.user_fixture()
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: stranger.id})

      assert {:error, {:redirect, %{to: "/canvas-layouts"}}} =
               live(conn, ~p"/canvas-layouts/#{template.id}")
    end

    test "shared non-owner sees read-only view without save controls", %{conn: conn, user: user} do
      owner = Psc.AccountsFixtures.user_fixture()
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: owner.id, name: "RO Tpl"})
      {:ok, _} = Canvas.share_template_with(template, user.email)

      {:ok, _lv, html} = live(conn, ~p"/canvas-layouts/#{template.id}")

      assert html =~ "read-only"
      refute html =~ "Save Template"
      refute html =~ "Add Column"
    end
  end
end
