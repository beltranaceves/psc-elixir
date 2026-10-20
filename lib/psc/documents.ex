defmodule Psc.Documents do
  @moduledoc """
  The Documents context for managing collaborative text documents with CRDTs.

  The collaboration machinery — the event log, the folded snapshot, the
  sequencing, the pruning and the consistency check — lives in `Psc.TextStore`
  and is shared with the notes. This module is the document-shaped façade over
  it.
  """

  import Ecto.Query, warn: false
  alias Psc.Repo
  alias Psc.Documents.{Document, DocumentEvent, Store}
  alias Psc.TextStore

  @pubsub_topic_prefix "document:"

  def pubsub_topic(document_id), do: "#{@pubsub_topic_prefix}#{document_id}"

  @doc """
  List all documents for a user.
  """
  def list_user_documents(user_id) do
    from(d in Document, where: d.user_id == ^user_id, order_by: [desc: d.updated_at])
    |> preload(:user)
    |> Repo.all()
  end

  @doc """
  List all documents shared with a user by email.
  """
  def list_shared_documents(user_email) do
    from(d in Document,
      where: fragment("? = ANY(?)", ^user_email, d.shared_with),
      order_by: [desc: d.updated_at]
    )
    |> preload(:user)
    |> Repo.all()
  end

  @doc """
  Get a single document.
  """
  def get_document(id) do
    Repo.get(Document, id)
  end

  @doc """
  Get a document with preloaded events.
  """
  def get_document_with_events(id) do
    Document
    |> preload(:events)
    |> Repo.get!(id)
  end

  @doc """
  Create a new document.
  """
  def create_document(user_id, attrs \\ %{}) do
    Document.changeset(%Document{}, Map.merge(attrs, %{user_id: user_id, crdt_state: ""}))
    |> Repo.insert()
  end

  @doc """
  Update document title.
  """
  def update_document_title(document, title) do
    document
    |> Document.changeset(%{title: title})
    |> Repo.update()
  end

  @doc """
  Share a document with a user by email.
  """
  def share_document_with(document, email) do
    new_shared_with =
      (document.shared_with || [])
      |> Enum.uniq()
      |> then(&(&1 ++ [email]))
      |> Enum.uniq()

    document
    |> Document.changeset(%{shared_with: new_shared_with})
    |> Repo.update()
  end

  @doc """
  Remove a user's access to a document.
  """
  def unshare_document(document, email) do
    new_shared_with =
      document.shared_with
      |> Enum.reject(&(&1 == email))

    document
    |> Document.changeset(%{shared_with: new_shared_with})
    |> Repo.update()
  end

  @doc """
  Check if a user can access a document (owner or shared with them).
  """
  def can_access_document?(document, user_email) do
    document.user.email == user_email ||
      Enum.any?(document.shared_with, &(&1 == user_email))
  end

  @doc """
  Apply an operation to the document and broadcast it.
  The operation is a delta in the format:
  %{"type" => "insert", "pos" => pos, "char" => char}
  %{"type" => "delete", "pos" => pos}

  NOTE: This only persists the event and broadcasts it.
  Content is persisted separately via save_content_to_db/2 on idle/timer.
  """
  def apply_operation(document_id, user_id, operation) do
    TextStore.apply_operation(Store, document_id, user_id, operation)
  end

  @doc """
  Save content to database. Used on idle/timer triggers.
  Also updates snapshot_seq to indicate the content is built through which event sequence.
  This ensures proper loading: we load content + replay events after snapshot_seq.
  """
  def save_content_to_db(document_id, content) do
    TextStore.save_content(Store, document_id, content)
  end

  @doc """
  Build content from events using snapshots for efficiency.
  If a snapshot exists, only replays events after it.
  Much faster than replaying all events from the beginning.
  """
  def build_content_from_events(document_id) do
    TextStore.load_content(Store, document_id)
  end

  @doc """
  Get document content - uses snapshots for faster loading.
  """
  def get_document_content(document_id) do
    TextStore.load_content(Store, document_id)
  end

  @doc """
  Get snapshot statistics for a document.
  """
  def get_snapshot_stats(document_id) do
    document = Repo.get!(Document, document_id)
    snapshot_seq = document.snapshot_seq || 0

    %{
      document_id: document_id,
      snapshot_seq: snapshot_seq,
      content_bytes: byte_size(document.content || ""),
      pending_events: TextStore.pending_event_count(Store, document_id)
    }
  end

  @doc """
  Number of pending (not yet folded into `content`) operations for a document.
  """
  def pending_event_count(document_id) do
    TextStore.pending_event_count(Store, document_id)
  end

  @doc """
  Delete events that are already folded into the saved content.

  Pruning normally happens on every save, but it only ever touches documents
  that are edited again — a document abandoned before its first idle save keeps
  its tail of events forever. This sweeps every row at or below its owner's
  `snapshot_seq`. Returns the number of deleted rows.
  """
  def sweep_folded_events do
    TextStore.sweep_folded_events(Store)
  end

  @doc """
  Convert text changes to delta operations.
  """
  def text_to_operations(old_text, new_text) do
    Psc.Documents.CRDT.text_to_deltas(old_text, new_text)
  end

  @doc """
  The event schema of a document.
  """
  def event_module, do: DocumentEvent
end
