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

      # Accents survive.
      assert html =~ "bg-sky-400"
      assert html =~ "bg-amber-400"
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
  end
end
