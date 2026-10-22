defmodule Psc.Repo.Migrations.AddAgentModelToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      # "provider:model_id", e.g. "anthropic:claude-haiku-4-5". Null means the
      # deployment default (AGENT_MODEL).
      add :agent_model, :string
    end
  end
end
