defmodule Psc.Repo.Migrations.AddCatalogToCanvasLayouts do
  use Ecto.Migration

  def change do
    alter table(:canvas_layouts) do
      add :public, :boolean, default: false, null: false
      add :use_count, :integer, default: 0, null: false
      add :fork_count, :integer, default: 0, null: false
      add :forked_from_id, references(:canvas_layouts, type: :binary_id, on_delete: :nilify_all)
    end
  end
end
