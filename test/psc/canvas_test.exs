defmodule Psc.CanvasTest do
  use Psc.DataCase, async: true

  import Ecto.Query

  alias Psc.Canvas
  alias Psc.Canvas.Structure
  alias Psc.Canvas.UnstrCanvasEvent
  alias Psc.CanvasFixtures

  describe "template CRUD" do
    test "create_template/2 assigns the author" do
      user = Psc.AccountsFixtures.user_fixture()

      assert {:ok, template} =
               Canvas.create_template(user.id, %{
                 "name" => "T1",
                 "layout_map" => CanvasFixtures.template_layout_map_fixture()
               })

      assert template.author_id == user.id
    end

    test "update_template/2 updates name and layout_map" do
      user = Psc.AccountsFixtures.user_fixture()
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id})

      assert {:ok, updated} = Canvas.update_template(template, %{"name" => "Renamed"})
      assert updated.name == "Renamed"

      lm = CanvasFixtures.template_layout_map_fixture()
      assert {:ok, updated} = Canvas.update_template(template, %{"layout_map" => lm})
      assert updated.layout_map["cells"] == lm["cells"]
    end

    test "delete_template/1 removes the template" do
      user = Psc.AccountsFixtures.user_fixture()
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id})

      assert {:ok, _} = Canvas.delete_template(template)
      assert Canvas.get_canvas_layout(template.id) == nil
    end
  end

  describe "catalog columns" do
    test "a new template is private and uncounted" do
      user = Psc.AccountsFixtures.user_fixture()
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id})

      refute template.public
      assert template.use_count == 0
      assert template.fork_count == 0
      assert template.forked_from_id == nil
    end

    test "the changeset casts :public and ignores the context-owned fields" do
      user = Psc.AccountsFixtures.user_fixture()
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id})

      {:ok, updated} =
        Canvas.update_template(template, %{
          "public" => "true",
          "use_count" => "999",
          "forked_from_id" => Ecto.UUID.generate()
        })

      assert updated.public == true
      assert updated.use_count == 0
      assert updated.forked_from_id == nil
    end

    test "deleting a source template nilifies its forks' lineage" do
      user = Psc.AccountsFixtures.user_fixture()
      source = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id})

      fork =
        CanvasFixtures.canvas_layout_fixture(%{author_id: user.id})
        |> change(forked_from_id: source.id)
        |> Repo.update!()

      assert {:ok, _} = Canvas.delete_template(source)

      fork = Repo.reload!(fork)
      assert fork.forked_from_id == nil
    end
  end

  describe "list_templates/1" do
    test "includes own and shared templates, excludes others" do
      user = Psc.AccountsFixtures.user_fixture()
      stranger = Psc.AccountsFixtures.user_fixture()

      own = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id, name: "Own"})
      other = CanvasFixtures.canvas_layout_fixture(%{author_id: stranger.id, name: "Other"})
      {:ok, _} = Canvas.share_template_with(other, user.email)

      names = Canvas.list_templates(user) |> Enum.map(& &1.name)

      assert "Own" in names
      assert "Other" in names
      assert length(names) == 2
      refute Enum.any?(Canvas.list_templates(stranger), &(&1.id == own.id))
    end
  end

  describe "catalog" do
    defp set_count(template, changes) do
      template |> change(changes) |> Repo.update!()
    end

    test "list_public_templates/1 lists only public templates, ranked by use" do
      author = Psc.AccountsFixtures.user_fixture()

      low = CanvasFixtures.canvas_layout_fixture(%{author_id: author.id, name: "Low"})
      high = CanvasFixtures.canvas_layout_fixture(%{author_id: author.id, name: "High"})
      private = CanvasFixtures.canvas_layout_fixture(%{author_id: author.id, name: "Private"})

      {:ok, _} = Canvas.publish_template(low)
      {:ok, _} = Canvas.publish_template(high)

      high = set_count(high, use_count: 3)
      low = set_count(low, use_count: 1)

      assert [%{id: high_id}, %{id: low_id}] = Canvas.list_public_templates()
      assert high_id == high.id
      assert low_id == low.id
      refute Enum.any?(Canvas.list_public_templates(), &(&1.id == private.id))
    end

    test "list_public_templates/1 preloads the author" do
      author = Psc.AccountsFixtures.user_fixture()
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: author.id})
      {:ok, _} = Canvas.publish_template(template)

      assert [%{author: %Psc.Accounts.User{email: email}}] = Canvas.list_public_templates()
      assert email == author.email
    end

    test "list_public_templates/1 narrows by name and description" do
      author = Psc.AccountsFixtures.user_fixture()

      named =
        CanvasFixtures.canvas_layout_fixture(%{author_id: author.id, name: "Rationale map"})

      described =
        CanvasFixtures.canvas_layout_fixture(%{
          author_id: author.id,
          name: "Something else",
          description: "for the framing questions"
        })

      other = CanvasFixtures.canvas_layout_fixture(%{author_id: author.id, name: "Unrelated"})

      for template <- [named, described, other],
          do: {:ok, _} = Canvas.publish_template(template)

      assert Canvas.list_public_templates("rationale") |> Enum.map(& &1.name) == [
               "Rationale map"
             ]

      assert Canvas.list_public_templates("framing questions") |> Enum.map(& &1.name) == [
               "Something else"
             ]

      # An empty query is no filter.
      assert length(Canvas.list_public_templates("")) == 3
      assert length(Canvas.list_public_templates()) == 3
    end

    test "list_public_templates/1 escapes the search wildcards" do
      author = Psc.AccountsFixtures.user_fixture()
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: author.id, name: "100%"})
      {:ok, _} = Canvas.publish_template(template)

      assert [%{name: "100%"}] = Canvas.list_public_templates("100%")
      # Unescaped, "10%" would match "100%" as a wildcard pattern.
      assert Canvas.list_public_templates("10%") == []
    end

    test "get_public_template/1 finds a public template and hides a private one" do
      author = Psc.AccountsFixtures.user_fixture()
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: author.id})

      assert Canvas.get_public_template(template.id) == nil

      {:ok, _} = Canvas.publish_template(template)
      assert %{id: id} = Canvas.get_public_template(template.id)
      assert id == template.id
    end

    test "publish_template/1 and unpublish_template/1 flip the flag" do
      author = Psc.AccountsFixtures.user_fixture()
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: author.id})

      {:ok, published} = Canvas.publish_template(template)
      assert published.public

      {:ok, unpublished} = Canvas.unpublish_template(published)
      refute unpublished.public
    end

    test "instantiate_template/3 counts the use" do
      author = Psc.AccountsFixtures.user_fixture()
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: author.id})

      {:ok, _canvas} = Canvas.instantiate_template(template, author.id)
      assert Canvas.get_canvas_layout(template.id).use_count == 1

      {:ok, _canvas} = Canvas.instantiate_template(template, author.id)
      assert Canvas.get_canvas_layout(template.id).use_count == 2
    end

    test "a failed instantiation leaves the count alone" do
      author = Psc.AccountsFixtures.user_fixture()
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: author.id})

      assert {:error, _changeset} =
               Canvas.instantiate_template(template, author.id, %{"notes_mode" => "bogus"})

      assert Canvas.get_canvas_layout(template.id).use_count == 0
    end

    test "fork_template/2 copies the definition and counts the fork" do
      author = Psc.AccountsFixtures.user_fixture()
      source = CanvasFixtures.canvas_layout_fixture(%{author_id: author.id})

      {:ok, fork} = Canvas.fork_template(source, author.id)

      assert fork.author_id == author.id
      assert fork.name == "#{source.name} (fork)"
      assert fork.forked_from_id == source.id
      assert fork.layout_map["cells"] == source.layout_map["cells"]
      assert Canvas.get_canvas_layout(source.id).fork_count == 1
    end

    test "forking the same source twice gives the forks different names" do
      author = Psc.AccountsFixtures.user_fixture()
      source = CanvasFixtures.canvas_layout_fixture(%{author_id: author.id})

      {:ok, first} = Canvas.fork_template(source, author.id)
      {:ok, second} = Canvas.fork_template(source, author.id)

      assert first.name == "#{source.name} (fork)"
      assert second.name == "#{source.name} (fork 2)"
      assert Canvas.get_canvas_layout(source.id).fork_count == 2
    end

    test "a fork that cannot be created leaves the source's count alone" do
      author = Psc.AccountsFixtures.user_fixture()
      source = CanvasFixtures.canvas_layout_fixture(%{author_id: author.id})

      # A template the changeset rejects: no rows.
      broken =
        source
        |> change(layout_map: %{"rows" => []})
        |> Repo.update!()

      assert {:error, _changeset} = Canvas.fork_template(broken, author.id)
      assert Canvas.get_canvas_layout(source.id).fork_count == 0
    end

    test "a fork is independent of its source, and survives it" do
      author = Psc.AccountsFixtures.user_fixture()
      source = CanvasFixtures.canvas_layout_fixture(%{author_id: author.id})

      {:ok, fork} = Canvas.fork_template(source, author.id)

      {:ok, _} = Canvas.update_template(fork, %{"name" => "Renamed fork"})
      assert Canvas.get_canvas_layout(source.id).name == source.name

      {:ok, _} = Canvas.delete_template(source)
      fork = Canvas.get_canvas_layout(fork.id)
      assert fork.name == "Renamed fork"
      assert fork.forked_from_id == nil
    end

    test "deleting a fork does not decrease the source's count" do
      author = Psc.AccountsFixtures.user_fixture()
      source = CanvasFixtures.canvas_layout_fixture(%{author_id: author.id})

      {:ok, fork} = Canvas.fork_template(source, author.id)
      {:ok, _} = Canvas.delete_template(fork)

      assert Canvas.get_canvas_layout(source.id).fork_count == 1
    end

    test "deleting a canvas does not decrease the template's count" do
      author = Psc.AccountsFixtures.user_fixture()
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: author.id})

      {:ok, canvas} = Canvas.instantiate_template(template, author.id)
      {:ok, _} = Canvas.delete_unstr_canvas(canvas)

      assert Canvas.get_canvas_layout(template.id).use_count == 1
    end
  end

  describe "template sharing" do
    test "share_template_with/2 is idempotent" do
      user = Psc.AccountsFixtures.user_fixture()
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id})

      {:ok, t1} = Canvas.share_template_with(template, "friend@example.com")
      {:ok, t2} = Canvas.share_template_with(t1, "friend@example.com")

      assert t2.shared_with == ["friend@example.com"]
    end

    test "unshare_template/2 removes the email" do
      user = Psc.AccountsFixtures.user_fixture()
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id})
      {:ok, t1} = Canvas.share_template_with(template, "friend@example.com")
      {:ok, t2} = Canvas.unshare_template(t1, "friend@example.com")

      assert t2.shared_with == []
    end

    test "can_access_template?/2 for author and shared users" do
      owner = Psc.AccountsFixtures.user_fixture()
      friend = Psc.AccountsFixtures.user_fixture()
      stranger = Psc.AccountsFixtures.user_fixture()

      template = CanvasFixtures.canvas_layout_fixture(%{author_id: owner.id})
      {:ok, template} = Canvas.share_template_with(template, friend.email)
      template = Canvas.get_template_with_author(template.id)

      assert Canvas.can_access_template?(template, owner.email)
      assert Canvas.can_access_template?(template, friend.email)
      refute Canvas.can_access_template?(template, stranger.email)
    end
  end

  describe "field_title/2" do
    test "uses an explicit title, including an intentionally empty one" do
      assert Canvas.field_title(%{"titles" => %{"content" => "Problem statement"}}, "content") ==
               "Problem statement"

      assert Canvas.field_title(%{"titles" => %{"notes" => ""}}, "notes") == ""
    end

    test "falls back to the field key, except for the content body" do
      assert Canvas.field_title(%{}, "notes") == "notes"
      assert Canvas.field_title(%{}, "content") == ""
    end
  end

  describe "template layout_map validation" do
    test "rejects templates with empty rows" do
      user = Psc.AccountsFixtures.user_fixture()
      lm = Map.put(CanvasFixtures.template_layout_map_fixture(), "rows", [])

      assert {:error, changeset} =
               Canvas.create_template(user.id, %{"name" => "Bad", "layout_map" => lm})

      assert "template must have at least one row" in errors_on(changeset).layout_map
    end

    test "rejects templates with empty columns" do
      user = Psc.AccountsFixtures.user_fixture()
      lm = Map.put(CanvasFixtures.template_layout_map_fixture(), "columns", [])

      assert {:error, changeset} =
               Canvas.create_template(user.id, %{"name" => "Bad", "layout_map" => lm})

      assert "template must have at least one column" in errors_on(changeset).layout_map
    end

    test "rejects duplicate field keys within a cell" do
      user = Psc.AccountsFixtures.user_fixture()

      lm =
        CanvasFixtures.template_layout_map_fixture()
        |> put_in(["cells", "r1_c1", "fields"], ["content", "content"])

      assert {:error, changeset} =
               Canvas.create_template(user.id, %{"name" => "Bad", "layout_map" => lm})

      assert "field keys must be unique within a cell" in errors_on(changeset).layout_map
    end
  end

  describe "instantiate_template/2" do
    test "copies per-field section titles into the canvas cells" do
      user = Psc.AccountsFixtures.user_fixture()

      lm = %{
        "rows" => [%{"id" => "r1", "label" => "R"}],
        "columns" => [%{"id" => "c1", "label" => "C"}],
        "layout" => [["r1_c1"]],
        "cells" => %{
          "r1_c1" => %{
            "label" => "Solo",
            "fields" => ["content"],
            "defaults" => %{"content" => ""},
            "titles" => %{"content" => "Problem statement"}
          }
        }
      }

      template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id, layout_map: lm})
      assert {:ok, canvas} = Canvas.instantiate_template(template, user.id)

      cells = Canvas.get_unstr_canvas_content(canvas.id)
      assert cells["r1_c1"]["titles"] == %{"content" => "Problem statement"}
    end

    test "transforms template cells into canvas cell shape" do
      user = Psc.AccountsFixtures.user_fixture()

      cell = fn label ->
        %{
          "label" => label,
          "fields" => ["title", "body"],
          "defaults" => %{"title" => "T", "body" => "B"}
        }
      end

      lm = %{
        "rows" => [%{"id" => "r1", "label" => "Row 1"}],
        "columns" => [
          %{"id" => "c1", "label" => "Col 1"},
          %{"id" => "c2", "label" => "Col 2"}
        ],
        "layout" => [["r1_c1", "r1_c2"]],
        "cells" => %{"r1_c1" => cell.("Alpha"), "r1_c2" => cell.("Beta")}
      }

      template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id, layout_map: lm})

      assert {:ok, canvas} = Canvas.instantiate_template(template, user.id)

      cells = Canvas.get_unstr_canvas_content(canvas.id)

      assert cells["rows"] == lm["rows"]
      assert cells["columns"] == lm["columns"]
      assert cells["layout"] == lm["layout"]
      refute Map.has_key?(cells, "relations")

      alpha = cells["r1_c1"]
      assert alpha["label"] == "Alpha"
      refute Map.has_key?(alpha, "semantics")
      assert alpha["row"] == "r1"
      assert alpha["column"] == "c1"
      assert alpha["title"] == "T"
      assert alpha["body"] == "B"

      assert cells["r1_c2"]["label"] == "Beta"
      assert cells["r1_c2"]["column"] == "c2"
    end

    test "cells without explicit fields default to a single content field" do
      user = Psc.AccountsFixtures.user_fixture()

      lm = %{
        "rows" => [%{"id" => "r1", "label" => "R"}],
        "columns" => [%{"id" => "c1", "label" => "C"}],
        "layout" => [["r1_c1"]],
        "cells" => %{"r1_c1" => %{"label" => "Solo"}}
      }

      template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id, layout_map: lm})
      assert {:ok, canvas} = Canvas.instantiate_template(template, user.id)

      cells = Canvas.get_unstr_canvas_content(canvas.id)
      assert cells["r1_c1"]["content"] == ""
      assert cells["r1_c1"]["field_order"] == ["content"]
    end

    test "preserves the template's field order in the canvas cell" do
      user = Psc.AccountsFixtures.user_fixture()

      lm = %{
        "rows" => [%{"id" => "r1", "label" => "R"}],
        "columns" => [%{"id" => "c1", "label" => "C"}],
        "layout" => [["r1_c1"]],
        "cells" => %{
          "r1_c1" => %{
            "label" => "Solo",
            "fields" => ["summary", "risks", "actions"],
            "defaults" => %{"summary" => "S", "risks" => "R", "actions" => "A"}
          }
        }
      }

      template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id, layout_map: lm})
      assert {:ok, canvas} = Canvas.instantiate_template(template, user.id)

      cell = Canvas.get_unstr_canvas_content(canvas.id)["r1_c1"]

      # A map iterates sorted, so the explicit list is what the editor reads.
      assert cell["field_order"] == ["summary", "risks", "actions"]
      assert Structure.field_names(cell) == ["summary", "risks", "actions"]
    end

    test "instantiated canvas is accessible to its author" do
      user = Psc.AccountsFixtures.user_fixture()
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id})

      assert {:ok, canvas} = Canvas.instantiate_template(template, user.id)
      canvas = Canvas.get_unstr_canvas_with_author(canvas.id)

      assert Canvas.can_access_unstr_canvas?(canvas, user.email)
    end

    test "is unaffected by the schema's empty-structure default" do
      user = Psc.AccountsFixtures.user_fixture()
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id})

      assert {:ok, canvas} = Canvas.instantiate_template(template, user.id)

      cells = Canvas.get_unstr_canvas_content(canvas.id)
      assert length(cells["rows"]) == length(template.layout_map["rows"])
      assert length(cells["columns"]) == length(template.layout_map["columns"])
    end
  end

  describe "creation paths" do
    test "a canvas with no cells is the empty structure" do
      user = Psc.AccountsFixtures.user_fixture()

      assert {:ok, canvas} = Canvas.create_unstr_canvas(user.id, %{"name" => "Empty"})

      assert canvas.cells["rows"] == []
      assert canvas.cells["columns"] == []
      assert canvas.cells["layout"] == []
    end

    test "blank_cells/0 is the empty structure and psc_cells/0 the built-in grid" do
      blank = Canvas.blank_cells()
      assert blank["rows"] == []
      assert blank["columns"] == []
      assert blank["layout"] == []

      psc = Canvas.psc_cells()
      assert length(psc["rows"]) == 3
      assert length(psc["columns"]) == 4
      assert length(psc["layout"]) == 3
      assert length(Enum.at(psc["layout"], 0)) == 4

      # Every layout position has a cell entry: the changeset's invariant.
      for row <- psc["layout"], key <- row do
        assert Map.has_key?(psc, key), "expected cell #{key} in the PSC structure"
      end
    end

    test "the PSC structure passes the changeset's cell validation" do
      user = Psc.AccountsFixtures.user_fixture()

      assert {:ok, canvas} =
               Canvas.create_unstr_canvas(user.id, %{
                 "name" => "PSC",
                 "cells" => Canvas.psc_cells()
               })

      assert length(canvas.cells["rows"]) == 3
    end

    test "the empty structure passes the changeset's cell validation" do
      user = Psc.AccountsFixtures.user_fixture()

      assert {:ok, canvas} =
               Canvas.create_unstr_canvas(user.id, %{
                 "name" => "Blank",
                 "cells" => Canvas.blank_cells()
               })

      assert canvas.cells["rows"] == []
    end
  end

  describe "structure operations" do
    # A representative instantiated state: 2×2 with labels, accents and a
    # field, the shape the editor's structure ops act on.
    defp structured_cells do
      %{
        "rows" => [
          %{"id" => "r1", "label" => "Row 1", "accent" => "amber"},
          %{"id" => "r2", "label" => "Row 2"}
        ],
        "columns" => [
          %{"id" => "c1", "label" => "Column 1", "accent" => "sky"},
          %{"id" => "c2", "label" => "Column 2"}
        ],
        "layout" => [["r1_c1", "r1_c2"], ["r2_c1", "r2_c2"]],
        "r1_c1" => %{
          "row" => "r1",
          "column" => "c1",
          "label" => "Cell 1",
          "content" => "hello",
          "titles" => %{"content" => "Body"}
        },
        "r1_c2" => %{"row" => "r1", "column" => "c2", "label" => "Cell 2", "content" => ""},
        "r2_c1" => %{"row" => "r2", "column" => "c1", "label" => "Cell 3", "content" => ""},
        "r2_c2" => %{"row" => "r2", "column" => "c2", "label" => "Cell 4", "content" => ""}
      }
    end

    defp apply_op(cells, op), do: Psc.Canvas.UnstrCanvasCRDT.apply_operation(op, cells)

    test "add_row appends the def, the matrix row and the cells" do
      cells =
        structured_cells()
        |> apply_op(%{"type" => "add_row", "id" => "r3", "label" => "Row 3"})

      assert Enum.map(cells["rows"], & &1["id"]) == ["r1", "r2", "r3"]
      assert length(cells["layout"]) == 3
      assert Enum.at(cells["layout"], 2) == ["r3_c1", "r3_c2"]

      assert cells["r3_c1"] == %{"row" => "r3", "column" => "c1", "label" => "r3_c1"}
      assert cells["r3_c2"] == %{"row" => "r3", "column" => "c2", "label" => "r3_c2"}

      # The existing cells are untouched.
      assert cells["r1_c1"]["content"] == "hello"
    end

    test "add_row on the empty structure starts the matrix" do
      cells =
        Canvas.blank_cells()
        |> apply_op(%{"type" => "add_row", "id" => "r1", "label" => "Only"})

      assert cells["rows"] == [%{"id" => "r1", "label" => "Only"}]
      assert cells["layout"] == [[]]
    end

    test "add_row is idempotent on an id that is already there" do
      cells = apply_op(structured_cells(), %{"type" => "add_row", "id" => "r1", "label" => "Dup"})
      assert Enum.map(cells["rows"], & &1["id"]) == ["r1", "r2"]
      assert length(cells["layout"]) == 2
    end

    test "add_column appends the def, extends every matrix row and creates the cells" do
      cells =
        structured_cells()
        |> apply_op(%{"type" => "add_column", "id" => "c3", "label" => "Column 3"})

      assert Enum.map(cells["columns"], & &1["id"]) == ["c1", "c2", "c3"]
      assert Enum.at(cells["layout"], 0) == ["r1_c1", "r1_c2", "r1_c3"]
      assert Enum.at(cells["layout"], 1) == ["r2_c1", "r2_c2", "r2_c3"]
      assert cells["r1_c3"]["column"] == "c3"
      assert cells["r2_c3"]["row"] == "r2"
    end

    test "add_column on the empty structure waits for the rows" do
      cells =
        Canvas.blank_cells()
        |> apply_op(%{"type" => "add_column", "id" => "c1", "label" => "Only"})

      assert cells["columns"] == [%{"id" => "c1", "label" => "Only"}]
      assert cells["layout"] == []

      # A row added afterwards picks the column up.
      cells = apply_op(cells, %{"type" => "add_row", "id" => "r1", "label" => "Only"})
      assert Enum.at(cells["layout"], 0) == ["r1_c1"]
    end

    test "remove_row drops the def, its matrix row and its cells, keeping the rest" do
      cells = apply_op(structured_cells(), %{"type" => "remove_row", "id" => "r1"})

      assert Enum.map(cells["rows"], & &1["id"]) == ["r2"]
      assert cells["layout"] == [["r2_c1", "r2_c2"]]
      refute Map.has_key?(cells, "r1_c1")
      refute Map.has_key?(cells, "r1_c2")
      assert cells["r2_c1"]["label"] == "Cell 3"
    end

    test "remove_row is idempotent on an id that is already gone" do
      cells = apply_op(structured_cells(), %{"type" => "remove_row", "id" => "r1"})
      again = apply_op(cells, %{"type" => "remove_row", "id" => "r1"})
      assert again == cells
    end

    test "remove_column drops the def, its matrix slice and its cells" do
      cells = apply_op(structured_cells(), %{"type" => "remove_column", "id" => "c2"})

      assert Enum.map(cells["columns"], & &1["id"]) == ["c1"]
      assert cells["layout"] == [["r1_c1"], ["r2_c1"]]
      refute Map.has_key?(cells, "r1_c2")
      refute Map.has_key?(cells, "r2_c2")
      assert cells["r1_c1"]["content"] == "hello"
    end

    test "update_row_label and update_column_label rename in place" do
      cells =
        structured_cells()
        |> apply_op(%{"type" => "update_row_label", "id" => "r2", "label" => "Strategy"})
        |> apply_op(%{"type" => "update_column_label", "id" => "c1", "label" => "Perceive"})

      assert Enum.at(cells["rows"], 1)["label"] == "Strategy"
      assert Enum.at(cells["columns"], 0)["label"] == "Perceive"
      # The other defs keep their labels and accents.
      assert Enum.at(cells["rows"], 0)["accent"] == "amber"
    end

    test "set_row_accent sets and clears a known token, and ignores an unknown one" do
      cells =
        apply_op(structured_cells(), %{
          "type" => "set_row_accent",
          "id" => "r2",
          "accent" => "teal"
        })

      assert Enum.at(cells["rows"], 1)["accent"] == "teal"

      cells = apply_op(cells, %{"type" => "set_row_accent", "id" => "r2", "accent" => nil})
      assert Enum.at(cells["rows"], 1)["accent"] == nil

      cells =
        apply_op(cells, %{"type" => "set_row_accent", "id" => "r2", "accent" => "chartreuse"})

      assert Enum.at(cells["rows"], 1)["accent"] == nil
    end

    test "set_cell_background sets and clears a known token, and ignores an unknown one" do
      cells =
        apply_op(structured_cells(), %{
          "type" => "set_cell_background",
          "cell_key" => "r1_c1",
          "background" => "sky"
        })

      assert cells["r1_c1"]["background"] == "sky"

      cells =
        apply_op(cells, %{
          "type" => "set_cell_background",
          "cell_key" => "r1_c1",
          "background" => ""
        })

      refute Map.has_key?(cells["r1_c1"], "background")

      cells =
        apply_op(cells, %{
          "type" => "set_cell_background",
          "cell_key" => "r1_c1",
          "background" => "chartreuse"
        })

      refute Map.has_key?(cells["r1_c1"], "background")

      # A metadata key is not a cell, and a background cannot overwrite it.
      cells =
        apply_op(cells, %{
          "type" => "set_cell_background",
          "cell_key" => "rows",
          "background" => "sky"
        })

      assert is_list(cells["rows"])
    end

    test "update_cell_label renames a cell" do
      cells =
        apply_op(structured_cells(), %{
          "type" => "update_cell_label",
          "cell_key" => "r1_c1",
          "label" => "Problem"
        })

      assert cells["r1_c1"]["label"] == "Problem"
      assert cells["r1_c1"]["content"] == "hello"
    end

    test "add_cell_field adds an empty value and an untitled section" do
      cells =
        apply_op(structured_cells(), %{
          "type" => "add_cell_field",
          "cell_key" => "r1_c1",
          "field" => "notes"
        })

      assert cells["r1_c1"]["notes"] == ""
      assert cells["r1_c1"]["titles"]["notes"] == ""
      assert cells["r1_c1"]["content"] == "hello"
    end

    test "add_cell_field appends to field_order and remove_cell_field drops it" do
      cells =
        structured_cells()
        |> apply_op(%{"type" => "add_cell_field", "cell_key" => "r1_c1", "field" => "notes"})

      assert cells["r1_c1"]["field_order"] == ["content", "notes"]

      cells =
        apply_op(cells, %{
          "type" => "remove_cell_field",
          "cell_key" => "r1_c1",
          "field" => "content"
        })

      assert cells["r1_c1"]["field_order"] == ["notes"]
    end

    test "add_cell_field rejects reserved keys and duplicates" do
      cells =
        structured_cells()
        |> apply_op(%{"type" => "add_cell_field", "cell_key" => "r1_c1", "field" => "row"})
        |> apply_op(%{"type" => "add_cell_field", "cell_key" => "r1_c1", "field" => "content"})

      assert cells["r1_c1"]["row"] == "r1"
      assert cells["r1_c1"]["content"] == "hello"
    end

    test "remove_cell_field drops the value and its title, and drops an empty titles map" do
      cells =
        structured_cells()
        |> apply_op(%{"type" => "remove_cell_field", "cell_key" => "r1_c1", "field" => "content"})

      refute Map.has_key?(cells["r1_c1"], "content")
      refute Map.has_key?(cells["r1_c1"], "titles")

      # A cell with several titled fields keeps the map while any remain.
      cells =
        structured_cells()
        |> apply_op(%{"type" => "add_cell_field", "cell_key" => "r1_c1", "field" => "notes"})
        |> apply_op(%{"type" => "remove_cell_field", "cell_key" => "r1_c1", "field" => "content"})

      assert cells["r1_c1"]["titles"] == %{"notes" => ""}
    end

    test "remove_cell_field never removes a reserved key" do
      cells =
        apply_op(structured_cells(), %{
          "type" => "remove_cell_field",
          "cell_key" => "r1_c1",
          "field" => "row"
        })

      assert cells["r1_c1"]["row"] == "r1"
    end

    test "update_cell_field_title sets a section title" do
      cells =
        apply_op(structured_cells(), %{
          "type" => "update_cell_field_title",
          "cell_key" => "r1_c1",
          "field" => "content",
          "title" => "The problem"
        })

      assert cells["r1_c1"]["titles"]["content"] == "The problem"
    end

    test "ops on cells and defs that are not there are no-ops" do
      cells = structured_cells()

      assert apply_op(cells, %{
               "type" => "update_cell_label",
               "cell_key" => "nope",
               "label" => "x"
             }) ==
               cells

      assert apply_op(cells, %{"type" => "add_cell_field", "cell_key" => "nope", "field" => "x"}) ==
               cells

      assert apply_op(cells, %{
               "type" => "remove_cell_field",
               "cell_key" => "nope",
               "field" => "x"
             }) ==
               cells

      assert apply_op(cells, %{"type" => "update_row_label", "id" => "nope", "label" => "x"}) ==
               cells

      assert apply_op(cells, %{"type" => "set_row_accent", "id" => "nope", "accent" => "teal"}) ==
               cells
    end

    test "a sequence of structure ops replays to the same state after a save" do
      user = Psc.AccountsFixtures.user_fixture()

      {:ok, canvas} =
        Canvas.create_unstr_canvas(user.id, %{"name" => "Replay", "cells" => Canvas.psc_cells()})

      id = canvas.id

      ops = [
        %{"type" => "add_row", "id" => "r4", "label" => "Row 4"},
        %{"type" => "update_row_label", "id" => "r4", "label" => "Reflection"},
        %{"type" => "add_column", "id" => "c5", "label" => "Act"},
        %{"type" => "update_cell_label", "cell_key" => "r4_perceive", "label" => "Review"},
        %{"type" => "add_cell_field", "cell_key" => "problem", "field" => "notes"},
        %{"type" => "set_column_accent", "id" => "c5", "accent" => "violet"},
        %{"type" => "remove_row", "id" => "tactics"}
      ]

      Enum.each(ops, &Canvas.apply_unstr_canvas_operation(id, user.id, &1))

      live = Canvas.get_unstr_canvas_content(id)

      # Fold the ops over the stored snapshot the way a reload would, and
      # compare: the ops are replay-safe.
      assert {:ok, _canvas} = Canvas.save_unstr_canvas_content_to_db(id, live)

      reloaded = Canvas.get_unstr_canvas_content(id)
      assert reloaded == live

      assert Enum.map(reloaded["rows"], & &1["id"]) == ["rationale", "strategy", "r4"]

      assert Enum.map(reloaded["columns"], & &1["id"]) == [
               "perceive",
               "form",
               "consolidate",
               "learn",
               "c5"
             ]

      refute Map.has_key?(reloaded, "manifestations")
      assert reloaded["r4_perceive"]["label"] == "Review"
      assert reloaded["problem"]["notes"] == ""
      assert Enum.at(reloaded["columns"], 4)["accent"] == "violet"
    end
  end

  describe "event pruning" do
    test "save prunes folded-in events while content stays loadable" do
      user = Psc.AccountsFixtures.user_fixture()
      {:ok, canvas} = Canvas.create_unstr_canvas(user.id, %{"name" => "Prune test"})
      id = canvas.id

      {:ok, _seq} =
        Canvas.apply_unstr_canvas_operation(id, user.id, %{
          "type" => "update_name",
          "value" => "Renamed"
        })

      {:ok, _seq} =
        Canvas.apply_unstr_canvas_operation(id, user.id, %{
          "type" => "update_cell",
          "cell_key" => "problem",
          "field" => "content",
          "value" => "hello"
        })

      assert Canvas.get_unstr_canvas_content(id)["$name"] == "Renamed"

      cells = Canvas.get_unstr_canvas_content(id)
      assert {:ok, _} = Canvas.save_unstr_canvas_content_to_db(id, cells)

      # Events folded into the snapshot are pruned
      event_count =
        Repo.aggregate(
          from(e in UnstrCanvasEvent, where: e.unstr_canvas_id == ^id),
          :count
        )

      assert event_count == 0

      # Content still loads from the snapshot alone
      assert Canvas.get_unstr_canvas_content(id)["problem"]["content"] == "hello"

      # New operations keep numbering above the snapshot and survive
      # another save/load cycle (the seq generator must be floored at
      # snapshot_seq after pruning)
      {:ok, seq} =
        Canvas.apply_unstr_canvas_operation(id, user.id, %{
          "type" => "update_cell",
          "cell_key" => "problem",
          "field" => "content",
          "value" => "world"
        })

      assert seq > 0
      assert Canvas.get_unstr_canvas_content(id)["problem"]["content"] == "world"

      cells = Canvas.get_unstr_canvas_content(id)
      assert {:ok, _} = Canvas.save_unstr_canvas_content_to_db(id, cells)
      assert Canvas.get_unstr_canvas_content(id)["problem"]["content"] == "world"
    end

    test "save without pending events keeps the snapshot sequence" do
      user = Psc.AccountsFixtures.user_fixture()
      {:ok, canvas} = Canvas.create_unstr_canvas(user.id, %{"name" => "Marker test"})
      id = canvas.id

      {:ok, 1} =
        Canvas.apply_unstr_canvas_operation(id, user.id, %{
          "type" => "update_name",
          "value" => "Renamed"
        })

      cells = Canvas.get_unstr_canvas_content(id)
      assert {:ok, %{snapshot_seq: 1}} = Canvas.save_unstr_canvas_content_to_db(id, cells)

      # Every connected client also runs idle/periodic saves. A save that finds
      # no pending events (the events were just pruned) must not walk the marker
      # back to 0.
      assert {:ok, %{snapshot_seq: 1}} = Canvas.save_unstr_canvas_content_to_db(id, cells)
      assert {:ok, %{snapshot_seq: 1}} = Canvas.save_unstr_canvas_content_to_db(id, cells)

      # The next event continues above snapshot_seq instead of reusing seq 1
      assert {:ok, 2} =
               Canvas.apply_unstr_canvas_operation(id, user.id, %{
                 "type" => "update_name",
                 "value" => "Again"
               })
    end

    test "sweep_folded_events/0 deletes events already covered by the marker" do
      user = Psc.AccountsFixtures.user_fixture()
      {:ok, canvas} = Canvas.create_unstr_canvas(user.id, %{"name" => "Sweep canvas"})
      id = canvas.id

      {:ok, 1} =
        Canvas.apply_unstr_canvas_operation(id, user.id, %{
          "type" => "update_name",
          "value" => "Renamed"
        })

      # Fold first so `cells` really covers seq 1, then re-insert the row —
      # recreating rows that escaped pruning.
      cells = Canvas.get_unstr_canvas_content(id)
      {:ok, _} = Canvas.save_unstr_canvas_content_to_db(id, cells)

      %Canvas.UnstrCanvasEvent{}
      |> Canvas.UnstrCanvasEvent.changeset(%{
        unstr_canvas_id: id,
        user_id: user.id,
        seq: 1,
        operation: %{"type" => "update_name", "value" => "Renamed"}
      })
      |> Repo.insert!()

      assert Canvas.sweep_folded_events() == 1
      assert Canvas.get_unstr_canvas_content(id)["$name"] == "Renamed"
    end

    test "sweep_folded_events/0 leaves unfolded events alone" do
      user = Psc.AccountsFixtures.user_fixture()
      {:ok, canvas} = Canvas.create_unstr_canvas(user.id, %{"name" => "Keep canvas"})
      id = canvas.id

      {:ok, _} =
        Canvas.apply_unstr_canvas_operation(id, user.id, %{
          "type" => "update_name",
          "value" => "Live"
        })

      assert Canvas.sweep_folded_events() == 0
      assert Canvas.get_unstr_canvas_content(id)["$name"] == "Live"
    end
  end
end
