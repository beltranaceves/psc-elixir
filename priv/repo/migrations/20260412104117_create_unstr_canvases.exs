defmodule Psc.Repo.Migrations.CreateUnstrCanvases do
  use Ecto.Migration

  def change do
    create table(:unstr_canvases, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :author_id, references(:users, on_delete: :delete_all), null: false
      add :shared_with, {:array, :string}, default: [], null: false

      # Flexible canvas structure: columns, rows, layout, and all cells
      add :cells, :map

      timestamps()
    end

    create index(:unstr_canvases, [:author_id])
  end
end
