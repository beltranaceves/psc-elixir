defmodule Psc.Canvas.Horizon do
  # TODO: this module is actually much more complex, but requires more understanding from my part
  use Ecto.Schema
  import Ecto.Changeset

  embedded_schema do
    field :row, Ecto.Enum, values: [:rationale]
    field :column, Ecto.Enum, values: [:learn]
    field :content, :string
  end

  def changeset(cell, attrs) do
    cell
    |> cast(attrs, [:row, :column, :content])
  end
end
