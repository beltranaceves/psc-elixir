defmodule Psc.CanvasPivotsTest do
  use Psc.DataCase, async: true

  alias Psc.AccountsFixtures
  alias Psc.Canvas
  alias Psc.Canvas.Structure
  alias Psc.Canvas.UnstrCanvasCRDT

  setup do
    owner = AccountsFixtures.user_fixture()

    {:ok, canvas} =
      Canvas.create_unstr_canvas(owner.id, %{"name" => "Plan", "cells" => Canvas.psc_cells()})

    key = canvas.cells |> Structure.cell_keys() |> hd()
    %{owner: owner, canvas: canvas, key: key}
  end

  defp edit(canvas, user, key, value) do
    op = %{"type" => "update_cell", "cell_key" => key, "field" => "content", "value" => value}
    {:ok, _seq} = Canvas.apply_unstr_canvas_operation(canvas.id, user.id, op)
  end

  # What the editor does on an edit: record it, then start a draft if needed.
  defp edit_and_draft(canvas, user, key, value) do
    edit(canvas, user, key, value)
    Canvas.start_draft(canvas.id, user.id)
  end

  defp name!(canvas, draft_id, name) do
    {:ok, pivot} = Canvas.name_pivot(canvas.id, draft_id, %{name: name, rationale: "Because"})
    pivot
  end

  describe "a new canvas" do
    test "starts at a named root version", %{canvas: c} do
      assert [root] = Canvas.list_pivots(c.id)
      assert root.name == "Initial version"
      assert root.kind == "pivot"
      assert root.parent_id == nil
      assert c.head_pivot_id == root.id
    end

    test "made from a template says which one", %{owner: o} do
      Canvas.seed_builtin_templates()
      template = Canvas.get_template_by_slug("bento")
      {:ok, canvas} = Canvas.instantiate_template(template, o.id)

      assert [root] = Canvas.list_pivots(canvas.id)
      assert root.rationale =~ template.name
    end
  end

  describe "start_draft/2" do
    test "an edit on a named version starts a draft under it", %{owner: o, canvas: c, key: key} do
      [root] = Canvas.list_pivots(c.id)

      assert {:ok, {:created, draft}} = edit_and_draft(c, o, key, "idea")
      assert draft.kind == "draft"
      assert draft.parent_id == root.id
      assert draft.name == nil
      assert Canvas.head_pivot_id(c.id) == draft.id

      # Further edits go into the same draft.
      assert {:ok, :exists} = edit_and_draft(c, o, key, "more")
      assert length(Canvas.list_pivots(c.id)) == 2
    end

    test "tells other editors", %{owner: o, canvas: c, key: key} do
      Phoenix.PubSub.subscribe(Psc.PubSub, Canvas.pubsub_topic_unstr(c.id))
      edit_and_draft(c, o, key, "idea")
      assert_receive {:pivots_changed}
    end

    test "renaming the canvas is not a versioned edit" do
      refute Canvas.versioned_operation?(%{"type" => "update_name", "value" => "x"})
      refute Canvas.versioned_operation?(%{"type" => "replace_cells", "cells" => %{}})
      assert Canvas.versioned_operation?(%{"type" => "update_cell"})
    end
  end

  describe "name_pivot/3" do
    test "names the current draft with the current content", %{owner: o, canvas: c, key: key} do
      {:ok, {:created, draft}} = edit_and_draft(c, o, key, "first")
      edit(c, o, key, "final")

      pivot = name!(c, draft.id, "Pricing test")

      assert pivot.kind == "pivot"
      assert pivot.cells[key]["content"] == "final"

      # The canvas still holds it, now named: the next edit starts a new draft.
      assert Canvas.head_pivot_id(c.id) == pivot.id
      assert {:ok, {:created, next}} = edit_and_draft(c, o, key, "again")
      assert next.parent_id == pivot.id
    end

    test "requires a name and a reason, and only names drafts", %{owner: o, canvas: c, key: key} do
      {:ok, {:created, draft}} = edit_and_draft(c, o, key, "x")

      assert {:error, changeset} = Canvas.name_pivot(c.id, draft.id, %{name: " ", rationale: ""})
      assert %{name: [_], rationale: [_]} = errors_on(changeset)

      [root | _] = Canvas.list_pivots(c.id)

      assert {:error, :not_a_draft} =
               Canvas.name_pivot(c.id, root.id, %{name: "x", rationale: "y"})
    end
  end

  describe "load_pivot/2" do
    test "moves the head without creating a version", %{owner: o, canvas: c, key: key} do
      [root] = Canvas.list_pivots(c.id)
      {:ok, {:created, draft}} = edit_and_draft(c, o, key, "idea")
      named = name!(c, draft.id, "Idea")

      assert {:ok, op} = Canvas.load_pivot(c.id, root)
      assert Canvas.head_pivot_id(c.id) == root.id
      assert length(Canvas.list_pivots(c.id)) == 2

      current = Canvas.get_unstr_canvas_content(c.id)

      assert UnstrCanvasCRDT.apply_operation(op, current)[key]["content"] ==
               root.cells[key]["content"]

      # Editing the loaded version branches: a new draft under the root.
      {:ok, {:created, branch}} = edit_and_draft(c, o, key, "other idea")
      assert branch.parent_id == root.id
      refute branch.parent_id == named.id
    end

    test "keeps the unnamed changes it leaves", %{owner: o, canvas: c, key: key} do
      [root] = Canvas.list_pivots(c.id)
      {:ok, {:created, draft}} = edit_and_draft(c, o, key, "unfinished thought")

      {:ok, _op} = Canvas.load_pivot(c.id, root)

      left = Enum.find(Canvas.list_pivots(c.id), &(&1.id == draft.id))
      assert left.kind == "draft"
      assert left.cells[key]["content"] == "unfinished thought"
    end

    test "the replace keeps the canvas name", %{canvas: c} do
      [root] = Canvas.list_pivots(c.id)
      op = %{"type" => "replace_cells", "cells" => Map.put(root.cells, "$name", "Old")}

      assert UnstrCanvasCRDT.apply_operation(op, %{"$name" => "New"})["$name"] == "New"
    end
  end

  describe "fork_pivot/3" do
    test "creates an independent canvas with its own root", %{owner: o, canvas: c, key: key} do
      {:ok, {:created, draft}} = edit_and_draft(c, o, key, "idea")
      pivot = name!(c, draft.id, "One")
      other = AccountsFixtures.user_fixture()

      assert {:ok, fork} = Canvas.fork_pivot(c, pivot, other.id)
      assert fork.author_id == other.id
      assert fork.name == "Plan (fork)"
      assert fork.cells[key]["content"] == "idea"
      assert [%{name: "One", parent_id: nil} = root] = Canvas.list_pivots(fork.id)
      assert fork.head_pivot_id == root.id

      edit(fork, other, key, "changed")
      assert Canvas.get_unstr_canvas_content(c.id)[key]["content"] == "idea"
    end

    test "with history copies the lineage, not the other branches",
         %{owner: o, canvas: c, key: key} do
      [root] = Canvas.list_pivots(c.id)
      {:ok, {:created, d1}} = edit_and_draft(c, o, key, "one")
      one = name!(c, d1.id, "One")
      {:ok, {:created, d2}} = edit_and_draft(c, o, key, "two")
      two = name!(c, d2.id, "Two")

      # A sibling branch under the root, which the fork must not copy.
      {:ok, _op} = Canvas.load_pivot(c.id, root)
      {:ok, {:created, d3}} = edit_and_draft(c, o, key, "other")
      name!(c, d3.id, "Other")

      assert {:ok, fork} = Canvas.fork_pivot(c, two, o.id, keep_history: true)

      copied = Canvas.list_pivots(fork.id)
      assert Enum.map(copied, & &1.name) == ["Initial version", "One", "Two"]

      assert Enum.map(copied, & &1.cells[key]["content"]) == [
               root.cells[key]["content"],
               "one",
               "two"
             ]

      [croot, cone, ctwo] = copied
      assert croot.parent_id == nil
      assert cone.parent_id == croot.id
      assert ctwo.parent_id == cone.id
      assert fork.head_pivot_id == ctwo.id
      assert fork.cells[key]["content"] == "two"
      refute cone.id == one.id
    end
  end

  describe "fork_in_place/3" do
    test "starts a draft right under the version and loads it", %{owner: o, canvas: c, key: key} do
      [root] = Canvas.list_pivots(c.id)
      {:ok, {:created, d1}} = edit_and_draft(c, o, key, "one")
      name!(c, d1.id, "One")
      {:ok, {:created, unfinished}} = edit_and_draft(c, o, key, "unfinished")

      assert {:ok, {draft, op}} = Canvas.fork_in_place(c.id, root, o.id)

      assert draft.kind == "draft"
      assert draft.parent_id == root.id
      assert Canvas.head_pivot_id(c.id) == draft.id

      current = Canvas.get_unstr_canvas_content(c.id)

      assert UnstrCanvasCRDT.apply_operation(op, current)[key]["content"] ==
               root.cells[key]["content"]

      # The draft that was left keeps its content.
      left = Enum.find(Canvas.list_pivots(c.id), &(&1.id == unfinished.id))
      assert left.cells[key]["content"] == "unfinished"
    end
  end
end
