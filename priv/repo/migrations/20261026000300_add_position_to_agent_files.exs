defmodule Psc.Repo.Migrations.AddPositionToAgentFiles do
  use Ecto.Migration

  def change do
    alter table(:agent_files) do
      # Draft order, so the manifest and the editor list are deterministic even
      # when a whole set is replaced in one transaction.
      add :position, :integer, null: false, default: 0
    end
  end
end
