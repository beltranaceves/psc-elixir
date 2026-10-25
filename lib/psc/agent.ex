defmodule Psc.Agent do
  @moduledoc """
  Conversations with the workspace agent.

  The agent itself is ephemeral: a turn starts a process, runs one read-only
  ReAct loop and exits. Everything that must survive - the session, its
  messages, the tool calls and their results - is a row in this context.

  Two limits keep the tables honest: `@max_messages_per_session` (200) and
  `@max_sessions_per_user` (50). Pruning runs on write, oldest first.
  """

  import Ecto.Query

  alias Psc.Agent.Connections
  alias Psc.Agent.Message
  alias Psc.Agent.Session
  alias Psc.Repo

  @max_messages_per_session 200
  @max_sessions_per_user 50
  @history_limit 40
  @title_length 60
  @stale_after_seconds 90

  @doc """
  Whether the agent tab is available to this user.

  It needs a connection of their own (or the legacy key pair) to call a model.
  """
  def enabled?(%Psc.Accounts.User{} = user), do: Connections.enabled?(user)

  @doc """
  What keeps a user from using the agent: `:connection` when they have no saved
  connection, `nil` when they are ready. The interface reports the actual gap.
  """
  def missing_configuration(%Psc.Accounts.User{} = user),
    do: Connections.missing_configuration(user)

  @doc """
  Whether the agent is configured at deployment level (`AGENT_MODEL` plus a key).
  """
  def enabled?, do: Application.get_env(:psc, :agent_enabled, false)

  @doc """
  The model spec a turn should use: the session's connection, else the user's
  default, else the legacy pair, else the deployment default.
  """
  def model_for(%Psc.Accounts.User{} = user), do: Connections.turn_config(nil, user).model

  def model_for(%Psc.Agent.Session{} = session, %Psc.Accounts.User{} = user),
    do: Connections.turn_config(session, user).model

  @doc "The provider key a turn should use, or nil."
  def api_key(%Psc.Accounts.User{} = user), do: Connections.turn_config(nil, user).api_key

  def api_key(%Psc.Agent.Session{} = session, %Psc.Accounts.User{} = user),
    do: Connections.turn_config(session, user).api_key

  @doc "Pins a session to a connection."
  def set_session_connection(session, connection),
    do: Connections.attach_to_session(session, connection)

  @doc "Every session of a user, most recently used first."
  def list_sessions(user_id) do
    from(s in Session,
      where: s.user_id == ^user_id,
      order_by: [desc: s.last_message_at, desc: s.inserted_at],
      limit: @max_sessions_per_user
    )
    |> Repo.all()
  end

  @doc """
  One session, but only if it belongs to `user_id`.

  Returns nil otherwise - a stranger's session id is indistinguishable from a
  missing one, which is what a caller should not be able to probe.
  """
  def get_session(id, user_id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} ->
        Repo.one(from s in Session, where: s.id == ^uuid and s.user_id == ^user_id)

      :error ->
        nil
    end
  end

  def get_session(_id, _user_id), do: nil

  @doc "Starts an empty session. The first user message names it."
  def create_session(user_id, attrs \\ %{}) do
    canvas_id = Map.get(attrs, :canvas_id) || Map.get(attrs, "canvas_id")

    %Session{user_id: user_id, canvas_id: canvas_id}
    |> Session.changeset(Map.put_new(attrs, :title, "New chat"))
    |> Repo.insert()
  end

  @doc """
  Sessions of one canvas, newest first.

  The agent belongs to the canvas it is opened in, so its history does not leak
  into another canvas's tab.
  """
  def list_sessions_for_canvas(canvas_id, user_id) do
    from(s in Session,
      where: s.canvas_id == ^canvas_id and s.user_id == ^user_id,
      order_by: [desc: s.last_message_at, desc: s.inserted_at],
      limit: @max_sessions_per_user
    )
    |> Repo.all()
  end

  @doc "The canvas's most recently used session, or nil."
  def latest_session(canvas_id, user_id) do
    from(s in Session,
      where: s.canvas_id == ^canvas_id and s.user_id == ^user_id,
      order_by: [desc: s.last_message_at, desc: s.inserted_at],
      limit: 1
    )
    |> Repo.one()
  end

  def rename_session(session, title) do
    session |> Session.changeset(%{title: title}) |> Repo.update()
  end

  @doc """
  Copies a session and its transcript, so a branch can diverge from it.

  Messages are copied as they stand - no model call, no cost - and the copy is
  named "<title> (copy)".
  """
  def duplicate_session(session) do
    Repo.transaction(fn ->
      {:ok, copy} =
        create_session(session.user_id, %{
          canvas_id: session.canvas_id,
          title: "#{session.title} (copy)"
        })

      messages = list_messages(session)

      for message <- messages do
        {:ok, _} =
          insert_message(copy, %{
            role: message.role,
            content: message.content,
            status: message.status,
            tool_calls: message.tool_calls,
            usage: message.usage,
            model: message.model
          })
      end

      copy
      |> Ecto.Changeset.change(
        message_count: length(messages),
        last_message_at: session.last_message_at || now()
      )
      |> Repo.update!()
    end)
  end

  def delete_session(session), do: Repo.delete(session)

  @doc """
  The transcript a turn replays, oldest first.

  Assistant messages that never completed are left out: an empty assistant turn
  in the prefix would be both invalid for the provider and a cache miss.
  """
  def history(session, limit \\ @history_limit) do
    from(m in Message,
      where: m.session_id == ^session.id,
      where: m.role == :user or m.status == :complete,
      order_by: [desc: m.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
    |> Enum.reverse()
  end

  @doc """
  Adds a user message and names the session when this is its first message.
  """
  def append_user_message(session, content) do
    Repo.transaction(fn ->
      first? = session.message_count in [nil, 0]
      {:ok, message} = insert_message(session, %{role: :user, content: content})

      session =
        if first?, do: rename_first(session, content), else: session

      session
      |> touch()
      |> prune()

      message
    end)
  end

  @doc """
  Creates the assistant message a turn fills in, so the UI has something to
  stream into before the first token arrives.

  Options: `:model` - the `provider:model` spec the turn will run, stored on the
  row so the transcript records what answered.
  """
  def start_assistant_message(session, opts \\ []) do
    Repo.transaction(fn ->
      {:ok, message} =
        insert_message(session, %{
          role: :assistant,
          status: :streaming,
          model: Keyword.get(opts, :model)
        })

      session |> touch() |> prune()
      message
    end)
  end

  @doc "Completes an assistant message with the turn's result."
  def finish_message(message, attrs) do
    message
    |> Message.changeset(Map.merge(%{status: :complete}, attrs))
    |> Repo.update()
  end

  def fail_message(message, reason) do
    message
    |> Message.changeset(%{status: :error, error: to_string(reason)})
    |> Repo.update()
  end

  def cancel_message(message) do
    message
    |> Message.changeset(%{status: :cancelled})
    |> Repo.update()
  end

  @doc """
  Marks turns that died with the process that was running them.

  A deploy or a crash leaves a `:streaming` message behind. Anything older than
  `@stale_after_seconds` cannot still have a turn behind it.
  """
  def cancel_stale_streaming(session) do
    cutoff = DateTime.utc_now() |> DateTime.add(-@stale_after_seconds, :second)

    from(m in Message,
      where: m.session_id == ^session.id and m.status == :streaming and m.updated_at < ^cutoff
    )
    |> Repo.update_all(set: [status: :cancelled, updated_at: DateTime.utc_now()])
  end

  @doc "Messages of a session, oldest first, as the chat renders them."
  def list_messages(session) do
    from(m in Message, where: m.session_id == ^session.id, order_by: [asc: m.inserted_at])
    |> Repo.all()
  end

  def get_message(id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.get(Message, uuid)
      :error -> nil
    end
  end

  @doc false
  def history_limit, do: @history_limit

  defp insert_message(session, attrs) do
    %Message{}
    |> Message.changeset(Map.merge(%{session_id: session.id}, attrs))
    |> Repo.insert()
  end

  # The row in hand has stale counters; re-read before upping them.
  defp touch(session) do
    session = Repo.reload!(session)

    session
    |> Ecto.Changeset.change(
      message_count: (session.message_count || 0) + 1,
      last_message_at: now()
    )
    |> Repo.update!()
  end

  defp rename_first(session, content) do
    title =
      content
      |> to_string()
      |> String.replace(~r/\s+/, " ")
      |> String.trim()
      |> String.slice(0, @title_length)
      |> case do
        "" -> "New chat"
        title -> title
      end

    session |> Session.changeset(%{title: title}) |> Repo.update!()
  end

  defp prune(session) do
    prune_messages(session.id)
    prune_sessions(session.user_id)
    session
  end

  defp prune_messages(session_id) do
    keep =
      from(m in Message,
        where: m.session_id == ^session_id,
        order_by: [desc: m.inserted_at],
        limit: @max_messages_per_session,
        select: m.id
      )

    from(m in Message, where: m.session_id == ^session_id and m.id not in subquery(keep))
    |> Repo.delete_all()
  end

  defp prune_sessions(user_id) do
    keep =
      from(s in Session,
        where: s.user_id == ^user_id,
        order_by: [desc: s.last_message_at, desc: s.inserted_at],
        limit: @max_sessions_per_user,
        select: s.id
      )

    from(s in Session, where: s.user_id == ^user_id and s.id not in subquery(keep))
    |> Repo.delete_all()
  end

  defp now, do: DateTime.utc_now()
end
