defmodule Psc.Notes do
  @moduledoc """
  Notes: collaborative Markdown that belongs to a canvas.

  A note is a child of its canvas. This context deliberately holds **no access
  rules**: a note's access is its canvas's access, checked once by
  `Psc.Canvas.can_access_unstr_canvas?/2` when the canvas editor mounts. There
  is no `shared_with` list to keep in sync and no share control on a note
  (ADR-027).

  The collaboration machinery — the event log, the folded snapshot, the
  sequencing, the pruning — lives in `Psc.TextStore` and is shared with the
  documents.
  """

  import Ecto.Query, warn: false
  alias Psc.Repo
  alias Psc.Notes.{Note, NoteEvent, Store}
  alias Psc.TextStore

  @pubsub_topic_prefix "note:"

  def pubsub_topic(note_id), do: "#{@pubsub_topic_prefix}#{note_id}"

  @doc """
  The notes of a canvas, most recently touched first.
  """
  def list_notes(canvas_id) do
    from(n in Note,
      where: n.canvas_id == ^canvas_id,
      order_by: [desc: n.updated_at, desc: n.inserted_at]
    )
    |> preload(:created_by)
    |> Repo.all()
  end

  @doc """
  Get a single note.
  """
  def get_note(id) do
    Repo.get(Note, id)
  end

  @doc """
  Get a note with its author preloaded.
  """
  def get_note_with_author(id) do
    Note
    |> preload(:created_by)
    |> Repo.get(id)
  end

  @doc """
  Create a note on a canvas.
  """
  def create_note(canvas_id, user_id, attrs \\ %{}) do
    %Note{}
    |> Note.changeset(
      Map.merge(attrs, %{
        canvas_id: canvas_id,
        created_by_id: user_id,
        content: Map.get(attrs, :content, "") || ""
      })
    )
    |> Repo.insert()
  end

  @doc """
  Copy a template's notes onto a canvas.

  A template's notes are part of its definition, so a canvas made from it
  starts with the same notes. The copy is independent: editing a note in the
  canvas never touches the template (ADR-009).

  Each entry is `%{"title" => ..., "content" => ...}`. A template that
  carries no notes simply produces a canvas without any.
  """
  def seed_notes(canvas, notes) do
    author_id = canvas.author_id

    Enum.each(List.wrap(notes), fn note ->
      create_note(canvas.id, author_id, %{
        title: note["title"] || "Untitled note",
        content: note["content"] || ""
      })
    end)

    canvas
  end

  @doc """
  Update a note's title and content.
  """
  def update_note(note, attrs) do
    note
    |> Note.changeset(attrs)
    |> Repo.update(stale_error_field: :base)
  end

  @doc """
  Delete a note. Its events go with it, through the database's cascade.
  """
  def delete_note(note) do
    Repo.delete(note)
  end

  @doc """
  Apply an operation to the note and broadcast it.

  Only the event is persisted here; the content is folded separately by
  `save_content_to_db/2` on the idle or periodic timer.

  `client_id` identifies the editing client (one LiveView process): the echo
  is then ignored by that process alone, so a second tab or browser of the
  same user still receives the edit.
  """
  def apply_operation(note_id, user_id, operation, client_id) do
    TextStore.apply_operation(Store, note_id, user_id, operation, client_id)
  end

  def apply_operation(note_id, user_id, operation) do
    TextStore.apply_operation(Store, note_id, user_id, operation)
  end

  @doc """
  Fold the content into the note and prune the events it covers.
  """
  def save_content_to_db(note_id, content) do
    TextStore.save_content(Store, note_id, content)
  end

  @doc """
  The note's content: the folded snapshot plus the events after it.
  """
  def get_note_content(note_id) do
    TextStore.load_content(Store, note_id)
  end

  @doc """
  Build the note's content from its event log.
  """
  def build_content_from_events(note_id) do
    TextStore.load_content(Store, note_id)
  end

  @doc """
  The number of operations not yet folded into the note's content.
  """
  def pending_event_count(note_id) do
    TextStore.pending_event_count(Store, note_id)
  end

  @doc """
  Convert text changes to delta operations.
  """
  def text_to_operations(old_text, new_text) do
    Psc.Text.text_to_deltas(old_text, new_text)
  end

  @doc """
  Delete events already folded into a note's saved content.

  Pruning normally happens on every save, but it only ever touches notes that
  are edited again — a note abandoned before its first save keeps its tail of
  events forever. This sweeps every row at or below its owner's
  `snapshot_seq`. Returns the number of deleted rows.
  """
  def sweep_folded_events do
    TextStore.sweep_folded_events(Store)
  end

  @doc """
  The event schema of a note.
  """
  def event_module, do: NoteEvent
end
