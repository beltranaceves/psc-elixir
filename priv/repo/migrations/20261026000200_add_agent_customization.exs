defmodule Psc.Repo.Migrations.AddAgentCustomization do
  use Ecto.Migration

  def up do
    alter table(:canvas_layouts) do
      add :agent_config, :map, null: false, default: %{}
    end

    alter table(:unstr_canvases) do
      add :agent_config, :map, null: false, default: %{}

      add :source_template_id,
          references(:canvas_layouts, type: :binary_id, on_delete: :nilify_all)

      add :agent_config_source_hash, :string
    end

    create table(:agent_files, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :template_id, references(:canvas_layouts, type: :binary_id, on_delete: :delete_all)
      add :canvas_id, references(:unstr_canvases, type: :binary_id, on_delete: :delete_all)

      add :name, :string, null: false
      add :description, :string
      add :content, :text, null: false, default: ""
      add :byte_size, :integer, null: false, default: 0

      timestamps(type: :utc_datetime_usec)
    end

    create index(:agent_files, [:template_id])
    create index(:agent_files, [:canvas_id])

    create unique_index(:agent_files, [:template_id, :name], where: "template_id IS NOT NULL")
    create unique_index(:agent_files, [:canvas_id, :name], where: "canvas_id IS NOT NULL")

    execute("""
    ALTER TABLE agent_files
    ADD CONSTRAINT agent_files_one_scope
    CHECK ((template_id IS NULL) <> (canvas_id IS NULL))
    """)

    alter table(:agent_sessions) do
      # The chat pins the profile it started with, so editing a canvas cannot
      # change an answer mid-conversation.
      add :role, :string
      add :profile, :map
    end
  end

  def down do
    alter table(:agent_sessions) do
      remove :role
      remove :profile
    end

    execute("ALTER TABLE agent_files DROP CONSTRAINT agent_files_one_scope")
    drop table(:agent_files)

    alter table(:unstr_canvases) do
      remove :agent_config_source_hash
      remove :source_template_id
      remove :agent_config
    end

    alter table(:canvas_layouts) do
      remove :agent_config
    end
  end
end
