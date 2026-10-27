defmodule Psc.CanvasBentoTest do
  use Psc.DataCase, async: true

  alias Psc.AccountsFixtures
  alias Psc.Canvas
  alias Psc.Canvas.Structure
  alias Psc.Canvas.UnstrCanvasCRDT
  alias Psc.CanvasFixtures

  defp bento_template do
    user = AccountsFixtures.user_fixture()

    template =
      CanvasFixtures.canvas_layout_fixture(%{
        author_id: user.id,
        layout_map: Canvas.bento_layout_map()
      })

    {template, user}
  end

  describe "the reducer" do
    test "a bento template instantiates into a bento canvas" do
      {template, user} = bento_template()

      assert Structure.mode(template.layout_map) == :bento

      {:ok, canvas} = Canvas.instantiate_template(template, user.id)

      cells = Canvas.get_unstr_canvas_content(canvas.id)

      assert Structure.mode(cells) == :bento
      assert Structure.columns(cells) == 12
      # The template's container height is copied, not recomputed.
      assert cells["bento_rows"] == 5

      assert Enum.map(Structure.cards(cells), & &1.key) == [
               "big_picture",
               "evidence",
               "decision",
               "open_questions"
             ]

      # The template's cards became editable values, not definitions.
      assert %{"label" => "Big picture", "content" => "", "placement" => placement} =
               cells["big_picture"]

      assert placement == %{"x" => 0, "y" => 0, "w" => 8, "h" => 3}
      refute Map.has_key?(cells["big_picture"], "fields")
      assert cells["big_picture"]["field_order"] == ["content"]
    end

    test "add, move, resize, accent and remove card are deterministic" do
      cells = %{"layout_mode" => "bento", "bento_columns" => 12}

      add = %{
        "type" => "add_card",
        "cell_key" => "one",
        "placement" => %{"x" => 0, "y" => 0, "w" => 6, "h" => 2},
        "label" => "One"
      }

      cells = UnstrCanvasCRDT.apply_operation(add, cells)
      assert %{"placement" => %{"x" => 0, "y" => 0, "w" => 6, "h" => 2}} = cells["one"]

      cells =
        UnstrCanvasCRDT.apply_operation(
          %{"type" => "move_card", "cell_key" => "one", "x" => 6, "y" => 1},
          cells
        )

      assert cells["one"]["placement"]["x"] == 6
      assert cells["one"]["placement"]["y"] == 1

      cells =
        UnstrCanvasCRDT.apply_operation(
          %{"type" => "resize_card", "cell_key" => "one", "w" => 8, "h" => 4},
          cells
        )

      # The card is at x=6, so widening it to 8 grows the board to 14.
      assert cells["one"]["placement"]["w"] == 8
      assert cells["one"]["placement"]["h"] == 4
      assert cells["bento_columns"] == 14

      cells =
        UnstrCanvasCRDT.apply_operation(
          %{"type" => "set_card_accent", "cell_key" => "one", "accent" => "rose"},
          cells
        )

      assert cells["one"]["accent"] == "rose"

      # Replaying the same sequence from scratch reaches the same state.
      replayed =
        [
          add,
          %{"type" => "move_card", "cell_key" => "one", "x" => 6, "y" => 1},
          %{"type" => "resize_card", "cell_key" => "one", "w" => 8, "h" => 4},
          %{"type" => "set_card_accent", "cell_key" => "one", "accent" => "rose"}
        ]
        |> Enum.reduce(
          %{"layout_mode" => "bento", "bento_columns" => 12},
          &UnstrCanvasCRDT.apply_operation/2
        )

      assert replayed == cells

      cells =
        UnstrCanvasCRDT.apply_operation(%{"type" => "remove_card", "cell_key" => "one"}, cells)

      # Removing the card leaves the widened grid behind: the board is a
      # container, and a drag never shrinks it.
      assert cells == %{"layout_mode" => "bento", "bento_columns" => 14}
    end

    test "clamping is identical for every replay of the same operation" do
      cells = %{"layout_mode" => "bento", "bento_columns" => 12}

      op = %{
        "type" => "add_card",
        "cell_key" => "wide",
        "placement" => %{"x" => 11, "y" => 0, "w" => 99, "h" => 99},
        "label" => "Wide"
      }

      first = UnstrCanvasCRDT.apply_operation(op, cells)
      second = UnstrCanvasCRDT.apply_operation(op, cells)

      assert first == second
      assert first["wide"]["placement"] == %{"x" => 0, "y" => 0, "w" => 12, "h" => 40}
    end

    test "bento operations are harmless on a table canvas" do
      table = %{
        "rows" => [%{"id" => "r1"}],
        "columns" => [%{"id" => "c1"}],
        "layout" => [["a"]],
        "a" => %{"content" => "kept"}
      }

      assert UnstrCanvasCRDT.apply_operation(
               %{"type" => "remove_card", "cell_key" => "a"},
               table
             ) == table

      assert UnstrCanvasCRDT.apply_operation(
               %{"type" => "add_card", "cell_key" => "b"},
               table
             ) == table
    end

    test "changing the row count keeps the cards as the floor" do
      cells = %{
        "layout_mode" => "bento",
        "bento_columns" => 12,
        "a" => %{"placement" => %{"x" => 0, "y" => 0, "w" => 6, "h" => 2}}
      }

      cells =
        UnstrCanvasCRDT.apply_operation(%{"type" => "set_bento_rows", "rows" => 9}, cells)

      assert cells["bento_rows"] == 9
      assert Structure.rows(cells) == 9

      low = UnstrCanvasCRDT.apply_operation(%{"type" => "set_bento_rows", "rows" => 1}, cells)
      assert low["bento_rows"] == 2
      assert Structure.rows(low) == 2
    end

    test "changing the column count clamps every card" do
      cells = %{
        "layout_mode" => "bento",
        "bento_columns" => 12,
        "a" => %{"placement" => %{"x" => 8, "y" => 0, "w" => 4, "h" => 2}}
      }

      cells =
        UnstrCanvasCRDT.apply_operation(
          %{"type" => "set_bento_columns", "columns" => 6},
          cells
        )

      assert cells["bento_columns"] == 6
      assert cells["a"]["placement"]["x"] == 2
      assert cells["a"]["placement"]["w"] == 4
    end
  end

  describe "persistence" do
    test "a bento canvas saves and reloads its placements through the event log" do
      {template, user} = bento_template()
      {:ok, canvas} = Canvas.instantiate_template(template, user.id)

      {:ok, _seq} =
        Canvas.apply_unstr_canvas_operation(canvas.id, user.id, %{
          "type" => "move_card",
          "cell_key" => "decision",
          "x" => 6,
          "y" => 3
        })

      cells = Canvas.get_unstr_canvas_content(canvas.id)
      assert cells["decision"]["placement"] == %{"x" => 6, "y" => 3, "w" => 6, "h" => 2}

      # Folding the snapshot keeps the same shape and prunes the event.
      {:ok, _canvas} = Canvas.save_unstr_canvas_content_to_db(canvas.id, cells)
      assert Canvas.get_unstr_canvas_content(canvas.id)["decision"]["placement"]["x"] == 6
    end

    test "the canvas schema rejects a card outside the board" do
      user = AccountsFixtures.user_fixture()

      assert {:error, changeset} =
               Canvas.create_unstr_canvas(user.id, %{
                 "name" => "Broken bento",
                 "cells" => %{
                   "layout_mode" => "bento",
                   "bento_columns" => 12,
                   "a" => %{"placement" => %{"x" => 10, "y" => 0, "w" => 6, "h" => 2}}
                 }
               })

      assert {"card a extends past the board's 12 columns", _meta} = changeset.errors[:cells]
    end
  end
end
