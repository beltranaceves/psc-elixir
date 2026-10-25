defmodule Psc.Canvas.StructureTest do
  use ExUnit.Case, async: true

  alias Psc.Canvas.Structure

  defp bento(cards \\ %{}) do
    Map.merge(%{"layout_mode" => "bento", "bento_columns" => 12}, cards)
  end

  defp card(x, y, w, h, extra \\ %{}) do
    Map.merge(%{"placement" => %{"x" => x, "y" => y, "w" => w, "h" => h}}, extra)
  end

  describe "mode" do
    test "a map without a mode is a table" do
      assert Structure.mode(%{"rows" => [], "columns" => [], "layout" => []}) == :table
      assert Structure.mode(%{}) == :table
    end

    test "a bento map says so" do
      assert Structure.mode(bento()) == :bento
      assert Structure.bento?(bento())
      refute Structure.bento?(%{"layout" => []})
    end
  end

  describe "table cards" do
    test "every matrix position is a card at its index" do
      cells = %{
        "rows" => [%{"id" => "r1", "label" => "Row 1"}, %{"id" => "r2", "label" => "Row 2"}],
        "columns" => [
          %{"id" => "c1", "label" => "Column 1", "accent" => "sky"},
          %{"id" => "c2", "label" => "Column 2"}
        ],
        "layout" => [["a", "b"], ["c", "d"]],
        "a" => %{"label" => "A", "content" => ""},
        "b" => %{"label" => "B", "content" => ""},
        "c" => %{"label" => "C", "content" => ""},
        "d" => %{"label" => "D", "content" => ""}
      }

      cards = Structure.cards(cells)

      assert Enum.map(cards, &{&1.key, &1.x, &1.y, &1.w, &1.h}) == [
               {"a", 0, 0, 1, 1},
               {"b", 1, 0, 1, 1},
               {"c", 0, 1, 1, 1},
               {"d", 1, 1, 1, 1}
             ]

      # The card takes its label from the cell, and its accent from its column.
      assert Enum.at(cards, 0).label == "A"
      assert Enum.at(cards, 0).accent == "sky"
      assert Enum.at(cards, 1).accent == nil
    end

    test "a table template reads its nested cells" do
      lm = %{
        "rows" => [%{"id" => "r1"}],
        "columns" => [%{"id" => "c1"}],
        "layout" => [["r1_c1"]],
        "cells" => %{"r1_c1" => %{"label" => "Only", "fields" => ["content"]}}
      }

      assert [%{key: "r1_c1", label: "Only"}] = Structure.cards(lm)
      assert Structure.cell_keys(lm) == ["r1_c1"]
    end

    test "an empty table is empty; a table with rows and columns is not" do
      assert Structure.empty?(%{"rows" => [], "columns" => [], "layout" => []})

      refute Structure.empty?(%{
               "rows" => [%{"id" => "r1"}],
               "columns" => [%{"id" => "c1"}],
               "layout" => [["r1_c1"]],
               "r1_c1" => %{}
             })
    end
  end

  describe "bento cards" do
    test "cards are ordered by y, then x" do
      cells =
        bento(%{
          "bottom" => card(0, 4, 6, 2),
          "right" => card(6, 0, 6, 2),
          "left" => card(0, 0, 6, 2)
        })

      assert Enum.map(Structure.cards(cells), & &1.key) == ["left", "right", "bottom"]
    end

    test "a cell without a placement renders as a single unit" do
      cells = bento(%{"loose" => %{"label" => "Loose"}})
      assert [%{x: 0, y: 0, w: 1, h: 1}] = Structure.cards(cells)
    end

    test "bounds report the column count and the deepest edge" do
      cells = bento(%{"a" => card(6, 2, 6, 3)})
      assert Structure.bounds(cells) == %{columns: 12, rows: 5}
    end

    test "an empty bento has no cards" do
      assert Structure.empty?(bento())
      refute Structure.empty?(bento(%{"a" => card(0, 0, 6, 2)}))
    end
  end

  describe "next_slot/1" do
    test "starts at the top left" do
      assert Structure.next_slot(bento()) == %{x: 0, y: 0, w: 6, h: 2}
    end

    test "fills a row before starting the next" do
      cells = bento(%{"a" => card(0, 0, 6, 2)})
      assert Structure.next_slot(cells) == %{x: 6, y: 0, w: 6, h: 2}
    end

    test "skips a card that covers both halves of a row" do
      cells = bento(%{"wide" => card(0, 0, 12, 2)})
      assert Structure.next_slot(cells) == %{x: 0, y: 2, w: 6, h: 2}
    end

    test "respects a gap left by a removed card" do
      cells = bento(%{"left" => card(0, 0, 6, 2), "right" => card(6, 0, 6, 2)})
      cells = Structure.remove_card(cells, "left")
      assert Structure.next_slot(cells) == %{x: 0, y: 0, w: 6, h: 2}
    end
  end

  describe "add_card/5" do
    test "adds a card with its placement and label" do
      cells = Structure.add_card(bento(), "new", %{"x" => 0, "y" => 4, "w" => 4, "h" => 2}, "New")

      assert %{"label" => "New", "content" => "", "placement" => placement} = cells["new"]
      assert placement == %{"x" => 0, "y" => 4, "w" => 4, "h" => 2}
      assert cells["layout_mode"] == "bento"
    end

    test "clamps a placement into the board" do
      cells = Structure.add_card(bento(), "new", %{"x" => 11, "y" => -3, "w" => 40, "h" => 0})

      assert %{"placement" => %{"x" => 0, "y" => 0, "w" => 12, "h" => 0.5}} = cells["new"]
    end

    test "is idempotent for an existing key" do
      cells = bento(%{"a" => card(0, 0, 6, 2)})
      assert Structure.add_card(cells, "a", nil, "Other") == cells
    end

    test "is a no-op on a table" do
      table = %{"rows" => [%{"id" => "r1"}], "columns" => [%{"id" => "c1"}]}
      assert Structure.add_card(table, "new") == table
    end
  end

  describe "move, resize and accents" do
    test "moves a card, clamped to the board" do
      cells = bento(%{"a" => card(0, 0, 6, 2)})
      moved = Structure.move(cells, "a", 9, 3)

      assert moved["a"]["placement"] == %{"x" => 6, "y" => 3, "w" => 6, "h" => 2}

      # A card cannot be dragged off the left/top edge.
      moved = Structure.move(cells, "a", -4, -1)
      assert moved["a"]["placement"]["x"] == 0
      assert moved["a"]["placement"]["y"] == 0
    end

    test "resizes a card, clamped to the board" do
      cells = bento(%{"a" => card(8, 0, 4, 2)})
      resized = Structure.resize(cells, "a", 9, 0)

      assert resized["a"]["placement"]["w"] == 4
      assert resized["a"]["placement"]["h"] == 0.5
    end

    test "resize moves in half units" do
      cells = bento(%{"a" => card(0, 0, 6, 2)})

      half = Structure.resize(cells, "a", 6.5, 2.5)
      assert half["a"]["placement"]["w"] == 6.5
      assert half["a"]["placement"]["h"] == 2.5

      # Anything finer than half a column snaps to the nearest half.
      snapped = Structure.resize(cells, "a", 6.3, 2.2)
      assert snapped["a"]["placement"]["w"] == 6.5
      assert snapped["a"]["placement"]["h"] == 2.0
    end

    test "a half-width card is valid; a quarter-width card is not" do
      assert Structure.validate(bento(%{"a" => card(0, 0, 0.5, 2)})) == :ok

      assert {:error, _, message} =
               Structure.validate(bento(%{"a" => card(0, 0, 1.25, 2)}))

      assert message =~ "half columns"
    end

    test "the board renders two tracks per column" do
      cells = bento(%{"a" => card(1, 2, 1.5, 2.5)})

      assert Structure.board_style(12) ==
               "--bento-columns: 12; grid-template-columns: repeat(24, minmax(0, 1fr)); " <>
                 "grid-auto-rows: minmax(32px, auto); gap: 8px;"

      assert [card] = Structure.cards(cells)
      assert Structure.placement_style(card) == "grid-column: 3 / span 3; grid-row: 5 / span 5;"
    end

    test "moving or resizing a missing card changes nothing" do
      cells = bento(%{"a" => card(0, 0, 6, 2)})
      assert Structure.move(cells, "nope", 1, 1) == cells
      assert Structure.resize(cells, "nope", 2, 2) == cells
    end

    test "sets a known accent and rejects an unknown one" do
      cells = bento(%{"a" => card(0, 0, 6, 2)})

      assert Structure.set_accent(cells, "a", "sky")["a"]["accent"] == "sky"
      assert Structure.set_accent(cells, "a", "not-a-token") == cells
      refute Map.has_key?(Structure.set_accent(cells, "a", "")["a"], "accent")
    end

    test "set_columns clamps every card into the narrower board" do
      cells = bento(%{"a" => card(8, 0, 4, 2), "b" => card(0, 0, 4, 2)})
      narrow = Structure.set_columns(cells, 6)

      assert narrow["bento_columns"] == 6
      assert narrow["a"]["placement"]["x"] == 2
      assert narrow["a"]["placement"]["w"] == 4
    end
  end

  describe "neighbours/2" do
    test "finds cards on each side geometrically" do
      cells =
        bento(%{
          "tl" => card(0, 0, 4, 2),
          "tr" => card(4, 0, 4, 2),
          "bl" => card(0, 2, 4, 2)
        })

      assert Structure.neighbours(cells, "tl") == %{left: nil, right: "tr", up: nil, down: "bl"}

      # Nothing is to the right of "tr", so a horizontal swipe moves on in
      # reading order; a vertical swipe never wraps.
      assert Structure.neighbours(cells, "tr") == %{left: "tl", right: "bl", up: nil, down: nil}
    end

    test "falls back to reading order at a ragged edge" do
      cells = bento(%{"a" => card(0, 0, 12, 2), "b" => card(0, 2, 12, 2)})

      # Nothing is geometrically to the right of `a`, so swipe moves on.
      assert Structure.neighbours(cells, "a").right == "b"
      assert Structure.neighbours(cells, "b").left == "a"
    end

    test "a missing key has no neighbours" do
      assert Structure.neighbours(bento(%{"a" => card(0, 0, 6, 2)}), "nope") ==
               %{left: nil, right: nil, up: nil, down: nil}
    end

    test "table neighbours follow the matrix" do
      cells = %{
        "rows" => [%{"id" => "r1"}, %{"id" => "r2"}],
        "columns" => [%{"id" => "c1"}, %{"id" => "c2"}],
        "layout" => [["a", "b"], ["c", "d"]],
        "a" => %{},
        "b" => %{},
        "c" => %{},
        "d" => %{}
      }

      assert Structure.neighbours(cells, "a") == %{left: nil, right: "b", up: nil, down: "c"}
      assert Structure.neighbours(cells, "d").left == "c"
      assert Structure.neighbours(cells, "d").up == "b"
    end
  end

  describe "validation" do
    test "an empty table canvas is valid" do
      assert Structure.validate(%{"rows" => [], "columns" => [], "layout" => []}) == :ok
    end

    test "a table canvas must keep its layout and cell data in step" do
      cells = %{"rows" => [%{"id" => "r1"}], "columns" => [%{"id" => "c1"}], "layout" => [["a"]]}
      assert {:error, :cells, "Missing cell data for keys: a"} = Structure.validate(cells)

      assert {:error, _, "Layout must be a 2D array of cell keys"} =
               Structure.validate(%{"layout" => "nope"})
    end

    test "a bento canvas is valid with no cards" do
      assert Structure.validate(bento()) == :ok
    end

    test "a bento placement must stay inside the board" do
      assert {:error, _, message} =
               Structure.validate(bento(%{"a" => card(10, 0, 6, 2)}))

      assert message =~ "extends past the board"
    end

    test "a bento card must carry whole units" do
      assert {:error, _, message} =
               Structure.validate(bento(%{"a" => card("0", 0, 6, 2)}))

      assert message =~ "half columns"
    end

    test "the column count is bounded" do
      assert {:error, _, message} =
               Structure.validate(%{"layout_mode" => "bento", "bento_columns" => 40})

      assert message =~ "between 4 and 16 columns"
    end

    test "a template needs at least one card" do
      assert {:error, _, "template must have at least one card"} =
               Structure.validate_template(bento())
    end

    test "a template rejects duplicate field keys" do
      template =
        bento(%{
          "a" => card(0, 0, 6, 2, %{"fields" => ["x", "x"], "defaults" => %{"x" => ""}})
        })

      assert {:error, _, "field keys must be unique within a cell"} =
               Structure.validate_template(template)
    end

    test "a template rejects an unknown accent" do
      template = bento(%{"a" => card(0, 0, 6, 2, %{"accent" => "chartreuse"})})

      assert {:error, _, "accents must be known color tokens"} =
               Structure.validate_template(template)
    end

    test "a bento template with cards, fields and accents is valid" do
      template =
        bento(%{
          "a" => card(0, 0, 6, 2, %{"fields" => ["content"], "accent" => "sky"}),
          "b" => card(6, 0, 6, 2, %{"fields" => ["content"], "accent" => "emerald"})
        })

      assert Structure.validate_template(template) == :ok
    end
  end
end
