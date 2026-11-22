defmodule Psc.Insights.Overview do
  @moduledoc """
  The simple, always-current facts at the top of the Analysis tab.

  Unlike findings, the overview is not stored: it is a pure function of the
  cells, `touch_map`, the canvas's edit statistics (`Psc.Canvas.EditStats`) and
  the names of the people in them, and it is rebuilt whenever the tab opens.

  Each tile is a map with an `id`, `label`, `icon`, a `value` (nil when there is
  nothing to show yet), a `detail` line, an optional `cell_key` the tile links
  to, and a `tone` (`:neutral`, `:positive` or `:negative`).
  """

  alias Psc.Insights.Cells

  @doc """
  Builds the tiles.

  `users` maps a user id (as a string) to a display name; ids it does not know
  are shown as "Former member".
  """
  def build(cells, touch_map, edit_stats, users, now \\ DateTime.utc_now()) do
    cards = Cells.cards(%{cells: cells})
    stats = edit_stats || %{}
    people = people(stats["users"] || %{}, users)

    [
      oldest(cards, touch_map || %{}, now),
      most_changed(cards, stats["cells"] || %{}),
      longest(cards),
      shortest(cards),
      most_edits(people),
      fewest_edits(people),
      net_added(people),
      net_removed(people)
    ]
  end

  @doc "When the edit counts started, as a `DateTime`, or nil."
  def counting_since(%{"since" => since}) when is_binary(since) do
    case DateTime.from_iso8601(since) do
      {:ok, at, _offset} -> at
      _error -> nil
    end
  end

  def counting_since(_stats), do: nil

  # ── Cells ──

  defp oldest(cards, touch_map, now) do
    touched =
      Enum.flat_map(cards, fn card ->
        case parse(touch_map[card.key]) do
          nil -> []
          at -> [{card, at}]
        end
      end)

    case Enum.min_by(touched, fn {_card, at} -> DateTime.to_unix(at, :microsecond) end, fn ->
           nil
         end) do
      nil ->
        tile("oldest", "Oldest cell", "hero-clock", nil, "No edits recorded yet")

      {card, at} ->
        tile("oldest", "Oldest cell", "hero-clock", card.label, "Last edited #{ago(now, at)}",
          cell_key: card.key
        )
    end
  end

  defp most_changed(cards, counts) do
    known = Map.new(cards, &{&1.key, &1})

    counts
    |> Enum.filter(fn {key, _n} -> Map.has_key?(known, key) end)
    |> Enum.max_by(fn {key, n} -> {n, key} end, fn -> nil end)
    |> case do
      nil ->
        tile("most_changed", "Most changed", "hero-fire", nil, "No edits counted yet")

      {key, n} ->
        tile("most_changed", "Most changed", "hero-fire", known[key].label, plural(n, "edit"),
          cell_key: key
        )
    end
  end

  defp longest(cards) do
    case filled(cards) do
      [] ->
        tile("longest", "Longest", "hero-bars-3-bottom-left", nil, "Nothing written yet")

      list ->
        {card, words} = Enum.max_by(list, fn {_card, words} -> words end)

        tile("longest", "Longest", "hero-bars-3-bottom-left", card.label, plural(words, "word"),
          cell_key: card.key
        )
    end
  end

  defp shortest(cards) do
    case filled(cards) do
      [] ->
        tile("shortest", "Shortest", "hero-minus", nil, "Nothing written yet")

      list ->
        {card, words} = Enum.min_by(list, fn {_card, words} -> words end)

        tile("shortest", "Shortest", "hero-minus", card.label, plural(words, "word"),
          cell_key: card.key
        )
    end
  end

  # Cells with some text, with their word count, in reading order (ties keep
  # the first cell).
  defp filled(cards) do
    cards
    |> Enum.map(fn card -> {card, word_count(Cells.content_text(card))} end)
    |> Enum.filter(fn {_card, words} -> words > 0 end)
  end

  defp word_count(text), do: text |> String.split(~r/\s+/, trim: true) |> length()

  # ── People ──

  defp people(totals, users) do
    totals
    |> Enum.map(fn {id, t} ->
      added = t["added"] || 0
      removed = t["removed"] || 0

      %{
        id: id,
        name: Map.get(users, id, "Former member"),
        edits: t["edits"] || 0,
        net: added - removed
      }
    end)
    |> Enum.filter(&(&1.edits > 0))
    |> Enum.sort_by(& &1.name)
  end

  defp most_edits([]),
    do: tile("most_edits", "Most edits", "hero-arrow-trending-up", nil, "No edits counted yet")

  defp most_edits(people) do
    person = Enum.max_by(people, & &1.edits)

    tile(
      "most_edits",
      "Most edits",
      "hero-arrow-trending-up",
      person.name,
      plural(person.edits, "edit")
    )
  end

  defp fewest_edits(people) when length(people) < 2,
    do:
      tile(
        "fewest_edits",
        "Fewest edits",
        "hero-arrow-trending-down",
        nil,
        "Needs two or more editors"
      )

  defp fewest_edits(people) do
    person = Enum.min_by(people, & &1.edits)

    tile(
      "fewest_edits",
      "Fewest edits",
      "hero-arrow-trending-down",
      person.name,
      plural(person.edits, "edit")
    )
  end

  defp net_added(people) do
    case Enum.filter(people, &(&1.net > 0)) do
      [] ->
        tile("net_added", "Net most added", "hero-plus", nil, "Nobody has added text yet")

      list ->
        person = Enum.max_by(list, & &1.net)

        tile("net_added", "Net most added", "hero-plus", person.name, "+#{chars(person.net)}",
          tone: :positive
        )
    end
  end

  defp net_removed(people) do
    case Enum.filter(people, &(&1.net < 0)) do
      [] ->
        tile(
          "net_removed",
          "Net most removed",
          "hero-minus-circle",
          nil,
          "Nobody has a net removal"
        )

      list ->
        person = Enum.min_by(list, & &1.net)

        tile(
          "net_removed",
          "Net most removed",
          "hero-minus-circle",
          person.name,
          "−#{chars(-person.net)}",
          tone: :negative
        )
    end
  end

  # ── Helpers ──

  defp tile(id, label, icon, value, detail, opts \\ []) do
    %{
      id: id,
      label: label,
      icon: icon,
      value: value,
      detail: detail,
      cell_key: Keyword.get(opts, :cell_key),
      tone: Keyword.get(opts, :tone, :neutral)
    }
  end

  defp chars(n), do: plural(n, "char")

  defp plural(1, word), do: "1 #{word}"
  defp plural(n, word), do: "#{format(n)} #{word}s"

  defp format(n) when n >= 1000 do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  defp format(n), do: Integer.to_string(n)

  defp ago(now, at) do
    seconds = max(DateTime.diff(now, at, :second), 0)

    cond do
      seconds < 3600 -> "#{max(div(seconds, 60), 1)} min ago"
      seconds < 86_400 -> "#{div(seconds, 3600)} h ago"
      true -> "#{div(seconds, 86_400)} d ago"
    end
  end

  defp parse(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _offset} -> at
      _error -> nil
    end
  end

  defp parse(%DateTime{} = at), do: at
  defp parse(_value), do: nil
end
