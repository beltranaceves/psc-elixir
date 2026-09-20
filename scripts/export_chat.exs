# scripts/export_chat.exs
#
# Exports a VS Code Copilot Chat session transcript to a readable markdown file
# for committing into the repository as an audit trail.
#
# Usage:
#   mix run --no-start scripts/export_chat.exs --session-id <id> [-o output.md]
#   mix run --no-start scripts/export_chat.exs [-o output.md]   # auto-detect newest session
#
# Transcripts live at:
#   %APPDATA%\Code\User\workspaceStorage\<workspace-hash>\GitHub.copilot-chat\transcripts\<session-id>.jsonl

defmodule ExportChat do
  @moduledoc false

  def main(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [session_id: :string, output: :string],
        aliases: [o: :output]
      )

    files = transcript_files()

    if files == [] do
      IO.puts(:stderr, "No transcripts found. Is VS Code Copilot Chat enabled?")
      System.halt(1)
    end

    session_id = opts[:session_id] || newest_session_id(files)

    file = Enum.find(files, &String.ends_with?(&1, "#{session_id}.jsonl"))

    unless file do
      IO.puts(:stderr, "Transcript not found for session: #{session_id}")
      System.halt(1)
    end

    events = parse_transcript(file)
    markdown = render(events, session_id)

    output = opts[:output] || default_output(events, session_id)
    File.mkdir_p!(Path.dirname(output))
    File.write!(output, markdown)

    IO.puts("Exported #{session_id} → #{output}")
  end

  defp transcript_files do
    appdata = System.get_env("APPDATA") || System.get_env("HOME")

    # Normalize to forward slashes: Path.wildcard/1 on Windows fails with
    # mixed separators (backslash drive prefix + forward-slash joins).
    glob =
      appdata
      |> String.replace("\\", "/")
      |> Path.join("Code/User/workspaceStorage/*/GitHub.copilot-chat/transcripts/*.jsonl")

    Path.wildcard(glob)
  end

  defp newest_session_id(files) do
    files
    |> Enum.max_by(fn f -> File.stat!(f).mtime end)
    |> Path.basename()
    |> String.replace(".jsonl", "")
  end

  defp parse_transcript(file) do
    file
    |> File.stream!()
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&Jason.decode!/1)
  end

  defp render(events, session_id) do
    header = render_header(events, session_id)
    tool_names = tool_name_map(events)

    body =
      events
      |> Enum.map(&render_event(&1, tool_names))
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n\n")

    header <> "\n\n---\n\n" <> body <> "\n"
  end

  # tool.execution_complete events only carry the toolCallId; look up the
  # tool name from the matching tool.execution_start event.
  defp tool_name_map(events) do
    Enum.reduce(events, %{}, fn
      %{"type" => "tool.execution_start", "data" => %{"toolCallId" => id, "toolName" => name}}, acc ->
        Map.put(acc, id, name)

      _, acc ->
        acc
    end)
  end

  defp render_header(events, session_id) do
    start =
      case Enum.find(events, &(&1["type"] == "session.start")) do
        nil -> %{}
        e -> e["data"] || %{}
      end

    started = format_ts(start["startTime"] || "")
    copilot = start["copilotVersion"] || "?"
    vscode = start["vscodeVersion"] || "?"

    """
    # Chat Audit

    - **Session:** `#{session_id}`
    - **Started:** #{started}
    - **Copilot:** #{copilot} · **VS Code:** #{vscode}
    """
  end

  defp render_event(%{"type" => "user.message", "data" => data, "timestamp" => ts}, _tool_names) do
    content = data["content"] || ""

    """
    ## 👤 User — #{format_ts(ts)}

    #{content}
    """
  end

  defp render_event(%{"type" => "assistant.message", "data" => data, "timestamp" => ts}, _tool_names) do
    content = data["content"] || ""
    reasoning = data["reasoningText"]

    parts = ["## 🤖 Assistant — #{format_ts(ts)}", content]

    if reasoning && String.trim(reasoning) != "" do
      parts ++ ["<details>\n<summary>Reasoning</summary>\n\n#{reasoning}\n\n</details>"]
    else
      parts
    end
    |> Enum.join("\n\n")
  end

  defp render_event(%{"type" => "tool.execution_start", "data" => data, "timestamp" => ts}, _) do
    "  🔧 `#{data["toolName"]}` — `#{inspect_args(data["arguments"])}` _(#{format_ts(ts)})_"
  end

  defp render_event(%{"type" => "tool.execution_complete", "data" => data}, tool_names) do
    status = if data["success"], do: "✅", else: "❌"
    name = tool_names[data["toolCallId"]] || "?"
    "  #{status} `#{name}`"
  end

  defp render_event(_, _), do: nil

  defp inspect_args(args) when is_map(args), do: Jason.encode!(args)
  defp inspect_args(args) when is_binary(args), do: args
  defp inspect_args(_), do: "{}"

  defp format_ts(ts) when is_binary(ts) do
    case DateTime.from_iso8601(ts) do
      {:ok, dt, _} ->
        dt
        |> DateTime.truncate(:second)
        |> DateTime.to_iso8601()
        |> String.replace("T", " ")
        |> String.replace("Z", " UTC")

      _ ->
        ts
    end
  end

  defp format_ts(_), do: ""

  defp default_output(events, session_id) do
    date =
      case Enum.find(events, &(&1["type"] == "session.start")) do
        nil -> Date.utc_today()
        e -> parse_date(e["data"]["startTime"])
      end
      |> to_string()

    short = String.slice(session_id, 0, 8)
    Path.join(["docs", "audit", "#{date}-#{short}.md"])
  end

  defp parse_date(ts) when is_binary(ts) do
    case Date.from_iso8601(String.slice(ts, 0, 10)) do
      {:ok, d} -> d
      _ -> Date.utc_today()
    end
  end

  defp parse_date(_), do: Date.utc_today()
end

ExportChat.main(System.argv())
