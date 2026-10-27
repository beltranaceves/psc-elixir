defmodule Psc.InsightsFixtures do
  @moduledoc """
  Canvas cells for the insights tests.

  A fixture is a one-row table canvas whose cells each carry one `content`
  field, in the order given. That keeps a test readable: a list of `{label,
  text}` pairs is the whole canvas.
  """

  @doc """
  Builds a table canvas cells map.

  Options: `:name`, `:description`, and `:fields` (the field names every cell
  gets; defaults to `["content"]`).
  """
  def cells(contents, opts \\ []) when is_list(contents) do
    fields = Keyword.get(opts, :fields, ["content"])

    columns =
      contents
      |> Enum.with_index(1)
      |> Enum.map(fn {{label, _text}, index} ->
        %{"id" => "c#{index}", "label" => label}
      end)

    keys = Enum.map(columns, &("r1_" <> &1["id"]))

    cells =
      contents
      |> Enum.with_index(1)
      |> Enum.map(fn {{label, text}, index} ->
        key = "r1_c#{index}"

        values =
          fields
          |> Enum.with_index()
          |> Map.new(fn {field, field_index} ->
            {field, if(field_index == 0, do: text, else: "")}
          end)

        data =
          Map.merge(values, %{
            "row" => "r1",
            "column" => "c#{index}",
            "label" => label,
            "field_order" => fields
          })

        {key, data}
      end)
      |> Map.new()

    %{
      "rows" => [%{"id" => "r1", "label" => "Row"}],
      "columns" => columns,
      "layout" => [keys],
      "$name" => Keyword.get(opts, :name, "Test canvas"),
      "$description" => Keyword.get(opts, :description, "")
    }
    |> Map.merge(cells)
  end
end
