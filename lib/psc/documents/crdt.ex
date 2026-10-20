defmodule Psc.Documents.CRDT do
  @moduledoc """
  The document-shaped view of the collaborative text operations.

  The operations themselves are pure and live in `Psc.Text`, shared with the
  notes. What stays here is the part that knows about documents: reading their
  event log and rebuilding their text from it.
  """

  alias Psc.Documents.DocumentEvent
  alias Psc.Repo
  import Ecto.Query

  @doc """
  Load all events for a document and return them in order.
  """
  def load_events(document_id) do
    from(e in DocumentEvent,
      where: e.document_id == ^document_id,
      order_by: [asc: e.seq]
    )
    |> Repo.all()
  end

  @doc """
  Rebuild document text from all stored events in sequence.
  """
  def rebuild_text(document_id) do
    document_id
    |> load_events()
    |> Enum.reduce("", &Psc.Text.apply_operation/2)
  end

  @doc """
  Apply a single operation to text.
  """
  defdelegate apply_operation(operation, text), to: Psc.Text

  @doc """
  Calculate the minimal delta operations between old and new text.
  """
  defdelegate text_to_deltas(old_text, new_text), to: Psc.Text

  @doc """
  Find the length of the common prefix between two strings.
  """
  defdelegate common_prefix_length(str1, str2), to: Psc.Text
end
