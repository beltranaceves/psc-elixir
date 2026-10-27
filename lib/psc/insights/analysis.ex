defmodule Psc.Insights.Analysis do
  @moduledoc """
  Runs the detectors and normalises their output.

  The result is plain data (`findings` and `stats`); `Psc.Insights` persists it
  in a `Psc.Insights.Report` row. Keeping the calculation separate from the
  storage makes the detectors testable without a database.
  """

  alias Psc.Insights.{Cells, Finding}

  alias Psc.Insights.Detectors.{Duplicate, Empty, Relevance, Stale}

  @detectors [Empty, Stale, Duplicate, Relevance]

  def detectors, do: @detectors

  @doc "Runs every detector (or the ones given in `:detectors`)."
  def run(context, opts \\ []) do
    detectors = Keyword.get(opts, :detectors, @detectors)

    findings =
      detectors
      |> Enum.flat_map(& &1.run(context))
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(fn finding ->
        {Finding.severity_rank(finding["severity"]), finding["kind"], finding["title"]}
      end)
      |> Enum.uniq_by(& &1["id"])

    %{findings: findings, stats: stats(context.cells)}
  end

  @doc "Coverage figures for the summary tiles."
  def stats(cells) do
    cards = Cells.cards(%{cells: cells})

    total = Enum.reduce(cards, 0, fn card, acc -> acc + length(card.fields) end)
    filled = Enum.reduce(cards, 0, fn card, acc -> acc + length(Cells.filled_fields(card)) end)
    empty_cells = Enum.count(cards, fn card -> Cells.filled_fields(card) == [] end)

    %{
      "cells" => length(cards),
      "fields" => total,
      "filled" => filled,
      "empty_cells" => empty_cells,
      "coverage" => if(total == 0, do: 0, else: round(filled / total * 100))
    }
  end

  @doc """
  Merges new findings into an existing list.

  Heuristics come first, so when an AI finding repeats one of them the
  heuristic id wins the `uniq_by`.
  """
  def merge(existing, new_findings) do
    (existing ++ new_findings)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(fn finding ->
      {Finding.severity_rank(finding["severity"]), finding["kind"], finding["title"]}
    end)
    |> Enum.uniq_by(& &1["id"])
  end
end
