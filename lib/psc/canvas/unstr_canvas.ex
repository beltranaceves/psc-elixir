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

    # Copied from the source template on instantiation and editable afterwards.
    # The source fields are set by the context, never by a request.
    field :agent_config, :map, default: %{}
    field :source_template_id, :binary_id
    field :agent_config_source_hash, :string

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
      :notes_mode,
      :agent_config
    ])
    |> update_change(:agent_config, &Psc.Agent.Config.normalize/1)
    |> validate_required([:name, :author_id, :cells])
    |> validate_inclusion(:notes_mode, Psc.Canvas.NotesMode.modes())
    |> validate_cells_structure()
  end

  defp validate_cells_structure(changeset) do
    # The shape rules live in Psc.Canvas.Structure: a table needs the matrix,
    # a bento needs bounded placements, and an empty canvas is valid in both.
    validate_change(changeset, :cells, fn :cells, cells ->
      case Psc.Canvas.Structure.validate(cells) do
        :ok -> []
        {:error, _field, message} -> [cells: message]
      end
    end)
  end
end
