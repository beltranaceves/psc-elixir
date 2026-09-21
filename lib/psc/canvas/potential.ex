defmodule Psc.Canvas.Potential do
  use Ecto.Schema
  import Ecto.Changeset

  embedded_schema do
    field :row, Ecto.Enum, values: [:strategy]
    field :column, Ecto.Enum, values: [:learn]
    field :content, :string
  end

  def changeset(cell, attrs) do
    cell
    |> cast(attrs, [:row, :column, :content])
  end
end
