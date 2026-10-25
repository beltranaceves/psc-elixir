defmodule Psc.CanvasImageTest do
  use Psc.DataCase, async: true

  alias Psc.AccountsFixtures
  alias Psc.Canvas
  alias Psc.Canvas.Structure
  alias Psc.Canvas.UnstrCanvasCRDT
  alias Psc.CanvasFixtures

  defp image(extra \\ %{}) do
    Map.merge(
      %{"layout_mode" => "image", "backdrop" => %{"url" => "/images/backdrop.png"}},
      extra
    )
  end

  defp cell(x, y, w, h, extra \\ %{}) do
    Map.merge(%{"placement" => %{"x" => x, "y" => y, "w" => w, "h" => h}}, extra)
  end

  defp image_template do
    user = AccountsFixtures.user_fixture()

    template =
      CanvasFixtures.canvas_layout_fixture(%{
        author_id: user.id,
        layout_map: Canvas.image_layout_map()
      })

    {template, user}
  end

  describe "the built-in image board" do
    test "is an image template with a backdrop, cards and a text cell" do
      lm = Canvas.image_layout_map()

      assert Structure.mode(lm) == :image
      assert Structure.image?(lm)
      refute Structure.bento?(lm)

      backdrop = Structure.backdrop(lm)
      assert backdrop.url == Canvas.image_backdrop_url()
      assert backdrop.fit == "contain"
      assert backdrop.alt == "Blueprint grid with three marked zones"
      assert backdrop.aspect == nil

      cards = Structure.cards(lm)
      assert Enum.map(cards, & &1.key) == ["brief", "risk", "next_step"]
      assert Enum.map(cards, & &1.kind) == ["card", "card", "text"]

      # Every card is a percentage rectangle inside the picture.
      assert Enum.all?(cards, &(&1.x + &1.w <= 100 and &1.y + &1.h <= 100))

      assert Structure.validate_template(lm) == :ok
    end

    test "instantiating it copies the backdrop, placements, kinds and defaults" do
      {template, user} = image_template()

      {:ok, canvas} = Canvas.instantiate_template(template, user.id)
      cells = Canvas.get_unstr_canvas_content(canvas.id)

      assert Structure.mode(cells) == :image
      assert cells["backdrop"]["url"] == Canvas.image_backdrop_url()
      assert cells["backdrop"]["fit"] == "contain"

      assert %{
               "label" => "Next step",
               "content" => "Next step",
               "kind" => "text",
               "placement" => %{"x" => 34, "y" => 78, "w" => 32, "h" => 8}
             } = cells["next_step"]

      # The definition stays a definition: no fields/defaults leak into the
      # canvas, and editing the template never mutates the copy.
      refute Map.has_key?(cells["next_step"], "fields")

      {:ok, _edited} =
        Canvas.update_template(template, %{
          "layout_map" => put_in(template.layout_map, ["next_step", "label"], "Changed")
        })

      assert Canvas.get_unstr_canvas_content(canvas.id)["next_step"]["label"] == "Next step"
    end
  end

  describe "image geometry" do
    test "placements are percentages of the backdrop" do
      cells = image(%{"a" => cell(10, 20, 30, 15, %{"kind" => "text", "label" => "A"})})

      assert [%{key: "a", x: 10, y: 20, w: 30, h: 15, kind: "text"}] = Structure.cards(cells)
      assert Structure.bounds(cells) == %{columns: 100, rows: 100}
      assert Structure.image_extent() == 100
      assert Structure.image_size_label(30, 15) == "30 × 15%"
      assert Structure.image_step() == 0.5
      assert Structure.image_min_size() == 2
    end

    test "the first free slot of an empty picture is the top left" do
      assert Structure.next_slot(image()) == %{x: 0, y: 0, w: 24, h: 12}
    end

    test "a new cell is clamped into the picture" do
      cells = Structure.add_card(image(), "a", %{"x" => 95, "y" => -5, "w" => 20, "h" => 200})

      assert cells["a"]["placement"] == %{"x" => 80, "y" => 0, "w" => 20, "h" => 100}
      assert cells["a"]["kind"] == "card"
    end

    test "moving and resizing snap to half percents and stay inside the picture" do
      cells = image(%{"a" => cell(20, 20, 30, 10)})

      moved = Structure.move(cells, "a", 33.3, 120)
      assert moved["a"]["placement"] == %{"x" => 33.5, "y" => 90, "w" => 30, "h" => 10}

      resized = Structure.resize(cells, "a", 200, 1)
      assert resized["a"]["placement"] == %{"x" => 0, "y" => 20, "w" => 100, "h" => 2}
    end

    test "a horizontal swipe finds the cell beside it" do
      cells =
        image(%{
          "left" => cell(0, 10, 20, 10),
          "right" => cell(30, 12, 20, 10)
        })

      assert Structure.neighbours(cells, "left").right == "right"
      assert Structure.neighbours(cells, "right").left == "left"
    end

    test "the board's shape follows the picture unless one is pinned" do
      # No picture: a fixed frame for the empty state.
      assert Structure.image_board_style(%{"layout_mode" => "image"}) ==
               "aspect-ratio: 1.7778;"

      # The picture supplies the height; a pinned ratio frames it.
      assert Structure.image_board_style(image()) == ""

      pinned =
        image(%{"backdrop" => %{"url" => "/images/plan.svg", "aspect" => 1.5, "fit" => "cover"}})

      assert Structure.image_board_style(pinned) == "aspect-ratio: 1.5;"
    end
  end

  describe "the backdrop" do
    test "a valid URL, fit, description and shape are stored normalized" do
      cells =
        Structure.set_backdrop(image(), %{
          "url" => "https://example.com/plan.svg",
          "fit" => "cover",
          "alt" => "  Floor plan  ",
          "aspect" => "1.5"
        })

      assert cells["backdrop"] == %{
               "url" => "https://example.com/plan.svg",
               "fit" => "cover",
               "alt" => "Floor plan",
               "aspect" => 1.5
             }
    end

    test "an unsafe or empty URL never reaches the map" do
      cells = image()

      assert Structure.set_backdrop(cells, %{"url" => "javascript:alert(1)"})["backdrop"]["url"] ==
               "/images/backdrop.png"

      assert Structure.set_backdrop(cells, %{"url" => "https://exa mple.com/a.png"})["backdrop"][
               "url"
             ] == "/images/backdrop.png"

      cleared = Structure.set_backdrop(cells, %{"url" => "  "})
      refute Structure.backdrop?(cleared)

      # A canvas may be blank, but a backdrop map without a URL is malformed.
      assert {:error, :layout_map, "backdrop must be an image URL"} =
               Structure.validate(image(%{"backdrop" => %{}}))
    end

    test "data URIs, root paths and http are accepted" do
      assert Structure.valid_backdrop_url?("https://example.com/a.svg")
      assert Structure.valid_backdrop_url?("http://example.com/a.png")
      assert Structure.valid_backdrop_url?("/images/plan.svg")
      assert Structure.valid_backdrop_url?("data:image/svg+xml,<svg></svg>")

      refute Structure.valid_backdrop_url?("ftp://example.com/a.png")
      refute Structure.valid_backdrop_url?("javascript:alert(1)")
      refute Structure.valid_backdrop_url?("")
      refute Structure.valid_backdrop_url?(nil)
    end

    test "an unknown fit keeps the current one and an out-of-range shape is dropped" do
      cells = Structure.set_backdrop(image(), %{"url" => "/x.svg", "fit" => "bogus"})
      assert cells["backdrop"]["fit"] == "contain"

      cells = Structure.set_backdrop(cells, %{"aspect" => 99})
      refute Map.has_key?(cells["backdrop"], "aspect")

      cells = Structure.set_backdrop(cells, %{"aspect" => 1.5})
      assert cells["backdrop"]["aspect"] == 1.5

      # `"auto"` through the form clears a pinned shape.
      cells = Structure.set_backdrop(cells, %{"aspect" => nil})
      refute Map.has_key?(cells["backdrop"], "aspect")
    end
  end

  describe "the reducer" do
    test "add, move, resize, kind, accent, backdrop and remove are deterministic" do
      start = %{"layout_mode" => "image", "backdrop" => %{"url" => "/images/plan.png"}}

      ops = [
        %{
          "type" => "add_card",
          "cell_key" => "cell1",
          "label" => "Lobby",
          "placement" => %{"x" => 10, "y" => 10, "w" => 24, "h" => 12}
        },
        %{"type" => "move_card", "cell_key" => "cell1", "x" => 12.5, "y" => 8},
        %{"type" => "resize_card", "cell_key" => "cell1", "w" => 30, "h" => 18},
        %{"type" => "set_cell_kind", "cell_key" => "cell1", "kind" => "text"},
        %{"type" => "set_card_accent", "cell_key" => "cell1", "accent" => "rose"},
        %{
          "type" => "set_backdrop",
          "backdrop" => %{"url" => "/images/other.svg", "fit" => "cover", "aspect" => 1.0}
        },
        %{
          "type" => "update_cell",
          "cell_key" => "cell1",
          "field" => "content",
          "value" => "Main entrance"
        }
      ]

      cells = Enum.reduce(ops, start, &UnstrCanvasCRDT.apply_operation/2)
      replayed = Enum.reduce(ops, start, &UnstrCanvasCRDT.apply_operation/2)

      assert replayed == cells
      assert cells["cell1"]["placement"] == %{"x" => 12.5, "y" => 8, "w" => 30, "h" => 18}
      assert cells["cell1"]["kind"] == "text"
      assert cells["cell1"]["accent"] == "rose"
      assert cells["cell1"]["content"] == "Main entrance"

      assert cells["backdrop"] == %{
               "url" => "/images/other.svg",
               "fit" => "cover",
               "aspect" => 1.0
             }

      removed =
        UnstrCanvasCRDT.apply_operation(%{"type" => "remove_card", "cell_key" => "cell1"}, cells)

      refute Map.has_key?(removed, "cell1")
      assert Structure.backdrop?(removed)
    end

    test "image operations are harmless on a table canvas" do
      table = %{
        "rows" => [%{"id" => "r1"}],
        "columns" => [%{"id" => "c1"}],
        "layout" => [["a"]],
        "a" => %{"content" => "kept"}
      }

      assert UnstrCanvasCRDT.apply_operation(%{"type" => "add_card", "cell_key" => "b"}, table) ==
               table

      assert UnstrCanvasCRDT.apply_operation(
               %{"type" => "set_backdrop", "backdrop" => %{"url" => "/x.png"}},
               table
             ) == table

      assert UnstrCanvasCRDT.apply_operation(
               %{"type" => "set_cell_kind", "cell_key" => "a", "kind" => "text"},
               table
             ) == table
    end
  end

  describe "validation" do
    test "a canvas may exist without a backdrop but a template may not" do
      bare = %{
        "layout_mode" => "image",
        "a" => cell(10, 10, 20, 10)
      }

      assert Structure.validate(bare) == :ok

      assert {:error, :layout_map, "template must have a backdrop"} =
               Structure.validate_template(bare)
    end

    test "a template needs at least one cell" do
      assert {:error, :layout_map, "template must have at least one cell"} =
               Structure.validate_template(image())
    end

    test "an out-of-bounds, too small or unknown-kind cell is rejected" do
      assert {:error, :layout_map, "cell a extends past the backdrop"} =
               Structure.validate(image(%{"a" => cell(90, 0, 20, 10)}))

      assert {:error, :layout_map, "cell a must be at least 2% wide and tall"} =
               Structure.validate(image(%{"a" => cell(0, 0, 1, 10)}))

      assert {:error, :layout_map, "cell a has an unknown kind"} =
               Structure.validate(image(%{"a" => cell(0, 0, 10, 10, %{"kind" => "sticky"})}))

      assert {:error, :layout_map, "cell a must be placed and sized in half units"} =
               Structure.validate(image(%{"a" => cell(0.3, 0, 10, 10)}))

      assert {:error, :layout_map, "cell a has no placement"} =
               Structure.validate(image(%{"a" => %{"label" => "A"}}))
    end

    test "the canvas schema rejects an image cell outside the backdrop" do
      user = AccountsFixtures.user_fixture()

      assert {:error, changeset} =
               Canvas.create_unstr_canvas(user.id, %{
                 "name" => "Broken image board",
                 "cells" => %{
                   "layout_mode" => "image",
                   "backdrop" => %{"url" => "/images/plan.png"},
                   "a" => cell(90, 0, 20, 10)
                 }
               })

      assert {"cell a extends past the backdrop", _meta} = changeset.errors[:cells]
    end

    test "the schema rejects a backdrop that is not an image URL" do
      user = AccountsFixtures.user_fixture()

      assert {:error, changeset} =
               Canvas.create_unstr_canvas(user.id, %{
                 "name" => "Broken backdrop",
                 "cells" => %{
                   "layout_mode" => "image",
                   "backdrop" => %{"url" => "javascript:alert(1)"},
                   "a" => cell(0, 0, 20, 10)
                 }
               })

      assert {"backdrop must be an image URL", _meta} = changeset.errors[:cells]
    end
  end

  describe "persistence" do
    test "an image board saves and reloads placements and the backdrop" do
      {template, user} = image_template()
      {:ok, canvas} = Canvas.instantiate_template(template, user.id)

      {:ok, _seq} =
        Canvas.apply_unstr_canvas_operation(canvas.id, user.id, %{
          "type" => "move_card",
          "cell_key" => "brief",
          "x" => 12.5,
          "y" => 20
        })

      {:ok, _seq} =
        Canvas.apply_unstr_canvas_operation(canvas.id, user.id, %{
          "type" => "set_backdrop",
          "backdrop" => %{"url" => "/images/replacement.svg", "fit" => "cover"}
        })

      cells = Canvas.get_unstr_canvas_content(canvas.id)
      assert cells["brief"]["placement"]["x"] == 12.5
      assert cells["backdrop"]["url"] == "/images/replacement.svg"
      assert cells["backdrop"]["fit"] == "cover"

      {:ok, _canvas} = Canvas.save_unstr_canvas_content_to_db(canvas.id, cells)
      reloaded = Canvas.get_unstr_canvas_content(canvas.id)
      assert reloaded["brief"]["placement"]["y"] == 20
      assert reloaded["backdrop"]["url"] == "/images/replacement.svg"
    end
  end
end
