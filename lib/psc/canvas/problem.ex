defmodule Psc.Canvas.Problem do
  use Ecto.Schema
  import Ecto.Changeset

  embedded_schema do
    field :row, Ecto.Enum, values: [:rationale]
    field :column, Ecto.Enum, values: [:perceive]
    field :content, :string
  end

  def changeset(cell, attrs) do
    cell
    |> cast(attrs, [:row, :column, :content])
    |> validate_required([:row, :column, :content])
  end
end