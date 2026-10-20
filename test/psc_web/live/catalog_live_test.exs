defmodule PscWeb.CatalogLiveTest do
  use PscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Psc.Canvas
  alias Psc.CanvasFixtures

  setup :register_and_log_in_user

  defp set_count(template, changes) do
    template |> Ecto.Changeset.change(changes) |> Psc.Repo.update!()
  end

  # The byte offset of a needle in the rendered html, so two cards can be
  # compared for order without depending on how the markup is laid out.
  defp position_of(html, needle) do
    case :binary.match(html, needle) do
      {position, _length} -> position
      :nomatch -> raise "expected #{inspect(needle)} in the rendered html"
    end
  end

  defp open_modal(lv, template) do
    lv
    |> element(~s|button[phx-click='open_template'][phx-value-id='#{template.id}']|)
    |> render_click()
  end

  describe "index" do
    test "renders the catalog, ranked by use", %{conn: conn, user: user} do
      low = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id, name: "Low"})
      high = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id, name: "High"})

      _private = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id, name: "Private"})

      {:ok, _} = Canvas.publish_template(low)
      {:ok, _} = Canvas.publish_template(high)

      _high = set_count(high, use_count: 3)
      _low = set_count(low, use_count: 1)

      {:ok, lv, html} = live(conn, ~p"/catalog")

      assert has_element?(lv, "#header-page-title", "Catalog")
      assert html =~ ~s|href="/catalog"|

      html = render(lv)
      assert position_of(html, "High") < position_of(html, "Low")
      refute html =~ "Private"
      assert html =~ "Used 3"
      assert html =~ "Used 1"
    end

    test "shows the empty state when nothing is public", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/catalog")

      assert has_element?(lv, "#catalog-grid", "No public templates yet.")
    end

    test "search narrows the list and clearing it restores the ranking", %{conn: conn, user: user} do
      named = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id, name: "Rationale map"})
      other = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id, name: "Unrelated"})

      {:ok, _} = Canvas.publish_template(named)
      {:ok, _} = Canvas.publish_template(other)

      {:ok, lv, _html} = live(conn, ~p"/catalog")

      html = lv |> form("#catalog-search", %{"q" => "rationale"}) |> render_change()
      assert html =~ "Rationale map"
      refute html =~ "Unrelated"

      html = lv |> form("#catalog-search", %{"q" => ""}) |> render_change()
      assert html =~ "Rationale map"
      assert html =~ "Unrelated"
    end

    test "a card opens the modal with the details and the grid", %{conn: conn, user: user} do
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id, name: "Detail Tpl"})
      {:ok, _} = Canvas.publish_template(template)

      {:ok, lv, _html} = live(conn, ~p"/catalog")
      refute has_element?(lv, "#catalog-template-dialog")

      html = open_modal(lv, template)

      assert has_element?(lv, ~s|#catalog-template-dialog[data-open='true']|)
      assert has_element?(lv, "#catalog-template-dialog", "Detail Tpl")
      assert has_element?(lv, "#catalog-template-dialog", "2 rows × 2 columns")
      # The grid preview is a picture of the template, not its editor.
      assert has_element?(lv, "#catalog-template-dialog", "Row 1")
      assert has_element?(lv, "#catalog-template-dialog", "Cell 1")
      assert html =~ "Used 0"
    end

    test "a fork shows its lineage", %{conn: conn, user: user} do
      source = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id, name: "Source Tpl"})
      {:ok, fork} = Canvas.fork_template(source, user.id)
      {:ok, _} = Canvas.publish_template(fork)

      {:ok, lv, _html} = live(conn, ~p"/catalog")

      open_modal(lv, fork)

      assert has_element?(lv, "#catalog-template-dialog", "Forked from Source Tpl")
    end

    test "closing the modal clears it", %{conn: conn, user: user} do
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id, name: "Closable"})
      {:ok, _} = Canvas.publish_template(template)

      {:ok, lv, _html} = live(conn, ~p"/catalog")

      open_modal(lv, template)
      assert has_element?(lv, "#catalog-template-dialog")

      lv |> render_click("close_template", %{})

      refute has_element?(lv, "#catalog-template-dialog")
    end

    test "using a template creates a canvas and counts the use", %{conn: conn, user: user} do
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id, name: "Usable Tpl"})
      {:ok, _} = Canvas.publish_template(template)

      {:ok, lv, _html} = live(conn, ~p"/catalog")

      assert {:error, {:redirect, %{to: to}}} =
               lv |> render_click("use_template", %{"id" => template.id})

      assert to =~ "/canvas/"
      assert [%{name: "Usable Tpl"}] = Canvas.list_user_unstr_canvases(user.id)
      assert Canvas.get_canvas_layout(template.id).use_count == 1
    end

    test "a template I do not own can be used from the catalog", %{conn: conn, user: user} do
      owner = Psc.AccountsFixtures.user_fixture()

      template =
        CanvasFixtures.canvas_layout_fixture(%{author_id: owner.id, name: "Not Mine"})

      {:ok, _} = Canvas.publish_template(template)

      {:ok, lv, _html} = live(conn, ~p"/catalog")

      assert {:error, {:redirect, %{to: to}}} =
               lv |> render_click("use_template", %{"id" => template.id})

      assert to =~ "/canvas/"
      assert [%{name: "Not Mine"}] = Canvas.list_user_unstr_canvases(user.id)
      assert Canvas.get_canvas_layout(template.id).use_count == 1
    end

    test "forking creates a template I own and counts the fork", %{conn: conn, user: user} do
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id, name: "Forkable"})
      {:ok, _} = Canvas.publish_template(template)

      {:ok, lv, _html} = live(conn, ~p"/catalog")

      assert {:error, {:redirect, %{to: to}}} =
               lv |> render_click("fork_template", %{"id" => template.id})

      assert to =~ "/templates/"

      assert [fork] =
               Enum.filter(Canvas.list_templates(user), &(&1.name == "Forkable (fork)"))

      assert fork.forked_from_id == template.id
      assert fork.layout_map["cells"] == template.layout_map["cells"]
      assert Canvas.get_canvas_layout(template.id).fork_count == 1
    end

    test "a private template cannot be used or forked from the catalog", %{conn: conn, user: user} do
      template = CanvasFixtures.canvas_layout_fixture(%{author_id: user.id, name: "Hidden Tpl"})

      {:ok, lv, _html} = live(conn, ~p"/catalog")

      html = lv |> render_click("use_template", %{"id" => template.id})
      assert html =~ "Template not found"
      assert Canvas.list_user_unstr_canvases(user.id) == []

      html = lv |> render_click("fork_template", %{"id" => template.id})
      assert html =~ "Template not found"
      assert Canvas.get_canvas_layout(template.id).fork_count == 0
    end
  end
end
