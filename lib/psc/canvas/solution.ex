defmodule Psc.Canvas.Solution do
  use Ecto.Schema
  import Ecto.Changeset

  embedded_schema do
    field :row, Ecto.Enum, values: [:rationale]
    field :column, Ecto.Enum, values: [:consolidate]
    field :solution, :string
    field :prospect, :string
    field :warrant, :string
    field :backing, :string
  end

  def changeset(cell, attrs) do
    cell
    |> cast(attrs, [:row, :column, :solution, :prospect, :warrant, :backing])
    |> validate_required([:row, :column, :solution, :prospect, :warrant, :backing])
  end
end
