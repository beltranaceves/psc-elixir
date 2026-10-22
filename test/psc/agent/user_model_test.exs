defmodule Psc.Agent.UserModelTest do
  use Psc.DataCase, async: true

  alias Psc.Accounts
  alias Psc.AccountsFixtures
  alias Psc.Agent
  alias Psc.Agent.UserModel

  test "the transformer swaps in the model from the tool context" do
    assert {:ok, %{model: "groq:llama-3.3-70b-versatile"}} =
             UserModel.transform_request(%{}, %{}, %{}, %{model: "groq:llama-3.3-70b-versatile"})
  end

  test "the transformer strips the provider options Jido injects" do
    # `previous_response_id` is injected after the per-request options merge and
    # makes strict providers (OpenRouter) reject the request; the transformer
    # runs later, so an empty map here removes it.
    assert {:ok, %{llm_opts: [provider_options: []]}} =
             UserModel.transform_request(%{}, %{}, %{}, %{})
  end

  test "without a model the transformer defers to the agent default" do
    assert {:ok, overrides} = UserModel.transform_request(%{}, %{}, %{}, %{})
    refute Map.has_key?(overrides, :model)
  end

  test "a saved model wins over the deployment default" do
    user = AccountsFixtures.user_fixture()

    {:ok, user} =
      Accounts.update_agent_key(user, %{
        "agent_api_key" => "sk-test",
        "agent_model" => "anthropic:claude-haiku-4-5"
      })

    assert Agent.model_for(user) == "anthropic:claude-haiku-4-5"
    assert Agent.enabled?(user)
  end

  test "an unsupported or malformed model is rejected" do
    user = AccountsFixtures.user_fixture()

    assert {:error, changeset} =
             Accounts.update_agent_key(user, %{"agent_model" => "not-a-provider:x"})

    assert changeset.errors[:agent_model]

    assert {:error, changeset} =
             Accounts.update_agent_key(user, %{"agent_model" => "openai"})

    assert changeset.errors[:agent_model]
  end

  test "clearing the model falls back to the deployment default" do
    user = AccountsFixtures.user_fixture()

    {:ok, user} =
      Accounts.update_agent_key(user, %{
        "agent_api_key" => "sk-test",
        "agent_model" => "groq:llama-3.3-70b-versatile"
      })

    {:ok, user} = Accounts.update_agent_key(user, %{"agent_model" => ""})

    assert Agent.model_for(user) == Application.get_env(:jido_ai, :model_aliases)[:default]
  end

  test "a user with no key is not enabled even with a model" do
    user = AccountsFixtures.user_fixture()

    {:ok, user} =
      Accounts.update_agent_key(user, %{"agent_model" => "openai:gpt-4.1-mini"})

    refute Agent.enabled?(user)
  end
end
