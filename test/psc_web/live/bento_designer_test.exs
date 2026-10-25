defmodule PscWeb.BentoDesignerTest do
  use PscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Psc.Canvas
  alias Psc.Canvas.Structure

  setup :register_and_log_in_user

  test "the library offers the bento board in the New Template picker", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/templates")

    assert has_element?(view, "#new-template-card")

    view |> element("#new-template-card") |> render_click()

    assert has_element?(view, "#new-template-mode-bento[href='/templates/new?mode=bento']")
    refute has_element?(view, "#new-bento-template-card")
  end

  test "a new bento template starts with one card on a 12-column board", %{
    conn: conn,
    user: user
  } do
    {:ok, view, _html} = live(conn, ~p"/templates/new?mode=bento")

    assert has_element?(view, "#designer-bento")
    assert has_element?(view, "#bento-card-card1")
    assert has_element?(view, ~s|#designer-bento-columns[value="12"]|)
    assert has_element?(view, ~s|#designer-bento-rows[value="4"]|)
    assert has_element?(view, "#designer-size-card1", "6 × 2")
    assert has_element?(view, "#card-card1-label")
    refute has_element?(view, "#template-grid table")

    # The board section reports what is in it.
    assert render(view) =~ "1 card on 12 columns"

    view
    |> form("#template-form", %{"name" => "Bento #{user.id}", "description" => ""})
    |> render_submit()

    assert_redirect(view, ~p"/templates")

    template = Canvas.list_templates(user) |> Enum.find(&(&1.name == "Bento #{user.id}"))
    assert template
    assert Structure.mode(template.layout_map) == :bento
    assert Enum.map(Structure.cards(template.layout_map), & &1.key) == ["card1"]
  end

  test "cards can be added, renamed, resized and coloured", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/templates/new?mode=bento")

    view |> element("#designer-add-card") |> render_click()
    assert has_element?(view, "#bento-card-card2")

    view |> form("#card-label-card2", %{"value" => "Decision"}) |> render_change()

    # Arrow keys on the move grip: one unit left, then shift+down to grow.
    view
    |> element("#designer-move-card2")
    |> render_keydown(%{"key" => "ArrowLeft"})

    view
    |> element("#designer-move-card2")
    |> render_keydown(%{"key" => "ArrowDown", "shiftKey" => true})

    view |> element("#card-accent-card2") |> render_click()
    view |> element(~s|button[phx-value-accent="teal"]|) |> render_click()

    # The card reports its own grid, including the half row.
    assert has_element?(view, "#designer-size-card2", "6 × 2.5")

    view
    |> form("#template-form", %{"name" => "Bento shape #{user.id}", "description" => ""})
    |> render_submit()

    template = Canvas.list_templates(user) |> Enum.find(&(&1.name == "Bento shape #{user.id}"))
    card = Structure.card(template.layout_map, "card2")

    assert card.label == "Decision"
    assert {card.x, card.y, card.w, card.h} == {5.5, 0, 6, 2.5}
    assert card.accent == "teal"
  end

  test "a dragged card keeps a half-unit position through a save", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/templates/new?mode=bento")

    view
    |> form("#designer-columns-form", %{"value" => "12"})
    |> render_change()

    render_hook(view, "move_card", %{"cell_key" => "card1", "x" => 2.5, "y" => 1.5})

    assert has_element?(view, "#designer-size-card1", "6 × 2")
    assert has_element?(view, ~s|#bento-card-card1[style*="grid-column: 6 / span 12"]|)

    view
    |> form("#template-form", %{"name" => "Bento half #{user.id}", "description" => ""})
    |> render_submit()

    template = Canvas.list_templates(user) |> Enum.find(&(&1.name == "Bento half #{user.id}"))
    card = Structure.card(template.layout_map, "card1")

    assert {card.x, card.y} == {2.5, 1.5}
  end

  test "a card can take another field and its section title", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/templates/new?mode=bento")

    view |> form("#cell-card1-add-field-form", %{"field" => "evidence"}) |> render_submit()
    assert has_element?(view, "#cell-card1-field-evidence")

    view
    |> form("#cell-card1-field-evidence-title-form", %{"value" => "Evidence"})
    |> render_change()

    view
    |> form("#template-form", %{"name" => "Bento fields #{user.id}", "description" => ""})
    |> render_submit()

    template = Canvas.list_templates(user) |> Enum.find(&(&1.name == "Bento fields #{user.id}"))
    cell = Structure.cell(template.layout_map, "card1")

    assert "evidence" in cell["fields"]
    assert cell["titles"]["evidence"] == "Evidence"
  end

  test "the last card cannot be removed", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/templates/new?mode=bento")

    view |> element("#designer-remove-card1") |> render_click()

    # A template needs at least one card to be valid, so the designer keeps the
    # last one rather than letting a save fail later.
    assert has_element?(view, "#bento-card-card1")
  end

  test "the template's board size is editable and saved", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/templates/new?mode=bento")

    render_change(view, "set_bento_columns", %{"value" => "16"})
    render_change(view, "set_bento_rows", %{"value" => "10"})

    assert has_element?(view, ~s|#designer-bento-columns[value="16"]|)
    assert has_element?(view, ~s|#designer-bento-rows[value="10"]|)

    view
    |> form("#template-form", %{"name" => "Bento size #{user.id}", "description" => ""})
    |> render_submit()

    template = Canvas.list_templates(user) |> Enum.find(&(&1.name == "Bento size #{user.id}"))
    assert template.layout_map["bento_columns"] == 16
    assert template.layout_map["bento_rows"] == 10

    {:ok, canvas} = Canvas.instantiate_template(template, user.id)
    cells = Canvas.get_unstr_canvas_content(canvas.id)
    assert Structure.columns(cells) == 16
    assert Structure.rows(cells) == 10
  end

  test "a saved bento template instantiates a bento canvas", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/templates/new?mode=bento")

    view |> element("#designer-add-card") |> render_click()

    view
    |> form("#template-form", %{"name" => "Bento live #{user.id}", "description" => ""})
    |> render_submit()

    template = Canvas.list_templates(user) |> Enum.find(&(&1.name == "Bento live #{user.id}"))
    {:ok, canvas} = Canvas.instantiate_template(template, user.id)

    cells = Canvas.get_unstr_canvas_content(canvas.id)
    assert Structure.mode(cells) == :bento
    assert Enum.map(Structure.cards(cells), & &1.key) == ["card1", "card2"]
    assert cells["card1"]["placement"] == %{"x" => 0, "y" => 0, "w" => 6, "h" => 2}

    # And the canvas editor renders the board, not the table.
    {:ok, editor, _html} = live(conn, ~p"/canvas/#{canvas.id}")
    assert has_element?(editor, "#bento-board")
    assert has_element?(editor, "#bento-card-card1")
  end
end
