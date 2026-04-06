defmodule Psc.Documents.ConsistencyManager do
  @moduledoc """
  Manages eventual consistency for collaborative documents.
  Provides periodic sync and full reconciliation capabilities.
  """

  alias Psc.Documents
  alias Psc.Documents.CRDT

  @doc """
  Verify that a client's text state matches the server's authoritative state.
  Returns :ok if consistent, or {:diverged, server_text, operations} if not.
  """
  def verify_consistency(document_id, client_text) do
    server_text = Documents.build_content_from_events(document_id)

    if client_text == server_text do
      :ok
    else
      # Client has diverged from server
      {:diverged, server_text}
    end
  end

  @doc """
  Calculate the operations needed to sync a client from their current state
  to the server's authoritative state.
  """
  def sync_operations(document_id, client_text) do
    server_text = Documents.build_content_from_events(document_id)
    CRDT.text_to_deltas(client_text, server_text)
  end

  @doc """
  Get the full event history for a document with checksums.
  Useful for auditing and ensuring consistency.
  """
  def get_document_history(document_id) do
    events = CRDT.load_events(document_id)

    events
    |> Enum.reduce(
      %{"text" => "", "events" => []},
      fn event, acc ->
        new_text = CRDT.apply_operation(event, acc["text"])

        %{
          "text" => new_text,
          "events" => acc["events"] ++ [
            %{
              "seq" => event.seq,
              "user_id" => event.user_id,
              "operation" => event.operation,
              "resulting_text" => new_text,
              "text_hash" => hash_text(new_text)
            }
          ]
        }
      end
    )
  end

  @doc """
  Compute a simple hash of the text for consistency verification.
  """
  def hash_text(text) do
    :crypto.hash(:sha256, text) |> Base.encode16(case: :lower)
  end

  @doc """
  Rebuild the document state from the event log.
  This is the source of truth for eventual consistency.
  """
  def rebuild_from_events(document_id) do
    Documents.build_content_from_events(document_id)
  end
end
