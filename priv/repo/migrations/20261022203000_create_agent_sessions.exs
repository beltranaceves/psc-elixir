defmodule Psc.Repo.Migrations.CreateAgentSessions do
  use Ecto.Migration

  def change do
    create table(:agent_sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :title, :string, null: false, default: "New chat"
      add :message_count, :integer, null: false, default: 0
      add :last_message_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:agent_sessions, [:user_id, :last_message_at])

    create table(:agent_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :session_id, references(:agent_sessions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :role, :string, null: false
      add :content, :text, null: false, default: ""
      add :status, :string, null: false, default: "complete"
      add :error, :text
      add :tool_calls, {:array, :map}, null: false, default: []
      add :usage, :map

      # Microseconds, not seconds: a turn inserts the user message and the
      # assistant placeholder in the same second, and both the transcript order
      # and the pruning order have to be unambiguous.
      timestamps(type: :utc_datetime_usec)
    end

    create index(:agent_messages, [:session_id, :inserted_at])
  end
end
