defmodule Psc.Repo.Migrations.AddEditStatsAndAiReview do
  use Ecto.Migration

  def change do
    alter table(:unstr_canvases) do
      # Per-cell edit counts and per-user edit/character totals, folded from the
      # event log at save time like `touch_map`. The Analysis overview reads it.
      add :edit_stats, :map, null: false, default: %{}
    end

    alter table(:canvas_insights) do
      # The AI review runs on demand, apart from the heuristic pass, so it keeps
      # its own fingerprint and time.
      add :ai_fingerprint, :string
      add :ai_computed_at, :utc_datetime_usec
    end
  end
end
