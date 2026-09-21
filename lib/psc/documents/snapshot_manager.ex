defmodule Psc.Documents.SnapshotManager do
  @moduledoc """
  Manages snapshots for efficient document persistence and loading.

  Strategy:
  - Snapshots store a copy of the document content + the event seq number at snapshot time
  - When loading, we replay only events after the snapshot (much faster)
  - Periodic snapshots reduce the number of events to replay
  - Old events can be archived/deleted after snapshot (optional, for now we keep for audit)
  """

  alias Psc.Repo
  alias Psc.Documents.{Document, DocumentEvent, CRDT}
  import Ecto.Query

  # Create snapshot after every 100 operations
  @snapshot_interval 100
  @doc """
  Create a snapshot of the document at the current event sequence.
  Stores the content and the seq number so we only replay events after this snapshot.
  """
  def create_snapshot(document_id) do
    document = Repo.get!(Document, document_id)

    # Get the highest seq number
    max_seq =
      Repo.one(
        from(e in DocumentEvent,
          where: e.document_id == ^document_id,
          select: max(e.seq)
        )
      ) || 0

    # Rebuild content from events
    content = rebuild_from_snapshot(document_id)

    # Store snapshot
    document
    |> Document.changeset(%{
      snapshot_content: content,
      snapshot_seq: max_seq
    })
    |> Repo.update()
  end

  @doc """
  Load document content efficiently using saved content + recent events.
  The content field is updated on every idle/periodic save with snapshot_seq updated
  to indicate through which event sequence the content is built.
  We only replay events that occurred after that sequence number.
  """
  def load_with_snapshot(document_id) do
    document = Repo.get!(Document, document_id)

    # Use the saved content field (updated on idle/periodic saves)
    content = document.content || ""
    snapshot_seq = document.snapshot_seq || 0

    # Load only events after the saved content
    events =
      from(e in DocumentEvent,
        where: e.document_id == ^document_id and e.seq > ^snapshot_seq,
        order_by: [asc: e.seq]
      )
      |> Repo.all()

    # Replay only the recent events on top of the saved content
    Enum.reduce(events, content, &CRDT.apply_operation/2)
  end

  @doc """
  Rebuild content from snapshot + all events after snapshot.
  Private - used internally for snapshots.
  """
  def rebuild_from_snapshot(document_id) do
    document = Repo.get!(Document, document_id)
    content = document.snapshot_content || ""
    snapshot_seq = document.snapshot_seq || 0

    # Load events after snapshot
    events =
      from(e in DocumentEvent,
        where: e.document_id == ^document_id and e.seq > ^snapshot_seq,
        order_by: [asc: e.seq]
      )
      |> Repo.all()

    Enum.reduce(events, content, &CRDT.apply_operation/2)
  end

  @doc """
  Check if a snapshot should be created based on the number of events since last snapshot.
  """
  def should_create_snapshot?(document_id) do
    document = Repo.get!(Document, document_id)

    max_seq =
      Repo.one(
        from(e in DocumentEvent,
          where: e.document_id == ^document_id,
          select: max(e.seq)
        )
      ) || 0

    # Create snapshot if we have more than @snapshot_interval events since last snapshot
    max_seq - (document.snapshot_seq || 0) >= @snapshot_interval
  end

  @doc """
  Get statistics about the document's event log and snapshots.
  """
  def get_stats(document_id) do
    document = Repo.get!(Document, document_id)

    total_events =
      Repo.one(
        from(e in DocumentEvent,
          where: e.document_id == ^document_id,
          select: count(e.id)
        )
      ) || 0

    events_since_snapshot = total_events - (document.snapshot_seq || 0)

    %{
      document_id: document_id,
      total_events: total_events,
      snapshot_seq: document.snapshot_seq,
      events_since_snapshot: events_since_snapshot,
      should_snapshot: events_since_snapshot >= @snapshot_interval,
      snapshot_efficiency:
        "#{round(document.snapshot_seq / max(total_events, 1) * 100)}% of events in snapshot"
    }
  end
end
