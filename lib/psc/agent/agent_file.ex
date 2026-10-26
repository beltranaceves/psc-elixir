defmodule Psc.Agent.AgentFile do
  @moduledoc """
  One reference document attached to a template or a canvas.

  Files are text, not binaries: they are read by the agent through
  `Psc.Agent.Tools.ReadFile`, and the free-tier database is the only storage
  this deployment has.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "agent_files" do
    # `path` is the identity and preserves a directory upload's tree
    # (`docs/spec/bento.md`); `name` is the basename for display.
    field :path, :string
    field :name, :string
    field :description, :string
    field :content, :string, default: ""
    field :byte_size, :integer, default: 0
    field :position, :integer, default: 0

    belongs_to :template, Psc.Canvas.Layout, type: :binary_id
    belongs_to :canvas, Psc.Canvas.UnstrCanvas, type: :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(file, attrs) do
    file
    |> cast(attrs, [
      :path,
      :name,
      :description,
      :content,
      :byte_size,
      :position,
      :template_id,
      :canvas_id
    ])
    |> validate_required([:path, :name, :byte_size])
    |> validate_length(:path, max: 240)
    |> validate_length(:name, max: 120)
    |> validate_length(:description, max: 200)
    |> unique_constraint([:template_id, :path], name: :agent_files_template_id_path_index)
    |> unique_constraint([:canvas_id, :path], name: :agent_files_canvas_id_path_index)
    |> check_constraint(:template_id, name: :agent_files_one_scope)
  end
end
