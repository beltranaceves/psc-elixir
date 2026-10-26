defmodule Psc.Agent.Profile do
  @moduledoc """
  The effective agent setup for one chat: the immutable PSC policy plus the
  configured instructions, the selected role, the enabled tools and the
  reference-file manifest.

  A profile is resolved from a canvas once, then pinned on the session with
  `to_map/1`. Later turns rebuild it from that snapshot, which keeps the
  provider's cacheable system prompt byte-stable even when the canvas is edited
  while the chat is open.
  """

  alias Psc.Agent.CanvasAgent
  alias Psc.Agent.Config
  alias Psc.Agent.Files
  alias Psc.Agent.Tools
  alias Psc.Canvas
  alias Psc.Canvas.UnstrCanvas

  @max_manifest 1_000

  defstruct [
    :canvas_id,
    :role,
    :role_name,
    :system_prompt,
    :tools,
    :files,
    :config
  ]

  @doc "The profile a canvas currently offers, optionally for a specific role."
  def for_canvas(canvas, role_key \\ nil)

  def for_canvas(%UnstrCanvas{} = canvas, role_key) do
    config = Config.normalize(canvas.agent_config)
    role = Config.role(config, role_key)
    tools = Config.enabled_tool_names(config)
    files = canvas.id |> Files.list_canvas() |> Enum.map(&file_meta/1)

    %__MODULE__{
      canvas_id: canvas.id,
      role: role && role["key"],
      role_name: Config.role_name(role),
      system_prompt: compose(CanvasAgent.base_prompt(), config["prompt"], role, files, tools),
      tools: tools,
      files: files,
      config: config
    }
  end

  def for_canvas(_canvas, _role_key), do: disabled()

  @doc "The profile a session runs with: its pin, else the canvas's current setup."
  def for_session(%{profile: profile} = session) when is_map(profile) and map_size(profile) > 0 do
    from_map(profile, session.canvas_id)
  end

  def for_session(session) do
    case session.canvas_id && Canvas.get_unstr_canvas(session.canvas_id) do
      %UnstrCanvas{} = canvas -> for_canvas(canvas, session.role)
      _other -> disabled()
    end
  end

  @doc "The snapshot stored on the session."
  def to_map(%__MODULE__{} = profile) do
    %{
      "version" => Config.version(),
      "canvas_id" => profile.canvas_id,
      "role" => profile.role,
      "role_name" => profile.role_name,
      "system_prompt" => profile.system_prompt,
      "tools" => profile.tools,
      "files" => profile.files
    }
  end

  def from_map(profile, canvas_id \\ nil) when is_map(profile) do
    profile = Map.new(profile, fn {key, value} -> {to_string(key), value} end)

    tools =
      profile
      |> Map.get("tools")
      |> List.wrap()
      |> Enum.filter(&is_binary/1)
      |> Enum.filter(&(&1 in Tools.names()))
      |> Enum.uniq()

    %__MODULE__{
      canvas_id: Map.get(profile, "canvas_id") || canvas_id,
      role: Map.get(profile, "role"),
      role_name: Map.get(profile, "role_name"),
      system_prompt: Map.get(profile, "system_prompt") || CanvasAgent.base_prompt(),
      tools: tools,
      files: Map.get(profile, "files") || [],
      config: nil
    }
  end

  @doc """
  Layered system prompt: policy first, then the configured text, the role and
  the file manifest. With no customization the base prompt is returned
  unchanged, so existing chats keep the exact prefix they had.
  """
  def compose(base, prompt, role, files, tools) do
    blocks =
      [
        prompt_block(prompt),
        role_block(role),
        file_block(files, tools)
      ]
      |> Enum.reject(&is_nil/1)

    case blocks do
      [] -> base
      blocks -> base <> "\n\n" <> Enum.join(blocks, "\n\n")
    end
  end

  defp prompt_block(prompt) do
    case trim(prompt) do
      "" -> nil
      text -> "## Configured instructions\n\n" <> text
    end
  end

  defp role_block(nil), do: nil

  defp role_block(role) when is_map(role) do
    case trim(role["instructions"]) do
      "" ->
        nil

      text ->
        name =
          case trim(role["name"]) do
            "" -> "Role"
            name -> name
          end

        "## Role: #{name}\n\n" <> text
    end
  end

  defp role_block(_role), do: nil

  defp file_block(files, tools) do
    files =
      files
      |> List.wrap()
      |> Enum.filter(&is_map/1)
      |> Enum.take(Files.max_files())

    cond do
      "read_agent_file" not in tools -> nil
      files == [] -> nil
      true -> "## Reference files\n\n" <> manifest(files)
    end
  end

  defp manifest(files) do
    lines =
      Enum.map_join(files, "\n", fn file ->
        description = trim(file["description"])
        suffix = if description, do: " — #{description}", else: ""
        path = file["path"] || file["name"]
        "- #{path}#{suffix} (#{file["byte_size"] || 0} bytes)"
      end)

    """
    The following files belong to this canvas. Read one with read_agent_file \
    when it would help answer the question.

    #{String.slice(lines, 0, @max_manifest)}
    """
    |> String.trim()
  end

  defp file_meta(file) do
    path = file.path || file.name

    %{
      "id" => file.id,
      "path" => path,
      "name" => file.name || Path.basename(path),
      "description" => file.description,
      "byte_size" => file.byte_size || byte_size(file.content || "")
    }
  end

  defp disabled do
    %__MODULE__{
      canvas_id: nil,
      role: nil,
      role_name: nil,
      system_prompt: CanvasAgent.base_prompt(),
      tools: [],
      files: [],
      config: nil
    }
  end

  defp trim(nil), do: ""

  defp trim(value) when is_binary(value) do
    case String.trim(value) do
      "" -> ""
      text -> text
    end
  end

  defp trim(_value), do: ""
end
