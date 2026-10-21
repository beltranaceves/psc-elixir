defmodule Psc.Admin do
  @moduledoc """
  Read-only figures for the administration dashboard.

  This is not a second data layer: writes still go through `Psc.Canvas`,
  `Psc.Accounts` and `Psc.Notes`. Only counts live here, so the dashboard can
  show the instance's shape without loading rows.
  """

  import Ecto.Query, warn: false

  alias Psc.Repo
  alias Psc.Accounts.User
  alias Psc.Canvas.{Layout, UnstrCanvas, UnstrCanvasEvent}
  alias Psc.Notes.Note

  @doc """
  A map of the instance's row counts.
  """
  def stats do
    %{
      users: count(User),
      admins: count(from(u in User, where: u.role == :admin)),
      templates: count(Layout),
      built_in_templates: count(from(l in Layout, where: l.built_in)),
      public_templates: count(from(l in Layout, where: l.public)),
      canvases: count(UnstrCanvas),
      notes: count(Note),
      canvas_events: count(UnstrCanvasEvent)
    }
  end

  defp count(queryable), do: Repo.aggregate(queryable, :count, :id)
end
