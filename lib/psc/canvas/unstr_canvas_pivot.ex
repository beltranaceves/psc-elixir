defmodule Psc.Canvas.UnstrCanvasPivot do
  @moduledoc """
  A version of a canvas: a snapshot of its cells, and, once someone names it,
  the reason for the change (ADR-043).

  Versions form a tree through `parent_id`. The canvas points at the version it
  currently holds (`unstr_canvases.head_pivot_id`). Editing a named version
  starts a `"draft"` under it, which collects the edits until it is named
  (`"pivot"`). `"restore"` is a legacy kind from before versions were loaded
  instead of restored; those rows read as named versions.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "unstr_canvas_pivots" do
    field :name, :string
    field :rationale, :string
    field :kind, :string, default: "pivot"
    field :cells, :map, default: %{}

    belongs_to :unstr_canvas, Psc.Canvas.UnstrCanvas
    belongs_to :parent, __MODULE__
    belongs_to :author, Psc.Accounts.User, type: :id

    timestamps(type: :utc_datetime_usec)
  end

  @doc "A draft: unnamed edits under the version they started from."
  def draft?(%__MODULE__{kind: kind}), do: kind == "draft"

  @doc """
  Naming a version: the name and the reason are required. The canvas, parent,
  author, kind and cells are set by `Psc.Canvas`, never cast from a form.
  """
  def changeset(pivot, attrs) do
    pivot
    |> cast(attrs, [:name, :rationale])
    |> update_change(:name, &String.trim/1)
    |> update_change(:rationale, &String.trim/1)
    |> validate_required([:name, :rationale])
    |> validate_length(:name, max: 120)
    |> validate_length(:rationale, max: 2000)
  end
end
