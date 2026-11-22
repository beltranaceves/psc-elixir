defmodule Psc.Repo.Migrations.AddHeadAndDraftsToPivots do
  use Ecto.Migration

  def up do
    # The version the canvas currently holds (git's HEAD). Editing a named
    # version starts a draft under it; loading a version moves the pointer.
    alter table(:unstr_canvases) do
      add :head_pivot_id,
          references(:unstr_canvas_pivots, type: :binary_id, on_delete: :nilify_all)
    end

    # A draft has no name or reason until someone gives it one.
    alter table(:unstr_canvas_pivots) do
      modify :name, :string, null: true, from: {:string, null: false}
      modify :rationale, :text, null: true, from: {:text, null: false}
    end

    # Existing canvases point at their latest pivot.
    execute """
    UPDATE unstr_canvases c
    SET head_pivot_id = (
      SELECT p.id FROM unstr_canvas_pivots p
      WHERE p.unstr_canvas_id = c.id
      ORDER BY p.inserted_at DESC
      LIMIT 1
    )
    """
  end

  def down do
    execute "DELETE FROM unstr_canvas_pivots WHERE kind = 'draft'"

    alter table(:unstr_canvas_pivots) do
      modify :name, :string, null: false, from: {:string, null: true}
      modify :rationale, :text, null: false, from: {:text, null: true}
    end

    alter table(:unstr_canvases) do
      remove :head_pivot_id
    end
  end
end
