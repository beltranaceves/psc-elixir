defmodule Psc.Repo.Migrations.CreateNotesAndNoteEvents do
  use Ecto.Migration

  def change do
    # A note belongs to a canvas. It carries no `shared_with` and no owner:
    # its access is exactly its canvas's access (ADR-027).
    create table(:notes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string

      # The folded snapshot of the note's Markdown. There is no second copy.
      add :content, :text, default: ""
      add :snapshot_seq, :integer, default: 0

      add :canvas_id, references(:unstr_canvases, on_delete: :delete_all, type: :binary_id),
        null: false

      # Who wrote the note. Attribution only — never used for access control.
      add :created_by_id, references(:users, on_delete: :nilify_all), null: true

      timestamps(type: :utc_datetime)
    end

    create index(:notes, [:canvas_id])
    create index(:notes, [:created_by_id])

    create table(:note_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :operation, :map, null: false
      add :seq, :integer, null: false

      add :note_id, references(:notes, on_delete: :delete_all, type: :binary_id), null: false

      # Who made the edit: used to avoid echoing a user's own operation back
      # to them, and for audit.
      add :user_id, references(:users, on_delete: :nilify_all), null: true

      timestamps(type: :utc_datetime)
    end

    create index(:note_events, [:note_id])
    create unique_index(:note_events, [:note_id, :seq])
  end
end
