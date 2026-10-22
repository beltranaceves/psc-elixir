defmodule Psc.Agent.Tools.ListCanvases do
  @moduledoc """
  Lists the canvases the caller owns or was invited to.
  """

  use Jido.Action,
    name: "list_canvases",
    description:
      "List the canvases the current user can open, newest first, marking each " <>
        "as \"owner\" or \"shared\". Use the returned id with get_canvas, " <>
        "list_notes or get_note.",
    schema: []

  alias Psc.Agent.Tools.Ref
  alias Psc.Agent.Tools.Scope
  alias Psc.Canvas

  @impl true
  def run(_params, context) do
    with {:ok, user} <- Scope.user(context) do
      owned = Enum.map(Canvas.list_user_unstr_canvases(user.id), &summarise(&1, "owner"))
      shared = Enum.map(Canvas.list_shared_unstr_canvases(user.email), &summarise(&1, "shared"))

      {:ok,
       %{
         canvases: owned ++ shared,
         refs: Enum.map(owned ++ shared, &Ref.canvas(&1.id, &1.name, &1.description))
       }}
    end
  end

  defp summarise(canvas, access) do
    %{
      id: canvas.id,
      name: canvas.name,
      description: canvas.description,
      access: access,
      updated_at: Scope.iso8601(canvas.updated_at)
    }
  end
end
