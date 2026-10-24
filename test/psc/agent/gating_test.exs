defmodule Psc.Agent.GatingTest do
  # Mutates the deployment-wide model aliases, so it must not run in parallel.
  use Psc.DataCase, async: false

  alias Psc.Accounts
  alias Psc.AccountsFixtures
  alias Psc.Agent

  setup do
    aliases = Application.get_env(:jido_ai, :model_aliases)
    on_exit(fn -> Application.put_env(:jido_ai, :model_aliases, aliases) end)
    :ok
  end

  test "reports a missing key, then ready once the user has one" do
    user = AccountsFixtures.user_fixture()

    assert Agent.missing_configuration(user) == :key
    refute Agent.enabled?(user)

    {:ok, user} = Accounts.update_agent_key(user, %{"agent_api_key" => "sk-test"})

    # In tests the model comes from the deployment alias.
    assert Agent.missing_configuration(user) == nil
    assert Agent.enabled?(user)
  end

  test "reports a missing model when the key is saved but nothing names a model" do
    Application.put_env(:jido_ai, :model_aliases, %{})

    user = AccountsFixtures.user_fixture()
    {:ok, user} = Accounts.update_agent_key(user, %{"agent_api_key" => "sk-test"})

    assert Agent.missing_configuration(user) == :model
    refute Agent.enabled?(user)

    {:ok, user} = Accounts.update_agent_key(user, %{"agent_model" => "openai:gpt-4o-mini"})

    assert Agent.missing_configuration(user) == nil
    assert Agent.enabled?(user)
  end
end
