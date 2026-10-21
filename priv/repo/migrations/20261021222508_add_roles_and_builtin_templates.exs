defmodule Psc.Repo.Migrations.AddRolesAndBuiltinTemplates do
  use Ecto.Migration

  def change do
    alter table(:users) do
      # Authorization is a role, not a boolean: the admin surface will grow
      # (built-in templates, catalog moderation) and a second role should not
      # need a migration.
      add :role, :string, null: false, default: "member"
    end

    alter table(:canvas_layouts) do
      # Built-in templates are seeded by the release task and shown to every
      # user. The slug is the stable identity used by the seed (upsert) and by
      # the picker, so a rename never creates a duplicate.
      add :built_in, :boolean, null: false, default: false
      add :slug, :string
    end

    create unique_index(:canvas_layouts, [:slug], where: "slug IS NOT NULL")
  end
end
