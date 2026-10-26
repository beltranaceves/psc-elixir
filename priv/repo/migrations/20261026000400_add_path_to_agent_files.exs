defmodule Psc.Repo.Migrations.AddPathToAgentFiles do
  use Ecto.Migration

  def up do
    alter table(:agent_files) do
      # The nested path a directory upload brings in. Existing flat files keep
      # their old name as their path.
      add :path, :string
    end

    execute("UPDATE agent_files SET path = name WHERE path IS NULL")

    alter table(:agent_files) do
      modify :path, :string, null: false
    end

    drop unique_index(:agent_files, [:template_id, :name],
           name: :agent_files_template_id_name_index
         )

    drop unique_index(:agent_files, [:canvas_id, :name], name: :agent_files_canvas_id_name_index)

    create unique_index(:agent_files, [:template_id, :path], where: "template_id IS NOT NULL")
    create unique_index(:agent_files, [:canvas_id, :path], where: "canvas_id IS NOT NULL")
  end

  def down do
    drop unique_index(:agent_files, [:template_id, :path],
           name: :agent_files_template_id_path_index
         )

    drop unique_index(:agent_files, [:canvas_id, :path], name: :agent_files_canvas_id_path_index)

    create unique_index(:agent_files, [:template_id, :name], where: "template_id IS NOT NULL")
    create unique_index(:agent_files, [:canvas_id, :name], where: "canvas_id IS NOT NULL")

    alter table(:agent_files) do
      remove :path
    end
  end
end
