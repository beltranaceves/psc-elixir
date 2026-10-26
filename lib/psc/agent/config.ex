defmodule Psc.Agent.Config do
  @moduledoc """
  The agent configuration a template or canvas carries: the additional system
  prompt, named roles, enabled tools and the reference files that accompany them.

  Everything here is pure and forgiving on purpose. A template is user content;
  a typo or an obsolete tool name must degrade to a safe profile, never crash a
  turn. `normalize/1` is the only gate, and it runs on every write and on every
  read.
  """

  alias Psc.Agent.Tools

  @version 1
  @max_prompt 8_000
  @max_roles 8
  @max_role_name 40
  @max_role_instructions 2_000

  def version, do: @version

  def default do
    %{
      "version" => @version,
      "prompt" => "",
      "roles" => [],
      "default_role" => nil,
      "tools" => nil
    }
  end

  @doc """
  Returns a complete, canonical config.

  Missing keys get defaults, over-long text is clipped, unknown tool names are
  dropped, role keys are made unique and the default role is repaired. A
  `tools` value of `nil` means "every read-only tool"; `[]` means none.
  """
  def normalize(nil), do: default()

  def normalize(config) when is_map(config) do
    config = stringify(config)
    roles = normalize_roles(Map.get(config, "roles"))

    %{
      "version" => @version,
      "prompt" => config |> Map.get("prompt", "") |> to_text() |> clamp(@max_prompt),
      "roles" => roles,
      "default_role" => default_role(config, roles),
      "tools" => normalize_tools(Map.get(config, "tools"))
    }
  end

  def normalize(_config), do: default()

  @doc "The tool names a config allows. `nil` in storage means every tool."
  def enabled_tool_names(config) do
    case normalize_tools(Map.get(normalize(config), "tools")) do
      nil -> Tools.names()
      names -> names
    end
  end

  def tool_enabled?(config, name) when is_binary(name) do
    name in enabled_tool_names(config)
  end

  @doc "A stable fingerprint of the normalized config, used for template drift."
  def hash(config) do
    :crypto.hash(:sha256, Jason.encode!(normalize(config)))
    |> Base.encode16(case: :lower)
  end

  @doc "The role selected by `key`, else the configured default, else the first."
  def role(config, key \\ nil) do
    config = normalize(config)
    roles = List.wrap(config["roles"])

    Enum.find(roles, &(&1["key"] == key)) ||
      Enum.find(roles, &(&1["key"] == config["default_role"])) ||
      List.first(roles)
  end

  def role_name(nil), do: nil
  def role_name(role) when is_map(role), do: role["name"]
  def role_name(_role), do: nil

  ## Draft helpers
  #
  # These run on the normalized map while a form is being edited. They
  # deliberately do not re-normalize: regenerating a role key from its name on
  # every keystroke would make the key jump while the author types.

  def put_prompt(config, prompt), do: Map.put(config, "prompt", to_text(prompt))

  def add_role(config) do
    roles = List.wrap(Map.get(config, "roles"))
    key = unique_key("role", MapSet.new(Enum.map(roles, & &1["key"])))
    role = %{"key" => key, "name" => "New role", "instructions" => ""}

    config
    |> Map.put("roles", roles ++ [role])
    |> Map.put("default_role", Map.get(config, "default_role") || key)
  end

  def remove_role(config, key) do
    roles = Enum.reject(List.wrap(Map.get(config, "roles")), &(&1["key"] == key))

    default =
      if Map.get(config, "default_role") == key do
        (List.first(roles) || %{})["key"]
      else
        Map.get(config, "default_role")
      end

    config
    |> Map.put("roles", roles)
    |> Map.put("default_role", default)
  end

  def put_role_field(config, key, field, value) when field in ["name", "instructions"] do
    roles =
      Enum.map(List.wrap(Map.get(config, "roles")), fn role ->
        if role["key"] == key, do: Map.put(role, field, to_text(value)), else: role
      end)

    Map.put(config, "roles", roles)
  end

  def put_role_field(config, _key, _field, _value), do: config

  def set_default_role(config, key), do: Map.put(config, "default_role", key)

  def toggle_tool(config, name) when is_binary(name) do
    if name in Tools.names() do
      current = enabled_tool_names(config)
      next = if name in current, do: List.delete(current, name), else: current ++ [name]
      next = Enum.filter(Tools.names(), &(&1 in next))

      Map.put(config, "tools", if(next == Tools.names(), do: nil, else: next))
    else
      config
    end
  end

  @doc """
  Applies one field of the agent form, identified by LiveView's `_target`.

  The form sends one event per change; the target is the input's name path
  (`["agent_prompt"]`, `["role", key, "name"]`, …).
  """
  def apply_form_change(config, ["agent_prompt"], params) do
    put_prompt(config, Map.get(params, "agent_prompt", ""))
  end

  def apply_form_change(config, ["role", key, field], params)
      when field in ["name", "instructions"] do
    put_role_field(config, key, field, get_in(params, ["role", key, field]))
  end

  def apply_form_change(config, _target, _params), do: config

  ## Normalization internals

  defp normalize_tools(nil), do: nil
  defp normalize_tools("all"), do: nil

  defp normalize_tools(tools) when is_list(tools) do
    selected =
      tools
      |> Enum.filter(&is_binary/1)
      |> MapSet.new()
      |> then(fn selected -> Enum.filter(Tools.names(), &MapSet.member?(selected, &1)) end)

    cond do
      selected == Tools.names() -> nil
      selected == [] -> []
      true -> selected
    end
  end

  defp normalize_tools(_tools), do: nil

  defp normalize_roles(roles) when is_list(roles) do
    {roles, _used} =
      roles
      |> Enum.map(&normalize_role/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.take(@max_roles)
      |> Enum.reduce({[], MapSet.new()}, fn role, {acc, used} ->
        key = unique_key(role["key"], used)
        {[Map.put(role, "key", key) | acc], MapSet.put(used, key)}
      end)

    Enum.reverse(roles)
  end

  defp normalize_roles(_roles), do: []

  defp normalize_role(role) when is_map(role) do
    role = stringify(role)
    name = role |> Map.get("name", "") |> to_text() |> clamp(@max_role_name)

    instructions =
      role |> Map.get("instructions", "") |> to_text() |> clamp(@max_role_instructions)

    if name == "" and instructions == "" do
      nil
    else
      base = role |> Map.get("key", "") |> to_text() |> slug()
      base = if base == "", do: slug(name), else: base
      base = if base == "", do: "role", else: base

      %{"key" => base, "name" => name, "instructions" => instructions}
    end
  end

  defp normalize_role(_role), do: nil

  defp default_role(config, roles) do
    requested = config |> Map.get("default_role") |> to_text()

    cond do
      requested != "" and Enum.any?(roles, &(&1["key"] == requested)) -> requested
      roles != [] -> List.first(roles)["key"]
      true -> nil
    end
  end

  defp unique_key(base, used) do
    1
    |> Stream.iterate(&(&1 + 1))
    |> Stream.map(fn
      1 -> base
      n -> "#{base}-#{n}"
    end)
    |> Enum.find(&(not MapSet.member?(used, &1)))
    |> String.slice(0, 40)
  end

  defp slug(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> String.slice(0, 40)
  end

  defp clamp(text, max) do
    text = text |> String.replace(~r/[\x00-\x08\x0B\x0C\x0E-\x1F]/, "") |> String.trim()
    if String.length(text) > max, do: String.slice(text, 0, max), else: text
  end

  defp to_text(nil), do: ""
  defp to_text(value) when is_binary(value), do: value
  defp to_text(value) when is_number(value) or is_atom(value), do: to_string(value)
  defp to_text(_value), do: ""

  defp stringify(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end
end
