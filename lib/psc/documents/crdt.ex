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
  - %{"type" => "insert", "pos" => pos, "text" => text}  (current form, one op per run)
  - %{"type" => "insert", "pos" => pos, "char" => char}  (legacy, one op per character)
  - %{"type" => "delete", "pos" => pos, "count" => n}    (current form, one op per run)
  - %{"type" => "delete", "pos" => pos}                  (legacy, one character)
  """
  def apply_operation(event, text) when is_struct(event) do
    apply_operation(event.operation, text)
  end

  def apply_operation(%{"type" => "insert", "pos" => pos} = op, text) do
    # Clamp position to valid range
    pos = pos |> min(String.length(text)) |> max(0)

    inserted = op["text"] || op["char"] || ""
    before = String.slice(text, 0, pos)
    after_part = String.slice(text, pos..-1//1)
    before <> inserted <> after_part
  end

  def apply_operation(%{"type" => "delete", "pos" => pos} = op, text) do
    count = op["count"] || 1
    length = String.length(text)

    if pos >= 0 and pos < length do
      deleted = min(count, length - pos)
      before = String.slice(text, 0, pos)
      after_part = String.slice(text, (pos + deleted)..-1//1)
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

      {old, new} when byte_size(new) > byte_size(old) ->
        # Insertion detected
        find_insertion_point(old_text, new_text)

      {old, new} when byte_size(new) < byte_size(old) ->
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
    pos = find_first_diff_position(old_text, new_text, 0, old_len, new_len)

    # Get the inserted text
    inserted_length = new_len - old_len
    inserted_text = String.slice(new_text, pos, inserted_length)

    # A contiguous run is one operation (and one event row) — pasting a
    # document used to emit one row per character.
    if inserted_text == "" do
      []
    else
      [%{"type" => "insert", "pos" => pos, "text" => inserted_text}]
    end
  end

  defp find_deletion_point(old_text, new_text) do
    # Find where the texts diverge
    pos = find_first_diff_position(old_text, new_text, 0)

    # How many characters were deleted
    deleted_count = String.length(old_text) - String.length(new_text)

    if deleted_count <= 0 do
      []
    else
      [%{"type" => "delete", "pos" => pos, "count" => deleted_count}]
    end
  end

  defp find_first_diff_position(str1, str2, pos, len1 \\ nil, len2 \\ nil) do
    len1 = len1 || String.length(str1)
    len2 = len2 || String.length(str2)

    cond do
      pos >= len1 or pos >= len2 ->
        pos

      String.at(str1, pos) == String.at(str2, pos) ->
        find_first_diff_position(str1, str2, pos + 1, len1, len2)

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
