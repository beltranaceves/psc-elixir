defmodule Psc.Agent.TurnTest do
  use Psc.DataCase, async: false

  alias Psc.AccountsFixtures
  alias Psc.Agent
  alias Psc.Agent.Turn

  setup do
    user = AccountsFixtures.user_fixture()
    {:ok, session} = Agent.create_session(user.id)

    %{user: user, session: session, scope: Psc.Accounts.Scope.for_user(user)}
  end

  test "a scripted turn streams, persists and broadcasts", %{
    session: session,
    scope: scope
  } do
    {:ok, _user} = Agent.append_user_message(session, "What canvases do I have?")
    {:ok, assistant} = Agent.start_assistant_message(session)

    Phoenix.PubSub.subscribe(Psc.PubSub, Turn.topic(session.id))

    script = [
      {:delta, "Let me look."},
      {:tool, "list_canvases", %{}, %{"canvases" => []}},
      {:answer, "You have no canvases yet."}
    ]

    assert {:ok, completed} = Turn.run(session, assistant, scope, script: script)
    assert completed.status == :complete
    assert completed.content == "You have no canvases yet."
    assert [%{"name" => "list_canvases", "status" => "ok"}] = completed.tool_calls

    id = completed.id
    assert_receive {:delta, ^id, "Let me look."}
    assert_receive {:tool_started, ^id, %{"name" => "list_canvases"}}
    assert_receive {:tool_finished, ^id, %{"name" => "list_canvases", "status" => "ok"}}
    assert_receive {:completed, ^id, %{content: "You have no canvases yet."}}
  end

  test "a scripted failure marks the message and keeps it out of history", %{
    session: session,
    scope: scope
  } do
    {:ok, _user} = Agent.append_user_message(session, "Break please")
    {:ok, assistant} = Agent.start_assistant_message(session)

    assert {:error, failed} = Turn.run(session, assistant, scope, script: [{:error, "boom"}])
    assert failed.status == :error

    assert session |> Agent.history() |> Enum.map(& &1.role) == [:user]
  end

  test "render_prompt is append-only and deterministic", %{session: session} do
    {:ok, _} = Agent.append_user_message(session, "First question")
    {:ok, first} = Agent.start_assistant_message(session)
    {:ok, _} = Agent.finish_message(first, %{content: "First answer"})
    {:ok, _} = Agent.append_user_message(session, "Second question")

    once = Turn.render_prompt(session)
    twice = Turn.render_prompt(session)

    assert once == twice
    assert once =~ "First question"
    assert once =~ "First answer"
    assert String.ends_with?(String.trim_trailing(once), "Second question")
  end

  test "the first turn is sent unwrapped", %{session: session} do
    {:ok, _} = Agent.append_user_message(session, "Just this")
    assert Turn.render_prompt(session) == "Just this"
  end

  test "an unscripted turn fails into the message instead of crashing", %{
    session: session,
    scope: scope
  } do
    # The test configuration points the model at a provider that does not exist,
    # so this exercises the real Jido path (server, ask_stream, await) without a
    # network call.
    {:ok, _} = Agent.append_user_message(session, "Hello there")
    {:ok, assistant} = Agent.start_assistant_message(session)

    assert {:error, failed} = Turn.run(session, assistant, scope)
    assert failed.status == :error
    assert failed.error
    assert Psc.Repo.reload!(assistant).status == :error
  end
end
