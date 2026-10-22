defmodule Psc.Repo.Migrations.AddAgentApiKeyToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      # A per-user provider key. Write-only in the UI: it is never rendered back.
      add :agent_api_key, :text
    end
  end
end
