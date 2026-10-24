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
               ~s|#bento-card-big_picture[style*="grid-column: 1 / span 8"]|
             )

      assert has_element?(
               view,
               ~s|#bento-card-evidence[style*="grid-column: 9 / span 4"]|
             )

      # The card's Markdown field keeps the same editor id as in a table.
      assert has_element?(view, "#md-big_picture-content")
    end

    test "a table canvas still renders the grid", %{conn: conn, user: user} do
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id})
      {:ok, canvas} = Canvas.instantiate_template(template, user.id)

      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      assert has_element?(view, "#canvas-grid")
      refute has_element?(view, "#canvas-bento")
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

      view |> element("#add-card-button") |> render_click()

      # The board already fills two rows; the new card starts below them.
      assert %{"x" => 0, "y" => 5, "w" => 6, "h" => 2} = placement(canvas, "card1")
      assert has_element?(view, "#bento-card-card1")
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

      assert %{"x" => 1, "y" => 3} = placement(canvas, "decision")
      assert has_element?(view, ~s|#bento-card-decision[style*="grid-column: 2 / span 6"]|)

      view
      |> element("#bento-move-decision")
      |> render_keydown(%{"key" => "ArrowDown"})

      assert %{"x" => 1, "y" => 4} = placement(canvas, "decision")
    end

    test "shift with an arrow resizes a card", %{conn: conn, user: user} do
      canvas = bento_canvas(user)
      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      view |> element("#edit-layout-toggle") |> render_click()

      view
      |> element("#bento-move-evidence")
      |> render_keydown(%{"key" => "ArrowRight", "shiftKey" => true})

      assert %{"x" => 8, "y" => 0, "w" => 4, "h" => 3} = placement(canvas, "evidence")

      # It cannot grow past the board's edge.
      view
      |> element("#bento-move-evidence")
      |> render_keydown(%{"key" => "ArrowRight", "shiftKey" => true})

      assert %{"w" => 4} = placement(canvas, "evidence")
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

      assert has_element?(again, ~s|#bento-card-open_questions[style*="grid-row: 6 / span 2"]|)
      assert %{"x" => 0, "y" => 5} = placement(canvas, "open_questions")
    end
  end
end
