defmodule Psc.Agent.ConnectionsTest do
  use Psc.DataCase, async: false

  import Psc.AccountsFixtures

  alias Psc.Accounts
  alias Psc.Agent
  alias Psc.Agent.Connection
  alias Psc.Agent.Connections
  alias Psc.Agent.ModelCatalog

  defp create_connection(user, attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          "name" => "Test",
          "provider" => "openai",
          "model_id" => "gpt-4.1-mini",
          "api_key" => "sk-test-123"
        },
        attrs
      )

    Connections.create(user, attrs)
  end

  test "validates name, provider, model and key" do
    user = user_fixture()

    assert {:error, changeset} =
             Connections.create(user, %{
               "name" => "",
               "provider" => "not-a-provider",
               "model_id" => "two words",
               "api_key" => ""
             })

    assert changeset.errors[:name]
    assert changeset.errors[:provider]
    assert changeset.errors[:model_id]
    assert changeset.errors[:api_key]
  end

  test "self-hosted providers do not need a key" do
    user = user_fixture()

    assert {:ok, connection} =
             Connections.create(user, %{
               "name" => "Local",
               "provider" => "ollama",
               "model_id" => "llama3.1"
             })

    assert connection.api_key == nil
    assert connection.key_hint == nil
  end

  test "a base URL is normalized and validated" do
    user = user_fixture()

    assert {:ok, connection} =
             create_connection(user, %{"base_url" => "http://localhost:11434/v1/"})

    assert connection.base_url == "http://localhost:11434/v1"

    assert {:error, changeset} =
             create_connection(user, %{"name" => "Bad", "base_url" => "localhost:1234"})

    assert changeset.errors[:base_url]
  end

  test "the first connection becomes the default and names are unique per user" do
    user = user_fixture()

    assert {:ok, connection} = create_connection(user)
    assert Connections.default(user).id == connection.id

    assert {:error, changeset} = create_connection(user)
    assert changeset.errors[:name]
  end

  test "a blank key on update keeps the saved one" do
    user = user_fixture()
    {:ok, connection} = create_connection(user)

    assert {:ok, updated} =
             Connections.update(connection, %{"model_id" => "gpt-4.1", "api_key" => ""})

    assert updated.model_id == "gpt-4.1"
    assert updated.api_key == "sk-test-123"
    assert updated.key_hint == "…" <> String.slice("sk-test-123", -4, 4)
  end

  test "summaries never carry the key" do
    user = user_fixture()
    {:ok, connection} = create_connection(user)

    assert [summary] = Connections.summaries(user.id)
    assert summary.id == connection.id
    assert summary.default?
    assert summary.key_hint == "…" <> String.slice("sk-test-123", -4, 4)
    refute Map.has_key?(summary, :api_key)
    refute inspect(summary) =~ "sk-test-123"
  end

  test "deleting the default promotes another connection" do
    user = user_fixture()
    {:ok, first} = create_connection(user, %{"name" => "One"})
    {:ok, _second} = create_connection(user, %{"name" => "Two"})

    Connections.set_default(user, first)
    assert Connections.default(user).id == first.id

    assert {:ok, :ok} = Connections.delete(first)
    assert Connections.default(user).name == "Two"
  end

  test "caps connections per user" do
    user = user_fixture()

    for index <- 1..Connections.max_per_user() do
      assert {:ok, _} = create_connection(user, %{"name" => "Connection #{index}"})
    end

    assert {:error, :limit} = create_connection(user, %{"name" => "One too many"})
  end

  test "turn config prefers the session's connection, then the default" do
    user = user_fixture()
    {:ok, first} = create_connection(user, %{"name" => "One", "model_id" => "gpt-4.1"})

    {:ok, second} =
      create_connection(user, %{
        "name" => "Two",
        "provider" => "anthropic",
        "model_id" => "claude-haiku-4-5",
        "base_url" => "https://proxy.example/v1"
      })

    {:ok, session} = Agent.create_session(user.id)

    assert %{model: "openai:gpt-4.1", api_key: "sk-test-123", base_url: nil} =
             Connections.turn_config(session, user)

    # The session's own connection wins over the default.
    {:ok, session} = Agent.set_session_connection(session, second)

    assert %{
             connection_id: second_id,
             model: "anthropic:claude-haiku-4-5",
             api_key: "sk-test-123",
             base_url: "https://proxy.example/v1"
           } = Connections.turn_config(session, user)

    assert second_id == second.id
    refute Connections.turn_config(session, user).connection_id == first.id
  end

  test "a legacy key and model still resolve when there is no connection" do
    user = user_fixture()

    {:ok, user} =
      Accounts.update_agent_key(user, %{
        "agent_api_key" => "sk-legacy",
        "agent_model" => "groq:llama-3.3-70b-versatile"
      })

    assert %{model: "groq:llama-3.3-70b-versatile", api_key: "sk-legacy"} =
             Connections.turn_config(nil, user)

    assert Connections.missing_configuration(user) == nil
  end

  test "a legacy key without a model is not usable" do
    aliases = Application.get_env(:jido_ai, :model_aliases)

    try do
      Application.put_env(:jido_ai, :model_aliases, %{})

      user = user_fixture()
      {:ok, user} = Accounts.update_agent_key(user, %{"agent_api_key" => "sk-legacy"})

      assert Connections.missing_configuration(user) == :connection
      refute Connections.enabled?(user)
    after
      Application.put_env(:jido_ai, :model_aliases, aliases)
    end
  end

  test "model suggestions come from the packaged catalog" do
    refute ModelCatalog.suggestions("openai") == []
    assert ModelCatalog.suggestions("moonshot_ai") == []
  end

  test "the provider catalog marks local providers as keyless" do
    assert Connection.needs_key?("ollama") == false
    assert Connection.needs_key?("openai") == true
    assert Connection.default_base_url("ollama") =~ "localhost"
    assert Connection.model_spec(%Connection{provider: "groq", model_id: "x"}) == "groq:x"
  end
end
