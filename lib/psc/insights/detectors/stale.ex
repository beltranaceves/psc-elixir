defmodule Psc.Insights.Detectors.Stale do
  @moduledoc """
  Finds cells that have not been edited in a long time.

  The timestamp comes from `unstr_canvases.touch_map`, which the save fold fills
  from the events it is about to prune. A canvas with fewer than two touched
  cells produces nothing: there is no baseline yet.

  The threshold is relative as well as absolute - `max(21 days, 2 x the age of
  the most recently touched cell)` - so a canvas that is still being worked on
  flags the cells left behind, while a canvas where every cell is equally old
  reports nothing.
  """

  @behaviour Psc.Insights.Detector

  alias Psc.Insights.{Cells, Finding}

  @min_days 21
  @max_findings 6

  @impl true
  def key, do: "stale"

  @impl true
  def run(context) do
    ages =
      context
      |> Cells.cards()
      |> Enum.filter(fn card -> Cells.filled_fields(card) != [] end)
      |> Enum.flat_map(fn card ->
        case touched_at(context.touch_map[card.key]) do
          nil -> []
          at -> [{card, at, days_between(context.now, at)}]
        end
      end)

    if length(ages) < 2 do
      []
    else
      threshold = threshold(Enum.map(ages, fn {_card, _at, days} -> days end))

      ages
      |> Enum.filter(fn {_card, _at, days} -> days >= threshold end)
      |> Enum.sort_by(fn {_card, _at, days} -> -days end)
      |> Enum.take(@max_findings)
      |> Enum.map(&finding/1)
    end
  end

  defp finding({card, at, days}) do
    Finding.new("stale", %{
      "cell_keys" => [card.key],
      "severity" => "warning",
      "confidence" => 1.0,
      "title" => "Not touched in #{trunc(days)} days",
      "detail" =>
        "#{card.label} was last edited on #{Calendar.strftime(at, "%b %-d, %Y")} while the rest of the canvas has moved on.",
      "evidence" => %{
        "days_since_edit" => trunc(days),
        "last_touched_at" => DateTime.to_iso8601(at)
      }
    })
  end

  defp threshold(days) do
    max(@min_days, 2 * Enum.min(days))
  end

  defp days_between(%DateTime{} = now, %DateTime{} = at) do
    DateTime.diff(now, at, :second) / 86_400
  end

  defp touched_at(nil), do: nil

  defp touched_at(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _offset} -> at
      {:error, _reason} -> nil
    end
  end

  defp touched_at(%DateTime{} = value), do: value
  defp touched_at(_value), do: nil
end
