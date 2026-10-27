defmodule PscWeb.Admin.Filters.UserRole do
  @moduledoc """
  Filters the users index by role.

  The value is the string Ecto stores for `users.role`, so the select compares
  directly against the enum field.
  """

  use Backpex.Filters.Select

  @impl Backpex.Filter
  def label, do: "Role"

  @impl Backpex.Filters.Select
  def prompt, do: "Any role"

  @impl Backpex.Filters.Select
  def options(_assigns), do: [{"Admin", :admin}, {"Member", :member}]
end
