defmodule Psc.Canvas.Layout do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "canvas_layouts" do
    field :name, :string
    field :description, :string
    field :layout_map, :map, default: %{}

    timestamps()
  end

  def changeset(layout, attrs) do
    layout
    |> cast(attrs, [:name, :description, :layout_map])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end
