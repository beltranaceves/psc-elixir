defmodule Psc.Notes.NoteEvent do
  @moduledoc """
  One operation in a note's event log.

  The log is a write-ahead log: the note's `content` is the folded snapshot and
  the events above its `snapshot_seq` are what still have to be replayed.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "note_events" do
    field :operation, :map
    field :seq, :integer

    belongs_to :note, Psc.Notes.Note, type: :binary_id
    belongs_to :user, Psc.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:operation, :seq, :note_id, :user_id])
    |> validate_required([:operation, :seq, :note_id])
    |> foreign_key_constraint(:note_id)
  end
end
