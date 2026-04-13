defmodule Psc.Repo.Migrations.CreateCanvasLayouts do
  use Ecto.Migration

  def change do
    create table(:canvas_layouts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :layout_map, :map, default: %{}

      timestamps()
    end

    create unique_index(:canvas_layouts, [:name])
  end
end
