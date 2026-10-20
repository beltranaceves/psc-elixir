defmodule Psc.Notes.Note do
  @moduledoc """
  A note: collaborative Markdown that belongs to a canvas.

  A note carries no `shared_with` and no owner. Its access is exactly its
  canvas's access, checked once when the canvas editor mounts (ADR-027).
  `created_by_id` records who wrote it — attribution, never a permission.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "notes" do
    field :title, :string
    field :content, :string
    field :snapshot_seq, :integer, default: 0

    belongs_to :canvas, Psc.Canvas.UnstrCanvas, type: :binary_id
    belongs_to :created_by, Psc.Accounts.User

    has_many :events, Psc.Notes.NoteEvent, foreign_key: :note_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(note, attrs) do
    note
    |> cast(attrs, [:title, :content, :canvas_id, :created_by_id, :snapshot_seq])
    |> validate_required([:canvas_id])
    |> foreign_key_constraint(:canvas_id)
  end
end
