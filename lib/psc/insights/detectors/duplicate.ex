defmodule Psc.Insights.Detectors.Duplicate do
  @moduledoc """
  Finds near-identical text in two places.

  Content is compared as overlapping four-word shingles. The Jaccard
  similarity is language-agnostic and cheap enough for a canvas: even a few
  hundred fields compare in milliseconds, and the detector caps its input.

  Duplicates are intentionally a warning, not a critical: repeating a phrase
  can be deliberate.
  """

  @behaviour Psc.Insights.Detector

  alias Psc.Insights.{Cells, Finding}

  @min_chars 40
  @min_tokens 3
  @shingle_size 4
  @threshold 0.6
  @max_docs 400
  @max_findings 4

  @impl true
  def key, do: "duplicate"

  @impl true
  def run(context) do
    docs =
      for card <- Cells.cards(context),
          field <- card.fields,
          text = Cells.value(card.cell[field]),
          String.length(text) >= @min_chars,
          shingles = shingles(text),
          MapSet.size(shingles) > 0 do
        %{
          key: card.key,
          label: card.label,
          field: field,
          text: text,
          shingles: shingles
        }
      end
      |> Enum.take(@max_docs)

    docs
    |> pairs()
    |> Enum.map(fn {a, b, similarity} -> finding(a, b, similarity) end)
    |> Enum.reject(&is_nil/1)
    |> Enum.take(@max_findings)
  end

  defp pairs(docs) do
    indexed = Enum.with_index(docs)

    for {a, i} <- indexed,
        {b, j} <- indexed,
        i < j,
        similarity = jaccard(a.shingles, b.shingles),
        similarity >= @threshold do
      {a, b, similarity}
    end
    |> Enum.sort_by(fn {_a, _b, similarity} -> -similarity end)
  end

  defp finding(a, b, similarity) do
    Finding.new("duplicate", %{
      "cell_keys" => [a.key, b.key],
      "field" => a.field,
      "severity" => "warning",
      "confidence" => Float.round(similarity, 2),
      "title" => "Possible duplicate: #{a.label} and #{b.label}",
      "detail" => "Both contain: “#{quoted(a.text)}”.",
      "evidence" => %{
        "similarity" => Float.round(similarity, 2),
        "other_field" => b.field
      }
    })
  end

  defp quoted(text) do
    text
    |> Cells.snippet()
    |> String.trim_trailing(".")
    |> String.trim_trailing(";")
  end

  defp jaccard(a, b) do
    intersection = MapSet.intersection(a, b) |> MapSet.size()
    union = MapSet.union(a, b) |> MapSet.size()

    if union == 0, do: 0.0, else: intersection / union
  end

  defp shingles(text) do
    tokens =
      text
      |> String.downcase()
      |> String.replace(~r/[^\p{L}\p{N}]+/u, " ")
      |> String.split(" ", trim: true)

    size = min(@shingle_size, length(tokens))

    if size < @min_tokens do
      MapSet.new()
    else
      tokens
      |> Enum.chunk_every(size, 1, :discard)
      |> MapSet.new()
    end
  end
end
