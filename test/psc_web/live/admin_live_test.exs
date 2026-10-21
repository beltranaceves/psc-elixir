defmodule PscWeb.AdminLiveTest do
  use PscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Psc.Accounts
  alias Psc.AccountsFixtures
  alias Psc.Canvas

  setup do
    Canvas.seed_builtin_templates()
    :ok
  end

  describe "guards" do
    test "anonymous visitors are sent to the login page", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/admin")
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/admin/users")
    end

    test "members are turned away from every admin page", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)

      for path <- [
            ~p"/admin",
            ~p"/admin/users",
            ~p"/admin/templates",
            ~p"/admin/canvases",
            ~p"/admin/notes"
          ] do
        assert {:error, {:redirect, %{to: "/canvas"}}} = live(conn, path)
      end
    end
  end

  describe "as an admin" do
    setup :register_and_log_in_admin

    test "the dashboard shows the instance figures", %{conn: conn, user: admin} do
      _member = AccountsFixtures.user_fixture()

      {:ok, lv, html} = live(conn, ~p"/admin")

      assert html =~ "Administration"
      assert html =~ "Instance figures"
      assert html =~ admin.email

      # The four resource cards are the navigation into the CRUD pages.
      assert has_element?(lv, ~s|a[href="/admin/users"]|)
      assert has_element?(lv, ~s|a[href="/admin/templates"]|)
      assert has_element?(lv, ~s|a[href="/admin/canvases"]|)
      assert has_element?(lv, ~s|a[href="/admin/notes"]|)
    end

    test "the users table lists accounts", %{conn: conn, user: admin} do
      member = AccountsFixtures.user_fixture()

      {:ok, _lv, html} = live(conn, ~p"/admin/users")

      assert html =~ "Users"
      assert html =~ admin.email
      assert html =~ member.email
      assert html =~ "backpex-app-shell"
    end

    test "the templates table shows the built-in defaults", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/admin/templates")

      assert html =~ "Templates"
      assert html =~ "Problem–Solution Canvas"
      assert html =~ "Scratchpad"
    end

    test "the canvases and notes tables render", %{conn: conn} do
      {:ok, _lv, canvases_html} = live(conn, ~p"/admin/canvases")
      assert canvases_html =~ "Canvases"

      {:ok, _lv, notes_html} = live(conn, ~p"/admin/notes")
      assert notes_html =~ "Notes"
    end

    test "the template show page renders a built-in default", %{conn: conn} do
      psc = Canvas.get_template_by_slug("psc")

      {:ok, _lv, html} = live(conn, ~p"/admin/templates/#{psc.id}/show")

      assert html =~ "Problem–Solution Canvas"
    end

    test "the users changeset refuses to demote the last admin", %{user: admin} do
      assert Accounts.admin_count() == 1

      changeset = PscWeb.Admin.UserLive.changeset(admin, %{"role" => "member"}, %{})
      refute changeset.valid?
      assert changeset.errors[:role]
    end

    test "the users changeset accepts the changeset Backpex passes while validating", %{
      user: admin
    } do
      _second = AccountsFixtures.admin_fixture()

      # Backpex calls the changeset function with an `Ecto.Changeset` while the
      # form is being validated; a `%User{}`-only clause crashed here before.
      changeset =
        PscWeb.Admin.UserLive.changeset(
          Ecto.Changeset.change(admin),
          %{"role" => "member"},
          %{}
        )

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :role) == :member
    end
  end
end
