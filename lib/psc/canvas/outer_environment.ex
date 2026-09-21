defmodule Psc.Canvas.OuterEnvironment do
  use Ecto.Schema
  import Ecto.Changeset

  embedded_schema do
    field :row, Ecto.Enum, values: [:strategy]
    field :column, Ecto.Enum, values: [:perceive]
    field :external_services, :string
    field :external_implements, :string
    field :external_repositories, :string
    field :external_people, :string
  end

  def changeset(cell, attrs) do
    cell
    |> cast(attrs, [
      :row,
      :column,
      :external_services,
      :external_implements,
      :external_repositories,
      :external_people
    ])
  end
end
