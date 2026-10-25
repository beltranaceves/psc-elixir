defmodule PscWeb.ImageLiveTest do
  use PscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Psc.Canvas
  alias Psc.Canvas.Structure
  alias Psc.CanvasFixtures

  setup :register_and_log_in_user

  defp image_canvas(user) do
    template =
      CanvasFixtures.canvas_layout_fixture(%{
        author_id: user.id,
        layout_map: Canvas.image_layout_map()
      })

    {:ok, canvas} = Canvas.instantiate_template(template, user.id)
    canvas
  end

  defp cells(canvas), do: Canvas.get_unstr_canvas_content(canvas.id)
  defp placement(canvas, key), do: Structure.cell(cells(canvas), key)["placement"]

  describe "rendering" do
    test "an image canvas renders floating cells over the backdrop", %{
      conn: conn,
      user: user
    } do
      canvas = image_canvas(user)
      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      assert has_element?(view, "#canvas-image")
      assert has_element?(view, "#image-board")
      refute has_element?(view, "#canvas-grid")
      refute has_element?(view, "#canvas-bento")

      # The picture is the board's backdrop.
      assert has_element?(
               view,
               ~s|#image-board img[src="/images/image-board-blueprint.svg"]|
             )

      # A card keeps the table's cell body and Markdown field ids.
      assert has_element?(view, "#image-cell-brief")
      assert has_element?(view, "#cell-card-brief")
      assert has_element?(view, "#md-brief-content")

      # Its rectangle is a percentage of the picture, not a grid track.
      assert has_element?(view, ~s|#image-cell-brief[style*="left: 4%"]|)
      assert has_element?(view, ~s|#image-cell-brief[style*="width: 28%"]|)

      # A text cell is a single input, not a card.
      assert has_element?(view, "#image-cell-next_step")
      assert has_element?(view, "#text-cell-next_step")
      refute has_element?(view, "#cell-card-next_step")
      assert has_element?(view, ~s|#text-cell-next_step[value="Next step"]|)

      # The cell kind is metadata, never an editable field.
      refute has_element?(view, "#cell-field-brief-kind")

      assert has_element?(view, "#image-size", "3 cells")
      refute has_element?(view, "#edit-structure-toggle")
    end

    test "a table canvas still renders the grid", %{conn: conn, user: user} do
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id})
      {:ok, canvas} = Canvas.instantiate_template(template, user.id)

      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      assert has_element?(view, "#canvas-grid")
      refute has_element?(view, "#canvas-image")
    end

    test "a text cell edits the same content field as a card", %{conn: conn, user: user} do
      canvas = image_canvas(user)
      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      view
      |> form("#text-cell-form-next_step", %{
        "cell_key" => "next_step",
        "values" => %{"content" => "Emergency exit"}
      })
      |> render_change()

      assert cells(canvas)["next_step"]["content"] == "Emergency exit"
    end

    test "a card takes a background from the palette", %{conn: conn, user: user} do
      canvas = image_canvas(user)
      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      view |> element("#edit-layout-toggle") |> render_click()

      view |> element("#cell-colors-brief") |> render_click()
      assert has_element?(view, "#cell-colors-panel-brief")

      view |> element("#cell-colors-brief-background-rose") |> render_click()

      assert Structure.cell(cells(canvas), "brief")["background"] == "rose"
      assert has_element?(view, "#cell-card-brief.bg-rose-100")
    end

    test "a text cell takes a background from the board control", %{conn: conn, user: user} do
      canvas = image_canvas(user)
      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      view |> element("#edit-layout-toggle") |> render_click()

      view |> element("#cell-colors-next_step") |> render_click()
      assert has_element?(view, "#cell-colors-panel-next_step")

      view |> element("#cell-colors-next_step-background-emerald") |> render_click()

      assert Structure.cell(cells(canvas), "next_step")["background"] == "emerald"
      assert has_element?(view, "#text-cell-next_step.bg-emerald-100")
    end

    test "an accent outlines a card and a text cell", %{conn: conn, user: user} do
      canvas = image_canvas(user)
      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      view |> element("#edit-layout-toggle") |> render_click()

      view |> element("#cell-colors-brief") |> render_click()
      view |> element("#cell-colors-brief-outline-rose") |> render_click()

      assert Structure.cell(cells(canvas), "brief")["accent"] == "rose"
      assert has_element?(view, "#cell-card-brief.ring-rose-400")

      # A text cell has no card frame, so the label itself carries the outline.
      view |> element("#cell-colors-next_step") |> render_click()
      view |> element("#cell-colors-next_step-outline-teal") |> render_click()

      assert Structure.cell(cells(canvas), "next_step")["accent"] == "teal"
      assert has_element?(view, "#text-cell-next_step.ring-teal-400")
    end
  end

  describe "layout editing" do
    test "adds a card and a text cell in free slots", %{conn: conn, user: user} do
      canvas = image_canvas(user)
      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      refute has_element?(view, "#add-image-cell")

      view |> element("#edit-layout-toggle") |> render_click()
      assert has_element?(view, "#add-image-cell")
      assert has_element?(view, "#add-image-text")

      view |> element("#add-image-cell") |> render_click()

      assert has_element?(view, "#image-cell-cell1")
      assert has_element?(view, "#cell-card-cell1")
      assert %{"x" => 32, "y" => 0, "w" => 24, "h" => 12} = placement(canvas, "cell1")

      view |> element("#add-image-text") |> render_click()

      assert has_element?(view, "#image-cell-text1")
      assert has_element?(view, "#text-cell-text1")
      assert cells(canvas)["text1"]["kind"] == "text"
      refute has_element?(view, "#cell-card-text1")
    end

    test "a card moves and resizes in half percents", %{conn: conn, user: user} do
      canvas = image_canvas(user)
      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      view |> element("#edit-layout-toggle") |> render_click()

      # One operation per gesture: this is the payload the drag hook sends.
      render_hook(view, "move_card", %{"cell_key" => "brief", "x" => 12.5, "y" => 22})

      assert %{"x" => 12.5, "y" => 22, "w" => 28, "h" => 18} = placement(canvas, "brief")
      assert has_element?(view, ~s|#image-cell-brief[style*="left: 12.5%"]|)
      assert has_element?(view, "#image-size-brief", "28 × 18%")

      render_hook(view, "resize_card", %{"cell_key" => "brief", "w" => 40.5, "h" => 24})

      assert %{"x" => 12.5, "y" => 22, "w" => 40.5, "h" => 24} = placement(canvas, "brief")

      # Arrow keys nudge by half a percent, and shift+arrow resizes.
      view
      |> element("#image-move-brief")
      |> render_keydown(%{"key" => "ArrowRight"})

      assert placement(canvas, "brief")["x"] == 13.0

      view
      |> element("#image-move-brief")
      |> render_keydown(%{"key" => "ArrowDown", "shiftKey" => true})

      assert placement(canvas, "brief")["h"] == 24.5
    end

    test "a cell can become a plain text label and back", %{conn: conn, user: user} do
      canvas = image_canvas(user)
      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      view |> element("#edit-layout-toggle") |> render_click()

      view |> element("#image-kind-brief") |> render_click()

      assert cells(canvas)["brief"]["kind"] == "text"
      assert has_element?(view, "#text-cell-brief")
      refute has_element?(view, "#cell-card-brief")

      # The toggle now offers the way back.
      assert has_element?(view, ~s|#image-kind-brief[phx-value-kind="card"]|)

      view |> element("#image-kind-brief") |> render_click()

      assert cells(canvas)["brief"]["kind"] == "card"
      assert has_element?(view, "#cell-card-brief")
    end

    test "the backdrop is a canvas operation", %{conn: conn, user: user} do
      canvas = image_canvas(user)
      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      view |> element("#edit-layout-toggle") |> render_click()

      assert has_element?(
               view,
               ~s|#image-backdrop-url[value="/images/image-board-blueprint.svg"]|
             )

      view
      |> form("#image-backdrop-form", %{
        "url" => "https://example.com/plan.svg",
        "fit" => "cover",
        "aspect" => "16:9",
        "alt" => "The floor plan"
      })
      |> render_change()

      backdrop = cells(canvas)["backdrop"]
      assert backdrop["url"] == "https://example.com/plan.svg"
      assert backdrop["fit"] == "cover"
      assert backdrop["alt"] == "The floor plan"
      assert_in_delta backdrop["aspect"], 16 / 9, 0.0001

      # The frame keeps the pinned shape while the picture is fitted inside it.
      assert has_element?(view, ~s|#image-board[style*="aspect-ratio"]|)
      assert has_element?(view, ~s|#image-board img[src="https://example.com/plan.svg"]|)

      # Typing `auto` unpins the shape.
      view
      |> form("#image-backdrop-form", %{
        "url" => "https://example.com/plan.svg",
        "aspect" => "auto"
      })
      |> render_change()

      refute Map.has_key?(cells(canvas)["backdrop"], "aspect")
    end

    test "an unsafe backdrop URL is ignored", %{conn: conn, user: user} do
      canvas = image_canvas(user)
      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      view |> element("#edit-layout-toggle") |> render_click()

      view
      |> form("#image-backdrop-form", %{"url" => "javascript:alert(1)"})
      |> render_change()

      assert cells(canvas)["backdrop"]["url"] == "/images/image-board-blueprint.svg"
      assert has_element?(view, ~s|#image-board img[src="/images/image-board-blueprint.svg"]|)
    end

    test "removing an empty cell needs no confirmation", %{conn: conn, user: user} do
      canvas = image_canvas(user)
      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      view |> element("#edit-layout-toggle") |> render_click()
      view |> element("#add-image-cell") |> render_click()

      assert has_element?(view, "#remove-image-cell-cell1")

      view |> element("#remove-image-cell-cell1") |> render_click()

      refute has_element?(view, "#image-cell-cell1")
      refute Map.has_key?(Structure.cells(cells(canvas)), "cell1")
    end

    test "renaming the canvas keeps the board rendering", %{conn: conn, user: user} do
      canvas = image_canvas(user)
      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      render_change(view, "update_name", %{"value" => "Renamed picture"})

      assert has_element?(view, "#image-board")
      assert has_element?(view, "#image-cell-brief")
      assert has_element?(view, ~s|#canvas-name-form input[value="Renamed picture"]|)
      assert "$name" not in Structure.cell_keys(cells(canvas))
    end

    test "a second client sees a move", %{conn: conn, user: user} do
      canvas = image_canvas(user)
      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")
      {:ok, other, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      view |> element("#edit-layout-toggle") |> render_click()

      render_hook(view, "move_card", %{"cell_key" => "brief", "x" => 20, "y" => 30})

      assert has_element?(other, ~s|#image-cell-brief[style*="left: 20%"]|)
      assert has_element?(other, ~s|#image-cell-brief[style*="top: 30%"]|)
    end
  end
end
