defmodule Psc.Insights.Detectors.Empty do
  @moduledoc """
  Finds fields that are still blank.

  A cell with no content at all is a warning; a cell that is only missing some
  fields is informational. A canvas-level coverage finding summarises the
  whole structure, so a canvas that is mostly untouched says so once instead
  of only cell by cell.
  """

  @behaviour Psc.Insights.Detector

  alias Psc.Insights.{Cells, Finding}

  @max_cell_findings 8
  @low_coverage 0.3

  @impl true
  def key, do: "empty"

  @impl true
  def run(context) do
    cards = Cells.cards(context)

    cell_findings =
      cards
      |> Enum.map(&cell_finding/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(fn finding -> {finding["severity"] != "warning", finding["title"]} end)
      |> Enum.take(@max_cell_findings)

    List.wrap(coverage_finding(cards)) ++ cell_findings
  end

  defp cell_finding(%{fields: []}), do: nil

  defp cell_finding(card) do
    empty = Cells.empty_fields(card)

    case {empty, length(card.fields)} do
      {[], _total} ->
        nil

      {empty, total} when length(empty) == total ->
        Finding.new("empty", %{
          "cell_keys" => [card.key],
          "severity" => "warning",
          "confidence" => 1.0,
          "title" => "#{card.label} has no content yet",
          "detail" => "Every field in this cell is empty.",
          "evidence" => %{"empty_fields" => length(empty), "total_fields" => total}
        })

      {empty, total} ->
        Finding.new("empty", %{
          "cell_keys" => [card.key],
          "severity" => "info",
          "confidence" => 1.0,
          "title" =>
            "#{card.label} still has #{length(empty)} empty #{plural(length(empty), "field")}",
          "detail" => "Still empty: #{Cells.field_labels(card.cell, empty)}.",
          "evidence" => %{"empty_fields" => length(empty), "total_fields" => total}
        })
    end
  end

  defp coverage_finding(cards) do
    total = Enum.reduce(cards, 0, fn card, acc -> acc + length(card.fields) end)
    filled = Enum.reduce(cards, 0, fn card, acc -> acc + length(Cells.filled_fields(card)) end)

    cond do
      total == 0 ->
        nil

      filled == 0 ->
        Finding.new("coverage", %{
          "severity" => "warning",
          "confidence" => 1.0,
          "title" => "This canvas is still empty",
          "detail" => "None of its #{total} fields have been filled in yet.",
          "evidence" => %{"filled_fields" => 0, "total_fields" => total}
        })

      filled / total < @low_coverage ->
        Finding.new("coverage", %{
          "severity" => "info",
          "confidence" => 1.0,
          "title" => "Only #{round(filled / total * 100)}% of the canvas is filled",
          "detail" => "#{filled} of #{total} fields have content.",
          "evidence" => %{"filled_fields" => filled, "total_fields" => total}
        })

      true ->
        nil
    end
  end

  defp plural(1, word), do: word
  defp plural(_count, word), do: word <> "s"
end
