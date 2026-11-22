defmodule Psc.Canvas.EditStatsTest do
  use ExUnit.Case, async: true

  alias Psc.Canvas.EditStats

  @now ~U[2026-11-24 09:00:00Z]

  defp edit(key, field, value, user_id),
    do:
      {%{"type" => "update_cell", "cell_key" => key, "field" => field, "value" => value}, user_id,
       @now}

  describe "changed_span/2" do
    test "counts only the edited span" do
      assert EditStats.changed_span("hello world", "hello brave world") == {6, 0}
      assert EditStats.changed_span("hello brave world", "hello world") == {0, 6}
      assert EditStats.changed_span("the cat sat", "the dog sat") == {3, 3}
      assert EditStats.changed_span("", "abc") == {3, 0}
    end

    test "counts graphemes, not bytes" do
      assert EditStats.changed_span("café", "cafés") == {1, 0}
      assert EditStats.changed_span("ñandú", "") == {0, 5}
    end
  end

  describe "fold/4" do
    test "counts edits per cell and totals per user" do
      base = %{"r1_c1" => %{"content" => "abc"}}

      stats =
        EditStats.fold(
          EditStats.empty(),
          base,
          [
            edit("r1_c1", "content", "abcdef", 1),
            edit("r1_c1", "content", "ab", 2),
            edit("r1_c2", "content", "new", 1)
          ],
          @now
        )

      assert stats["cells"] == %{"r1_c1" => 2, "r1_c2" => 1}
      assert stats["users"]["1"] == %{"edits" => 2, "added" => 6, "removed" => 0}
      # "abcdef" -> "ab" compares with the value the first edit wrote.
      assert stats["users"]["2"] == %{"edits" => 1, "added" => 0, "removed" => 4}
      assert stats["since"] == "2026-11-24T09:00:00Z"
    end

    test "an edit that leaves the value unchanged is not counted" do
      base = %{"r1_c1" => %{"content" => "same"}}
      stats = EditStats.fold(EditStats.empty(), base, [edit("r1_c1", "content", "same", 1)], @now)

      assert stats["cells"] == %{}
      assert stats["users"] == %{}
    end

    test "adds to stored totals and keeps the original start" do
      stored = %{
        "since" => "2026-11-01T00:00:00Z",
        "cells" => %{"r1_c1" => 4},
        "users" => %{"1" => %{"edits" => 4, "added" => 10, "removed" => 2}}
      }

      stats = EditStats.fold(stored, %{}, [edit("r1_c1", "content", "xy", 1)], @now)

      assert stats["since"] == "2026-11-01T00:00:00Z"
      assert stats["cells"]["r1_c1"] == 5
      assert stats["users"]["1"] == %{"edits" => 5, "added" => 12, "removed" => 2}
    end

    test "other operations are replayed but not counted" do
      events = [
        {%{"type" => "update_name", "value" => "Renamed"}, 1, @now},
        edit("r1_c1", "content", "a", 1)
      ]

      stats = EditStats.fold(nil, %{}, events, @now)

      assert stats["cells"] == %{"r1_c1" => 1}
    end

    test "no events leaves the map without a start" do
      refute Map.has_key?(EditStats.fold(%{}, %{}, [], @now), "since")
    end
  end
end
