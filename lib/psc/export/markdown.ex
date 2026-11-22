defmodule Psc.Export.Markdown do
  @moduledoc """
  A canvas as one Markdown document, for the editor's Markdown export.

  The reader picks the sections (`sections/0`); each one reads the same data
  its tab shows. Unsaved canvas and note edits are included: content is read
  through the event tail, as the editor does. Agent chats are the reader's own,
  because chats are personal. The canvas's access rule is the gate for all of
  it.
  """

  alias Psc.{Agent, Canvas, Insights, Notes}
  alias Psc.Agent.Config
  alias Psc.Export.Data
  alias Psc.Insights.Cells

  @sections ~w(canvas notes analysis agent history info)

  @doc "The section keys, in document order."
  def sections, do: @sections

  @doc "A human label for a section key."
  def section_label("canvas"), do: "Canvas"
  def section_label("notes"), do: "Notes"
  def section_label("analysis"), do: "Analysis"
  def section_label("agent"), do: "Agent chats"
  def section_label("history"), do: "History"
  def section_label("info"), do: "Info and settings"

  @doc """
  Builds the document. Unknown section keys are ignored; at least one known
  one is required.

  Returns `{:ok, %{filename: filename, markdown: markdown}}`,
  `{:error, :not_found}` (no such canvas, or no access) or
  `{:error, :no_sections}`.
  """
  def build(scope, canvas_id, sections, now \\ DateTime.utc_now()) do
    sections = Enum.filter(@sections, &(&1 in List.wrap(sections)))

    with %{} = canvas <- Canvas.get_unstr_canvas_with_author(canvas_id),
         true <- can_access?(scope, canvas) || :not_found,
         [_ | _] <- sections do
      cells = Canvas.get_unstr_canvas_content(canvas.id)
      name = present(canvas.name) || "Untitled canvas"

      body =
        Enum.map_join(sections, "\n", fn section ->
          "## #{section_label(section)}\n\n" <> section(section, scope, canvas, cells, now)
        end)

      header = "# #{name}\n\n" <> "_Exported #{stamp(now)}_\n\n"

      # With the Canvas section the file can be imported again: the exact data
      # follows the readable text in a comment viewers do not show.
      data =
        case Data.build(canvas, cells, sections) do
          nil -> ""
          data -> "\n" <> Data.embed(data) <> "\n"
        end

      markdown = String.trim_trailing(header <> body) <> "\n" <> data

      {:ok, %{filename: filename(name), markdown: markdown}}
    else
      [] -> {:error, :no_sections}
      _other -> {:error, :not_found}
    end
  end

  defp can_access?(%{user: %{email: email}}, canvas),
    do: Canvas.can_access_unstr_canvas?(canvas, email)

  defp can_access?(_scope, _canvas), do: false

  # --- Canvas -----------------------------------------------------------------

  defp section("canvas", _scope, _canvas, cells, _now) do
    case Cells.cards(%{cells: cells}) do
      [] ->
        "_The canvas has no cells._\n"

      cards ->
        Enum.map_join(cards, "\n", fn card ->
          fields =
            card.fields
            |> Enum.map(fn field ->
              value = card.cell[field] |> Cells.value() |> String.trim()
              title = Cells.field_label(card.cell, field)
              text = if value == "", do: "_Empty_", else: value

              # A cell with one untitled field reads as plain text under the
              # cell's heading; more fields get their own labels.
              if length(card.fields) == 1 and title == field,
                do: text,
                else: "**#{title}**\n\n#{text}"
            end)

          body = if fields == [], do: "_Empty_", else: Enum.join(fields, "\n\n")
          "### #{card.label}\n\n#{body}\n"
        end)
    end
  end

  # --- Notes ------------------------------------------------------------------

  defp section("notes", _scope, canvas, _cells, _now) do
    case Notes.list_notes(canvas.id) do
      [] ->
        "_No notes._\n"

      notes ->
        Enum.map_join(notes, "\n", fn note ->
          content = note.id |> Notes.get_note_content() |> to_string() |> String.trim()
          title = present(note.title) || "Untitled note"
          "### #{title}\n\n" <> if(content == "", do: "_Empty_", else: content) <> "\n"
        end)
    end
  end

  # --- Analysis ---------------------------------------------------------------

  defp section("analysis", scope, canvas, cells, now) do
    overview =
      case Insights.overview(scope, canvas, cells, canvas.touch_map || %{}, now) do
        {:ok, %{tiles: tiles}} ->
          "### Overview\n\n" <>
            Enum.map_join(tiles, "\n", fn tile ->
              "- **#{tile.label}:** #{tile.value || "—"} (#{tile.detail})"
            end) <> "\n"

        _other ->
          ""
      end

    overview <> "\n" <> findings(Insights.get_report(scope, canvas.id), cells)
  end

  # --- Agent ------------------------------------------------------------------

  defp section("agent", scope, canvas, _cells, _now) do
    case Agent.list_sessions_for_canvas(canvas.id, scope.user.id) do
      [] ->
        "_You have no agent chats on this canvas._\n"

      sessions ->
        "_Your own chats; other people's chats are private to them._\n\n" <>
          Enum.map_join(sessions, "\n", &session/1)
    end
  end

  # --- History ----------------------------------------------------------------

  defp section("history", _scope, canvas, _cells, _now) do
    case Canvas.list_pivots(canvas.id) do
      [] ->
        "_No saved versions._\n"

      pivots ->
        by_id = Map.new(pivots, &{&1.id, &1})

        Enum.map_join(pivots, "\n", fn pivot ->
          name = present(pivot.name) || "Unnamed version"
          head = if pivot.id == canvas.head_pivot_id, do: " (current)", else: ""

          parent = by_id[pivot.parent_id]

          meta =
            [
              pivot.kind != "pivot" && pivot.kind,
              pivot.author && "by #{display_name(pivot.author.email)}",
              pivot.inserted_at && stamp(pivot.inserted_at),
              parent && "from “#{present(parent.name) || "Unnamed"}”"
            ]
            |> Enum.filter(& &1)
            |> Enum.join(" · ")

          rationale = present(pivot.rationale)

          "- **#{name}**#{head}" <>
            if(meta != "", do: " — #{meta}", else: "") <>
            if(rationale, do: "\n  #{indent(rationale)}", else: "")
        end) <> "\n"
    end
  end

  # --- Info -------------------------------------------------------------------

  defp section("info", _scope, canvas, cells, _now) do
    config = Config.normalize(canvas.agent_config)

    about =
      [
        {"Description", present(canvas.description)},
        {"Layout", cells |> Psc.Canvas.Structure.mode() |> to_string() |> String.capitalize()},
        {"Owner", canvas.author && display_name(canvas.author.email)},
        {"Shared with", shared_with(canvas.shared_with)},
        {"Created", canvas.inserted_at && stamp(canvas.inserted_at)},
        {"Updated", canvas.updated_at && stamp(canvas.updated_at)}
      ]
      |> Enum.filter(fn {_label, value} -> value end)
      |> Enum.map_join("\n", fn {label, value} -> "- **#{label}:** #{value}" end)

    "### About\n\n" <> about <> "\n\n" <> agent_settings(config, canvas.id)
  end

  defp findings(nil, _cells), do: "### Findings\n\n_The checks have not run yet._\n"

  defp findings(report, cells) do
    labels = Map.new(Cells.cards(%{cells: cells}), &{&1.key, &1.label})
    visible = Enum.reject(report.findings, &(&1["id"] in report.dismissed))

    stale =
      if Insights.ai_stale?(report, cells),
        do: "_The canvas changed after the last AI review._\n\n",
        else: ""

    list =
      case visible do
        [] ->
          "_No findings._\n"

        _findings ->
          Enum.map_join(visible, "\n", fn finding ->
            cell_list =
              (finding["cell_keys"] || [])
              |> Enum.map_join(", ", &(labels[&1] || &1))

            [
              "- **#{finding["title"]}** (#{finding["severity"]}, #{source(finding)})",
              present(finding["detail"]) && "  #{indent(finding["detail"])}",
              cell_list != "" && "  Cells: #{cell_list}"
            ]
            |> Enum.filter(& &1)
            |> Enum.join("\n")
          end) <> "\n"
      end

    "### Findings\n\n" <> stale <> list
  end

  defp source(%{"source" => "ai"} = finding) do
    attribution = finding["attribution"] || %{}
    Enum.join(Enum.filter(["AI", attribution["provider"], attribution["model"]], & &1), " · ")
  end

  defp source(_finding), do: "heuristic"

  defp session(session) do
    messages =
      session
      |> Agent.list_messages()
      |> Enum.flat_map(fn message ->
        content = String.trim(message.content || "")
        speaker = if message.role == :user, do: "You", else: "Agent"

        cond do
          content != "" -> ["**#{speaker}:**\n\n#{content}"]
          message.status == :error -> ["**#{speaker}:** _failed: #{message.error}_"]
          true -> []
        end
      end)

    title = present(session.title) || "Chat"
    body = if messages == [], do: "_No messages._", else: Enum.join(messages, "\n\n")
    "### #{title}\n\n#{body}\n"
  end

  defp agent_settings(config, canvas_id) do
    prompt = present(config["prompt"])

    roles =
      Enum.map_join(config["roles"], "\n", fn role ->
        default = if role["key"] == config["default_role"], do: " (default)", else: ""
        instructions = present(role["instructions"])

        "- **#{role["name"]}**#{default}" <>
          if(instructions, do: "\n  #{indent(instructions)}", else: "")
      end)

    files =
      canvas_id
      |> Agent.Files.list_canvas()
      |> Enum.map_join("\n", &"- `#{&1.path}`")

    [
      "### Agent",
      "**Prompt**\n\n" <> (prompt || "_None_"),
      "**Roles**\n\n" <> if(roles == "", do: "_None_", else: roles),
      "**Tools:** " <> Enum.join(Config.enabled_tool_names(config), ", "),
      "**Reference files**\n\n" <> if(files == "", do: "_None_", else: files)
    ]
    |> Enum.join("\n\n")
    |> Kernel.<>("\n")
  end

  defp shared_with([]), do: "Nobody"
  defp shared_with(emails), do: Enum.map_join(emails, ", ", &display_name/1)

  # The part of the address before the @, as the rest of the app shows people.
  defp display_name(email), do: email |> String.split("@") |> hd()

  defp indent(text), do: text |> String.trim() |> String.replace("\n", "\n  ")

  defp present(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present(_value), do: nil

  defp stamp(%DateTime{} = at), do: Calendar.strftime(at, "%Y-%m-%d %H:%M UTC")
  defp stamp(%NaiveDateTime{} = at), do: Calendar.strftime(at, "%Y-%m-%d %H:%M UTC")

  defp filename(name) do
    slug =
      name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/u, "-")
      |> String.trim("-")
      |> String.slice(0, 60)

    if(slug == "", do: "canvas", else: slug) <> ".md"
  end
end
