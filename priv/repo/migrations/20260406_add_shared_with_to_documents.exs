defmodule Psc.Repo.Migrations.AddSharedWithToDocuments do
  use Ecto.Migration

  def change do
    alter table(:documents) do
      add :shared_with, {:array, :string}, default: [], null: false
    end
  end
end
