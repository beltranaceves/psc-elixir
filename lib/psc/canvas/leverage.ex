defmodule Psc.Canvas.Leverage do
  use Ecto.Schema
  import Ecto.Changeset

  embedded_schema do
    field :row, Ecto.Enum, values: [:rationale]
    field :column, Ecto.Enum, values: [:form]
    field :technology, :string
    field :components, :string
    field :information, :string
    field :human_resources, :string
  end

  def changeset(cell, attrs) do
    cell
    |> cast(attrs, [:row, :column, :technology, :components, :information, :human_resources])
    |> validate_required([:row, :column, :technology, :components, :information, :human_resources])
  end
end
