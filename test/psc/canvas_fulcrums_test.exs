defmodule Psc.CanvasFulcrumsTest do
  use Psc.DataCase, async: true

  alias Psc.AccountsFixtures
  alias Psc.Canvas
  alias Psc.Canvas.Fulcrums
  alias Psc.Canvas.Structure
  alias Psc.Canvas.UnstrCanvasCRDT

  defp with_fulcrums(cells, mode, active) do
    [a, b, c | _] = Structure.cell_keys(cells)

    Map.merge(cells, %{
      "fulcrum_mode" => mode,
      "fulcrums" => [
        %{"id" => "f1", "name" => "Risk", "color" => "rose", "cells" => [a, b]},
        %{"id" => "f2", "name" => "Bet", "color" => "sky", "cells" => [b, c]}
      ],
      "$active_fulcrums" => active
    })
  end

  describe "highlighting" do
    test "single mode replaces the active fulcrum, and a second click clears it" do
      cells = with_fulcrums(Canvas.psc_cells(), "single", ["f1"])

      assert Fulcrums.toggle_active(cells, "f2") == ["f2"]
      assert Fulcrums.toggle_active(cells, "f1") == []
    end

    test "multiple mode adds fulcrums up" do
      cells = with_fulcrums(Canvas.psc_cells(), "multiple", ["f1"])

      assert Fulcrums.toggle_active(cells, "f2") == ["f1", "f2"]
    end

    test "off highlights nothing, even with ids saved, and keeps the list" do
      cells = with_fulcrums(Canvas.psc_cells(), "off", ["f1"])

      refute Fulcrums.enabled?(cells)
      assert Fulcrums.active_ids(cells) == []
      assert Fulcrums.highlights(cells) == %{}
      assert length(Fulcrums.list(cells)) == 2
      assert Fulcrums.template_attrs(cells)["fulcrum_mode"] == "off"
    end

    test "highlights map each cell to the colours of its active fulcrums" do
      cells = with_fulcrums(Canvas.psc_cells(), "multiple", ["f1", "f2"])
      [a, b, c | _] = Structure.cell_keys(cells)

      assert Fulcrums.highlights(cells) == %{a => ["rose"], b => ["rose", "sky"], c => ["sky"]}
    end

    test "an active id whose fulcrum is gone is ignored" do
      cells = with_fulcrums(Canvas.psc_cells(), "single", ["gone"])
      assert Fulcrums.active_ids(cells) == []
      assert Fulcrums.highlights(cells) == %{}
    end
  end

  describe "editing" do
    test "add, rename, colour, toggle a cell and remove" do
      [key | _] = Structure.cell_keys(Canvas.psc_cells())

      [fulcrum] = Fulcrums.add([])
      assert %{"id" => "f1", "cells" => []} = fulcrum

      [fulcrum] =
        [fulcrum]
        |> Fulcrums.rename("f1", "Risk")
        |> Fulcrums.set_color("f1", "teal")
        |> Fulcrums.set_color("f1", "not-a-colour")
        |> Fulcrums.toggle_cell("f1", key)

      assert %{"name" => "Risk", "color" => "teal", "cells" => [^key]} = fulcrum
      assert [%{"id" => "f2"}] = [fulcrum] |> Fulcrums.add() |> Fulcrums.remove("f1")
    end

    test "normalize drops cells the canvas does not have" do
      [key | _] = Structure.cell_keys(Canvas.psc_cells())
      list = [%{"id" => "f1", "name" => "X", "color" => "rose", "cells" => [key, "nope"]}]

      assert [%{"cells" => [^key]}] = Fulcrums.normalize(list, Canvas.psc_cells())
    end

    test "fulcrum keys are not cells" do
      cells = with_fulcrums(Canvas.psc_cells(), "single", ["f1"])
      refute Map.has_key?(Structure.cells(cells), "fulcrums")
      refute Map.has_key?(Structure.cells(cells), "$active_fulcrums")
    end
  end

  describe "operations and versions" do
    test "set_fulcrums is versioned content; set_active_fulcrums is not" do
      assert Canvas.versioned_operation?(%{"type" => "set_fulcrums", "fulcrums" => []})
      refute Canvas.versioned_operation?(%{"type" => "set_active_fulcrums", "ids" => []})
    end

    test "loading a version keeps the highlighted fulcrums and the canvas's setting" do
      before = with_fulcrums(Canvas.psc_cells(), "multiple", ["f1"])
      snapshot = before |> Map.put("$active_fulcrums", []) |> Map.put("fulcrum_mode", "off")

      after_load =
        UnstrCanvasCRDT.apply_operation(%{"type" => "replace_cells", "cells" => snapshot}, before)

      assert after_load["$active_fulcrums"] == ["f1"]
      assert after_load["fulcrum_mode"] == "multiple"
    end

    test "the canvas setting is its own, unversioned operation" do
      refute Canvas.versioned_operation?(%{"type" => "set_fulcrum_mode", "mode" => "off"})

      cells = with_fulcrums(Canvas.psc_cells(), "single", [])
      op = %{"type" => "set_fulcrum_mode", "mode" => "off"}
      assert UnstrCanvasCRDT.apply_operation(op, cells)["fulcrum_mode"] == "off"

      junk = %{"type" => "set_fulcrum_mode", "mode" => "nonsense"}
      assert UnstrCanvasCRDT.apply_operation(junk, cells)["fulcrum_mode"] == "single"
    end

    test "a canvas made from a template gets a copy of its fulcrums" do
      user = AccountsFixtures.user_fixture()
      Canvas.seed_builtin_templates()
      template = Canvas.get_template_by_slug("bento")
      [key | _] = Structure.cell_keys(template.layout_map)

      {:ok, template} =
        Canvas.update_template(template, %{
          "layout_map" =>
            Map.merge(template.layout_map, %{
              "fulcrum_mode" => "multiple",
              "fulcrums" => [
                %{"id" => "f1", "name" => "Core", "color" => "amber", "cells" => [key]}
              ]
            })
        })

      {:ok, canvas} = Canvas.instantiate_template(template, user.id)

      assert canvas.cells["fulcrum_mode"] == "multiple"
      assert [%{"name" => "Core", "cells" => [^key]}] = canvas.cells["fulcrums"]
      assert [root] = Canvas.list_pivots(canvas.id)
      assert root.cells["fulcrums"] == canvas.cells["fulcrums"]
    end
  end
end
