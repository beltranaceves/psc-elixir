defmodule Psc.Repo.Migrations.AddSnapshotToDocuments do
  use Ecto.Migration

  def change do
    alter table(:documents) do
      add :snapshot_content, :text, default: ""
      add :snapshot_seq, :integer, default: 0
    end
  end
end
