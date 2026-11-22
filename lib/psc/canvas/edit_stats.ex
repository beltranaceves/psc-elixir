defmodule Psc.Canvas.EditStats do
  @moduledoc """
  Aggregate edit statistics for a canvas, folded from the event log.

  A save prunes the events it folds into the snapshot, so anything the Analysis
  overview wants to know about past edits has to be counted before that happens.
  The result is one small map on the canvas row (`unstr_canvases.edit_stats`),
  never a row per edit, which keeps the free-tier row ceiling out of reach:

      %{
        "since" => "2026-11-24T09:00:00Z",
        "cells" => %{"r1_c1" => 12},
        "users" => %{"42" => %{"edits" => 12, "added" => 340, "removed" => 25}}
      }

  An edit is one `update_cell` event that changes a field's value. Added and
  removed characters come from the edited span between the old and the new
  value (the common prefix and suffix are ignored), so replacing a word counts
  both its removal and the new text.

  The counts start when this fold first runs on a canvas: events pruned before
  it existed are gone, and the cells do not record who wrote what.
  """

  alias Psc.Canvas.UnstrCanvasCRDT

  @doc "The empty statistics map."
  def empty, do: %{"cells" => %{}, "users" => %{}}

  @doc """
  Folds `events` into `stats`.

  `base_cells` is the snapshot the events apply to, and `events` are
  `{operation, user_id, inserted_at}` tuples in sequence order. Every operation
  is replayed on a working copy so each edit is compared with the value it
  replaced, including values written earlier in the same batch.
  """
  def fold(stats, base_cells, events, now \\ DateTime.utc_now()) do
    stats = normalise(stats)

    {stats, _cells} =
      Enum.reduce(events, {stats, base_cells || %{}}, fn {operation, user_id, _at},
                                                         {acc, cells} ->
        {count(acc, cells, operation, user_id), UnstrCanvasCRDT.apply_operation(operation, cells)}
      end)

    if events == [] or Map.has_key?(stats, "since") do
      stats
    else
      Map.put(stats, "since", DateTime.to_iso8601(DateTime.truncate(now, :second)))
    end
  end

  defp count(
         stats,
         cells,
         %{"type" => "update_cell", "cell_key" => key, "field" => field, "value" => value},
         user_id
       )
       when is_binary(key) and is_binary(field) do
    old = text(get_in(cells, [key, field]))
    new = text(value)

    if old == new do
      stats
    else
      {added, removed} = changed_span(old, new)
      user = to_string(user_id)

      stats
      |> update_in(["cells"], &Map.update(&1, key, 1, fn n -> n + 1 end))
      |> update_in(["users"], fn users ->
        Map.update(
          users,
          user,
          %{"edits" => 1, "added" => added, "removed" => removed},
          fn totals ->
            %{
              "edits" => (totals["edits"] || 0) + 1,
              "added" => (totals["added"] || 0) + added,
              "removed" => (totals["removed"] || 0) + removed
            }
          end
        )
      end)
    end
  end

  defp count(stats, _cells, _operation, _user_id), do: stats

  @doc """
  The characters added and removed between two strings.

  The common prefix and suffix are left out, so the counts describe the span
  that changed rather than the whole field.
  """
  def changed_span(old, new) do
    old = String.graphemes(old)
    new = String.graphemes(new)

    prefix = common_prefix(old, new, 0)
    old = Enum.drop(old, prefix)
    new = Enum.drop(new, prefix)

    suffix = common_prefix(Enum.reverse(old), Enum.reverse(new), 0)

    {length(new) - suffix, length(old) - suffix}
  end

  defp common_prefix([a | old], [a | new], n), do: common_prefix(old, new, n + 1)
  defp common_prefix(_old, _new, n), do: n

  defp text(value) when is_binary(value), do: value
  defp text(value) when is_number(value), do: to_string(value)
  defp text(_value), do: ""

  defp normalise(stats) when is_map(stats) do
    stats
    |> Map.put_new("cells", %{})
    |> Map.put_new("users", %{})
  end

  defp normalise(_stats), do: empty()
end
