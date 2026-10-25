defmodule Psc.Repo.Migrations.CreateAgentConnections do
  use Ecto.Migration

  def up do
    create table(:agent_connections, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :provider, :string, null: false
      add :model_id, :string, null: false
      add :api_key, :text
      add :key_hint, :string
      add :base_url, :string
      add :models, {:array, :string}, null: false, default: []
      add :models_fetched_at, :utc_datetime_usec
      add :last_used_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:agent_connections, [:user_id, :name])
    create index(:agent_connections, [:user_id, :last_used_at])

    alter table(:users) do
      add :default_agent_connection_id,
          references(:agent_connections, type: :binary_id, on_delete: :nilify_all)
    end

    alter table(:agent_sessions) do
      add :connection_id, references(:agent_connections, type: :binary_id, on_delete: :nilify_all)
    end

    alter table(:agent_messages) do
      add :model, :string
    end

    flush()

    # Users who already had a complete provider:model pair keep it as their
    # default connection. Incomplete pairs (a key without a model) cannot be
    # migrated and are left for the user to re-enter once.
    execute("""
    INSERT INTO agent_connections
      (id, user_id, name, provider, model_id, api_key, key_hint, inserted_at, updated_at)
    SELECT
      gen_random_uuid(),
      u.id,
      'My ' || split_part(u.agent_model, ':', 1) || ' connection',
      split_part(u.agent_model, ':', 1),
      substring(u.agent_model from position(':' in u.agent_model) + 1),
      u.agent_api_key,
      '…' || right(u.agent_api_key, 4),
      now(),
      now()
    FROM users u
    WHERE u.agent_api_key IS NOT NULL
      AND u.agent_api_key <> ''
      AND u.agent_model LIKE '%:%'
    """)

    execute("""
    UPDATE users u
    SET default_agent_connection_id = c.id
    FROM agent_connections c
    WHERE c.user_id = u.id
    """)
  end

  def down do
    alter table(:agent_messages) do
      remove :model
    end

    alter table(:agent_sessions) do
      remove :connection_id
    end

    alter table(:users) do
      remove :default_agent_connection_id
    end

    drop table(:agent_connections)
  end
end
