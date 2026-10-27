defmodule Psc.Insights.Detectors.Relevance do
  @moduledoc """
  Finds cells whose wording drifts from the rest of the canvas.

  The detector builds a TF-IDF vector for every cell from its content, then
  compares each cell with the others. A cell that shares almost no vocabulary
  with any peer - and not with the canvas description either - is reported as
  a low-confidence relevance signal, not as a verdict.

  This is the noisy detector by nature. It stays silent unless the canvas has
  at least four cells with enough text, and it caps itself at three findings.
  """

  @behaviour Psc.Insights.Detector

  alias Psc.Insights.{Cells, Finding}

  @min_docs 4
  @min_tokens 12
  @similarity_floor 0.08
  @max_findings 3

  @stopwords ~w(
    a about above after again against all am an and any are as at be because been
    before being below between both but by can could did do does doing down during
    each few for from further had has have having he her here hers herself him
    himself his how i if in into is it its itself just me more most my myself no
    nor not now of off on once only or other our ours ourselves out over own same
    she should so some such than that the their theirs them themselves then there
    these they this those through to too under until up very was we were what when
    where which while who whom why will with would you your yours yourself
    yourselves
  )

  @impl true
  def key, do: "relevance"

  @impl true
  def run(context) do
    docs = documents(context)

    if length(docs) < @min_docs do
      []
    else
      docs
      |> vectors()
      |> outliers(context.description)
      |> Enum.take(@max_findings)
      |> Enum.map(fn {doc, similarity} -> finding(doc, similarity) end)
    end
  end

  defp documents(context) do
    context
    |> Cells.cards()
    |> Enum.flat_map(fn card ->
      tokens = tokenize(Cells.content_text(card))

      if length(tokens) >= @min_tokens do
        [%{key: card.key, label: card.label, tokens: tokens, unique: MapSet.new(tokens)}]
      else
        []
      end
    end)
  end

  defp vectors(docs) do
    count = length(docs)

    document_frequency =
      Enum.reduce(docs, %{}, fn doc, acc ->
        Enum.reduce(doc.unique, acc, fn token, freq ->
          Map.update(freq, token, 1, &(&1 + 1))
        end)
      end)

    inverse_frequency =
      Map.new(document_frequency, fn {token, frequency} ->
        {token, :math.log((count + 1) / (frequency + 1)) + 1}
      end)

    Enum.map(docs, fn doc ->
      Map.put(doc, :vector, tf_idf(doc.tokens, inverse_frequency))
    end)
  end

  defp tf_idf(tokens, inverse_frequency) do
    total = length(tokens)

    tokens
    |> Enum.frequencies()
    |> Map.new(fn {token, frequency} ->
      {token, frequency / total * Map.get(inverse_frequency, token, 1.0)}
    end)
  end

  defp outliers(docs, description) do
    description_vector = description_vector(description, docs)

    docs
    |> Enum.map(fn doc ->
      peer_similarity =
        docs
        |> Enum.reject(&(&1.key == doc.key))
        |> Enum.map(&cosine(doc.vector, &1.vector))
        |> Enum.max(fn -> 0.0 end)

      description_similarity =
        case description_vector do
          nil -> 0.0
          vector -> cosine(doc.vector, vector)
        end

      {doc, max(peer_similarity, description_similarity)}
    end)
    |> Enum.filter(fn {_doc, similarity} -> similarity < @similarity_floor end)
    |> Enum.sort_by(fn {_doc, similarity} -> similarity end)
  end

  defp description_vector(description, docs) when is_binary(description) do
    tokens = tokenize(description)

    if length(tokens) >= 3 do
      vocabulary = docs |> Enum.flat_map(& &1.tokens) |> MapSet.new()

      if Enum.any?(tokens, &MapSet.member?(vocabulary, &1)) do
        tf_idf(tokens, Map.new(vocabulary, &{&1, 1.0}))
      else
        nil
      end
    end
  end

  defp description_vector(_description, _docs), do: nil

  defp finding(doc, similarity) do
    confidence = (1.0 - similarity / @similarity_floor) |> max(0.0) |> min(1.0)

    Finding.new("relevance", %{
      "cell_keys" => [doc.key],
      "severity" => "info",
      "confidence" => Float.round(confidence, 2),
      "title" => "#{doc.label} may drift from the rest of the canvas",
      "detail" =>
        "Its wording shares little with the other cells. Check that it is framed from the same perspective.",
      "evidence" => %{"similarity" => Float.round(similarity, 3)}
    })
  end

  defp cosine(a, b) do
    shared = a |> Map.keys() |> Enum.filter(&Map.has_key?(b, &1))

    dot = Enum.reduce(shared, 0.0, fn token, acc -> acc + a[token] * b[token] end)
    norm_a = :math.sqrt(Enum.reduce(a, 0.0, fn {_token, value}, acc -> acc + value * value end))
    norm_b = :math.sqrt(Enum.reduce(b, 0.0, fn {_token, value}, acc -> acc + value * value end))

    if norm_a == 0.0 or norm_b == 0.0 do
      0.0
    else
      dot / (norm_a * norm_b)
    end
  end

  defp tokenize(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}]+/u, " ")
    |> String.split(" ", trim: true)
    |> Enum.filter(fn token -> String.length(token) >= 3 and token not in @stopwords end)
  end
end
