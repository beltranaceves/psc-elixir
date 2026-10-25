defmodule PscWeb.UserLive.SettingsAgentTest do
  # Mutates application env for the model-fetch seam, so it must not run in
  # parallel.
  use PscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Psc.AccountsFixtures

  alias Psc.Agent.Connections

  defp create_connection(user, attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          "name" => "Work OpenAI",
          "provider" => "openai",
          "model_id" => "gpt-4.1-mini",
          "api_key" => "sk-secret-123"
        },
        attrs
      )

    {:ok, connection} = Connections.create(user, attrs)
    connection
  end

  defp fill_form(params) do
    %{
      connection:
        Map.merge(
          %{
            "name" => "Work OpenAI",
            "model_id" => "gpt-4.1-mini",
            "api_key" => "sk-secret-123",
            "base_url" => ""
          },
          params
        )
    }
  end

  test "creating a connection stores it and never renders the key back", %{conn: conn} do
    user = user_fixture()
    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/users/settings")

    lv |> element("button", "Add your first connection") |> render_click()
    assert has_element?(lv, "#connection-form")

    lv |> element("#connection_provider") |> render_click()

    lv
    |> element(~s|#connection-provider-list button[phx-value-provider="anthropic"]|)
    |> render_click()

    html =
      lv
      |> form(
        "#connection-form",
        fill_form(%{
          "model_id" => "claude-haiku-4-5",
          "api_key" => "sk-ant-secret-123"
        })
      )
      |> render_submit()

    assert [connection] = Connections.list(user.id)
    assert connection.name == "Work OpenAI"
    assert connection.provider == "anthropic"
    assert connection.model_id == "claude-haiku-4-5"
    assert connection.api_key == "sk-ant-secret-123"

    assert html =~ "Work OpenAI"
    assert html =~ "Anthropic · claude-haiku-4-5"
    assert html =~ "…-123"
    refute html =~ "sk-ant-secret-123"
  end

  test "editing without a key keeps the saved one", %{conn: conn} do
    user = user_fixture()
    connection = create_connection(user)

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/users/settings")

    lv |> element("#edit-connection-#{connection.id}") |> render_click()
    assert has_element?(lv, "#connection-form")

    lv
    |> form(
      "#connection-form",
      fill_form(%{"name" => "Renamed", "model_id" => "gpt-4.1", "api_key" => ""})
    )
    |> render_submit()

    updated = Connections.get(connection.id, user.id)
    assert updated.name == "Renamed"
    assert updated.model_id == "gpt-4.1"
    assert updated.api_key == "sk-secret-123"
    refute render(lv) =~ "sk-secret-123"
  end

  test "deleting the default promotes another connection", %{conn: conn} do
    user = user_fixture()
    first = create_connection(user, %{"name" => "First"})
    second = create_connection(user, %{"name" => "Second"})

    Connections.set_default(user, first)

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/users/settings")

    lv |> element("#delete-connection-#{first.id}") |> render_click()

    assert Connections.default(user).id == second.id
    refute has_element?(lv, "#connection-#{first.id}")
  end

  test "a connection can be made the default", %{conn: conn} do
    user = user_fixture()
    first = create_connection(user, %{"name" => "First"})
    second = create_connection(user, %{"name" => "Second"})

    assert Connections.default(user).id == first.id

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/users/settings")

    lv |> element("#default-connection-#{second.id}") |> render_click()

    assert Connections.default(user).id == second.id
  end

  test "the provider picker updates the dialog and carries its value", %{conn: conn} do
    user = user_fixture()
    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/users/settings")

    lv |> element("button", "Add your first connection") |> render_click()
    lv |> element("#connection_provider") |> render_click()
    assert has_element?(lv, "#connection-provider-list")

    lv
    |> element(~s|#connection-provider-list button[phx-value-provider="ollama"]|)
    |> render_click()

    refute has_element?(lv, "#connection-provider-list")
    assert has_element?(lv, "#connection_provider", "Ollama")
    assert has_element?(lv, ~s|input[name="connection[provider]"][value="ollama"]|)
    assert render(lv) =~ "Not required for this provider."
  end

  test "the test button fetches models and the save caches them", %{conn: conn} do
    user = user_fixture()
    previous = Application.get_env(:psc, :model_catalog_fetcher)
    on_exit(fn -> Application.put_env(:psc, :model_catalog_fetcher, previous) end)

    Application.put_env(:psc, :model_catalog_fetcher, fn _provider, _key, _base_url ->
      {:ok, ["gpt-4.1", "gpt-4.1-mini"]}
    end)

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/users/settings")

    lv |> element("button", "Add your first connection") |> render_click()

    html =
      lv
      |> form("#connection-form", fill_form(%{}))
      |> render_submit(%{"action" => "test"})

    assert html =~ "Connected — 2 models available."

    assert has_element?(
             lv,
             ~s|#connection-model-suggestions [data-suggestion="gpt-4.1-mini"]|
           )

    # Testing does not save anything.
    assert Connections.list(user.id) == []

    # The key input re-renders empty after the test round trip; the server keeps
    # the typed key so saving does not require retyping it.
    lv
    |> form("#connection-form", fill_form(%{"api_key" => ""}))
    |> render_submit(%{"action" => "save"})

    assert [connection] = Connections.list(user.id)
    assert connection.api_key == "sk-secret-123"
    assert connection.models == ["gpt-4.1", "gpt-4.1-mini"]
    assert connection.models_fetched_at
  end

  test "a failed test explains why and does not save", %{conn: conn} do
    user = user_fixture()
    previous = Application.get_env(:psc, :model_catalog_fetcher)
    on_exit(fn -> Application.put_env(:psc, :model_catalog_fetcher, previous) end)

    Application.put_env(:psc, :model_catalog_fetcher, fn _provider, _key, _base_url ->
      {:error, "The provider rejected this key."}
    end)

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/users/settings")

    lv |> element("button", "Add your first connection") |> render_click()

    html =
      lv
      |> form("#connection-form", fill_form(%{}))
      |> render_submit(%{"action" => "test"})

    assert html =~ "The provider rejected this key."
    assert Connections.list(user.id) == []
  end
end
