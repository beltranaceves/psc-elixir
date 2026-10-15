defmodule Psc.Repo.Migrations.AddSharingToCanvasLayouts do
  use Ecto.Migration

  def change do
    alter table(:canvas_layouts) do
      add :shared_with, {:array, :string}, default: []
    end

    alter table(:canvas_layouts) do
      add :author_id, references(:users, on_delete: :nilify_all)
    end

    create index(:canvas_layouts, [:author_id])
  end
end
