defmodule Psc.Canvas.Layout do
  use Ecto.Schema
  import Ecto.Changeset

  alias Psc.Canvas.Accent

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "canvas_layouts" do
    field :name, :string
    field :description, :string
    field :layout_map, :map, default: %{}
    field :shared_with, {:array, :string}, default: []

    belongs_to :author, Psc.Accounts.User, type: :id

    timestamps()
  end

  def changeset(layout, attrs) do
    layout
    |> cast(attrs, [:name, :description, :layout_map, :shared_with])
    |> validate_required([:name])
    |> unique_constraint(:name)
    |> validate_layout_map()
  end

  # Validates the template definition per docs/spec/creator.md:
  # - at least 1 row and 1 column
  # - every grid position has a cell key
  # - unique field keys within a cell
  defp validate_layout_map(changeset) do
    case get_field(changeset, :layout_map) do
      lm when is_map(lm) and map_size(lm) > 0 -> do_validate_layout_map(changeset, lm)
      _ -> changeset
    end
  end

  defp do_validate_layout_map(changeset, lm) do
    rows = lm["rows"] || []
    columns = lm["columns"] || []
    layout = lm["layout"] || []
    template_cells = lm["cells"] || %{}

    cond do
      Enum.empty?(rows) ->
        add_error(changeset, :layout_map, "template must have at least one row")

      Enum.empty?(columns) ->
        add_error(changeset, :layout_map, "template must have at least one column")

      grid_incomplete?(layout, length(rows), length(columns)) ->
        add_error(changeset, :layout_map, "every grid position must have a cell key")

      duplicate_fields?(template_cells) ->
        add_error(changeset, :layout_map, "field keys must be unique within a cell")

      invalid_accents?(rows, columns) ->
        add_error(changeset, :layout_map, "accents must be known color tokens")

      invalid_notes_mode?(lm) ->
        add_error(changeset, :layout_map, "notes mode must be known")

      true ->
        changeset
    end
  end

  # The note mode is optional: an older template without one keeps the default.
  defp invalid_notes_mode?(lm) do
    case lm["notes_mode"] do
      nil -> false
      mode -> mode not in Psc.Canvas.NotesMode.modes()
    end
  end

  defp grid_incomplete?(layout, row_count, column_count) do
    length(layout) != row_count or
      Enum.any?(layout, fn row -> length(row) != column_count or Enum.any?(row, &is_nil/1) end)
  end

  defp duplicate_fields?(template_cells) do
    Enum.any?(template_cells, fn {_key, meta} ->
      fields = meta["fields"] || []
      length(fields) != length(Enum.uniq(fields))
    end)
  end

  defp invalid_accents?(rows, columns) do
    Enum.any?(rows ++ columns, fn
      %{"accent" => accent} -> not Accent.valid?(accent)
      _meta -> false
    end)
  end
end
