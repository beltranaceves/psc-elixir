defmodule Psc.Repo.Migrations.ScopeAgentSessionsToCanvas do
  use Ecto.Migration

  def change do
    alter table(:agent_sessions) do
      # The agent belongs to a canvas: its tab, its transcript, its scope.
      add :canvas_id, references(:unstr_canvases, type: :binary_id, on_delete: :delete_all)
    end

    create index(:agent_sessions, [:canvas_id, :last_message_at])
  end
end
