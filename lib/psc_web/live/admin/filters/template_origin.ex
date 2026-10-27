defmodule PscWeb.Admin.Filters.TemplateOrigin do
  @moduledoc """
  Filters the templates index by who owns the row: the seeded defaults or the
  templates users created.
  """

  use Backpex.Filters.Boolean

  import Ecto.Query

  @impl Backpex.Filter
  def label, do: "Origin"

  @impl Backpex.Filters.Boolean
  def options(_assigns) do
    [
      %{label: "Built-in", key: "built_in", predicate: dynamic([template], template.built_in)},
      %{label: "Custom", key: "custom", predicate: dynamic([template], not template.built_in)}
    ]
  end
end
