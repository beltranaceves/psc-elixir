defmodule Psc.CanvasAccentsTest do
  use Psc.DataCase, async: true

  alias Psc.Canvas.Accent
  alias Psc.Canvas.Layout
  alias Psc.CanvasFixtures

  describe "accent tokens" do
    test "accepts every palette token plus no accent" do
      assert Accent.valid?(nil)
      assert Accent.valid?("")
      assert Enum.all?(Accent.tokens(), &Accent.valid?/1)
    end

    test "rejects values outside the palette" do
      refute Accent.valid?("burgundy")
      refute Accent.valid?("#ff0000")
      refute Accent.valid?(123)
    end
  end

  describe "instantiation" do
    test "copies template accents into the canvas structure" do
      user = Psc.AccountsFixtures.user_fixture()

      layout_map =
        CanvasFixtures.template_layout_map_fixture()
        |> Map.update!("columns", fn columns ->
          List.update_at(columns, 0, &Map.put(&1, "accent", "violet"))
        end)
        |> Map.update!("rows", fn rows ->
          List.update_at(rows, 0, &Map.put(&1, "accent", "teal"))
        end)

      template =
        CanvasFixtures.canvas_layout_fixture(%{author_id: user.id, layout_map: layout_map})

      {:ok, canvas} = Psc.Canvas.instantiate_template(template, user.id)

      assert Enum.find(canvas.cells["columns"], &(&1["id"] == "c1"))["accent"] == "violet"
      assert Enum.find(canvas.cells["rows"], &(&1["id"] == "r1"))["accent"] == "teal"
      # Untouched entries keep no accent key at all.
      refute Map.has_key?(Enum.find(canvas.cells["columns"], &(&1["id"] == "c2")), "accent")
    end
  end

  describe "template layout validation" do
    defp layout_map_with(accent) do
      %{
        "rows" => [%{"id" => "r1", "label" => "Row 1", "accent" => accent}],
        "columns" => [%{"id" => "c1", "label" => "Column 1"}],
        "layout" => [["r1_c1"]],
        "cells" => %{
          "r1_c1" => %{"fields" => ["content"], "defaults" => %{"content" => ""}}
        }
      }
    end

    test "accepts a palette token" do
      changeset =
        Layout.changeset(%Layout{}, %{name: "Accented", layout_map: layout_map_with("sky")})

      assert changeset.valid?
    end

    test "accepts a template without accents" do
      changeset =
        Layout.changeset(%Layout{}, %{name: "Plain", layout_map: layout_map_with(nil)})

      assert changeset.valid?
    end

    test "rejects an unknown accent token" do
      changeset =
        Layout.changeset(%Layout{}, %{name: "Bad", layout_map: layout_map_with("burgundy")})

      refute changeset.valid?
      assert %{layout_map: ["accents must be known color tokens"]} = errors_on(changeset)
    end
  end
end
