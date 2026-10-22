defmodule Psc.Agent.Tools.ListTemplates do
  @moduledoc """
  Lists the canvas templates the caller may start a canvas from.
  """

  use Jido.Action,
    name: "list_templates",
    description:
      "List the canvas templates available to the current user: the built-in " <>
        "defaults, the ones they authored, and the ones shared with them. Use the " <>
        "returned id or name to describe where a canvas came from.",
    schema: []

  alias Psc.Agent.Tools.Ref
  alias Psc.Agent.Tools.Scope
  alias Psc.Canvas

  @impl true
  def run(_params, context) do
    with {:ok, user} <- Scope.user(context) do
      templates =
        user
        |> Canvas.list_templates()
        |> Enum.map(fn template ->
          %{
            id: template.id,
            name: template.name,
            description: template.description,
            built_in: template.built_in,
            updated_at: Scope.iso8601(template.updated_at)
          }
        end)

      {:ok,
       %{
         templates: templates,
         refs: Enum.map(templates, &Ref.template(&1.id, &1.name, &1.description))
       }}
    end
  end
end
