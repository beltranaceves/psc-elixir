defmodule Psc.Insights.Finding do
  @moduledoc """
  One analysis result, normalised to a JSON-friendly map.

  A finding names the cells it is about, carries a stable id (so it can be
  dismissed and survive the next run), a severity and a source. The id is
  derived from the kind, the cells, the field and the title - never from a
  random value - and ignores the source so an AI finding about the same issue
  deduplicates against the heuristic one.
  """

  @kinds ~w(empty stale duplicate relevance coverage contradiction)
  @ai_kinds ~w(duplicate relevance coverage contradiction)
  @severities ~w(info warning critical)
  @max_title 120
  @max_detail 600
  @max_evidence 240

  def kinds, do: @kinds
  def ai_kinds, do: @ai_kinds
  def severities, do: @severities

  @doc "Builds a normalised finding, or nil when the kind is not recognised."
  def new(kind, attrs) when kind in @kinds and is_map(attrs) do
    attrs = stringify(attrs)
    cells = cells(attrs["cell_keys"])
    title = text(attrs["title"], @max_title)

    %{
      "id" => id(kind, cells, attrs["field"], title),
      "kind" => kind,
      "severity" => severity(attrs["severity"]),
      "confidence" => confidence(attrs["confidence"]),
      "cell_keys" => cells,
      "field" => field(attrs["field"]),
      "title" => title,
      "detail" => text(attrs["detail"], @max_detail),
      "evidence" => map_or_empty(attrs["evidence"]),
      "source" => source(attrs["source"]),
      "attribution" => map_or_empty(attrs["attribution"])
    }
  end

  def new(_kind, _attrs), do: nil

  @doc """
  Normalises an AI-produced finding.

  Only kinds an LLM can reasonably judge are accepted; anything else is
  dropped rather than re-labelled. The source and attribution are set here,
  never trusted from the model.
  """
  def from_ai(attrs, attribution) when is_map(attrs) do
    kind = attrs["kind"] || attrs[:kind]
    title = attrs["title"] || attrs[:title]

    if kind in @ai_kinds and is_binary(title) and String.trim(title) != "" do
      new(kind, Map.merge(stringify(attrs), %{"source" => "ai", "attribution" => attribution}))
    end
  end

  def from_ai(_attrs, _attribution), do: nil

  @doc "An HTML-id-safe form of the finding id."
  def dom_id(%{"id" => id}) when is_binary(id) do
    "insight-" <> String.replace(id, ~r/[^a-zA-Z0-9]+/, "-")
  end

  def dom_id(_finding), do: "insight-unknown"

  def severity_rank("critical"), do: 0
  def severity_rank("warning"), do: 1
  def severity_rank(_severity), do: 2

  def severity(%{"severity" => severity}), do: severity(severity)
  def severity("critical"), do: "critical"
  def severity("warning"), do: "warning"
  def severity(_severity), do: "info"

  defp id(kind, cells, field, title) do
    anchor =
      cond do
        cells != [] -> Enum.join(cells, "+") <> ":" <> (field || "")
        kind == "coverage" -> "canvas"
        true -> "canvas:" <> slug(title)
      end

    "v1:#{kind}:#{anchor}"
  end

  defp slug(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> String.slice(0, 48)
  end

  defp cells(values) do
    values
    |> List.wrap()
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.slice(&1, 0, 80))
    |> Enum.uniq()
    |> Enum.take(6)
  end

  defp field(value) when is_binary(value) and value != "", do: String.slice(value, 0, 80)
  defp field(_value), do: nil

  defp confidence(value) when is_number(value), do: value |> max(0.0) |> min(1.0)
  defp confidence(_value), do: nil

  defp source("ai"), do: "ai"
  defp source(_source), do: "heuristic"

  defp text(value, max) when is_binary(value) do
    value
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, max)
  end

  defp text(_value, _max), do: ""

  defp map_or_empty(value) when is_map(value) do
    Map.new(value, fn {key, val} -> {to_string(key), scalar(val)} end)
  end

  defp map_or_empty(_value), do: %{}

  defp scalar(value) when is_number(value) or is_boolean(value), do: value
  defp scalar(nil), do: nil
  defp scalar(value) when is_binary(value), do: text(value, @max_evidence)
  defp scalar(value), do: value |> inspect() |> text(@max_evidence)

  defp stringify(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end
end
