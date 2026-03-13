defmodule Psc.Canvas.Merit do
  use Ecto.Schema
  import Ecto.Changeset

  embedded_schema do
    field :row, Ecto.Enum, values: [:tactics]
    field :column, Ecto.Enum, values: [:consolidate]
    field :merit, :string
    field :value, :string
    field :reservation, :string
    field :rebuttal, :string
  end

  def changeset(cell, attrs) do
    cell
    |> cast(attrs, [:row, :column, :merit, :value, :reservation, :rebuttal])
    |> validate_required([:row, :column, :merit, :value, :reservation, :rebuttal])
  end
end
