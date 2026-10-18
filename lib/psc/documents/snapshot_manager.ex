defmodule Psc.Documents.SnapshotManager do
  @moduledoc """
  Reads and reports on a document's folded state.

  There is no separate snapshot copy of the text: `documents.content` *is* the
  snapshot. Every idle/periodic save folds the pending operations into it and
  records how far it has been folded through in `snapshot_seq`, pruning the
  events it covered. Loading therefore only has to replay the events above
  `snapshot_seq` (normally none).
  """

  alias Psc.Repo
  alias Psc.Documents.{Document, DocumentEvent, CRDT}
  import Ecto.Query

  @doc """
  Load document content: the folded `content` plus any events recorded after it.
  """
  def load_with_snapshot(document_id) do
    document = Repo.get!(Document, document_id)

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
  Get statistics about the document's event log and folded state.
  """
  def get_stats(document_id) do
    document = Repo.get!(Document, document_id)
    snapshot_seq = document.snapshot_seq || 0

    pending_events =
      Repo.one(
        from(e in DocumentEvent,
          where: e.document_id == ^document_id and e.seq > ^snapshot_seq,
          select: count(e.id)
        )
      ) || 0

    %{
      document_id: document_id,
      snapshot_seq: snapshot_seq,
      content_bytes: byte_size(document.content || ""),
      pending_events: pending_events
    }
  end
end
