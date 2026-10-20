defmodule Psc.Documents.Store do
  @moduledoc """
  The shape of a document as a collaborative text store.

  Documents and notes share the same machinery (`Psc.TextStore`); this module
  is where a document declares its own tables, fields and topic.
  """

  @behaviour Psc.TextStore

  alias Psc.Documents.{Document, DocumentEvent}

  @impl Psc.TextStore
  def store, do: Document

  @impl Psc.TextStore
  def event, do: DocumentEvent

  @impl Psc.TextStore
  def foreign_key, do: :document_id

  @impl Psc.TextStore
  def content_field, do: :content

  @impl Psc.TextStore
  def topic(id), do: Psc.Documents.pubsub_topic(id)

  @impl Psc.TextStore
  def event_tag, do: :operation
end
