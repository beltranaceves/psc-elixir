defmodule PscWeb.CanvasLayoutLiveTest do
  use PscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Psc.Canvas
  alias Psc.CanvasFixtures

  setup :register_and_log_in_user

  describe "index (template library)" do
    test "renders the template library page", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/templates")

      assert html =~ "Templates"
      assert html =~ "New Template"
      assert has_element?(lv, "header h1#header-page-title", "Templates")
      # The create action is the first tile of the library, not a header button.
      assert has_element?(lv, "#template-grid #new-template-card")
      refute has_element?(lv, ~s|header a[href="/templates/new"]|)
      refute has_element?(lv, "main h1")
      # Creating happens in the designer only — no duplicate inline form.
      refute html =~ "Create New Template"
      refute html =~ ~s(id="new-template-form")
    end

    test "the New Template action opens the designer", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/templates")

      {:ok, editor, _html} =
        lv
        |> element("a[href='/templates/new']")
        |> render_click()
        |> follow_redirect(conn, ~p"/templates/new")

      assert has_element?(editor, "#template-form")
    end

    test "own templates show the Owner badge", %{conn: conn, user: user} do
      CanvasFixtures.canvas_layout_fixture(%{author_id: user.id, name: "Owned Tpl"})

      {:ok, _lv, html} = live(conn, ~p"/templates")

      assert html =~ "Owned Tpl"
      assert html =~ "Owner"
    end

    test "shared templates show the Shared badge and no owner actions", %{conn: conn, user: user} do
      owner = Psc.AccountsFixtures.user_fixture()
      CanvasFixtures.canvas_layout_fixture(%{author_id: owner.id, name: "Shared Tpl"})
      template = Canvas.list_templates(owner) |> List.first()
      {:ok, _} = Canvas.share_template_with(template, user.email)

      {:ok, _lv, html} = live(conn, ~p"/templates")

      assert html =~ "Shared Tpl"
      assert html =~ "Shared"
      refute html =~ "Delete"
    end

    test "deleting requires two-step confirmation", %{conn: conn, user: user} do
      CanvasFixtures.canvas_layout_fixture(%{author_id: user.id, name: "Doomed Tpl"})
      [template] = Canvas.list_templates(user)

      {:ok, lv, _html} = live(conn, ~p"/templates")

      lv
      |> element("button[phx-click='confirm_delete'][phx-value-id='#{template.id}']")
      |> render_click()

      html =
        lv
        |> element("button[phx-click='delete_template'][phx-value-id='#{template.id}']")
        |> render_click()

      assert html =~ "Template deleted"
      refute html =~ "Doomed Tpl"
      assert Canvas.get_canvas_layout(template.id) == nil
    end

    test "instantiate creates a canvas and redirects to the editor", %{conn: conn, user: user} do
      CanvasFixtures.canvas_layout_fixture(%{author_id: user.id, name: "Instantiable"})
      [template] = Canvas.list_templates(user)

      {:ok, lv, _html} = live(conn, ~p"/templates")

      assert {:error, {:redirect, %{to: "/canvas/" <> canvas_id}}} =
               lv
               |> element("button[phx-click='instantiate'][phx-value-id='#{template.id}']")
               |> render_click()

      assert Canvas.list_user_unstr_canvases(user.id)
             |> Enum.any?(&(&1.id == canvas_id))
    end
  end

  describe "editor (designer)" do
    test "renders the new template page", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/templates/new")

      assert has_element?(lv, "#header-page-title", "Designer")
      assert has_element?(lv, ~s|a[href="/templates"][aria-current="page"]|)
      assert html =~ "Name"
      # The back link is page chrome, above the collapsible sections.
      assert has_element?(lv, ~s|a[href="/templates"]|)
      assert html =~ "Add Column"
      assert html =~ "Add Row"
    end

    test "adds a column and a row to the grid", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/templates/new")

      lv |> element("button[phx-click='add_column']") |> render_click()
      html = lv |> element("button[phx-click='add_row']") |> render_click()

      assert html =~ "Column 1"
      assert html =~ "Row 1"
    end

    test "picks the note mode and keeps it in the template", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/templates/new")

      # A new template starts with a list of notes.
      assert has_element?(lv, "#notes-mode-multi[aria-pressed='true']")
      assert has_element?(lv, "#notes-mode-single[aria-pressed='false']")

      lv |> element("#notes-mode-single") |> render_click()

      assert has_element?(lv, "#notes-mode-single[aria-pressed='true']")
      assert has_element?(lv, "#notes-mode-multi[aria-pressed='false']")

      # The mode is saved with the template.
      lv |> element("button[phx-click='add_column']") |> render_click()
      lv |> element("button[phx-click='add_row']") |> render_click()

      lv
      |> form("#template-form", %{"name" => "Scratchpad Tpl", "description" => ""})
      |> render_submit()

      assert [template] = Canvas.list_templates(user)
      assert template.layout_map["notes_mode"] == "single"

      # And it comes back when the template is opened again.
      {:ok, lv, _html} = live(conn, ~p"/templates/#{template.id}")
      assert has_element?(lv, "#notes-mode-single[aria-pressed='true']")
    end

    test "a canvas made from a scratchpad template is a scratchpad", %{user: user} do
      template =
        CanvasFixtures.canvas_layout_fixture(%{
          author_id: user.id,
          layout_map:
            Map.put(CanvasFixtures.template_layout_map_fixture(), "notes_mode", "single")
        })

      {:ok, canvas} = Canvas.instantiate_template(template, user.id)

      assert canvas.notes_mode == "single"
    end

    test "a template can carry notes, and a canvas inherits them", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/templates/new")

      lv |> element("button[phx-click='add_column']") |> render_click()
      lv |> element("button[phx-click='add_row']") |> render_click()
      lv |> element("button[phx-click='add_note']") |> render_click()

      assert has_element?(lv, "#template-notes-list")

      lv
      |> form("#template-note-0-title-form", %{"index" => "0", "value" => "Framing questions"})
      |> render_change()

      lv
      |> form("#template-note-0-content-form", %{
        "index" => "0",
        "content" => "What is the actual problem?"
      })
      |> render_change()

      lv
      |> form("#template-form", %{"name" => "Notes Tpl", "description" => ""})
      |> render_submit()

      assert [template] = Canvas.list_templates(user)

      assert [%{"title" => "Framing questions", "content" => content}] =
               template.layout_map["notes"]

      assert content == "What is the actual problem?"

      # A canvas made from it starts with a copy of the note.
      {:ok, canvas} = Canvas.instantiate_template(template, user.id)

      assert [note] = Psc.Notes.list_notes(canvas.id)
      assert note.title == "Framing questions"
      assert Psc.Notes.get_note_content(note.id) == "What is the actual problem?"

      # The copy is independent: editing the canvas's note leaves the template
      # alone.
      assert {:ok, _note} = Psc.Notes.update_note(note, %{content: "Changed"})

      assert template.layout_map["notes"] == [
               %{"title" => "Framing questions", "content" => content}
             ]
    end

    test "switching a template to the scratchpad mode keeps only the first note", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/templates/new")

      lv |> element("button[phx-click='add_note']") |> render_click()
      lv |> element("button[phx-click='add_note']") |> render_click()
      assert has_element?(lv, "#template-note-0")
      assert has_element?(lv, "#template-note-1")

      lv |> element("#notes-mode-single") |> render_click()

      assert has_element?(lv, "#template-note-0")
      refute has_element?(lv, "#template-note-1")
    end

    test "a scratchpad always has one note to write its starting content into", %{
      conn: conn,
      user: user
    } do
      {:ok, lv, _html} = live(conn, ~p"/templates/new")

      # A fresh template has no notes, and the scratchpad mode has no
      # "Add note" action — so switching modes has to make the note itself.
      refute has_element?(lv, "#template-note-0")

      lv |> element("#notes-mode-single") |> render_click()

      assert has_element?(lv, "#template-note-0")
      assert has_element?(lv, "#template-note-0-input")

      lv
      |> form("#template-note-0-content-form", %{"index" => "0", "content" => "Start here."})
      |> render_change()

      lv |> element("button[phx-click='add_column']") |> render_click()
      lv |> element("button[phx-click='add_row']") |> render_click()

      lv
      |> form("#template-form", %{"name" => "Scratchpad Tpl", "description" => ""})
      |> render_submit()

      assert [template] = Canvas.list_templates(user)
      assert template.layout_map["notes_mode"] == "single"

      assert template.layout_map["notes"] == [
               %{"title" => "", "content" => "Start here."}
             ]
    end

    test "the note editor previews its Markdown while it is not in focus", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/templates/new")

      lv |> element("button[phx-click='add_note']") |> render_click()
      lv |> element("button[phx-click='add_column']") |> render_click()
      lv |> element("button[phx-click='add_row']") |> render_click()

      lv
      |> form("#template-note-0-content-form", %{"index" => "0", "content" => "# Framing"})
      |> render_change()

      # The editor starts as a preview: the rendered Markdown, not the text.
      assert has_element?(lv, "#template-note-0-preview")
      assert has_element?(lv, "#template-note-0-input")
      assert has_element?(lv, "#template-note-0-preview", "The note is empty.")

      # Blurring the textarea asks the server to re-render, and the reply is
      # pushed back to that one editor.
      lv |> render_click("render_template_note", %{"index" => "0", "content" => "# Framing"})

      assert_push_event(lv, "template_note_0_rendered", %{content: "# Framing", html: html})
      assert html =~ "<h1"
    end

    test "edits cell details directly in the grid", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/templates/new")

      lv |> element("button[phx-click='add_column']") |> render_click()
      lv |> element("button[phx-click='add_row']") |> render_click()

      # No selection step: the label, field defaults and the add-field form are
      # all inside the cell itself.
      assert has_element?(lv, "#cell-r1_c1-label")
      assert has_element?(lv, "#cell-r1_c1-field-content")
      assert has_element?(lv, "#cell-r1_c1 form[phx-submit='add_cell_field']")
      assert has_element?(lv, "#cell-r1_c1-new-field")

      refute has_element?(lv, "button[phx-click='select_cell']")
      refute has_element?(lv, "#cell-r1_c1-label[placeholder='Cell label']")

      # Fresh cells have no label, so the cell key is the placeholder.
      assert has_element?(lv, "#cell-r1_c1-label[placeholder='r1_c1']")

      # Editing the label happens in place. The wrapping form serializes the
      # hidden cell_key/field inputs alongside the value.
      html =
        lv
        |> element("#cell-r1_c1 form[phx-change='update_cell_meta']")
        |> render_change(%{"value" => "Problem", "cell_key" => "r1_c1", "field" => "label"})

      assert html =~ ~s(value="Problem")
    end

    test "adds a field directly in the cell", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/templates/new")

      lv |> element("button[phx-click='add_column']") |> render_click()
      lv |> element("button[phx-click='add_row']") |> render_click()

      html =
        lv
        |> element("#cell-r1_c1 form[phx-submit='add_cell_field']")
        |> render_submit(%{"field" => "notes"})

      assert html =~ "notes"
      assert has_element?(lv, "#cell-r1_c1-field-notes")
    end

    test "sets an optional section title per field", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/templates/new")

      lv |> element("button[phx-click='add_column']") |> render_click()
      lv |> element("button[phx-click='add_row']") |> render_click()

      # The conventional content field starts untitled: the key is the
      # placeholder, the value is empty so no heading is rendered downstream.
      assert has_element?(lv, "#cell-r1_c1-field-content-title[placeholder='content']")
      assert has_element?(lv, ~s|#cell-r1_c1-field-content-title[value=""]|)

      html =
        lv
        |> element("#cell-r1_c1-field-content-title-form")
        |> render_change(%{
          "value" => "Problem statement",
          "cell_key" => "r1_c1",
          "field" => "content"
        })

      assert html =~ "Problem statement"
      assert has_element?(lv, "#unsaved-changes-hint")

      # Clearing the title is allowed and stored explicitly.
      lv
      |> element("#cell-r1_c1-field-content-title-form")
      |> render_change(%{"value" => "", "cell_key" => "r1_c1", "field" => "content"})

      assert has_element?(lv, ~s|#cell-r1_c1-field-content-title[value=""]|)
    end

    test "tracks unsaved changes and cancels cleanly when there are none", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/templates/new")

      # Nothing edited yet: no dirty badge and no confirmation needed.
      refute has_element?(lv, "#unsaved-changes-hint")

      assert {:error, {:live_redirect, %{to: "/templates"}}} =
               lv |> element("#cancel-template-editing") |> render_click()
    end

    test "asks for confirmation in a modal before discarding a dirty draft", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/templates/new")

      lv |> element("button[phx-click='add_column']") |> render_click()

      # Cancel opens the modal instead of navigating straight away.
      html = lv |> element("#cancel-template-editing") |> render_click()
      assert html =~ "Discard unsaved changes?"
      assert has_element?(lv, "#discard-template-dialog[data-open='true']")

      # "Keep editing" returns to the draft with the dialog closed.
      lv |> element("#keep-editing-template") |> render_click()
      refute has_element?(lv, "#discard-template-dialog[data-open='true']")
      assert has_element?(lv, "#cancel-template-editing")

      # "Discard and leave" is what actually navigates away.
      lv |> element("#cancel-template-editing") |> render_click()

      assert {:error, {:live_redirect, %{to: "/templates"}}} =
               lv |> element("#discard-template-changes") |> render_click()
    end

    test "a closed discard dialog resets the pending confirmation", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/templates/new")

      lv |> element("button[phx-click='add_column']") |> render_click()
      lv |> element("button[phx-click='add_row']") |> render_click()
      lv |> element("#cancel-template-editing") |> render_click()
      assert has_element?(lv, "#discard-template-dialog[data-open='true']")

      # Escape / outside click / × reach the server as this mapped event.
      render_hook(lv, "leave_dialog_closed", %{})

      refute has_element?(lv, "#discard-template-dialog[data-open='true']")
      assert has_element?(lv, "#cell-r1_c1-label")
    end

    test "marks the draft dirty when the template name changes", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/templates/new")

      lv
      |> form("#template-form", %{"name" => "Draft", "description" => ""})
      |> render_change()

      assert has_element?(lv, "#unsaved-changes-hint")
    end

    test "shares a template through the modal", %{conn: conn, user: user} do
      template =
        CanvasFixtures.canvas_layout_fixture(%{author_id: user.id, name: "Shareable Tpl"})

      {:ok, lv, _html} = live(conn, ~p"/templates/#{template.id}")

      # Combo button: share icon + current label.
      assert has_element?(lv, "#share-template-button .hero-share")
      assert lv |> element("#share-template-button") |> render() =~ "Share"

      refute has_element?(lv, "#share-template-dialog[data-open='true']")
      lv |> element("#share-template-button") |> render_click()
      assert has_element?(lv, "#share-template-dialog[data-open='true']")

      html =
        lv
        |> form("#share-template-dialog-form", %{"email" => "friend@example.com"})
        |> render_submit()

      assert html =~ "Template shared with friend@example.com"
      assert has_element?(lv, ~s|#share-template-dialog [data-email="friend@example.com"]|)

      # The modal stays open so several people can be invited; Done closes it.
      lv
      |> element(~s|#share-template-dialog [data-email="friend@example.com"] button|)
      |> render_click()

      refute has_element?(lv, ~s|#share-template-dialog [data-email="friend@example.com"]|)

      lv |> element("#share-template-dialog button[phx-click='share_closed']") |> render_click()
      refute has_element?(lv, "#share-template-dialog[data-open='true']")
    end

    test "removes rows and columns with the same compact × control", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/templates/new")

      lv |> element("button[phx-click='add_column']") |> render_click()
      lv |> element("button[phx-click='add_row']") |> render_click()
      lv |> element("button[phx-click='add_row']") |> render_click()

      # Both axes expose the same × affordance in the header row.
      assert has_element?(lv, "#remove-row-r1[title='Remove row']")
      assert has_element?(lv, "#remove-column-c1[title='Remove column']")
      assert lv |> element("#remove-row-r1") |> render() =~ "hero-x-mark"

      html = lv |> element("#remove-row-r1") |> render_click()

      refute html =~ "Row 1"
      assert html =~ "Row 2"
      refute has_element?(lv, "#remove-row-r1")
    end

    test "saves a new template and redirects to the library", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/templates/new")

      lv |> element("button[phx-click='add_column']") |> render_click()
      lv |> element("button[phx-click='add_row']") |> render_click()

      assert {:error, {:redirect, %{to: "/templates"}}} =
               lv
               |> form("#template-form", %{"name" => "Saved Tpl", "description" => "desc"})
               |> render_submit()

      {:ok, _lv, html} = live(conn, ~p"/templates")
      assert html =~ "Saved Tpl"
      assert Canvas.list_templates(user) |> Enum.any?(&(&1.name == "Saved Tpl"))
    end

    test "the header reads Designer while the Templates nav stays current", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/templates/new")

      # Header title is the surface, not the record…
      assert has_element?(lv, "#header-page-title", "Designer")
      # …while the route highlight stays on the Templates section.
      assert has_element?(lv, ~s|a[href="/templates"][aria-current="page"]|)
      # No in-page title block; the shared header owns the page heading.
      refute has_element?(lv, "main h1")

      lv |> form("#template-form", %{"name" => "Rationale map"}) |> render_change()

      assert has_element?(lv, "#header-page-title", "Designer")
      refute has_element?(lv, "#header-page-title", "Rationale map")
    end

    test "editing an existing template loads its structure", %{conn: conn, user: user} do
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id, name: "Loaded Tpl"})

      {:ok, lv, html} = live(conn, ~p"/templates/#{template.id}")

      assert has_element?(lv, "#header-page-title", "Designer")
      # Share is page chrome, above the collapsible sections.
      assert has_element?(lv, "#share-template-button .hero-share")
      assert html =~ "Loaded Tpl"
      assert html =~ "Row 1"
      assert html =~ "Column 1"
    end

    test "sets row and column accents and saves them with the layout", %{
      conn: conn,
      user: user
    } do
      {:ok, lv, _html} = live(conn, ~p"/templates/new")

      lv |> element("button[phx-click='add_column']") |> render_click()
      lv |> element("button[phx-click='add_row']") |> render_click()

      # The swatch toggles the inline palette; choosing a color closes it and
      # paints the header bar immediately (live preview before saving).
      refute has_element?(lv, "#accent-picker-column-c1")
      lv |> element("#accent-swatch-column-c1") |> render_click()
      assert has_element?(lv, "#accent-picker-column-c1")

      html = lv |> element("#accent-option-column-c1-sky") |> render_click()
      refute has_element?(lv, "#accent-picker-column-c1")
      assert html =~ ~s(id="accent-bar-column-c1")
      assert html =~ "bg-sky-400"

      lv |> element("#accent-swatch-row-r1") |> render_click()
      html = lv |> element("#accent-option-row-r1-amber") |> render_click()
      assert html =~ ~s(id="accent-bar-row-r1")
      assert html =~ "bg-amber-400"

      assert {:error, {:redirect, %{to: "/templates"}}} =
               lv
               |> form("#template-form", %{"name" => "Accented Tpl", "description" => "desc"})
               |> render_submit()

      template = Canvas.list_templates(user) |> Enum.find(&(&1.name == "Accented Tpl"))
      assert hd(template.layout_map["columns"])["accent"] == "sky"
      assert hd(template.layout_map["rows"])["accent"] == "amber"

      {:ok, lv, html} = live(conn, ~p"/templates/#{template.id}")
      assert html =~ ~s(id="accent-bar-column-c1")
      assert html =~ ~s(id="accent-bar-row-r1")
      assert has_element?(lv, "#accent-bar-column-c1.bg-sky-400")
      assert has_element?(lv, "#accent-bar-row-r1.bg-amber-400")
    end

    test "clearing an accent removes the bar", %{conn: conn, user: user} do
      layout_map =
        CanvasFixtures.template_layout_map_fixture()
        |> Map.update!("columns", fn columns ->
          List.update_at(columns, 0, &Map.put(&1, "accent", "sky"))
        end)

      template =
        CanvasFixtures.canvas_layout_fixture(%{
          author_id: user.id,
          name: "Clearing Tpl",
          layout_map: layout_map
        })

      {:ok, lv, html} = live(conn, ~p"/templates/#{template.id}")
      assert html =~ ~s(id="accent-bar-column-c1")

      lv |> element("#accent-swatch-column-c1") |> render_click()

      html =
        lv
        |> element("button[phx-click='set_column_accent'][phx-value-accent='']")
        |> render_click()

      refute html =~ ~s(id="accent-bar-column-c1")

      assert {:error, {:redirect, %{to: "/templates"}}} =
               lv
               |> form("#template-form", %{"name" => "Clearing Tpl"})
               |> render_submit()

      {:ok, _lv, html} = live(conn, ~p"/templates/#{template.id}")
      refute html =~ ~s(id="accent-bar-column-c1")
    end

    test "non-owner without access is redirected", %{conn: conn} do
      stranger = Psc.AccountsFixtures.user_fixture()
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: stranger.id})

      assert {:error, {:redirect, %{to: "/templates"}}} =
               live(conn, ~p"/templates/#{template.id}")
    end

    test "shared non-owner sees read-only view without save controls", %{conn: conn, user: user} do
      owner = Psc.AccountsFixtures.user_fixture()
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: owner.id, name: "RO Tpl"})
      {:ok, _} = Canvas.share_template_with(template, user.email)

      {:ok, _lv, html} = live(conn, ~p"/templates/#{template.id}")

      assert html =~ "read-only"
      refute html =~ "Save Template"
      refute html =~ "Add Column"
    end
  end
end
