defmodule Psc.Notes.Store do
  @moduledoc """
  The shape of a note as a collaborative text store.

  Notes and documents share the same machinery (`Psc.TextStore`); this module is
  where a note declares its own tables, fields and topic.
  """

  @behaviour Psc.TextStore

  alias Psc.Notes.{Note, NoteEvent}

  @impl Psc.TextStore
  def store, do: Note

  @impl Psc.TextStore
  def event, do: NoteEvent

  @impl Psc.TextStore
  def foreign_key, do: :note_id

  @impl Psc.TextStore
  def content_field, do: :content

  @impl Psc.TextStore
  def topic(id), do: Psc.Notes.pubsub_topic(id)
end
