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

      # The picker is cards, not a select: blank first, then the built-in PSC,
      # then one per template.
      assert has_element?(lv, ~s|#template-picker-blank[aria-pressed='true']|)
      assert has_element?(lv, ~s|#template-picker-psc[aria-pressed='false']|)
      assert has_element?(lv, ~s|#template-picker-#{own.id}[aria-pressed='false']|)
      assert has_element?(lv, ~s|#template-picker-#{shared.id}[aria-pressed='false']|)
    end

    test "picking a template card selects it", %{conn: conn, user: user} do
      template =
        CanvasFixtures.canvas_layout_fixture(%{author_id: user.id, name: "Pickable template"})

      {:ok, lv, _html} = live(conn, ~p"/canvas")

      # Blank starts selected.
      assert has_element?(lv, ~s|#template-picker-blank[aria-pressed='true']|)

      lv |> element("#template-picker-#{template.id}") |> render_click()

      assert has_element?(lv, ~s|#template-picker-#{template.id}[aria-pressed='true']|)
      assert has_element?(lv, ~s|#template-picker-blank[aria-pressed='false']|)

      # The hidden input carries the choice to the submit.
      form_html = lv |> element("#new-canvas-form") |> render()
      assert form_html =~ ~s|name="template_id" value="#{template.id}"|
    end

    test "picking the built-in PSC card selects it", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/canvas")

      lv |> element("#template-picker-psc") |> render_click()

      assert has_element?(lv, ~s|#template-picker-psc[aria-pressed='true']|)
      assert has_element?(lv, ~s|#template-picker-blank[aria-pressed='false']|)

      form_html = lv |> element("#new-canvas-form") |> render()
      assert form_html =~ ~s|name="template_id" value="psc"|
    end

    test "a forged picker id is not accepted", %{conn: conn} do
      other = AccountsFixtures.user_fixture()

      private =
        CanvasFixtures.canvas_layout_fixture(%{author_id: other.id, name: "Private template"})

      {:ok, lv, _html} = live(conn, ~p"/canvas")

      render_click(lv, "select_template", %{"id" => private.id})

      # The draft stays blank: the id was never offered by the picker.
      form_html = lv |> element("#new-canvas-form") |> render()
      assert form_html =~ ~s|name="template_id" value=""|
    end

    test "creates a canvas from a template with the template's structure", %{
      conn: conn,
      user: user
    } do
      template =
        CanvasFixtures.canvas_layout_fixture(%{author_id: user.id, name: "Structured template"})

      {:ok, lv, _html} = live(conn, ~p"/canvas")

      # The card is how a template id reaches the submit.
      lv |> element("#template-picker-#{template.id}") |> render_click()

      lv
      |> form("#new-canvas-form", %{
        "name" => "From a template",
        "description" => "made in a test"
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

    test "creating from a picked card uses the card's template and opens the canvas", %{
      conn: conn,
      user: user
    } do
      template =
        CanvasFixtures.canvas_layout_fixture(%{author_id: user.id, name: "Card template"})

      {:ok, lv, _html} = live(conn, ~p"/canvas")

      lv |> element("#template-picker-#{template.id}") |> render_click()

      assert {:error, {:redirect, %{to: to}}} =
               lv
               |> form("#new-canvas-form", %{"name" => "From the card"})
               |> render_submit()

      assert to == "/canvas/#{template.id}" or String.starts_with?(to, "/canvas/")

      assert [canvas] = Canvas.list_user_unstr_canvases(user.id)
      assert canvas.name == "From the card"
      assert to == "/canvas/#{canvas.id}"

      # The card's template is what was instantiated.
      assert length(canvas.cells["rows"]) == length(template.layout_map["rows"])
    end

    test "creating a blank canvas opens it too", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/canvas")

      assert {:error, {:redirect, %{to: to}}} =
               lv
               |> form("#new-canvas-form", %{"name" => "Blank one", "template_id" => ""})
               |> render_submit()

      assert [canvas] = Canvas.list_user_unstr_canvases(user.id)
      assert canvas.name == "Blank one"
      assert to == "/canvas/#{canvas.id}"

      # Truly blank: no rows, no columns — the owner builds it in place.
      assert canvas.cells["rows"] == []
      assert canvas.cells["columns"] == []
    end

    test "creating from the PSC card yields the built-in 12-cell grid", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/canvas")

      lv |> element("#template-picker-psc") |> render_click()

      assert {:error, {:redirect, %{to: to}}} =
               lv |> form("#new-canvas-form", %{"name" => "Classic PSC"}) |> render_submit()

      assert [canvas] = Canvas.list_user_unstr_canvases(user.id)
      assert to == "/canvas/#{canvas.id}"

      assert length(canvas.cells["rows"]) == 3
      assert length(canvas.cells["columns"]) == 4
      assert Map.has_key?(canvas.cells, "problem")
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
      assert has_element?(lv, "#cell-field-r1_c1-content label", "Problem statement")
      # …while an intentionally empty one is not rendered at all.
      refute has_element?(lv, "#cell-field-r1_c1-content label", "notes")
    end

    test "the conventional content field has no section title", %{conn: conn, user: user} do
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id})
      {:ok, canvas} = Canvas.instantiate_template(template, user.id)

      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      refute has_element?(lv, "#cell-field-r1_c1-content label", "content")
      assert has_element?(lv, "#cell-field-r1_c1-content #md-r1_c1-content")
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
      # Every view is rendered; the inactive ones are hidden, so the client can
      # switch tabs without waiting for the server.
      assert has_element?(lv, "#canvas-panel-editor:not(.hidden)")
      assert has_element?(lv, "#canvas-panel-notes.hidden")

      # Switching tabs shows the notes view and hides the grid.
      lv |> element("#canvas-tab-notes") |> render_click()
      assert has_element?(lv, "#canvas-tab-notes[aria-selected='true']")
      assert has_element?(lv, "#canvas-notes")
      assert has_element?(lv, "#canvas-panel-notes:not(.hidden)")
      assert has_element?(lv, "#canvas-panel-editor.hidden")

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

    test "structure editing is the owner's toggle, hidden from shared users", %{
      conn: conn,
      user: user
    } do
      owner = Psc.AccountsFixtures.user_fixture()
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: owner.id})
      {:ok, canvas} = Canvas.instantiate_template(template, owner.id)
      {:ok, _} = Canvas.share_unstr_canvas_with(canvas, user.email)

      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      # The owner sees the toggle; a shared user does not.
      refute has_element?(lv, "#edit-structure-toggle")
    end

    test "the owner toggles Edit structure and the controls appear", %{conn: conn, user: user} do
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id})
      {:ok, canvas} = Canvas.instantiate_template(template, user.id)

      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      assert has_element?(lv, "#edit-structure-toggle[aria-pressed='false']")
      refute has_element?(lv, "button[phx-click='add_column']")

      lv |> element("#edit-structure-toggle") |> render_click()

      assert has_element?(lv, "#edit-structure-toggle[aria-pressed='true']")
      assert has_element?(lv, "button[phx-click='add_column']")
      assert has_element?(lv, "button[phx-click='add_row']")
      # The grid's headers become inputs, and each cell gains its controls.
      assert has_element?(lv, "#column-c1-label-form input[name='label']")
      assert has_element?(lv, "#row-r1-label-form input[name='label']")
      assert has_element?(lv, "#cell-label-r1_c1")
      assert has_element?(lv, "#cell-add-field-r1_c1")
    end

    test "adding a row and a column applies the operations", %{conn: conn, user: user} do
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id})
      {:ok, canvas} = Canvas.instantiate_template(template, user.id)

      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}")
      lv |> element("#edit-structure-toggle") |> render_click()

      lv |> render_click("add_row", %{})
      lv |> render_click("add_column", %{})

      cells = Canvas.get_unstr_canvas_content(canvas.id)
      assert Enum.map(cells["rows"], & &1["id"]) == ["r1", "r2", "r3"]
      assert Enum.map(cells["columns"], & &1["id"]) == ["c1", "c2", "c3"]
      assert Enum.at(cells["layout"], 2) == ["r3_c1", "r3_c2", "r3_c3"]
      assert cells["r3_c1"]["label"] == "r3_c1"
    end

    test "renaming a row and a column applies the operations", %{conn: conn, user: user} do
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id})
      {:ok, canvas} = Canvas.instantiate_template(template, user.id)

      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}")
      lv |> element("#edit-structure-toggle") |> render_click()

      lv
      |> form("#row-r1-label-form", %{"structure_id" => "r1", "label" => "Rationale"})
      |> render_change()

      lv
      |> form("#column-c1-label-form", %{"structure_id" => "c1", "label" => "Perceive"})
      |> render_change()

      cells = Canvas.get_unstr_canvas_content(canvas.id)
      assert Enum.at(cells["rows"], 0)["label"] == "Rationale"
      assert Enum.at(cells["columns"], 0)["label"] == "Perceive"
    end

    test "accenting a row applies the operation", %{conn: conn, user: user} do
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id})
      {:ok, canvas} = Canvas.instantiate_template(template, user.id)

      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}")
      lv |> element("#edit-structure-toggle") |> render_click()

      lv |> element("#accent-swatch-row-r1") |> render_click()

      # The swatch opens the inline palette; choosing a token sets the accent.
      assert has_element?(lv, "button[phx-click='set_row_accent'][phx-value-accent='teal']")

      lv
      |> element("button[phx-click='set_row_accent'][phx-value-accent='teal']")
      |> render_click()

      cells = Canvas.get_unstr_canvas_content(canvas.id)
      assert Enum.at(cells["rows"], 0)["accent"] == "teal"
    end

    test "removing an empty row goes straight away", %{conn: conn, user: user} do
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id})
      {:ok, canvas} = Canvas.instantiate_template(template, user.id)

      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}")
      lv |> element("#edit-structure-toggle") |> render_click()

      lv |> element("button[phx-click='request_remove_row'][phx-value-id='r2']") |> render_click()

      refute has_element?(lv, "#remove-structure-dialog")

      cells = Canvas.get_unstr_canvas_content(canvas.id)
      assert Enum.map(cells["rows"], & &1["id"]) == ["r1"]
      refute Map.has_key?(cells, "r2_c1")
    end

    test "removing a row with content asks first, and the confirm removes it", %{
      conn: conn,
      user: user
    } do
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id})
      {:ok, canvas} = Canvas.instantiate_template(template, user.id)

      {:ok, _} =
        Canvas.apply_unstr_canvas_operation(canvas.id, user.id, %{
          "type" => "update_cell",
          "cell_key" => "r2_c1",
          "field" => "content",
          "value" => "precious work"
        })

      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}")
      lv |> element("#edit-structure-toggle") |> render_click()

      lv |> element("button[phx-click='request_remove_row'][phx-value-id='r2']") |> render_click()

      assert has_element?(lv, "#remove-structure-dialog[data-open='true']")
      assert has_element?(lv, "#remove-structure-dialog", "Row 2")

      # Keeping it removes nothing.
      lv |> element("button[phx-click='dismiss_remove_structure']") |> render_click()
      refute has_element?(lv, "#remove-structure-dialog")

      assert Enum.map(Canvas.get_unstr_canvas_content(canvas.id)["rows"], & &1["id"]) == [
               "r1",
               "r2"
             ]

      # Removing it does.
      lv |> element("button[phx-click='request_remove_row'][phx-value-id='r2']") |> render_click()
      lv |> element("#confirm-remove-structure") |> render_click()

      cells = Canvas.get_unstr_canvas_content(canvas.id)
      assert Enum.map(cells["rows"], & &1["id"]) == ["r1"]
      refute Map.has_key?(cells, "r2_c1")
    end

    test "cell label, fields and section titles apply their operations", %{conn: conn, user: user} do
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id})
      {:ok, canvas} = Canvas.instantiate_template(template, user.id)

      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}")
      lv |> element("#edit-structure-toggle") |> render_click()

      lv
      |> form("#cell-label-r1_c1", %{"cell_key" => "r1_c1", "label" => "Problem"})
      |> render_change()

      lv
      |> form("#cell-add-field-r1_c1", %{"cell_key" => "r1_c1", "field" => "notes"})
      |> render_submit()

      lv
      |> form("#cell-title-r1_c1-notes", %{
        "cell_key" => "r1_c1",
        "field" => "notes",
        "title" => "Notes"
      })
      |> render_change()

      cells = Canvas.get_unstr_canvas_content(canvas.id)
      assert cells["r1_c1"]["label"] == "Problem"
      assert cells["r1_c1"]["notes"] == ""
      assert cells["r1_c1"]["titles"]["notes"] == "Notes"

      lv
      |> form("#cell-title-r1_c1-content", %{
        "cell_key" => "r1_c1",
        "field" => "content",
        "title" => "Body"
      })
      |> render_change()

      lv
      |> element(
        "button[phx-click='remove_cell_field'][phx-value-cell_key='r1_c1'][phx-value-field='notes']"
      )
      |> render_click()

      cells = Canvas.get_unstr_canvas_content(canvas.id)
      assert cells["r1_c1"]["titles"]["content"] == "Body"
      refute Map.has_key?(cells["r1_c1"], "notes")
    end

    test "a shared user forging a structure event is a no-op", %{conn: conn, user: user} do
      owner = Psc.AccountsFixtures.user_fixture()
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: owner.id})
      {:ok, canvas} = Canvas.instantiate_template(template, owner.id)
      {:ok, _} = Canvas.share_unstr_canvas_with(canvas, user.email)

      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      render_click(lv, "add_row", %{})

      # The forged operation is a no-op: the structure is untouched.
      assert Enum.map(Canvas.get_unstr_canvas_content(canvas.id)["rows"], & &1["id"]) == [
               "r1",
               "r2"
             ]
    end

    test "a blank canvas renders the empty state and is built in place", %{conn: conn, user: user} do
      {:ok, canvas} =
        Canvas.create_unstr_canvas(user.id, %{"name" => "Blank", "cells" => Canvas.blank_cells()})

      {:ok, lv, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      assert has_element?(lv, "#canvas-grid", "This canvas has no structure yet.")
      assert has_element?(lv, "button[phx-click='add_row']")

      lv |> render_click("add_row", %{})
      lv |> render_click("add_column", %{})
      lv |> render_click("add_column", %{})

      cells = Canvas.get_unstr_canvas_content(canvas.id)
      assert Enum.map(cells["rows"], & &1["id"]) == ["r1"]
      assert Enum.map(cells["columns"], & &1["id"]) == ["c1", "c2"]
      assert Enum.at(cells["layout"], 0) == ["r1_c1", "r1_c2"]

      # The grid renders once the structure exists.
      assert has_element?(lv, "#cell-card-r1_c1")
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
