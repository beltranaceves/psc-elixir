defmodule Psc.Agent.Tools.ReadFile do
  @moduledoc """
  Reads one reference file attached to a canvas.

  The file set is part of the canvas, so access is the canvas's access. The chat
  supplies the canvas id through the tool context; MCP clients pass it
  explicitly.
  """

  use Jido.Action,
    name: "read_agent_file",
    description:
      "Read one reference file attached to a canvas.\n" <>
        "\n" <>
        "Use the canvas id the conversation is about (the chat supplies it " <>
        "automatically). Paths come from the reference-files manifest in the " <>
        "system prompt. Results larger than the read budget are truncated and " <>
        "flagged with `truncated: true`.",
    schema: [
      canvas_id: [
        type: :string,
        doc: "The canvas id. Optional in the chat, required for MCP calls."
      ],
      path: [
        type: :string,
        required: true,
        doc: "The file path exactly as it appears in the reference-files manifest."
      ]
    ]

  alias Psc.Agent.Files
  alias Psc.Agent.Tools.Ref
  alias Psc.Agent.Tools.Scope
  alias Psc.Canvas

  @not_found "No canvas or file with that id that you can access."
  @max_read 16_000

  @impl true
  def run(params, context) do
    with {:ok, user} <- Scope.user(context),
         {:ok, canvas_id} <- canvas_id(params, context),
         {:ok, canvas_id} <- Scope.uuid(canvas_id, "Canvas id"),
         %{} = canvas <- fetch_canvas(canvas_id),
         :ok <- authorize(canvas, user),
         {:ok, file} <- fetch_file(canvas.id, Map.get(params, :path)) do
      {content, truncated?} = truncate(file.content || "", @max_read)
      path = file.path || file.name

      {:ok,
       %{
         canvas_id: canvas.id,
         path: path,
         name: file.name || Path.basename(path),
         description: file.description,
         byte_size: file.byte_size || byte_size(file.content || ""),
         truncated: truncated?,
         content: content,
         refs: [Ref.file(canvas.id, path, Ref.excerpt(file.content))]
       }}
    end
  end

  defp canvas_id(params, context) do
    case Map.get(params, :canvas_id) || Map.get(context, :canvas_id) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _other -> {:error, "I need a canvas id to read a file."}
    end
  end

  defp fetch_canvas(id), do: Canvas.get_unstr_canvas(id) || {:error, @not_found}

  defp authorize(canvas, user) do
    if Canvas.can_access_unstr_canvas?(canvas, user.email) do
      :ok
    else
      {:error, @not_found}
    end
  end

  defp fetch_file(canvas_id, path) when is_binary(path) do
    case Files.get_canvas_file(canvas_id, String.trim(path)) do
      nil -> {:error, @not_found}
      file -> {:ok, file}
    end
  end

  defp fetch_file(_canvas_id, _path), do: {:error, "A file path is required."}

  # The read budget bounds one tool result; the ReAct iteration cap bounds the
  # turn. Files are capped at 32 KB, so this truncates only the largest ones.
  defp truncate(content, max) do
    if String.length(content) <= max do
      {content, false}
    else
      {String.slice(content, 0, max), true}
    end
  end
end
