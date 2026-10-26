defmodule Psc.AgentTest do
  use Psc.DataCase, async: true

  alias Psc.AccountsFixtures
  alias Psc.Agent

  setup do
    user = AccountsFixtures.user_fixture()
    %{user: user}
  end

  test "a new session is not visible to another user", %{user: user} do
    {:ok, session} = Agent.create_session(user.id)
    other = AccountsFixtures.user_fixture()

    assert Agent.get_session(session.id, user.id).id == session.id
    assert Agent.get_session(session.id, other.id) == nil
    assert Agent.get_session("not-a-uuid", user.id) == nil
  end

  test "the first user message names the session", %{user: user} do
    {:ok, session} = Agent.create_session(user.id)
    assert session.title == "New chat"

    {:ok, _message} = Agent.append_user_message(session, "  What   changed on Q3?  ")

    session = Psc.Repo.reload!(session)
    assert session.title == "What changed on Q3?"
    assert session.message_count == 1
    assert session.last_message_at
  end

  test "the first message pins the profile and role", %{user: user} do
    {:ok, canvas} =
      Psc.Canvas.create_unstr_canvas(user.id, %{
        "name" => "Pinned",
        "cells" => Psc.Canvas.blank_cells(),
        "agent_config" => %{
          "prompt" => "Pin me.",
          "roles" => [
            %{"key" => "critic", "name" => "Critic", "instructions" => "Challenge."}
          ],
          "default_role" => "critic"
        }
      })

    {:ok, session} = Agent.create_session(user.id, %{canvas_id: canvas.id})
    profile = Agent.Profile.for_canvas(canvas, "critic")

    {:ok, _message} = Agent.append_user_message(session, "hello", profile: profile)

    session = Psc.Repo.reload!(session)
    assert session.role == "critic"
    assert session.profile["system_prompt"] =~ "Pin me."
    assert session.profile["tools"] == Agent.Tools.names()
  end

  test "a role can only change before the first message", %{user: user} do
    {:ok, session} = Agent.create_session(user.id)

    assert {:ok, session} = Agent.set_session_role(session, "critic")
    assert session.role == "critic"

    {:ok, _message} = Agent.append_user_message(session, "hello")
    assert {:error, :started} = Agent.set_session_role(session, "other")
  end

  test "a long first message is truncated, not wrapped", %{user: user} do
    {:ok, session} = Agent.create_session(user.id)
    {:ok, _} = Agent.append_user_message(session, String.duplicate("a", 200))

    assert String.length(Psc.Repo.reload!(session).title) == 60
  end

  test "history keeps user turns and completed answers, oldest first", %{user: user} do
    {:ok, session} = Agent.create_session(user.id)

    {:ok, _} = Agent.append_user_message(session, "First")
    {:ok, done} = Agent.start_assistant_message(session)
    {:ok, _} = Agent.finish_message(done, %{content: "Answer"})

    {:ok, _} = Agent.append_user_message(session, "Second")
    {:ok, pending} = Agent.start_assistant_message(session)

    contents = session |> Agent.history() |> Enum.map(& &1.content)
    assert contents == ["First", "Answer", "Second"]

    {:ok, _} = Agent.fail_message(pending, "boom")
    refute Enum.any?(Agent.history(session), &(&1.id == pending.id))
  end

  test "a stale streaming message is swept to cancelled", %{user: user} do
    {:ok, session} = Agent.create_session(user.id)
    {:ok, message} = Agent.start_assistant_message(session)

    # Nothing is older than the cutoff yet.
    assert Agent.cancel_stale_streaming(session) == {0, nil}

    message
    |> Ecto.Changeset.change(updated_at: DateTime.add(DateTime.utc_now(), -600, :second))
    |> Psc.Repo.update!()

    assert {1, nil} = Agent.cancel_stale_streaming(session)
    assert Psc.Repo.reload!(message).status == :cancelled
  end

  test "messages beyond the cap are pruned, oldest first", %{user: user} do
    {:ok, session} = Agent.create_session(user.id)

    for index <- 1..205 do
      {:ok, _} = Agent.append_user_message(session, "Message #{index}")
    end

    count =
      Psc.Repo.aggregate(from(m in Psc.Agent.Message, where: m.session_id == ^session.id), :count)

    assert count == 200

    oldest = session |> Agent.history(1_000) |> List.first()
    assert oldest.content == "Message 6"
  end

  test "sessions beyond the cap are pruned", %{user: user} do
    for index <- 1..55 do
      {:ok, session} = Agent.create_session(user.id)
      {:ok, _} = Agent.append_user_message(session, "Session #{index}")
    end

    assert length(Agent.list_sessions(user.id)) == 50
  end

  test "deleting a session deletes its messages", %{user: user} do
    {:ok, session} = Agent.create_session(user.id)
    {:ok, _} = Agent.append_user_message(session, "Hi")

    {:ok, _} = Agent.delete_session(session)
    assert Psc.Repo.all(from m in Psc.Agent.Message, where: m.session_id == ^session.id) == []
  end
end
