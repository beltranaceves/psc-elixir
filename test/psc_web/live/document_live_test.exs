defmodule PscWeb.DocumentLiveTest do
  use PscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Psc.Documents
  alias Psc.DocumentsFixtures

  setup :register_and_log_in_user

  describe "index" do
    test "renders the documents page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/documents")

      assert html =~ "My Documents"
    end

    test "shows the new-document form when requested", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/documents")

      refute has_element?(lv, "#new-document-form")

      lv |> element("button[phx-click='show_new_form']") |> render_click()

      assert has_element?(lv, "#new-document-form")
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
end