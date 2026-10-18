defmodule Psc.CanvasTest do
  use Psc.DataCase, async: true

  import Ecto.Query

  alias Psc.Canvas
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
    end

    test "instantiated canvas is accessible to its author" do
      user = Psc.AccountsFixtures.user_fixture()
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id})

      assert {:ok, canvas} = Canvas.instantiate_template(template, user.id)
      canvas = Canvas.get_unstr_canvas_with_author(canvas.id)

      assert Canvas.can_access_unstr_canvas?(canvas, user.email)
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
