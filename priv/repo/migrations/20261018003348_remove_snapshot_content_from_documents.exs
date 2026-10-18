defmodule Psc.Repo.Migrations.RemoveSnapshotContentFromDocuments do
  use Ecto.Migration

  # `documents.content` is the folded snapshot; `snapshot_content` was a second,
  # never-read copy of the same text.
  def change do
    alter table(:documents) do
      remove :snapshot_content
    end
  end
end
