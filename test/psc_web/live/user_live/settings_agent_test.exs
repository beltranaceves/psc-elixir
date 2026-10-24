defmodule PscWeb.UserLive.SettingsAgentTest do
  # Mutates the deployment-wide model aliases, so it must not run in parallel.
  use PscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Psc.AccountsFixtures

  alias Psc.Accounts

  describe "agent key" do
    test "saving the key stores it and never renders it back", %{conn: conn} do
      user = user_fixture()
      {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/users/settings")

      html =
        lv
        |> form("#agent-key-form",
          user: %{
            provider: "anthropic",
            model_id: "claude-haiku-4-5",
            agent_api_key: "sk-ant-secret"
          }
        )
        |> render_submit()

      stored = Accounts.get_user(user.id)
      assert stored.agent_api_key == "sk-ant-secret"
      assert stored.agent_model == "anthropic:claude-haiku-4-5"

      assert html =~ "A key is saved for anthropic:claude-haiku-4-5"
      refute html =~ "sk-ant-secret"
    end

    test "a key saved before this session is reported as saved on another device", %{conn: conn} do
      user = user_fixture()

      {:ok, user} =
        Accounts.update_agent_key(user, %{
          "agent_api_key" => "sk-secret",
          "agent_model" => "openai:gpt-4o-mini"
        })

      # The second device signs in with the account as it looked before the key
      # was saved: the row itself, not that stale struct, carries the key.
      stale = %{user | agent_api_key: nil, agent_model: nil}

      {:ok, _lv, html} =
        conn
        |> log_in_user(stale)
        |> live(~p"/users/settings")

      assert html =~ "A key is saved for openai:gpt-4o-mini"
      refute html =~ "sk-secret"
    end

    test "removing a key and saving the same one again persists it", %{conn: conn} do
      user = user_fixture()

      {:ok, user} =
        Accounts.update_agent_key(user, %{
          "agent_api_key" => "sk-same",
          "agent_model" => "openai:gpt-4o-mini"
        })

      {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/users/settings")

      lv |> element("button", "Remove saved key") |> render_click()
      assert Accounts.get_user(user.id).agent_api_key == nil

      # The socket's user still carries the removed key; comparing against it
      # would make this save a no-op and leave the account without a key.
      lv
      |> form("#agent-key-form",
        user: %{
          provider: "openai",
          model_id: "gpt-4o-mini",
          agent_api_key: "sk-same"
        }
      )
      |> render_submit()

      assert Accounts.get_user(user.id).agent_api_key == "sk-same"
      assert render(lv) =~ "A key is saved for openai:gpt-4o-mini"
    end

    test "without an instance default the form says a model is required", %{conn: conn} do
      aliases = Application.get_env(:jido_ai, :model_aliases)
      on_exit(fn -> Application.put_env(:jido_ai, :model_aliases, aliases) end)
      Application.put_env(:jido_ai, :model_aliases, %{})

      user = user_fixture()
      {:ok, user} = Accounts.update_agent_key(user, %{"agent_api_key" => "sk-test"})

      {:ok, _lv, html} = conn |> log_in_user(user) |> live(~p"/users/settings")

      assert html =~ "this instance has no default model"
      assert html =~ "The agent stays off until you choose a model"
    end
  end
end
