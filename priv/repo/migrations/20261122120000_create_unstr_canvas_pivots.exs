defmodule Psc.Repo.Migrations.CreateUnstrCanvasPivots do
  use Ecto.Migration

  def change do
    # Named snapshots of a canvas with the reason for the change. A pivot is a
    # full copy of the cells, not a delta: the event log is pruned on save, so
    # it cannot be the version history (ADR-001, open issue 1).
    create table(:unstr_canvas_pivots, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :unstr_canvas_id,
          references(:unstr_canvases, type: :binary_id, on_delete: :delete_all),
          null: false

      add :parent_id,
          references(:unstr_canvas_pivots, type: :binary_id, on_delete: :nilify_all)

      add :author_id, references(:users, on_delete: :nilify_all)
      add :name, :string, null: false
      add :rationale, :text, null: false
      add :kind, :string, null: false, default: "pivot"
      add :cells, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:unstr_canvas_pivots, [:unstr_canvas_id, :inserted_at])
  end
end
