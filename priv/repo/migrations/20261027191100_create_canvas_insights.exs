defmodule Psc.Repo.Migrations.CreateCanvasInsights do
  use Ecto.Migration

  def change do
    # One row per canvas: the latest analysis result. Findings live inside the
    # row instead of getting a table of their own, because the deployed
    # free-tier Postgres caps every table at 10k rows.
    create table(:canvas_insights, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :canvas_id, references(:unstr_canvases, type: :binary_id, on_delete: :delete_all),
        null: false

      add :fingerprint, :string, null: false
      add :snapshot_seq, :integer, null: false, default: 0
      add :computed_at, :utc_datetime_usec, null: false
      add :mode, :string, null: false, default: "heuristic"
      add :provider, :string
      add :model, :string
      add :findings, {:array, :map}, null: false, default: []
      add :dismissed, {:array, :string}, null: false, default: []
      add :stats, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:canvas_insights, [:canvas_id])
  end
end
