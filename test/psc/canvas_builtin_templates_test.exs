defmodule Psc.CanvasBuiltinTemplatesTest do
  use Psc.DataCase, async: true

  alias Psc.AccountsFixtures
  alias Psc.Canvas

  setup do
    Canvas.seed_builtin_templates()
    :ok
  end

  describe "seed_builtin_templates/0" do
    test "creates the defaults once and is idempotent" do
      # The setup already seeded them.
      assert {0, 3} = Canvas.seed_builtin_templates()

      assert %{built_in: true, slug: "psc", public: true} = Canvas.get_template_by_slug("psc")
      assert %{built_in: true, slug: "scratchpad"} = Canvas.get_template_by_slug("scratchpad")
    end

    test "never overwrites an edited default" do
      psc = Canvas.get_template_by_slug("psc")
      {:ok, _edited} = Canvas.update_template(psc, %{"name" => "Renamed default"})

      assert {0, 3} = Canvas.seed_builtin_templates()
      assert Canvas.get_template_by_slug("psc").name == "Renamed default"
    end

    test "a built-in cannot be deleted" do
      psc = Canvas.get_template_by_slug("psc")

      assert {:error, :built_in} = Canvas.delete_template(psc)
      assert Canvas.get_template_by_slug("psc")
    end

    test "the built-in fields are not castable" do
      user = AccountsFixtures.user_fixture()

      {:ok, template} =
        Canvas.create_template(user.id, %{
          "name" => "User template",
          "layout_map" => Psc.CanvasFixtures.template_layout_map_fixture(),
          "built_in" => true,
          "slug" => "psc"
        })

      refute template.built_in
      assert is_nil(template.slug)
    end
  end

  describe "access" do
    test "every user sees and can use the defaults" do
      user = AccountsFixtures.user_fixture()

      slugs = user |> Canvas.list_templates() |> Enum.map(& &1.slug)
      assert "psc" in slugs
      assert "scratchpad" in slugs
      assert "bento" in slugs

      psc = Canvas.get_template_by_slug("psc")
      assert Canvas.can_access_template?(psc, user.email)
      assert Canvas.can_access_template?(psc, "stranger@example.com")
    end

    test "instantiating the PSC default reproduces the 12-cell grid" do
      user = AccountsFixtures.user_fixture()
      psc = Canvas.get_template_by_slug("psc")

      assert {:ok, canvas} = Canvas.instantiate_template(psc, user.id, %{"name" => "Mine"})

      assert length(canvas.cells["rows"]) == 3
      assert length(canvas.cells["columns"]) == 4
      assert Map.has_key?(canvas.cells, "problem")
      assert Map.has_key?(canvas.cells, "mission")
      assert canvas.cells["leverage"]["technology"] == ""
    end

    test "the PSC layout map has a definition for every grid cell" do
      layout_map = Canvas.psc_layout_map()

      keys = layout_map["layout"] |> List.flatten() |> MapSet.new()
      assert MapSet.new(Map.keys(layout_map["cells"])) == keys

      for {_key, cell} <- layout_map["cells"] do
        assert cell["fields"] != []
        assert Map.keys(cell["defaults"]) |> Enum.sort() == Enum.sort(cell["fields"])
      end
    end

    test "the scratchpad default opens its canvas in single-note mode" do
      user = AccountsFixtures.user_fixture()
      scratchpad = Canvas.get_template_by_slug("scratchpad")

      assert {:ok, canvas} =
               Canvas.instantiate_template(scratchpad, user.id, %{"name" => "Notes"})

      assert canvas.notes_mode == "single"
    end
  end
end
