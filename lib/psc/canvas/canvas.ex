defmodule Psc.Canvas.Canvas do
  use Ecto.Schema
  import Ecto.Changeset

  schema "canvases" do
    field :name, :string
    field :description, :string

    belongs_to :author, Psc.Accounts.User, type: :binary_id

    embeds_many :permissions, Psc.Canvas.Permission, on_replace: :delete

    # All 12 cells
    embeds_one :problem, Psc.Canvas.Problem, on_replace: :delete
    embeds_one :leverage, Psc.Canvas.Leverage, on_replace: :delete
    embeds_one :solution_cluster, Psc.Canvas.SolutionCluster, on_replace: :delete
    embeds_one :horizon, Psc.Canvas.Horizon, on_replace: :delete
    embeds_one :outer_environment, Psc.Canvas.OuterEnvironment, on_replace: :delete
    embeds_one :inner_environment, Psc.Canvas.InnerEnvironment, on_replace: :delete
    embeds_one :evolvability_cluster, Psc.Canvas.EvolvabilityCluster, on_replace: :delete
    embeds_one :potential, Psc.Canvas.Potential, on_replace: :delete
    embeds_one :manifestations, Psc.Canvas.Manifestations, on_replace: :delete
    embeds_one :capabilities, Psc.Canvas.Capabilities, on_replace: :delete
    embeds_one :merit_cluster, Psc.Canvas.MeritCluster, on_replace: :delete
    embeds_one :mission, Psc.Canvas.Mission, on_replace: :delete

    timestamps()
  end

  def changeset(canvas, attrs) do
    canvas
    |> cast(attrs, [:name, :description, :author_id])
    |> validate_required([:name, :author_id])
    |> cast_embed(:permissions)
    |> cast_embed(:problem)
    |> cast_embed(:leverage)
    |> cast_embed(:solution_cluster)
    |> cast_embed(:horizon)
    |> cast_embed(:outer_environment)
    |> cast_embed(:inner_environment)
    |> cast_embed(:evolvability_cluster)
    |> cast_embed(:potential)
    |> cast_embed(:manifestations)
    |> cast_embed(:capabilities)
    |> cast_embed(:merit_cluster)
    |> cast_embed(:mission)
  end
end
