defmodule Psc.Canvas.UnstrCanvas do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "unstr_canvases" do
    field :name, :string
    field :description, :string

    field :shared_with, {:array, :string}, default: []

    # How the canvas's Notes view behaves: "multi" (a list of notes) or
    # "single" (one scratchpad). Copied from the template.
    field :notes_mode, :string, default: "multi"

    belongs_to :author, Psc.Accounts.User, type: :id

    field :snapshot_seq, :integer, default: 0
    has_many :events, Psc.Canvas.UnstrCanvasEvent, foreign_key: :unstr_canvas_id

    # A note belongs to a canvas and inherits its access rules.
    has_many :notes, Psc.Notes.Note, foreign_key: :canvas_id, on_delete: :delete_all

    # An empty structure: a canvas with no rows and no columns yet. Anyone with
    # access builds it in place (structure editing); the built-in PSC grid is an
    # explicit choice (Canvas.psc_cells/0), not a silent default.
    field :cells, :map, default: %{"rows" => [], "columns" => [], "layout" => []}

    timestamps()
  end

  def changeset(unstr_canvas, attrs) do
    # Add a step to validate that cells has the correct structure
    unstr_canvas
    |> cast(attrs, [
      :name,
      :description,
      :author_id,
      :shared_with,
      :cells,
      :snapshot_seq,
      :notes_mode
    ])
    |> validate_required([:name, :author_id, :cells])
    |> validate_inclusion(:notes_mode, Psc.Canvas.NotesMode.modes())
    |> validate_cells_structure()
  end

  defp validate_cells_structure(changeset) do
    # Validates that the cells field contains all the keys outlined in the layout 2d array
    validate_change(changeset, :cells, fn :cells, cells ->
      layout = get_in(cells, ["layout"])

      if is_list(layout) and Enum.all?(layout, &is_list/1) do
        # Flatten the layout to get all cell keys
        cell_keys = layout |> List.flatten() |> Enum.uniq()

        # Metadata keys that should be excluded from cell validation
        metadata_keys = ["columns", "rows", "layout"]
        all_cell_keys = cells |> Map.keys() |> Enum.reject(&(&1 in metadata_keys))

        missing_keys = cell_keys -- all_cell_keys

        if missing_keys == [] do
          []
        else
          [cells: "Missing cell data for keys: #{Enum.join(missing_keys, ", ")}"]
        end
      else
        [cells: "Layout must be a 2D array of cell keys"]
      end
    end)
  end
end
