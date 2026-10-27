defmodule Psc.Agent.Connections do
  @moduledoc """
  Saved provider connections: CRUD, the user's default, and the configuration a
  turn should run with.

  Resolution order for a turn - the first hit wins:

    1. the session's own `connection_id` (a chat keeps the model it ran on),
    2. the user's `default_agent_connection_id`,
    3. the most recently used connection,
    4. the legacy `users.agent_api_key` / `agent_model` pair,
    5. the deployment default model, with the provider key taken from the
       environment (the behaviour before connections existed).

  Connections are personal: every read is scoped by `user_id`, and `summary/2`
  is the only shape the interface sees - it never contains the key.
  """

  import Ecto.Query

  alias Psc.Accounts.User
  alias Psc.Agent.Connection
  alias Psc.Agent.TurnConfig
  alias Psc.Repo

  @max_per_user 10

  def max_per_user, do: @max_per_user

  def list(user_id) do
    from(c in Connection,
      where: c.user_id == ^user_id,
      order_by: [desc_nulls_last: c.last_used_at, desc: c.inserted_at]
    )
    |> Repo.all()
  end

  @doc "Display maps for the settings page and the agent panel."
  def summaries(user_id) do
    connections = list(user_id)
    default_id = default_id(user_id) || (List.first(connections) && List.first(connections).id)

    Enum.map(connections, &Connection.summary(&1, default?: &1.id == default_id))
  end

  def get(id, user_id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} ->
        Repo.one(from c in Connection, where: c.id == ^uuid and c.user_id == ^user_id)

      :error ->
        nil
    end
  end

  def get(_id, _user_id), do: nil

  @doc """
  Creates a connection for a user.

  Options: `:models` - the ids from a successful provider fetch, cached for
  autocomplete. The first connection of a user becomes their default.
  """
  def create(%User{} = user, attrs, opts \\ []) do
    if count(user.id) >= @max_per_user do
      {:error, :limit}
    else
      changeset =
        %Connection{user_id: user.id}
        |> Connection.changeset(attrs)
        |> maybe_put_models(Keyword.get(opts, :models))

      Repo.transact(fn ->
        with {:ok, connection} <- Repo.insert(changeset) do
          promote_first(user, connection)
          {:ok, connection}
        end
      end)
    end
  end

  @doc """
  Updates a connection. A blank `api_key` means "keep the saved one": editing
  the model must not wipe the credential.
  """
  def update(%Connection{} = connection, attrs, opts \\ []) do
    changeset =
      connection
      |> Connection.changeset(keep_saved_key(attrs))
      |> maybe_put_models(Keyword.get(opts, :models))

    Repo.update(changeset)
  end

  @doc "Deletes a connection and promotes another one when it was the default."
  def delete(%Connection{} = connection) do
    Repo.transact(fn ->
      user = Repo.get(User, connection.user_id)
      {:ok, _} = Repo.delete(connection)
      user = user && Repo.reload!(user)

      if user && is_nil(user.default_agent_connection_id) do
        next = most_recent(user.id)

        user
        |> Ecto.Changeset.change(default_agent_connection_id: next && next.id)
        |> Repo.update!()
      end

      {:ok, :ok}
    end)
  end

  def set_default(%User{} = user, %Connection{} = connection) do
    if connection.user_id == user.id do
      user
      |> Repo.reload!()
      |> Ecto.Changeset.change(default_agent_connection_id: connection.id)
      |> Repo.update()
    else
      {:error, :not_found}
    end
  end

  @doc "The user's default connection, or the most recently used one."
  def default(%User{} = user) do
    case default_id(user.id) do
      nil -> most_recent(user.id)
      id -> get(id, user.id) || most_recent(user.id)
    end
  end

  def default(_user), do: nil

  ## Administration

  @doc """
  Every saved connection with its owner, for the admin surface.

  `list/1` is deliberately per-account; this is the only cross-account read.
  Like `summary/2`, the shape never carries the key — only the `key_hint`.
  """
  def admin_summaries do
    defaults =
      Repo.all(from u in User, select: {u.id, u.default_agent_connection_id})
      |> Map.new()

    from(c in Connection, order_by: [desc: c.inserted_at], preload: [:user])
    |> Repo.all()
    |> Enum.map(&admin_summary(&1, Map.get(defaults, &1.user_id) == &1.id))
  end

  @doc """
  One connection by id, regardless of owner, with its user preloaded.
  """
  def admin_get(id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.one(from c in Connection, where: c.id == ^uuid, preload: [:user])
      :error -> nil
    end
  end

  def admin_get(_id), do: nil

  @doc """
  The display map an admin row renders from. Requires the `:user` preload.
  """
  def admin_summary(%Connection{user: %User{} = user} = connection, default? \\ false) do
    connection
    |> Connection.summary(default?: default?)
    |> Map.merge(%{
      user_id: connection.user_id,
      user_email: user.email,
      inserted_at: connection.inserted_at
    })
  end

  @doc """
  The name a new admin-issued key gets when the form leaves the name blank.

  Names are unique per account, so an existing `"OpenAI key"` becomes
  `"OpenAI key 2"` instead of failing an insert the admin never asked about.
  """
  def suggested_name(user_id, provider) do
    names = Repo.all(from c in Connection, where: c.user_id == ^user_id, select: c.name)
    first_free_name(names, "#{Connection.provider_label(provider)} key", 1)
  end

  defp first_free_name(names, base, counter) do
    candidate = if counter == 1, do: base, else: "#{base} #{counter}"

    if candidate in names,
      do: first_free_name(names, base, counter + 1),
      else: candidate
  end

  @doc "The id of the user's default connection, if one is set."
  def default_id(user_id) do
    Repo.one(from u in User, where: u.id == ^user_id, select: u.default_agent_connection_id)
  end

  @doc "The connection a session should use next: its own, else the default."
  def for_session(session, %User{} = user) do
    from_session(session, user) || default(user)
  end

  def for_session(_session, _user), do: nil

  @doc """
  The model, key and endpoint a turn should use.

  Returns a `Psc.Agent.TurnConfig`; `model` may be nil when nothing is
  configured, and callers gate on `missing_configuration/1` first.
  """
  def turn_config(session, %User{} = user) do
    case for_session(session, user) do
      %Connection{} = connection ->
        %TurnConfig{
          connection_id: connection.id,
          model: Connection.model_spec(connection),
          api_key: connection.api_key,
          base_url: connection.base_url
        }

      nil ->
        legacy_config(user)
    end
  end

  def turn_config(_session, _user), do: %TurnConfig{}

  @doc """
  What keeps a user from using the agent: `:connection` when they have neither a
  connection nor a usable legacy key, `nil` when they are ready.
  """
  def missing_configuration(%User{} = user) do
    cond do
      has_connection?(user.id) -> nil
      legacy_usable?(user) -> nil
      true -> :connection
    end
  end

  def missing_configuration(_user), do: :connection

  def enabled?(%User{} = user), do: is_nil(missing_configuration(user))
  def enabled?(_user), do: false

  @doc "Records that a connection produced a turn."
  def mark_used(%Connection{} = connection) do
    connection
    |> Ecto.Changeset.change(last_used_at: DateTime.utc_now())
    |> Repo.update()
  end

  def mark_used(_connection), do: {:ok, nil}

  @doc "Pins a session to a connection (programmatic field, never cast)."
  def attach_to_session(session, %Connection{} = connection) do
    if session.connection_id == connection.id do
      {:ok, session}
    else
      session
      |> Ecto.Changeset.change(connection_id: connection.id)
      |> Repo.update()
    end
  end

  def attach_to_session(session, _connection), do: {:ok, session}

  def deployment_model do
    case Application.get_env(:jido_ai, :model_aliases, %{}) do
      %{default: model} when is_binary(model) -> model
      _other -> nil
    end
  end

  defp from_session(%{connection_id: id}, user) when is_binary(id), do: get(id, user.id)
  defp from_session(_session, _user), do: nil

  defp legacy_config(%User{agent_api_key: key} = user) when is_binary(key) and key != "" do
    %TurnConfig{
      connection_id: nil,
      model: user.agent_model || deployment_model(),
      api_key: key,
      base_url: nil
    }
  end

  defp legacy_config(_user) do
    %TurnConfig{connection_id: nil, model: deployment_model(), api_key: nil, base_url: nil}
  end

  defp legacy_usable?(%User{} = user) do
    User.agent_key?(user) and is_binary(user.agent_model || deployment_model())
  end

  defp has_connection?(user_id) do
    Repo.exists?(from c in Connection, where: c.user_id == ^user_id)
  end

  defp count(user_id) do
    Repo.aggregate(from(c in Connection, where: c.user_id == ^user_id), :count)
  end

  defp most_recent(user_id) do
    from(c in Connection,
      where: c.user_id == ^user_id,
      order_by: [desc_nulls_last: c.last_used_at, desc: c.inserted_at],
      limit: 1
    )
    |> Repo.one()
  end

  defp promote_first(%User{} = user, %Connection{} = connection) do
    current = Repo.get(User, user.id)

    if current && is_nil(current.default_agent_connection_id) do
      current
      |> Ecto.Changeset.change(default_agent_connection_id: connection.id)
      |> Repo.update!()
    end
  end

  defp maybe_put_models(changeset, models) when is_list(models) do
    changeset
    |> Ecto.Changeset.put_change(:models, models |> Enum.uniq() |> Enum.take(500))
    |> Ecto.Changeset.put_change(:models_fetched_at, DateTime.utc_now())
  end

  defp maybe_put_models(changeset, _models), do: changeset

  defp keep_saved_key(attrs) when is_map(attrs) do
    case param(attrs, "api_key") do
      value when value in [nil, ""] ->
        attrs
        |> Map.delete("api_key")
        |> Map.delete(:api_key)

      _value ->
        attrs
    end
  end

  defp keep_saved_key(attrs), do: attrs

  defp param(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, String.to_atom(key))
end
