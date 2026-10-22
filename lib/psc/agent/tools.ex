defmodule Psc.Agent.Tools do
  @moduledoc """
  The single list of tools an agent may use.

  The same modules are the MCP tool surface, so a capability cannot exist in the
  chat and be missing from `/mcp`. They are read-only: nothing here writes, which
  is why an agent cannot corrupt the event-sourced aggregates.
  """

  @tools [
    Psc.Agent.Tools.ListTemplates,
    Psc.Agent.Tools.ListCanvases,
    Psc.Agent.Tools.GetCanvas,
    Psc.Agent.Tools.ListNotes,
    Psc.Agent.Tools.GetNote
  ]

  @doc "Every tool module, in a stable order."
  def all, do: @tools

  @doc "The tool with the given name, or nil."
  def fetch(name) when is_binary(name), do: Enum.find(@tools, &(&1.name() == name))
  def fetch(_name), do: nil

  @doc """
  MCP-shaped descriptors: `name`, `description`, `inputSchema`.

  The JSON Schema is derived from the action's own schema, so the model sees the
  same contract Jido validates against.
  """
  def mcp_specs do
    Enum.map(@tools, fn tool ->
      %{
        "name" => tool.name(),
        "description" => tool.description(),
        "inputSchema" => Jido.Action.Schema.to_json_schema(tool.schema())
      }
    end)
  end
end
