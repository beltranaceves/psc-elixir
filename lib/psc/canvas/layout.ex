defmodule Psc.Canvas.Layout do
  use Ecto.Schema
  import Ecto.Changeset

  alias Psc.Canvas.Structure

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "canvas_layouts" do
    field :name, :string
    field :description, :string
    field :layout_map, :map, default: %{}
    field :shared_with, {:array, :string}, default: []

    # The catalog. `:public` is the owner's choice; the counts and the lineage
    # are set by the context, never by a request, so they stay out of the cast.
    field :public, :boolean, default: false
    field :use_count, :integer, default: 0
    field :fork_count, :integer, default: 0
    field :forked_from_id, :binary_id

    # Seeded templates, managed from the admin. Both fields are system-set:
    # `built_in` and `slug` stay out of the changeset's cast list so a form
    # cannot turn a user template into a built-in (or claim a slug).
    field :built_in, :boolean, default: false
    field :slug, :string

    belongs_to :author, Psc.Accounts.User, type: :id

    timestamps()
  end

  def changeset(layout, attrs) do
    layout
    |> cast(attrs, [:name, :description, :layout_map, :shared_with, :public])
    |> validate_required([:name])
    |> unique_constraint(:name)
    |> validate_layout_map()
  end

  # The shape rules live in Psc.Canvas.Structure: table templates need a
  # complete matrix, bento templates need bounded placements. Notes mode and
  # accents are checked in both modes.
  defp validate_layout_map(changeset) do
    case get_field(changeset, :layout_map) do
      lm when is_map(lm) and map_size(lm) > 0 ->
        case Structure.validate_template(lm) do
          :ok -> changeset
          {:error, _field, message} -> add_error(changeset, :layout_map, message)
        end

      _other ->
        changeset
    end
  end
end
