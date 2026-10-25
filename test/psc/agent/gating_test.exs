defmodule Psc.Agent.GatingTest do
  # Mutates the deployment-wide model aliases, so it must not run in parallel.
  use Psc.DataCase, async: false

  import Psc.AccountsFixtures

  alias Psc.Accounts
  alias Psc.Agent
  alias Psc.Agent.Connections

  setup do
    aliases = Application.get_env(:jido_ai, :model_aliases)
    on_exit(fn -> Application.put_env(:jido_ai, :model_aliases, aliases) end)
    :ok
  end

  defp create_connection(user) do
    {:ok, connection} =
      Connections.create(user, %{
        "name" => "Test",
        "provider" => "openai",
        "model_id" => "gpt-4.1-mini",
        "api_key" => "sk-test-123"
      })

    connection
  end

  test "reports a missing connection, then ready once the user has one" do
    user = user_fixture()

    assert Agent.missing_configuration(user) == :connection
    refute Agent.enabled?(user)

    create_connection(user)
    user = Accounts.get_user(user.id)

    assert Agent.missing_configuration(user) == nil
    assert Agent.enabled?(user)
  end

  test "a legacy key pair still counts as ready" do
    user = user_fixture()

    {:ok, user} =
      Accounts.update_agent_key(user, %{
        "agent_api_key" => "sk-test",
        "agent_model" => "openai:gpt-4.1-mini"
      })

    assert Agent.missing_configuration(user) == nil
    assert Agent.enabled?(user)
  end

  test "a legacy key without a model is not usable" do
    Application.put_env(:jido_ai, :model_aliases, %{})

    user = user_fixture()
    {:ok, user} = Accounts.update_agent_key(user, %{"agent_api_key" => "sk-test"})

    assert Agent.missing_configuration(user) == :connection
    refute Agent.enabled?(user)
  end
end
