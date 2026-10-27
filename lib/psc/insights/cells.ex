defmodule Psc.Insights.Cells do
  @moduledoc """
  Shared reading helpers for detectors.

  The canvas stores each cell as a flat map of field values plus reserved
  metadata (`label`, `field_order`, `titles`, ...). `Psc.Canvas.Structure`
  owns the shape; this module only turns it into the small maps detectors
  need, in reading order.
  """

  alias Psc.Canvas.Structure

  def cards(%{cells: cells}) do
    cells
    |> Structure.cards()
    |> Enum.map(fn card ->
      cell = Structure.cell(cells, card.key) || %{}
      fields = Structure.field_names(cell)

      %{
        key: card.key,
        label: card.label,
        cell: cell,
        fields: fields,
        content: Map.new(fields, fn field -> {field, value(cell[field])} end)
      }
    end)
  end

  def value(value) when is_binary(value), do: value
  def value(nil), do: ""
  def value(value) when is_number(value), do: to_string(value)
  def value(_value), do: ""

  def blank?(value), do: value |> value() |> String.trim() == ""

  def filled_fields(card), do: Enum.reject(card.fields, &blank?(card.cell[&1]))

  def empty_fields(card), do: Enum.filter(card.fields, &blank?(card.cell[&1]))

  def field_label(cell, field) do
    case cell["titles"] do
      %{} = titles -> titles[field] || field
      _other -> field
    end
  end

  def field_labels(cell, fields) do
    Enum.map_join(fields, ", ", &field_label(cell, &1))
  end

  def content_text(card) do
    card.fields
    |> Enum.map(&value(card.cell[&1]))
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  def snippet(text, max \\ 90) do
    text
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, max)
  end
end
