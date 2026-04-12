defmodule Psc.Repo.Migrations.CreateCanvases do
  use Ecto.Migration

  def change do
    create table(:canvases, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :author_id, references(:users, on_delete: :delete_all), null: false
      add :shared_with, {:array, :string}, default: [], null: false

      # 12 Canvas cells stored as JSONB
      add :problem, :map
      add :leverage, :map
      add :solution_cluster, :map
      add :horizon, :map
      add :outer_environment, :map
      add :inner_environment, :map
      add :evolvability_cluster, :map
      add :potential, :map
      add :manifestations, :map
      add :capabilities, :map
      add :merit_cluster, :map
      add :mission, :map

      timestamps()
    end

    create index(:canvases, [:author_id])
  end
end
