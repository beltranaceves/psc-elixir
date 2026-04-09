defmodule Psc.Canvas.EvolvabilityCluster do
  use Ecto.Schema
  import Ecto.Changeset

  embedded_schema do
    field :row, Ecto.Enum, values: [:strategy]
    field :column, Ecto.Enum, values: [:consolidate]
    field :evolvability, :string
    field :diffusibility, :string
    field :adoptability, :string
  end

  def changeset(cell, attrs) do
    cell
    |> cast(attrs, [:row, :column, :evolvability, :diffusibility, :adoptability])
  end
end
