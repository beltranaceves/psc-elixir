defmodule Psc.Documents do
  @moduledoc """
  The Documents context for managing collaborative text documents with CRDTs.
  """

  import Ecto.Query, warn: false
  alias Psc.Repo
  alias Psc.Documents.{Document, DocumentEvent}

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

    {:ok, _event} = Repo.insert(DocumentEvent.changeset(%DocumentEvent{}, event_attrs))

    # Broadcast to all subscribers
    Phoenix.PubSub.broadcast(
      Psc.PubSub,
      pubsub_topic(document_id),
      {:operation, user_id, operation, seq}
    )

    {:ok, build_content_from_events(document_id)}
  end

  @doc """
  Build content from all stored events.
  """
  def build_content_from_events(document_id) do
    events =
      from(e in DocumentEvent,
        where: e.document_id == ^document_id,
        order_by: [asc: e.seq]
      )
      |> Repo.all()

    Enum.reduce(events, "", fn event, content ->
      apply_operation_to_content(content, event.operation)
    end)
  end

  @doc """
  Get document content as a string from stored events.
  """
  def get_document_content(document_id) do
    build_content_from_events(document_id)
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

  @doc """
  Apply an operation to the content string.
  """
  defp apply_operation_to_content(content, %{"type" => "insert", "pos" => pos, "char" => char}) do
    # Ensure pos is within bounds
    pos = min(pos, String.length(content))
    pos = max(0, pos)

    before = String.slice(content, 0..pos - 1)
    after_part = String.slice(content, pos..-1)

    before <> char <> after_part
  end

  defp apply_operation_to_content(content, %{"type" => "delete", "pos" => pos}) do
    # Ensure pos is within bounds
    if pos >= 0 and pos < String.length(content) do
      before = String.slice(content, 0..pos - 1)
      after_part = String.slice(content, (pos + 1)..-1)
      before <> after_part
    else
      content
    end
  end

  defp apply_operation_to_content(content, _), do: content
end
