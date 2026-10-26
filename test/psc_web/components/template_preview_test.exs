defmodule PscWeb.Components.TemplatePreviewTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias PscWeb.Components.TemplatePreview

  defp card(label, x, y, w, h, accent \\ nil) do
    %{
      "label" => label,
      "fields" => ["content"],
      "defaults" => %{"content" => ""},
      "placement" => %{"x" => x, "y" => y, "w" => w, "h" => h}
    }
    |> then(&if(accent, do: Map.put(&1, "accent", accent), else: &1))
  end

  defp bento(cards) do
    Map.merge(
      %{"layout_mode" => "bento", "bento_columns" => 12, "bento_rows" => 6},
      cards
    )
  end

  defp image(cards, backdrop \\ %{"url" => "/images/plan.svg", "alt" => "Plan"}) do
    Map.merge(%{"layout_mode" => "image", "backdrop" => backdrop}, cards)
  end

  defp table do
    %{
      "rows" => [%{"id" => "r1"}, %{"id" => "r2"}, %{"id" => "r3"}],
      "columns" => [%{"id" => "c1"}, %{"id" => "c2"}, %{"id" => "c3"}, %{"id" => "c4"}],
      "layout" => [
        ["a", "b", "c", "d"],
        ["e", "f", "g", "h"],
        ["i", "j", "k", "l"]
      ],
      "cells" => %{}
    }
  end

  describe "dimensions/1" do
    test "a bento reports its board: columns × rows" do
      assert TemplatePreview.dimensions(bento(%{"a" => card("A", 0, 0, 6, 2)})) == "12 × 6"

      # A card below the container grows the board, so the caption follows.
      assert TemplatePreview.dimensions(bento(%{"a" => card("A", 0, 8, 6, 2)})) == "12 × 10"
    end

    test "a table keeps its matrix: rows × columns" do
      assert TemplatePreview.dimensions(table()) == "3 × 4"
    end

    test "an image board reports its cells" do
      assert TemplatePreview.dimensions(image(%{"a" => card("A", 10, 10, 20, 10)})) == "1 cell"

      assert TemplatePreview.dimensions(
               image(%{"a" => card("A", 10, 10, 20, 10), "b" => card("B", 40, 10, 20, 10)})
             ) == "2 cells"
    end

    test "a missing map is an empty grid" do
      assert TemplatePreview.dimensions(nil) == "0 × 0"
    end
  end

  describe "mini_preview/1" do
    test "a bento draws a box per card at its own row" do
      map =
        bento(%{
          "top" => card("Top", 0, 0, 6, 3, "sky"),
          "middle" => card("Middle", 6, 3, 6, 2),
          "bottom" => card("Bottom", 0, 8, 12, 2, "amber")
        })

      html = render_component(&TemplatePreview.mini_preview/1, layout_map: map)

      assert html =~ ~s|data-card-key="top"|
      assert html =~ ~s|data-card-key="middle"|
      assert html =~ ~s|data-card-key="bottom"|

      # Every card keeps its own track row: the bottom card is not folded back
      # over the ones above it.
      assert html =~ "grid-row: 1 / span 6"
      assert html =~ "grid-row: 7 / span 4"
      assert html =~ "grid-row: 17 / span 4"

      # The accent is the card's outline, never its fill: a preview draws a
      # bento card the way the canvas does.
      assert html =~ "ring-sky-400"
      assert html =~ "ring-amber-400"
      refute html =~ "bg-sky-400"
      refute html =~ "bg-amber-400"
    end

    test "a bento card's background token fills the box and its accent outlines it" do
      map =
        bento(%{
          "a" =>
            card("A", 0, 0, 6, 2)
            |> Map.put("accent", "sky")
            |> Map.put("background", "emerald")
        })

      html = render_component(&TemplatePreview.mini_preview/1, layout_map: map)

      assert html =~ "bg-emerald-100"
      assert html =~ "ring-sky-400"
      refute html =~ "bg-sky-400"
    end

    test "the schematic is decorative" do
      html = render_component(&TemplatePreview.mini_preview/1, layout_map: bento(%{}))
      assert html =~ ~s|aria-hidden="true"|
    end

    test "an empty bento says so instead of drawing nothing" do
      html = render_component(&TemplatePreview.mini_preview/1, layout_map: bento(%{}))
      assert html =~ "Empty board"
    end

    test "a table still draws one square per grid position" do
      html = render_component(&TemplatePreview.mini_preview/1, layout_map: table())

      # 3 rows × 4 columns.
      assert html |> String.split("rounded-[3px] bg-base-content/10") |> length() == 13
      refute html =~ "Empty board"
    end

    test "an image board draws its picture and every cell" do
      map =
        image(%{
          "a" => card("A", 10, 10, 20, 10, "sky"),
          "b" => card("B", 40, 30, 20, 10)
        })

      html = render_component(&TemplatePreview.mini_preview/1, layout_map: map)

      assert html =~ ~s|src="/images/plan.svg"|
      assert html =~ ~s|data-card-key="a"|
      assert html =~ ~s|data-card-key="b"|
      assert html =~ "left: 10%; top: 10%; width: 20%; height: 10%;"
      assert html =~ "bg-sky-400"
    end

    test "an image board without a backdrop says so" do
      map = image(%{}, nil)

      html = render_component(&TemplatePreview.mini_preview/1, layout_map: map)
      assert html =~ "Empty picture"
    end

    test "the large size gives every mode a taller slot for the type picker" do
      maps = [
        table(),
        bento(%{"a" => card("A", 0, 0, 6, 2)}),
        image(%{"a" => card("A", 10, 10, 20, 10)})
      ]

      for map <- maps do
        small = render_component(&TemplatePreview.mini_preview/1, layout_map: map)
        large = render_component(&TemplatePreview.mini_preview/1, layout_map: map, size: :lg)

        assert small =~ "h-16"
        refute small =~ "h-32"
        assert large =~ "h-32"
        refute large =~ "h-16"
      end
    end
  end

  describe "grid_preview/1" do
    test "a bento board is drawn with every card, however tall" do
      map =
        bento(%{
          "a" => card("A", 0, 0, 6, 2),
          "deep" => card("Deep", 0, 20, 6, 2)
        })

      html = render_component(&TemplatePreview.grid_preview/1, layout_map: map)

      assert html =~ "Deep"
      assert html =~ "grid-row: 41 / span 4"
    end

    test "a bento card's background token fills the box and its accent outlines it" do
      map =
        bento(%{
          "a" =>
            card("A", 0, 0, 6, 2)
            |> Map.put("accent", "sky")
            |> Map.put("background", "emerald")
        })

      html = render_component(&TemplatePreview.grid_preview/1, layout_map: map)

      assert html =~ "bg-emerald-100"
      assert html =~ "ring-sky-400"
      refute html =~ "bg-sky-400"
    end

    test "an image board is drawn over its picture" do
      map =
        image(%{
          "a" => card("Lobby", 10, 10, 20, 10),
          "b" => card("Exit", 60, 70, 20, 10)
        })

      html = render_component(&TemplatePreview.grid_preview/1, layout_map: map)

      assert html =~ ~s|src="/images/plan.svg"|
      assert html =~ ~s|alt="Plan"|
      assert html =~ "Lobby"
      assert html =~ "Exit"
      assert html =~ "left: 60%; top: 70%; width: 20%; height: 10%;"
    end
  end

  describe "structure_size/1 and structure_label/1" do
    test "each mode describes its own structure" do
      assert TemplatePreview.structure_size(table()) == "3 rows × 4 columns"

      assert TemplatePreview.structure_size(bento(%{"a" => card("A", 0, 0, 6, 2)})) ==
               "1 card on 12 columns"

      assert TemplatePreview.structure_size(image(%{"a" => card("A", 0, 0, 6, 2)})) ==
               "1 cell on a picture"

      assert TemplatePreview.structure_label(table()) == "Grid"
      assert TemplatePreview.structure_label(bento(%{})) == "Board"
      assert TemplatePreview.structure_label(image(%{})) == "Picture"
    end
  end
end
