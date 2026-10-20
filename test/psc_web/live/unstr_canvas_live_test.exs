defmodule PscWeb.UnstrCanvasLiveTest do
  use PscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Psc.AccountsFixtures
  alias Psc.Canvas
  alias Psc.CanvasFixtures

  setup :register_and_log_in_user

  describe "index (canvases)" do
    test "uses the header for the page title without a duplicate body heading", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/canvas")

      assert has_element?(lv, "header h1#header-page-title", "Canvases")
      refute has_element?(lv, "main h1")
    end

    test "marks the Canvases nav item as the current page", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/canvas")

      assert has_element?(lv, ~s|nav a[href="/canvas"][aria-current="page"]|)
      refute has_element?(lv, ~s|nav a[href="/templates"][aria-current="page"]|)
    end

    test "lists only templates the user may use", %{conn: conn, user: user} do
      own = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id, name: "Own template"})

      shared =
        CanvasFixtures.canvas_layout_fixture(%{
          name: "Shared template",
          shared_with: [user.email]
        })

      private = CanvasFixtures.canvas_layout_fixture(%{name: "Someone elses template"})

      {:ok, lv, html} = live(conn, ~p"/canvas")

      options_html = lv |> element("#new-canvas-form") |> render()

      refute html =~ "Back to Documents"
      assert options_html =~ "Own template"
      assert options_html =~ "Shared template"
      refute options_html =~ "Someone elses template"

      assert options_html =~ own.id
      assert options_html =~ shared.id
      refute options_html =~ private.id
    end

    test "creates a canvas from a template with the template's structure", %{
      conn: conn,
      user: user
    } do
      template =
        CanvasFixtures.canvas_layout_fixture(%{author_id: user.id, name: "Structured template"})

      {:ok, lv, _html} = live(conn, ~p"/canvas")

      lv
      |> form("#new-canvas-form", %{
        "name" => "From a template",
        "description" => "made in a test",
        "template_id" => template.id
      })
      |> render_submit()

      assert [canvas] = Canvas.list_user_unstr_canvases(user.id)
      assert canvas.name == "From a template"
      assert canvas.description == "made in a test"

      # Instantiation must produce flat cell keys (the shape the editor renders)
      cells = canvas.cells
      assert %{"rows" => rows, "columns" => columns, "layout" => layout} = cells
      assert length(rows) > 0
      assert length(columns) > 0

      %{"cells" => template_cells} = template.layout_map

      for row <- layout, key <- row, not is_nil(key) do
        assert Map.has_key?(cells, key), "expected flat cell key #{key} in the canvas"
        assert Map.has_key?(template_cells, key)
        assert cells[key]["row"]
        assert cells[key]["column"]
      end
    end

    test "creates a blank canvas when no template is chosen", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/canvas")

      lv
      |> form("#new-canvas-form", %{"name" => "Blank one", "template_id" => ""})
      |> render_submit()

      assert [canvas] = Canvas.list_user_unstr_canvases(user.id)
      assert canvas.name == "Blank one"
      # The default PSC structure
      assert canvas.cells["rows"]
    end

    test "refuses a template the user cannot access", %{conn: conn, user: user} do
      other = AccountsFixtures.user_fixture()
      foreign = CanvasFixtures.canvas_layout_fixture(%{author_id: other.id, name: "Private"})

      {:ok, lv, _html} = live(conn, ~p"/canvas")

      # Bypasses the select's option list on purpose: the guard must hold even
      # when a forged template id arrives at the server.
      html =
        render_submit(lv, "create_canvas", %{"name" => "Sneaky", "template_id" => foreign.id})

      assert html =~ "do not have access to that template"
      assert Canvas.list_user_unstr_canvases(user.id) == []
    end
  end

  describe "editor (canvas editor)" do
    test "renders a fixed-layout grid with equal columns and a viewport-driven height", %{
      conn: conn,
      user: user
    } do
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id})
      {:ok, canvas} = Canvas.instantiate_template(template, user.id)

      {:ok, _lv, html} = live(conn, ~p"/canvas/#{canvas.id}")

      # Content no longer drives column widths: 2x2 fixture → a label column
      # sized from the longest row name + two 12rem minimum data columns.
      assert html =~ "table-fixed"
      assert html =~ "min-width: calc("

      # The grid takes the remaining viewport height through flex, not a
      # viewport-unit calculation.
      assert html =~ "flex-1 table-fixed"
      refute html =~ "100vh"

      # Each data cell is a fixed-size, internally scrollable card.
      assert html =~ "canvas-cell"
    end

    test "renders template section titles and hides empty ones", %{conn: conn, user: user} do
      layout_map =
        CanvasFixtures.template_layout_map_fixture()
        |> update_in(["cells", "r1_c1"], fn cell ->
          Map.merge(cell, %{
            "fields" => ["content", "notes"],
            "defaults" => %{"content" => "Body", "notes" => ""},
            "titles" => %{"content" => "Problem statement", "notes" => ""}
          })
        end)

      template =
        CanvasFixtures.canvas_layout_fixture(%{author_id: user.id, layout_map: layout_map})

      {:ok, canvas} = Canvas.instantiate_template(template, user.id)

      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      # A custom section title is rendered…
      assert has_element?(lv, "#cell-form-r1_c1 label", "Problem statement")
      # …while an intentionally empty one is not rendered at all.
      refute has_element?(lv, "#cell-form-r1_c1 label", "notes")
    end

    test "the conventional content field has no section title", %{conn: conn, user: user} do
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id})
      {:ok, canvas} = Canvas.instantiate_template(template, user.id)

      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      refute has_element?(lv, "#cell-form-r1_c1 label", "content")
      assert has_element?(lv, "#cell-form-r1_c1 #md-r1_c1-content")
    end

    test "has a tab picker that swaps the panel", %{conn: conn, user: user} do
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id})
      {:ok, canvas} = Canvas.instantiate_template(template, user.id)

      {:ok, lv, html} = live(conn, ~p"/canvas/#{canvas.id}")

      assert html =~ "Analysis"
      assert html =~ "Notes"
      assert html =~ "Agent"
      assert has_element?(lv, "#canvas-tabs [role='tab']")

      # The tabs are rendered twice: in the app header for large screens and
      # as a bottom app bar for phones and tablets.
      assert has_element?(lv, "#canvas-tabs-bar [role='tab']")
      assert has_element?(lv, "#canvas-tab-bar-editor[aria-selected='true']")

      # The editor is the default view and shows the grid.
      assert has_element?(lv, "#canvas-tab-editor[aria-selected='true']")
      assert has_element?(lv, "#canvas-grid")
      refute has_element?(lv, "#canvas-placeholder-notes")

      # Switching tabs swaps the panel for the placeholder.
      lv |> element("#canvas-tab-notes") |> render_click()
      assert has_element?(lv, "#canvas-tab-notes[aria-selected='true']")
      assert has_element?(lv, "#canvas-placeholder-notes")
      refute has_element?(lv, "#canvas-grid")

      # The bottom bar switches tabs as well.
      lv |> element("#canvas-tab-bar-agent") |> render_click()
      assert has_element?(lv, "#canvas-tab-bar-agent[aria-selected='true']")
      assert has_element?(lv, "#canvas-tab-agent[aria-selected='true']")
      assert has_element?(lv, "#canvas-placeholder-agent")

      # Tabs are deep-linkable.
      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}?tab=agent")
      assert has_element?(lv, "#canvas-tab-agent[aria-selected='true']")
      assert has_element?(lv, "#canvas-placeholder-agent")
    end

    test "titles the header Canvas Editor and leaves the Canvases nav item unhighlighted", %{
      conn: conn,
      user: user
    } do
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id})
      {:ok, canvas} = Canvas.instantiate_template(template, user.id)

      {:ok, lv, html} = live(conn, ~p"/canvas/#{canvas.id}")

      assert html =~ ~s|id="header-page-title"|
      assert html =~ "Canvas Editor"

      refute has_element?(lv, ~s|nav a[href="/canvas"][aria-current="page"]|)
      refute has_element?(lv, ~s|nav a[href="/templates"][aria-current="page"]|)
    end

    test "shows the template's cell label as the header, not as an editable field", %{
      conn: conn,
      user: user
    } do
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id})
      {:ok, canvas} = Canvas.instantiate_template(template, user.id)

      {:ok, _lv, html} = live(conn, ~p"/canvas/#{canvas.id}")

      # Cells come from the template with their label metadata intact
      assert %{"row" => "r1", "column" => "c1", "label" => "Cell 1"} =
               canvas.cells["r1_c1"]

      refute Map.has_key?(canvas.cells["r1_c1"], "semantics")

      # The label is the cell header ...
      assert html =~ "Cell 1"

      # ... and metadata is not offered as content fields
      refute html =~ ~s(name="values[label]")
      refute html =~ ~s(name="values[row]")
      refute html =~ ~s(name="values[column]")

      # The template's real field is
      assert html =~ ~s(name="values[content]")
    end

    test "hides legacy semantics metadata from canvases created before its removal", %{
      conn: conn,
      user: user
    } do
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id})
      {:ok, canvas} = Canvas.instantiate_template(template, user.id)

      # Simulate a canvas saved while templates still carried "semantics".
      legacy_cells =
        Map.put(canvas.cells, "r1_c1", Map.put(canvas.cells["r1_c1"], "semantics", "problem"))

      {:ok, _} = Canvas.save_unstr_canvas_content_to_db(canvas.id, legacy_cells)

      {:ok, _lv, html} = live(conn, ~p"/canvas/#{canvas.id}")

      refute html =~ ~s(name="values[semantics]")
    end

    test "puts title, description, presence and actions in one header row", %{
      conn: conn,
      user: user
    } do
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id})
      {:ok, canvas} = Canvas.instantiate_template(template, user.id)

      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      # One compact header row: title, description, presence and the actions.
      assert has_element?(lv, "#canvas-header #canvas-name-form")
      assert has_element?(lv, "#canvas-header #canvas-description-form")
      assert has_element?(lv, "#canvas-header #active-users-tooltip")
      assert has_element?(lv, "#canvas-header #share-canvas-button")

      # The standalone "Canvas Structure" block is gone; the grid is the content.
      refute has_element?(lv, "#canvas-structure-tooltip")

      # The trigger is truncated; the full list lives in the hover tooltip.
      assert has_element?(lv, "#active-users-tooltip button")
      assert has_element?(lv, "#active-users-tooltip [data-part='content']", user.email)

      # ... and the grid itself stays always visible for editing.
      assert has_element?(lv, "#md-r1_c1-content")
    end

    test "renders accents defined by the template and offers no canvas picker", %{
      conn: conn,
      user: user
    } do
      layout_map =
        CanvasFixtures.template_layout_map_fixture()
        |> Map.update!("columns", fn columns ->
          List.update_at(columns, 0, &Map.put(&1, "accent", "sky"))
        end)
        |> Map.update!("rows", fn rows ->
          List.update_at(rows, 0, &Map.put(&1, "accent", "emerald"))
        end)

      template =
        CanvasFixtures.canvas_layout_fixture(%{author_id: user.id, layout_map: layout_map})

      {:ok, canvas} = Canvas.instantiate_template(template, user.id)

      # The template's JSON is the source of truth: instantiation copies the
      # accents into the canvas structure, and the editor only reads them.
      assert Enum.find(canvas.cells["columns"], &(&1["id"] == "c1"))["accent"] == "sky"
      assert Enum.find(canvas.cells["rows"], &(&1["id"] == "r1"))["accent"] == "emerald"

      {:ok, lv, html} = live(conn, ~p"/canvas/#{canvas.id}")

      assert html =~ ~s(id="accent-bar-column-c1")
      assert html =~ ~s(id="accent-bar-row-r1")
      assert html =~ "bg-sky-400"
      assert html =~ "bg-emerald-400"

      # Styling is authored in the template designer, never in the canvas.
      refute has_element?(lv, "#accent-swatch-column-c1")
      refute has_element?(lv, "#accent-picker-column-c1")
      refute has_element?(lv, ~s|button[phx-click="set_column_accent"]|)
    end

    test "shares a canvas through the modal", %{conn: conn, user: user} do
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id})
      {:ok, canvas} = Canvas.instantiate_template(template, user.id)

      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      assert has_element?(lv, "#share-canvas-button .hero-share")
      lv |> element("#share-canvas-button") |> render_click()
      assert has_element?(lv, "#share-canvas-dialog[data-open='true']")

      html =
        lv
        |> form("#share-canvas-dialog-form", %{"email" => "collab@example.com"})
        |> render_submit()

      assert html =~ "Canvas shared with collab@example.com"
      assert has_element?(lv, ~s|#share-canvas-dialog [data-email="collab@example.com"]|)
    end
  end
end
