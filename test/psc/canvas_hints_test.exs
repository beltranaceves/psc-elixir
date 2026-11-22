defmodule Psc.CanvasHintsTest do
  use Psc.DataCase, async: true

  alias Psc.AccountsFixtures
  alias Psc.Canvas
  alias Psc.Canvas.Structure
  alias Psc.Canvas.UnstrCanvasCRDT
  alias Psc.CanvasFixtures

  defp apply_op(cells, op), do: UnstrCanvasCRDT.apply_operation(op, cells)

  defp table_cells do
    %{
      "rows" => [%{"id" => "r1", "label" => "Row 1"}],
      "columns" => [%{"id" => "c1", "label" => "Column 1"}],
      "layout" => [["r1_c1"]],
      "r1_c1" => %{"row" => "r1", "column" => "c1", "label" => "Cell", "content" => "x"}
    }
  end

  describe "Structure.hint/1 and put_hint/2" do
    test "a blank hint is no hint and removes the key" do
      assert Structure.hint(%{"hint" => "  "}) == nil
      assert Structure.hint(%{}) == nil
      assert Structure.hint(%{"hint" => "Who has the problem?"}) == "Who has the problem?"

      assert Structure.put_hint(%{"hint" => "old"}, "  ") == %{}
      assert Structure.put_hint(%{"hint" => "old"}, nil) == %{}
    end

    test "a long hint is cut to the cap" do
      long = String.duplicate("a", Structure.max_hint() + 50)
      assert %{"hint" => hint} = Structure.put_hint(%{}, long)
      assert String.length(hint) == Structure.max_hint()
    end

    test "a hint is metadata, never a field" do
      assert "hint" in Structure.reserved_cell_keys()

      assert Structure.field_names(%{"label" => "Cell", "hint" => "h", "content" => ""}) == [
               "content"
             ]
    end
  end

  describe "hint operations" do
    test "update_cell_hint sets, replaces and clears a cell's hint" do
      cells =
        apply_op(table_cells(), %{
          "type" => "update_cell_hint",
          "cell_key" => "r1_c1",
          "hint" => "Describe the pain"
        })

      assert cells["r1_c1"]["hint"] == "Describe the pain"
      assert cells["r1_c1"]["content"] == "x"

      cleared =
        apply_op(cells, %{"type" => "update_cell_hint", "cell_key" => "r1_c1", "hint" => ""})

      refute Map.has_key?(cleared["r1_c1"], "hint")
    end

    test "update_cell_hint on a missing cell is a no-op" do
      cells = table_cells()

      assert apply_op(cells, %{"type" => "update_cell_hint", "cell_key" => "nope", "hint" => "x"}) ==
               cells
    end

    test "update_row_hint and update_column_hint change the def" do
      cells =
        table_cells()
        |> apply_op(%{"type" => "update_row_hint", "id" => "r1", "hint" => "Why"})
        |> apply_op(%{"type" => "update_column_hint", "id" => "c1", "hint" => "When"})

      assert [%{"id" => "r1", "label" => "Row 1", "hint" => "Why"}] = cells["rows"]
      assert [%{"id" => "c1", "label" => "Column 1", "hint" => "When"}] = cells["columns"]

      cleared = apply_op(cells, %{"type" => "update_row_hint", "id" => "r1", "hint" => " "})
      assert [%{"id" => "r1"} = row] = cleared["rows"]
      refute Map.has_key?(row, "hint")
    end

    test "a hint persists through the event log" do
      user = AccountsFixtures.user_fixture()
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id})
      {:ok, canvas} = Canvas.instantiate_template(template, user.id)

      {:ok, _seq} =
        Canvas.apply_unstr_canvas_operation(canvas.id, user.id, %{
          "type" => "update_cell_hint",
          "cell_key" => "r1_c1",
          "hint" => "Who is affected?"
        })

      assert Canvas.get_unstr_canvas_content(canvas.id)["r1_c1"]["hint"] == "Who is affected?"
    end
  end

  describe "templates" do
    test "validation rejects a hint that is not text or too long" do
      lm = CanvasFixtures.template_layout_map_fixture()

      assert :ok = Structure.validate_template(put_in(lm, ["cells", "r1_c1", "hint"], "Fine"))

      assert {:error, :layout_map, _} =
               Structure.validate_template(put_in(lm, ["cells", "r1_c1", "hint"], 42))

      too_long = String.duplicate("a", Structure.max_hint() + 1)
      rows = [%{"id" => "r1", "label" => "Row 1", "hint" => too_long} | tl(lm["rows"])]

      assert {:error, :layout_map, _} = Structure.validate_template(Map.put(lm, "rows", rows))
    end

    test "a table canvas copies the hints of its cells, rows and columns" do
      user = AccountsFixtures.user_fixture()

      lm =
        CanvasFixtures.template_layout_map_fixture()
        |> put_in(["cells", "r1_c1", "hint"], "The cell")
        |> Map.update!("rows", fn [first | rest] -> [Map.put(first, "hint", "The row") | rest] end)
        |> Map.update!("columns", fn [first | rest] ->
          [Map.put(first, "hint", "The column") | rest]
        end)

      template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id, layout_map: lm})
      {:ok, canvas} = Canvas.instantiate_template(template, user.id)
      cells = Canvas.get_unstr_canvas_content(canvas.id)

      assert cells["r1_c1"]["hint"] == "The cell"
      refute Map.has_key?(cells["r1_c2"], "hint")
      assert hd(cells["rows"])["hint"] == "The row"
      assert hd(cells["columns"])["hint"] == "The column"
      # The hint is not a field: the cell still has only its content.
      assert Structure.field_names(cells["r1_c1"]) == ["content"]
    end

    test "bento and image canvases copy their cells' hints" do
      user = AccountsFixtures.user_fixture()

      bento = put_in(Canvas.bento_layout_map(), ["decision", "hint"], "What did we choose?")
      image = put_in(Canvas.image_layout_map(), ["next_step", "hint"], "One concrete action")

      for {lm, key, hint} <- [
            {bento, "decision", "What did we choose?"},
            {image, "next_step", "One concrete action"}
          ] do
        template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id, layout_map: lm})
        {:ok, canvas} = Canvas.instantiate_template(template, user.id)

        assert Canvas.get_unstr_canvas_content(canvas.id)[key]["hint"] == hint
      end
    end
  end
end
