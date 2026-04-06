defmodule Psc.Documents.CRDT do
  @moduledoc """
  CRDT operations for collaborative document editing.
  Uses simple insert/delete delta format to track changes.
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
    |> Enum.reduce("", &apply_operation/2)
  end

  @doc """
  Apply a single operation to text.
  Operations are in delta format:
  - %{"type" => "insert", "pos" => pos, "char" => char}
  - %{"type" => "delete", "pos" => pos}
  """
  def apply_operation(event, text) when is_struct(event) do
    apply_operation(event.operation, text)
  end

  def apply_operation(%{"type" => "insert", "pos" => pos, "char" => char}, text) do
    # Clamp position to valid range
    pos = min(pos, String.length(text))
    pos = max(0, pos)

    before = String.slice(text, 0, pos)
    after_part = String.slice(text, pos..-1//1)
    before <> char <> after_part
  end

  def apply_operation(%{"type" => "delete", "pos" => pos}, text) do
    if pos >= 0 and pos < String.length(text) do
      before = String.slice(text, 0, pos)
      after_part = String.slice(text, (pos + 1)..-1//1)
      before <> after_part
    else
      text
    end
  end

  def apply_operation(_op, text), do: text

  @doc """
  Calculate the minimal delta operations between old and new text.
  Returns a list of delta operations needed to transform old -> new.
  """
  def text_to_deltas(old_text, new_text) when is_binary(old_text) and is_binary(new_text) do
    case {old_text, new_text} do
      {same, same} ->
        []

      {_old, new} when byte_size(new) > byte_size(_old) ->
        # Insertion detected
        find_insertion_point(old_text, new_text)

      {_old, new} when byte_size(new) < byte_size(_old) ->
        # Deletion detected
        find_deletion_point(old_text, new_text)

      {_old, _new} ->
        # Same length but different content
        []
    end
  end

  defp find_insertion_point(old_text, new_text) do
    old_len = String.length(old_text)
    new_len = String.length(new_text)
    
    # Find where the texts diverge
    pos = find_first_diff_position(old_text, new_text, 0)
    
    # Get the inserted text
    inserted_length = new_len - old_len
    inserted_text = String.slice(new_text, pos, inserted_length)
    
    # Create one insert operation per character
    inserted_text
    |> String.graphemes()
    |> Enum.with_index()
    |> Enum.map(fn {char, idx} ->
      %{"type" => "insert", "pos" => pos + idx, "char" => char}
    end)
  end

  defp find_deletion_point(old_text, new_text) do
    # Find where the texts diverge
    pos = find_first_diff_position(old_text, new_text, 0)
    
    # How many characters were deleted
    deleted_count = String.length(old_text) - String.length(new_text)
    
    # Create one delete operation per deleted character
    Enum.map(1..deleted_count, fn _ ->
      %{"type" => "delete", "pos" => pos}
    end)
  end

  defp find_first_diff_position(str1, str2, pos) do
    len1 = String.length(str1)
    len2 = String.length(str2)
    
    cond do
      pos >= len1 or pos >= len2 ->
        pos

      String.at(str1, pos) == String.at(str2, pos) ->
        find_first_diff_position(str1, str2, pos + 1)

      true ->
        pos
    end
  end

  @doc """
  Find the length of the common prefix between two strings.
  """
  def common_prefix_length(str1, str2) do
    find_first_diff_position(str1, str2, 0)
  end
end
