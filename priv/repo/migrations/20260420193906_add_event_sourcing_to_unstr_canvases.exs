defmodule Psc.Repo.Migrations.AddEventSourcingToUnstrCanvases do
  use Ecto.Migration

  def change do
    alter table(:unstr_canvases) do
      add :snapshot_seq, :integer, default: 0
    end

    create table(:unstr_canvas_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :operation, :map, null: false
      add :seq, :integer, null: false
      add :unstr_canvas_id, references(:unstr_canvases, on_delete: :delete_all, type: :binary_id), null: false
      add :user_id, references(:users, on_delete: :nilify_all), null: true

      timestamps()
    end

    create index(:unstr_canvas_events, [:unstr_canvas_id, :seq])
  end
end
