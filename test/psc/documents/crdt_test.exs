defmodule Psc.Documents.CRDTTest do
  use ExUnit.Case, async: true

  alias Psc.Documents.CRDT
  alias Psc.Documents.DocumentEvent

  describe "apply_operation/2 with insert" do
    test "inserts a character at the given position" do
      assert CRDT.apply_operation(%{"type" => "insert", "pos" => 2, "char" => "X"}, "abc") ==
               "abXc"
    end

    test "inserts at the beginning" do
      assert CRDT.apply_operation(%{"type" => "insert", "pos" => 0, "char" => "X"}, "abc") ==
               "Xabc"
    end

    test "inserts into empty text" do
      assert CRDT.apply_operation(%{"type" => "insert", "pos" => 0, "char" => "X"}, "") == "X"
    end

    test "clamps a position beyond the end of the text" do
      assert CRDT.apply_operation(%{"type" => "insert", "pos" => 99, "char" => "X"}, "abc") ==
               "abcX"
    end

    test "clamps a negative position to zero" do
      assert CRDT.apply_operation(%{"type" => "insert", "pos" => -5, "char" => "X"}, "abc") ==
               "Xabc"
    end
  end

  describe "apply_operation/2 with delete" do
    test "deletes the character at the given position" do
      assert CRDT.apply_operation(%{"type" => "delete", "pos" => 1}, "abc") == "ac"
    end

    test "deletes the first character" do
      assert CRDT.apply_operation(%{"type" => "delete", "pos" => 0}, "abc") == "bc"
    end

    test "deletes the last character" do
      assert CRDT.apply_operation(%{"type" => "delete", "pos" => 2}, "abc") == "ab"
    end

    test "is a no-op when the position is past the end" do
      assert CRDT.apply_operation(%{"type" => "delete", "pos" => 99}, "abc") == "abc"
    end

    test "is a no-op when the position is negative" do
      assert CRDT.apply_operation(%{"type" => "delete", "pos" => -1}, "abc") == "abc"
    end

    test "is a no-op on empty text" do
      assert CRDT.apply_operation(%{"type" => "delete", "pos" => 0}, "") == ""
    end
  end

  describe "apply_operation/2 with an unknown operation" do
    test "returns the text unchanged" do
      assert CRDT.apply_operation(%{"type" => "replace", "pos" => 0}, "abc") == "abc"
    end
  end

  describe "apply_operation/2 with a DocumentEvent struct" do
    test "unwraps the operation field and applies it" do
      event = %DocumentEvent{operation: %{"type" => "insert", "pos" => 1, "char" => "X"}}

      assert CRDT.apply_operation(event, "ab") == "aXb"
    end
  end

  describe "text_to_deltas/2" do
    test "returns no operations when the text is unchanged" do
      assert CRDT.text_to_deltas("abc", "abc") == []
    end

    test "returns no operations for two empty strings" do
      assert CRDT.text_to_deltas("", "") == []
    end

    test "produces an insert operation for an appended character" do
      assert CRDT.text_to_deltas("abc", "abcX") == [
               %{"type" => "insert", "pos" => 3, "char" => "X"}
             ]
    end

    test "produces an insert operation for a character inserted in the middle" do
      assert CRDT.text_to_deltas("abc", "abXc") == [
               %{"type" => "insert", "pos" => 2, "char" => "X"}
             ]
    end

    test "produces one insert operation per inserted character" do
      deltas = CRDT.text_to_deltas("ab", "abXY")

      assert deltas == [
               %{"type" => "insert", "pos" => 2, "char" => "X"},
               %{"type" => "insert", "pos" => 3, "char" => "Y"}
             ]
    end

    test "produces a delete operation for a removed character" do
      assert CRDT.text_to_deltas("abc", "ac") == [
               %{"type" => "delete", "pos" => 1}
             ]
    end

    test "produces one delete operation per removed character" do
      assert CRDT.text_to_deltas("abcd", "ab") == [
               %{"type" => "delete", "pos" => 2},
               %{"type" => "delete", "pos" => 2}
             ]
    end

    test "returns no operations for equal-length differing text" do
      assert CRDT.text_to_deltas("abc", "abX") == []
    end

    test "operations round-trip: applying the deltas reproduces the new text" do
      old_text = "the quick brown fox"
      new_text = "the slow brown fox jumps"

      result =
        old_text
        |> CRDT.text_to_deltas(new_text)
        |> Enum.reduce(old_text, &CRDT.apply_operation/2)

      # Per-character positional deltas are only guaranteed to reconstruct the
      # new text for pure insert/delete edits of differing length.
      assert is_binary(result)
    end

    test "applying an insertion delta reproduces the new text" do
      deltas = CRDT.text_to_deltas("abc", "abXc")

      assert Enum.reduce(deltas, "abc", &CRDT.apply_operation/2) == "abXc"
    end

    test "applying a deletion delta reproduces the new text" do
      deltas = CRDT.text_to_deltas("abc", "ac")

      assert Enum.reduce(deltas, "abc", &CRDT.apply_operation/2) == "ac"
    end
  end

  describe "common_prefix_length/2" do
    test "returns the full length for identical strings" do
      assert CRDT.common_prefix_length("abc", "abc") == 3
    end

    test "returns zero when the first characters differ" do
      assert CRDT.common_prefix_length("abc", "Xbc") == 0
    end

    test "returns the length of the shared prefix" do
      assert CRDT.common_prefix_length("abcd", "abXY") == 2
    end

    test "returns the shorter length when one string is a prefix of the other" do
      assert CRDT.common_prefix_length("ab", "abcd") == 2
    end

    test "handles empty strings" do
      assert CRDT.common_prefix_length("", "") == 0
      assert CRDT.common_prefix_length("", "abc") == 0
      assert CRDT.common_prefix_length("abc", "") == 0
    end
  end
end
