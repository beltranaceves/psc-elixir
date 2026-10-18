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

      {:ok, lv, _html} = live(conn, ~p"/canvases")

      options_html = lv |> element("#new-canvas-form") |> render()

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

      # Cells come from the template with their label/semantics metadata intact
      assert %{"row" => "r1", "column" => "c1", "label" => "Cell 1", "semantics" => "free"} =
               canvas.cells["r1_c1"]

      # The label is the cell header ...
      assert html =~ "Cell 1"

      # ... and metadata is not offered as content fields
      refute html =~ ~s(name="values[label]")
      refute html =~ ~s(name="values[semantics]")
      refute html =~ ~s(name="values[row]")
      refute html =~ ~s(name="values[column]")

      # The template's real field is
      assert html =~ ~s(name="values[content]")
    end
  end
end
