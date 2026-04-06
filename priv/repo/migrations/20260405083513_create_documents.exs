defmodule Psc.Repo.Migrations.CreateDocuments do
  use Ecto.Migration

  def change do
    create table(:documents) do
      add :title, :string, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :content, :text, default: ""
      add :crdt_state, :string, default: ""

      timestamps()
    end

    create index(:documents, [:user_id])

    create table(:document_events) do
      add :document_id, references(:documents, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :operation, :map, null: false
      add :seq, :integer, null: false

      timestamps()
    end

    create index(:document_events, [:document_id])
    create unique_index(:document_events, [:document_id, :seq])
  end
end
