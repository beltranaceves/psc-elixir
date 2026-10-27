defmodule PscWeb.AdminLiveTest do
  use PscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Psc.Accounts
  alias Psc.AccountsFixtures
  alias Psc.Agent.Connections
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
            ~p"/admin/api-keys",
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
      assert has_element?(lv, ~s|a[href="/admin/api-keys"]|)
      assert has_element?(lv, ~s|a[href="/admin/canvases"]|)
      assert has_element?(lv, ~s|a[href="/admin/notes"]|)

      # A fresh instance gets the first-run callout instead of empty lists.
      assert html =~ "Nothing has been created yet."
    end

    test "the dashboard gauges both event tables against the row budget", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/admin")

      assert has_element?(lv, "#admin-dashboard")
      assert html =~ "Event log"
      assert html =~ "Canvas events"
      assert html =~ "Note events"
      assert html =~ "10,000"
    end

    test "the dashboard lists the most recent canvases", %{conn: conn, user: admin} do
      canvas = Psc.NotesFixtures.canvas_fixture(%{:user => admin, "name" => "Roadmap retro"})

      {:ok, lv, _html} = live(conn, ~p"/admin")

      assert render(lv) =~ "Roadmap retro"
      assert has_element?(lv, ~s|a[href="/admin/canvases/#{canvas.id}/show"]|)
    end

    test "the refresh control reloads the figures", %{conn: conn, user: admin} do
      {:ok, lv, _html} = live(conn, ~p"/admin")

      _canvas = Psc.NotesFixtures.canvas_fixture(%{:user => admin, "name" => "Created later"})

      refute render(lv) =~ "Created later"

      html = lv |> element("#admin-refresh") |> render_click()

      assert html =~ "Created later"
    end

    test "the users table lists accounts", %{conn: conn, user: admin} do
      member = AccountsFixtures.user_fixture()

      {:ok, _lv, html} = live(conn, ~p"/admin/users")

      assert html =~ "Users"
      assert html =~ admin.email
      assert html =~ member.email
      assert html =~ "backpex-app-shell"
      assert html =~ "Accounts"
    end

    test "the templates table shows the built-in defaults", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/admin/templates")

      assert html =~ "Templates"
      assert html =~ "Problem–Solution Canvas"
      assert html =~ "Scratchpad"
      assert html =~ "Instantiations"
    end

    test "the templates table filters by origin", %{conn: conn} do
      {:ok, _lv, html} = live(conn, "/admin/templates?filters[built_in][]=custom")

      # Every seeded default is built-in, so a custom-only listing is empty.
      refute html =~ "Problem–Solution Canvas"
    end

    test "the canvases table shows the owner", %{conn: conn} do
      owner = AccountsFixtures.user_fixture()
      _canvas = Psc.NotesFixtures.canvas_fixture(%{:user => owner, "name" => "Owned canvas"})

      {:ok, _lv, html} = live(conn, ~p"/admin/canvases")

      assert html =~ "Owned canvas"
      assert html =~ owner.email
    end

    test "the notes table shows the author", %{conn: conn, user: admin} do
      _note = Psc.NotesFixtures.note_fixture(%{user: admin, title: "Authored note"})

      {:ok, _lv, html} = live(conn, ~p"/admin/notes")

      assert html =~ "Authored note"
      assert html =~ admin.email
    end

    test "the canvases and notes tables render", %{conn: conn} do
      {:ok, _lv, canvases_html} = live(conn, ~p"/admin/canvases")
      assert canvases_html =~ "Canvases"

      {:ok, _lv, notes_html} = live(conn, ~p"/admin/notes")
      assert notes_html =~ "Notes"
    end

    test "every resource exposes filters or metrics" do
      assert PscWeb.Admin.UserLive.filters()[:role].module == PscWeb.Admin.Filters.UserRole

      assert PscWeb.Admin.TemplateLive.filters()[:public].module ==
               PscWeb.Admin.Filters.TemplateVisibility

      assert PscWeb.Admin.TemplateLive.filters()[:built_in].module ==
               PscWeb.Admin.Filters.TemplateOrigin

      assert PscWeb.Admin.CanvasLive.filters()[:notes_mode].module ==
               PscWeb.Admin.Filters.CanvasNotesMode

      resources = [
        PscWeb.Admin.UserLive,
        PscWeb.Admin.TemplateLive,
        PscWeb.Admin.CanvasLive,
        PscWeb.Admin.NoteLive
      ]

      for resource <- resources do
        refute resource.metrics() == []
      end
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

  describe "api keys" do
    setup :register_and_log_in_admin

    test "the page lists issued keys without ever rendering the secret", %{conn: conn} do
      member = AccountsFixtures.user_fixture()

      {:ok, _connection} =
        Connections.create(member, %{
          "name" => "Professor key",
          "provider" => "openai",
          "model_id" => "gpt-4.1-mini",
          "api_key" => "sk-prof-secret-9876"
        })

      {:ok, lv, html} = live(conn, ~p"/admin/api-keys")

      assert html =~ "API keys"
      assert html =~ member.email
      assert html =~ "Professor key"
      assert html =~ "…9876"
      refute render(lv) =~ "sk-prof-secret-9876"
    end

    test "issuing a key turns the agent on for the selected account", %{conn: conn} do
      member = AccountsFixtures.user_fixture()

      {:ok, lv, _html} = live(conn, ~p"/admin/api-keys")

      html =
        lv
        |> form("#api-key-form",
          key: %{
            user_id: member.id,
            provider: "openai",
            model_id: "gpt-4.1-mini",
            api_key: "sk-issued-secret-4321"
          }
        )
        |> render_submit()

      assert html =~ "Key issued for #{member.email}"
      assert html =~ "…4321"
      refute html =~ "sk-issued-secret-4321"

      assert [connection] = Connections.list(member.id)
      assert connection.api_key == "sk-issued-secret-4321"
      assert connection.name == "OpenAI key"
      assert Connections.default_id(member.id) == connection.id
      assert Connections.enabled?(member)
    end

    test "a key without a model is refused and nothing is stored", %{conn: conn} do
      member = AccountsFixtures.user_fixture()

      {:ok, lv, _html} = live(conn, ~p"/admin/api-keys")

      html =
        lv
        |> form("#api-key-form",
          key: %{
            user_id: member.id,
            provider: "openai",
            model_id: "",
            api_key: "sk-incomplete-1234"
          }
        )
        |> render_submit()

      assert html =~ "blank"
      assert Connections.list(member.id) == []
    end

    test "a key without an account is refused", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/api-keys")

      html =
        lv
        |> form("#api-key-form",
          key: %{provider: "openai", model_id: "gpt-4.1-mini", api_key: "sk-orphan-1234"}
        )
        |> render_submit()

      assert html =~ "Choose the account"
      assert Connections.admin_summaries() == []
    end

    test "rotating replaces the stored key", %{conn: conn} do
      member = AccountsFixtures.user_fixture()

      {:ok, connection} =
        Connections.create(member, %{
          "name" => "Professor key",
          "provider" => "openai",
          "model_id" => "gpt-4.1-mini",
          "api_key" => "sk-old-secret-1111"
        })

      {:ok, lv, _html} = live(conn, ~p"/admin/api-keys")

      lv
      |> element("button[phx-click='rotate'][phx-value-id='#{connection.id}']")
      |> render_click()

      html =
        lv
        |> form("#rotate-key-form-#{connection.id}", rotate: %{api_key: "sk-new-secret-2222"})
        |> render_submit()

      assert html =~ "Key rotated for #{member.email}"
      assert html =~ "…2222"
      refute html =~ "sk-new-secret-2222"
      assert Connections.get(connection.id, member.id).api_key == "sk-new-secret-2222"
    end

    test "making a key the default switches the account", %{conn: conn} do
      member = AccountsFixtures.user_fixture()

      {:ok, first} =
        Connections.create(member, %{
          "name" => "First",
          "provider" => "openai",
          "model_id" => "gpt-4.1-mini",
          "api_key" => "sk-first-secret-1111"
        })

      {:ok, second} =
        Connections.create(member, %{
          "name" => "Second",
          "provider" => "openai",
          "model_id" => "gpt-4.1",
          "api_key" => "sk-second-secret-2222"
        })

      assert Connections.default_id(member.id) == first.id

      {:ok, lv, _html} = live(conn, ~p"/admin/api-keys")

      html =
        lv
        |> element("button[phx-click='set_default'][phx-value-id='#{second.id}']")
        |> render_click()

      assert html =~ "is now the default for #{member.email}"
      assert Connections.default_id(member.id) == second.id
    end

    test "deleting a key removes it for the account", %{conn: conn} do
      member = AccountsFixtures.user_fixture()

      {:ok, connection} =
        Connections.create(member, %{
          "name" => "Professor key",
          "provider" => "openai",
          "model_id" => "gpt-4.1-mini",
          "api_key" => "sk-delete-me-1234"
        })

      {:ok, lv, _html} = live(conn, ~p"/admin/api-keys")

      html =
        lv
        |> element("button[phx-click='delete'][phx-value-id='#{connection.id}']")
        |> render_click()

      assert html =~ "Key deleted for #{member.email}"
      assert Connections.list(member.id) == []
      refute Connections.enabled?(member)
    end

    test "the account sees the issued key in its own settings", %{conn: conn} do
      member = AccountsFixtures.user_fixture()

      {:ok, admin_lv, _html} = live(conn, ~p"/admin/api-keys")

      admin_lv
      |> form("#api-key-form",
        key: %{
          user_id: member.id,
          provider: "openai",
          model_id: "gpt-4.1-mini",
          api_key: "sk-handed-over-1234"
        }
      )
      |> render_submit()

      {:ok, member_lv, html} = conn |> log_in_user(member) |> live(~p"/users/settings")

      assert has_element?(member_lv, "#agent-connections")
      assert html =~ "OpenAI key"
      assert html =~ "…1234"
      refute html =~ "sk-handed-over-1234"
    end

    test "the per-account limit is reported instead of raising", %{conn: conn} do
      member = AccountsFixtures.user_fixture()

      for index <- 1..Connections.max_per_user() do
        {:ok, _connection} =
          Connections.create(member, %{
            "name" => "Key #{index}",
            "provider" => "openai",
            "model_id" => "gpt-4.1-mini",
            "api_key" => "sk-limit-#{index}000"
          })
      end

      {:ok, lv, _html} = live(conn, ~p"/admin/api-keys")

      html =
        lv
        |> form("#api-key-form",
          key: %{
            user_id: member.id,
            provider: "openai",
            model_id: "gpt-4.1-mini",
            api_key: "sk-eleventh-1234"
          }
        )
        |> render_submit()

      assert html =~ "maximum of #{Connections.max_per_user()} keys"
      assert length(Connections.list(member.id)) == Connections.max_per_user()
    end
  end
end
