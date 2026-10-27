defmodule Psc.Repo.Migrations.AddTouchMapToUnstrCanvases do
  use Ecto.Migration

  def change do
    alter table(:unstr_canvases) do
      # Per-cell last-edit timestamps, folded from the event log at save time.
      # It stays out of `cells` so the CRDT state, templates and previews keep
      # their shape; the insights "stale" detector is the only reader.
      add :touch_map, :map, null: false, default: %{}
    end
  end
end
