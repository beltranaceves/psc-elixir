defmodule PscWeb.UnstrCanvasLiveTest do
  use PscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Psc.AccountsFixtures
  alias Psc.Canvas
  alias Psc.CanvasFixtures

  setup :register_and_log_in_user

  describe "index (canvases)" do
    test "lists only templates the user may use", %{conn: conn, user: user} do
      own = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id, name: "Own template"})

      shared =
        CanvasFixtures.canvas_layout_fixture(%{
          name: "Shared template",
          shared_with: [user.email]
        })

      private = CanvasFixtures.canvas_layout_fixture(%{name: "Someone elses template"})

      {:ok, lv, html} = live(conn, ~p"/canvases")

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

      {:ok, lv, _html} = live(conn, ~p"/canvases")

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
      {:ok, lv, _html} = live(conn, ~p"/canvases")

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

      {:ok, lv, _html} = live(conn, ~p"/canvases")

      # Bypasses the select's option list on purpose: the guard must hold even
      # when a forged template id arrives at the server.
      html =
        render_submit(lv, "create_canvas", %{"name" => "Sneaky", "template_id" => foreign.id})

      assert html =~ "do not have access to that template"
      assert Canvas.list_user_unstr_canvases(user.id) == []
    end
  end

  describe "editor (canvas editor)" do
    test "shows the template's cell label as the header, not as an editable field", %{
      conn: conn,
      user: user
    } do
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id})
      {:ok, canvas} = Canvas.instantiate_template(template, user.id)

      {:ok, _lv, html} = live(conn, ~p"/canvases/#{canvas.id}")

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

      {:ok, _lv, html} = live(conn, ~p"/canvases/#{canvas.id}")

      refute html =~ ~s(name="values[semantics]")
    end

    test "puts the description under the title and the structure summary in a tooltip", %{
      conn: conn,
      user: user
    } do
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id})
      {:ok, canvas} = Canvas.instantiate_template(template, user.id)

      {:ok, lv, html} = live(conn, ~p"/canvases/#{canvas.id}")

      # Title and description share the header, in that order.
      assert has_element?(lv, "#canvas-header #canvas-name-form")
      assert has_element?(lv, "#canvas-header #canvas-description-form")

      # The columns/rows summary is no longer rendered as page content; it
      # lives inside the hover tooltip attached to the structure heading.
      assert has_element?(lv, "#canvas-structure-tooltip")

      document = LazyHTML.from_fragment(html)

      tooltip_content =
        LazyHTML.query(document, "#canvas-structure-tooltip [data-part='content']")

      tooltip_text = LazyHTML.text(tooltip_content)
      assert tooltip_text =~ "Columns"
      assert tooltip_text =~ "Rows"
      assert tooltip_text =~ "Column 1"
      assert tooltip_text =~ "Row 1"

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

      {:ok, lv, html} = live(conn, ~p"/canvases/#{canvas.id}")

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

      {:ok, lv, _html} = live(conn, ~p"/canvases/#{canvas.id}")

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
