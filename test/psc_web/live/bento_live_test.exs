defmodule PscWeb.BentoLiveTest do
  use PscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Psc.Canvas
  alias Psc.Canvas.Structure
  alias Psc.CanvasFixtures

  setup :register_and_log_in_user

  defp bento_canvas(user) do
    template =
      CanvasFixtures.canvas_layout_fixture(%{
        author_id: user.id,
        layout_map: Canvas.bento_layout_map()
      })

    {:ok, canvas} = Canvas.instantiate_template(template, user.id)
    canvas
  end

  defp cells(canvas), do: Canvas.get_unstr_canvas_content(canvas.id)
  defp placement(canvas, key), do: Structure.cell(cells(canvas), key)["placement"]

  describe "rendering" do
    test "a bento canvas renders a board of cards, not a table", %{conn: conn, user: user} do
      canvas = bento_canvas(user)
      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      assert has_element?(view, "#canvas-bento")
      assert has_element?(view, "#bento-board")
      refute has_element?(view, "#canvas-grid")
      refute has_element?(view, "#edit-structure-toggle")

      for key <- ["big_picture", "evidence", "decision", "open_questions"] do
        assert has_element?(view, "#bento-card-#{key}")
        assert has_element?(view, "#cell-card-#{key}")
      end

      # The placement is the card's grid rectangle.
      assert has_element?(
               view,
               ~s|#bento-card-big_picture[style*="grid-column: 1 / span 16"]|
             )

      assert has_element?(
               view,
               ~s|#bento-card-evidence[style*="grid-column: 17 / span 8"]|
             )

      # The card's Markdown field keeps the same editor id as in a table.
      assert has_element?(view, "#md-big_picture-content")

      # The board reports its real grid: 12 columns, five rows of cards.
      assert has_element?(view, "#bento-size", "12 × 5")
    end

    test "a table canvas still renders the grid", %{conn: conn, user: user} do
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id})
      {:ok, canvas} = Canvas.instantiate_template(template, user.id)

      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      assert has_element?(view, "#canvas-grid")
      refute has_element?(view, "#canvas-bento")
    end

    test "renaming the canvas keeps the board rendering", %{conn: conn, user: user} do
      canvas = bento_canvas(user)
      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      # The name is a CRDT operation that lands beside the cards as `$name`;
      # it must not be mistaken for one.
      render_change(view, "update_name", %{"value" => "Renamed bento"})

      assert has_element?(view, "#bento-board")
      assert has_element?(view, "#bento-card-big_picture")
      assert has_element?(view, "#canvas-name-form input[value='Renamed bento']")
      assert "$name" not in Structure.cell_keys(cells(canvas))
    end

    test "a card carries its server-computed neighbours for the mobile swipe", %{
      conn: conn,
      user: user
    } do
      canvas = bento_canvas(user)
      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      # big_picture is 8 wide at the top left; evidence sits beside it.
      assert has_element?(
               view,
               ~s|#cell-card-big_picture[data-cell-nav*='"right":"evidence"']|
             )

      assert has_element?(view, ~s|#cell-card-big_picture[data-cell-nav*='"down":"decision"']|)
    end
  end

  describe "layout editing" do
    test "adds a card in the first free slot", %{conn: conn, user: user} do
      canvas = bento_canvas(user)
      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      refute has_element?(view, "#add-card-button")

      view |> element("#edit-layout-toggle") |> render_click()
      assert has_element?(view, "#add-card-button")

      # Every card shows its own width × height while arranging.
      assert has_element?(view, "#bento-size-decision", "6 × 2")

      # The board's own grid is editable while arranging.
      assert has_element?(view, ~s|#bento-columns-input[value="12"]|)
      assert has_element?(view, ~s|#bento-rows-input[value="5"]|)

      view |> element("#add-card-button") |> render_click()

      # The board already fills two rows; the new card starts below them.
      assert %{"x" => 0, "y" => 5, "w" => 6, "h" => 2} = placement(canvas, "card1")
      assert has_element?(view, "#bento-card-card1")
    end

    test "the board's columns and rows are editable numbers", %{conn: conn, user: user} do
      canvas = bento_canvas(user)
      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      view |> element("#edit-layout-toggle") |> render_click()

      # Narrowing the board clamps the cards that no longer fit.
      render_change(view, "set_bento_columns", %{"value" => "8"})

      assert %{"x" => 0, "y" => 0, "w" => 8, "h" => 3} = placement(canvas, "big_picture")
      assert %{"x" => 4, "y" => 0, "w" => 4, "h" => 3} = placement(canvas, "evidence")
      assert has_element?(view, ~s|#bento-columns-input[value="8"]|)

      # A taller board reserves empty space below the cards.
      render_change(view, "set_bento_rows", %{"value" => "9"})
      assert Map.get(cells(canvas), "bento_rows") == 9
      assert has_element?(view, ~s|#bento-rows-input[value="9"]|)

      # The cards are the floor: a shorter request is ignored by the input's
      # minimum, and the board keeps its content.
      assert has_element?(view, ~s|#bento-rows-input[min="5"]|)

      # Widening the board leaves room to move a card into it.
      render_change(view, "set_bento_columns", %{"value" => "16"})
      assert Map.get(cells(canvas), "bento_columns") == 16

      render_hook(view, "move_card", %{"cell_key" => "open_questions", "x" => 10, "y" => 3})
      assert %{"x" => 10, "y" => 3} = placement(canvas, "open_questions")

      # Out-of-range values are ignored, not clamped, so typing 1 on the way
      # to 12 does not resize anything.
      render_change(view, "set_bento_columns", %{"value" => "1"})
      assert Map.get(cells(canvas), "bento_columns") == 16

      render_change(view, "set_bento_columns", %{"value" => "200"})
      assert Map.get(cells(canvas), "bento_columns") == 16

      # Dragging a card past the edge grows the board with it.
      render_hook(view, "move_card", %{"cell_key" => "evidence", "x" => 13, "y" => 0})
      assert Map.get(cells(canvas), "bento_columns") == 16

      # Back to reading: the badge reports the new grid.
      view |> element("#edit-layout-toggle") |> render_click()
      assert has_element?(view, "#bento-size", "16 × 9")
    end

    test "an empty board offers the first card", %{conn: conn, user: user} do
      template =
        CanvasFixtures.canvas_layout_fixture(%{
          author_id: user.id,
          layout_map: %{
            "layout_mode" => "bento",
            "bento_columns" => 12,
            "only" => %{
              "label" => "Only",
              "fields" => ["content"],
              "defaults" => %{"content" => ""},
              "placement" => %{"x" => 0, "y" => 0, "w" => 12, "h" => 2}
            }
          }
        })

      {:ok, canvas} = Canvas.instantiate_template(template, user.id)
      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      refute has_element?(view, "#bento-empty")

      # Remove the only card: the empty state takes over.
      render_click(view, "request_remove_card", %{"cell_key" => "only"})

      assert has_element?(view, "#bento-empty")
      assert has_element?(view, "#empty-add-card")

      view |> element("#empty-add-card") |> render_click()
      refute has_element?(view, "#bento-empty")
      assert has_element?(view, "#bento-card-card1")
    end

    test "the arrow keys on the drag grip move a card", %{conn: conn, user: user} do
      canvas = bento_canvas(user)
      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      view |> element("#edit-layout-toggle") |> render_click()

      view
      |> element("#bento-move-decision")
      |> render_keydown(%{"key" => "ArrowRight"})

      # One press moves half a column: the position step matches the size step.
      assert %{"x" => 0.5, "y" => 3} = placement(canvas, "decision")
      assert has_element?(view, ~s|#bento-card-decision[style*="grid-column: 2 / span 12"]|)

      view
      |> element("#bento-move-decision")
      |> render_keydown(%{"key" => "ArrowDown"})

      assert %{"x" => 0.5, "y" => 3.5} = placement(canvas, "decision")
    end

    test "shift with an arrow resizes a card in half units", %{conn: conn, user: user} do
      canvas = bento_canvas(user)
      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      view |> element("#edit-layout-toggle") |> render_click()

      # decision is 6 columns wide at x=0; one shift+right adds half a column.
      view
      |> element("#bento-move-decision")
      |> render_keydown(%{"key" => "ArrowRight", "shiftKey" => true})

      assert %{"x" => 0, "y" => 3, "w" => 6.5, "h" => 2} = placement(canvas, "decision")
      assert has_element?(view, ~s|#bento-card-decision[style*="grid-column: 1 / span 13"]|)
      assert has_element?(view, "#bento-size-decision", "6.5 × 2")

      # Height resizes in half rows too.
      view
      |> element("#bento-move-decision")
      |> render_keydown(%{"key" => "ArrowDown", "shiftKey" => true})

      assert %{"h" => 2.5} = placement(canvas, "decision")

      # evidence sits at the old right edge: widening it grows the board.
      view
      |> element("#bento-move-evidence")
      |> render_keydown(%{"key" => "ArrowRight", "shiftKey" => true})

      assert %{"x" => 8, "y" => 0, "w" => 4.5, "h" => 3} = placement(canvas, "evidence")
      assert Map.get(cells(canvas), "bento_columns") == 13
    end

    test "a drag's final rectangle is applied like any other operation", %{
      conn: conn,
      user: user
    } do
      canvas = bento_canvas(user)
      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      render_hook(view, "move_card", %{"cell_key" => "decision", "x" => 6, "y" => 0})

      assert %{"x" => 6, "y" => 0, "w" => 6, "h" => 2} = placement(canvas, "decision")

      render_hook(view, "resize_card", %{"cell_key" => "decision", "w" => 4, "h" => 4})

      assert %{"x" => 6, "y" => 0, "w" => 4, "h" => 4} = placement(canvas, "decision")
    end

    test "removing an empty card goes straight away; a card with content asks", %{
      conn: conn,
      user: user
    } do
      canvas = bento_canvas(user)
      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      render_click(view, "request_remove_card", %{"cell_key" => "evidence"})
      refute has_element?(view, "#bento-card-evidence")
      refute Map.has_key?(cells(canvas), "evidence")

      # A card with a value is destructive to remove.
      render_change(view, "update_cell", %{
        "cell_key" => "decision",
        "values" => %{"content" => "a decision worth keeping"}
      })

      render_click(view, "request_remove_card", %{"cell_key" => "decision"})
      assert has_element?(view, "#remove-structure-dialog")
      assert has_element?(view, "#bento-card-decision")

      view |> element("#confirm-remove-structure") |> render_click()

      refute has_element?(view, "#bento-card-decision")
      refute Map.has_key?(cells(canvas), "decision")
    end

    test "a card takes an accent from the palette", %{conn: conn, user: user} do
      canvas = bento_canvas(user)
      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      view |> element("#edit-layout-toggle") |> render_click()

      view |> element("#card-accent-decision") |> render_click()
      assert has_element?(view, ~s|button[phx-value-accent="rose"]|)

      view
      |> element(~s|button[phx-click="set_card_accent"][phx-value-accent="rose"]|)
      |> render_click()

      assert Structure.cell(cells(canvas), "decision")["accent"] == "rose"
      refute has_element?(view, ~s|button[phx-value-accent="rose"]|)
    end
  end

  describe "persistence" do
    test "a move survives a reload", %{conn: conn, user: user} do
      canvas = bento_canvas(user)
      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      render_hook(view, "move_card", %{"cell_key" => "open_questions", "x" => 0, "y" => 5})

      # The browser reloads: the snapshot plus the event log rebuilds the board.
      {:ok, again, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      assert has_element?(again, ~s|#bento-card-open_questions[style*="grid-row: 11 / span 4"]|)
      assert %{"x" => 0, "y" => 5} = placement(canvas, "open_questions")

      # The board grew a row with the card.
      assert has_element?(again, "#bento-size", "12 × 7")
    end
  end
end
