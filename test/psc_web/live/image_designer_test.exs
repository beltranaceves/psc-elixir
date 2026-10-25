defmodule PscWeb.ImageDesignerTest do
  use PscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Psc.Canvas
  alias Psc.Canvas.Structure

  setup :register_and_log_in_user

  test "the library offers the image board in the New Template picker", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/templates")

    assert has_element?(view, "#new-template-card")

    view |> element("#new-template-card") |> render_click()

    assert has_element?(view, "#new-template-mode-image[href='/templates/new?mode=image']")
    refute has_element?(view, "#new-image-template-card")
  end

  test "a new image template starts with the sample picture and two cells", %{
    conn: conn,
    user: user
  } do
    {:ok, view, _html} = live(conn, ~p"/templates/new?mode=image")

    assert has_element?(view, "#designer-image")
    assert has_element?(view, "#image-cell-card1")
    assert has_element?(view, "#image-cell-text1")
    assert has_element?(view, "#designer-add-cell")
    assert has_element?(view, "#designer-add-text")
    refute has_element?(view, "#template-grid table")
    refute has_element?(view, "#designer-bento")

    assert has_element?(
             view,
             ~s|#designer-backdrop-url[value="/images/image-board-blueprint.svg"]|
           )

    assert has_element?(view, "#designer-image-size", "2 cells on a picture")
    assert render(view) =~ "2 cells on a picture"

    # The text cell previews what it will look like on the canvas.
    assert has_element?(view, "#designer-image-text-preview-text1")

    view
    |> form("#template-form", %{"name" => "Picture #{user.id}", "description" => ""})
    |> render_submit()

    assert_redirect(view, ~p"/templates")

    template = Canvas.list_templates(user) |> Enum.find(&(&1.name == "Picture #{user.id}"))
    assert template
    assert Structure.mode(template.layout_map) == :image
    assert Structure.backdrop(template.layout_map).url == Canvas.image_backdrop_url()
    assert Enum.map(Structure.cards(template.layout_map), & &1.key) == ["card1", "text1"]
    assert Enum.map(Structure.cards(template.layout_map), & &1.kind) == ["card", "text"]
  end

  test "cells can be added, renamed, moved, resized and turned into text", %{
    conn: conn,
    user: user
  } do
    {:ok, view, _html} = live(conn, ~p"/templates/new?mode=image")

    view |> element("#designer-add-cell") |> render_click()
    assert has_element?(view, "#image-cell-card2")

    view |> element("#designer-add-text") |> render_click()
    assert has_element?(view, "#image-cell-text2")
    assert has_element?(view, "#designer-image-text-preview-text2")

    view
    |> form("#image-label-card2", %{"value" => "Entrance"})
    |> render_change()

    # Arrow keys on the move grip: half a percent left, then shift+down to grow.
    view
    |> element("#designer-image-move-card2")
    |> render_keydown(%{"key" => "ArrowLeft"})

    view
    |> element("#designer-image-move-card2")
    |> render_keydown(%{"key" => "ArrowDown", "shiftKey" => true})

    view |> element("#designer-image-kind-card2") |> render_click()
    view |> element("#designer-image-kind-card2") |> render_click()

    view |> element("#designer-image-accent-card2") |> render_click()
    view |> element(~s|button[phx-value-accent="teal"]|) |> render_click()

    view |> form("#cell-card2-add-field-form", %{"field" => "note"}) |> render_submit()

    assert has_element?(view, "#cell-card2-field-note")

    view
    |> form("#template-form", %{"name" => "Picture shape #{user.id}", "description" => ""})
    |> render_submit()

    template = Canvas.list_templates(user) |> Enum.find(&(&1.name == "Picture shape #{user.id}"))
    assert template

    card = Structure.card(template.layout_map, "card2")
    assert card.label == "Entrance"

    # The new cell starts in the first free slot, then the keyboard steps it.
    assert card.x == 0.0
    assert card.y == 0.0
    assert card.h == 12.5
    assert card.accent == "teal"
    assert card.kind == "card"

    text = Structure.card(template.layout_map, "text2")
    assert text.kind == "text"
  end

  test "a cell keeps a half-percent placement through a save", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/templates/new?mode=image")

    render_hook(view, "move_card", %{"cell_key" => "card1", "x" => 12.5, "y" => 22.5})

    assert has_element?(view, "#designer-image-size-card1", "26 × 18%")
    assert has_element?(view, ~s|#image-cell-card1[style*="left: 12.5%"]|)

    view
    |> form("#template-form", %{"name" => "Picture half #{user.id}", "description" => ""})
    |> render_submit()

    template = Canvas.list_templates(user) |> Enum.find(&(&1.name == "Picture half #{user.id}"))
    card = Structure.card(template.layout_map, "card1")
    assert {card.x, card.y} == {12.5, 22.5}
  end

  test "the backdrop is part of the template and must be an image", %{
    conn: conn,
    user: user
  } do
    {:ok, view, _html} = live(conn, ~p"/templates/new?mode=image")

    view
    |> form("#designer-backdrop-form", %{
      "url" => "https://example.com/plan.svg",
      "fit" => "cover",
      "aspect" => "4:3",
      "alt" => "Plan"
    })
    |> render_change()

    assert has_element?(view, ~s|#designer-image img[src="https://example.com/plan.svg"]|)
    assert has_element?(view, ~s|#designer-image[style*="aspect-ratio"]|)

    # An unsafe URL never replaces the stored picture.
    view
    |> form("#designer-backdrop-form", %{"url" => "javascript:alert(1)"})
    |> render_change()

    assert has_element?(view, ~s|#designer-image img[src="https://example.com/plan.svg"]|)

    view
    |> form("#template-form", %{"name" => "Picture backdrop #{user.id}", "description" => ""})
    |> render_submit()

    template =
      Canvas.list_templates(user) |> Enum.find(&(&1.name == "Picture backdrop #{user.id}"))

    backdrop = Structure.backdrop(template.layout_map)
    assert backdrop.url == "https://example.com/plan.svg"
    assert backdrop.fit == "cover"
    assert backdrop.alt == "Plan"
    assert_in_delta backdrop.aspect, 4 / 3, 0.0001
  end

  test "a template without a backdrop cannot be saved", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/templates/new?mode=image")

    view
    |> form("#designer-backdrop-form", %{"url" => ""})
    |> render_change()

    refute has_element?(view, ~s|#designer-image img|)

    view
    |> form("#template-form", %{"name" => "Picture blank #{user.id}", "description" => ""})
    |> render_submit()

    refute Canvas.list_templates(user) |> Enum.find(&(&1.name == "Picture blank #{user.id}"))
    assert render(view) =~ "Failed to save template"
  end

  test "a saved image template produces an image canvas", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/templates/new?mode=image")

    view
    |> element("#designer-add-text")
    |> render_click()

    view
    |> form("#template-form", %{"name" => "Picture copy #{user.id}", "description" => ""})
    |> render_submit()

    template = Canvas.list_templates(user) |> Enum.find(&(&1.name == "Picture copy #{user.id}"))
    {:ok, canvas} = Canvas.instantiate_template(template, user.id)

    assert Structure.mode(canvas.cells) == :image
    assert canvas.cells["backdrop"]["url"] == Canvas.image_backdrop_url()
    assert canvas.cells["text1"]["kind"] == "text"
    assert canvas.cells["text1"]["placement"] == %{"x" => 38, "y" => 76, "w" => 24, "h" => 8}

    {:ok, live_view, _html} = live(conn, ~p"/canvas/#{canvas.id}")
    assert has_element?(live_view, "#image-board")
    assert has_element?(live_view, "#text-cell-text1")
  end
end
