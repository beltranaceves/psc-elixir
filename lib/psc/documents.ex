defmodule Psc.Documents do
  @moduledoc """
  The Documents context for managing collaborative text documents with CRDTs.
  """

  import Ecto.Query, warn: false
  alias Psc.Repo
  alias Psc.Documents.{Document, DocumentEvent}
  alias Psc.Documents.CRDT
  alias Psc.Documents.SnapshotManager

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
    # Get next sequence number
    seq = next_sequence(document_id)

    # Save event
    event_attrs = %{
      operation: operation,
      seq: seq,
      document_id: document_id,
      user_id: user_id
    }

    case Repo.insert(DocumentEvent.changeset(%DocumentEvent{}, event_attrs)) do
      {:ok, _event} ->
        # Broadcast to all subscribers
        broadcast_operation(document_id, user_id, operation, seq)
        {:ok, seq}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Broadcast an operation to all subscribers.
  """
  defp broadcast_operation(document_id, user_id, operation, seq) do
    Phoenix.PubSub.broadcast(
      Psc.PubSub,
      pubsub_topic(document_id),
      {:operation, user_id, operation, seq}
    )
  end

  @doc """
  Save content to database. Used on idle/timer triggers.
  Also updates snapshot_seq to indicate the content is built through which event sequence.
  This ensures proper loading: we load content + replay events after snapshot_seq.
  """
  def save_content_to_db(document_id, content) do
    # Get the current max sequence number so we know content is built through this point
    max_seq =
      Repo.one(
        from(e in DocumentEvent,
          where: e.document_id == ^document_id,
          select: max(e.seq)
        )
      ) || 0

    document_id
    |> get_document()
    |> Document.changeset(%{content: content, snapshot_seq: max_seq})
    |> Repo.update()
  end

  @doc """
  Build content from events using snapshots for efficiency.
  If a snapshot exists, only replays events after it.
  Much faster than replaying all events from the beginning.
  """
  def build_content_from_events(document_id) do
    SnapshotManager.load_with_snapshot(document_id)
  end

  @doc """
  Get document content - uses snapshots for faster loading.
  """
  def get_document_content(document_id) do
    SnapshotManager.load_with_snapshot(document_id)
  end

  @doc """
  Create a snapshot of the document's current state.
  Call periodically to reduce the number of events to replay.
  """
  def create_snapshot(document_id) do
    SnapshotManager.create_snapshot(document_id)
  end

  @doc """
  Check if document should be snapshotted based on event count.
  """
  def should_snapshot?(document_id) do
    SnapshotManager.should_create_snapshot?(document_id)
  end

  @doc """
  Get snapshot statistics for a document.
  """
  def get_snapshot_stats(document_id) do
    SnapshotManager.get_stats(document_id)
  end

  @doc """
  Convert text changes to delta operations.
  """
  def text_to_operations(old_text, new_text) do
    CRDT.text_to_deltas(old_text, new_text)
  end

  @doc """
  Get next sequence number for a document.
  """
  defp next_sequence(document_id) do
    case Repo.one(
           from(e in DocumentEvent,
             where: e.document_id == ^document_id,
             select: max(e.seq)
           )
         ) do
      nil -> 1
      max_seq -> max_seq + 1
    end
  end
end
