defmodule PscWeb.DocumentLiveTest do
  use PscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Psc.Documents
  alias Psc.DocumentsFixtures

  setup :register_and_log_in_user

  describe "index" do
    test "renders the documents page", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/documents")

      assert html =~ "My Documents"
      # Documents is parked: the page is reachable but not linked from the nav.
      refute has_element?(lv, ~s|nav a[href="/documents"]|)
    end

    test "shows the new-document form when requested", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/documents")

      refute has_element?(lv, "#new-document-form")

      lv |> element("button[phx-click='show_new_form']") |> render_click()

      assert has_element?(lv, "#new-document-form")
      assert has_element?(lv, "#new-document-title")
    end

    test "lists only the current user's documents", %{conn: conn, user: user} do
      DocumentsFixtures.document_fixture(%{user: user, title: "My own document"})
      DocumentsFixtures.document_fixture(%{title: "Someone elses document"})

      {:ok, _lv, html} = live(conn, ~p"/documents")

      assert html =~ "My own document"
      refute html =~ "Someone elses document"
    end

    test "shows an empty state when the user has no documents", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/documents")

      assert html =~ "No documents yet"
    end
  end

  describe "create_document" do
    test "creates a document via the form and persists it", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/documents")

      lv |> element("button[phx-click='show_new_form']") |> render_click()
      lv |> element("#new-document-form") |> render_change(%{"title" => "Fresh document"})
      lv |> element("#new-document-form") |> render_submit(%{"title" => "Fresh document"})

      assert [document] = Documents.list_user_documents(user.id)
      assert document.title == "Fresh document"
    end

    test "rejects a blank title", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/documents")

      lv |> element("button[phx-click='show_new_form']") |> render_click()
      lv |> element("#new-document-form") |> render_submit(%{"title" => "   "})

      assert Documents.list_user_documents(user.id) == []
    end
  end

  describe "editor" do
    test "renders Markdown content in the inline preview", %{conn: conn, user: user} do
      document = DocumentsFixtures.document_fixture(%{user: user})
      {:ok, _document} = Documents.save_content_to_db(document.id, "# Project notes\n\n**Ready**")

      {:ok, lv, html} = live(conn, ~p"/documents/#{document.id}")

      assert has_element?(lv, "#document-editor[phx-hook='DocumentEditorHook']")
      assert has_element?(lv, "#document-markdown-preview")
      assert has_element?(lv, "#editor-form")
      assert html =~ "<h1>\nProject notes</h1>"
      assert html =~ "<strong>Ready</strong>"
    end

    test "debounces content changes on the server round trip", %{conn: conn, user: user} do
      document = DocumentsFixtures.document_fixture(%{user: user})
      {:ok, lv, _html} = live(conn, ~p"/documents/#{document.id}")

      assert has_element?(lv, "#editor-form[phx-debounce='300']")
    end

    test "a paste becomes a single event row", %{conn: conn, user: user} do
      document = DocumentsFixtures.document_fixture(%{user: user})
      {:ok, lv, _html} = live(conn, ~p"/documents/#{document.id}")

      pasted = String.duplicate("pasted text ", 1_000)

      lv
      |> element("#editor-form")
      |> render_change(%{"content" => pasted})

      assert Documents.pending_event_count(document.id) == 1
      assert Documents.get_document_content(document.id) == pasted
    end

    test "typing one character at a time still coalesces per change", %{conn: conn, user: user} do
      document = DocumentsFixtures.document_fixture(%{user: user})
      {:ok, lv, _html} = live(conn, ~p"/documents/#{document.id}")

      for i <- 1..3 do
        lv
        |> element("#editor-form")
        |> render_change(%{"content" => String.duplicate("a", i)})
      end

      assert Documents.pending_event_count(document.id) == 3
    end

    test "folds pending events into content once the threshold is reached", %{
      conn: conn,
      user: user
    } do
      document = DocumentsFixtures.document_fixture(%{user: user})
      {:ok, lv, _html} = live(conn, ~p"/documents/#{document.id}")

      # One operation per change, below the 500 threshold: events accumulate
      for i <- 1..499 do
        lv
        |> element("#editor-form")
        |> render_change(%{"content" => String.duplicate("a", i)})
      end

      assert Documents.pending_event_count(document.id) == 499
      assert Documents.get_document_content(document.id) == String.duplicate("a", 499)

      # Crossing the threshold folds immediately instead of waiting for idle
      lv
      |> element("#editor-form")
      |> render_change(%{"content" => String.duplicate("a", 500)})

      assert Documents.pending_event_count(document.id) == 0
      assert Documents.get_document_content(document.id) == String.duplicate("a", 500)
    end

    test "shares a document through the modal", %{conn: conn, user: user} do
      document = DocumentsFixtures.document_fixture(%{user: user})
      {:ok, lv, _html} = live(conn, ~p"/documents/#{document.id}")

      assert has_element?(lv, "#share-document-button .hero-share")
      lv |> element("#share-document-button") |> render_click()
      assert has_element?(lv, "#share-document-dialog[data-open='true']")

      html =
        lv
        |> form("#share-document-dialog-form", %{"email" => "pal@example.com"})
        |> render_submit()

      assert html =~ "Document shared with pal@example.com"
      assert has_element?(lv, ~s|#share-document-dialog [data-email="pal@example.com"]|)

      # The modal also carries the shareable link.
      assert has_element?(lv, "#share-document-dialog-link[value='/documents/#{document.id}']")
    end
  end
end
