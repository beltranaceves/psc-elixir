defmodule PscWeb.Admin.Filters.TemplateVisibility do
  @moduledoc """
  Filters the templates index by catalog visibility.
  """

  use Backpex.Filters.Boolean

  import Ecto.Query

  @impl Backpex.Filter
  def label, do: "Visibility"

  @impl Backpex.Filters.Boolean
  def options(_assigns) do
    [
      %{label: "Public", key: "public", predicate: dynamic([template], template.public)},
      %{label: "Private", key: "private", predicate: dynamic([template], not template.public)}
    ]
  end
end
