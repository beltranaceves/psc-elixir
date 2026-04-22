defmodule Psc.Canvas.UnstrCanvasEvent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "unstr_canvas_events" do
    field :operation, :map
    field :seq, :integer

    belongs_to :unstr_canvas, Psc.Canvas.UnstrCanvas
    belongs_to :user, Psc.Accounts.User, type: :id

    timestamps()
  end

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:operation, :seq, :unstr_canvas_id, :user_id])
    |> validate_required([:operation, :seq, :unstr_canvas_id, :user_id])
  end
end
