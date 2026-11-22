defmodule Psc.Export.MarkdownTest do
  use Psc.DataCase, async: true

  alias Psc.Accounts.Scope
  alias Psc.AccountsFixtures
  alias Psc.{Agent, Canvas, Notes}
  alias Psc.Export.Markdown
  alias Psc.InsightsFixtures

  setup do
    user = AccountsFixtures.user_fixture()

    {:ok, canvas} =
      Canvas.create_unstr_canvas(user.id, %{
        "name" => "Launch Plan!",
        "description" => "Where we start",
        "cells" =>
          InsightsFixtures.cells([
            {"Problem", "Teams need a faster onboarding path"},
            {"Risks", ""}
          ])
      })

    %{user: user, scope: Scope.for_user(user), canvas: canvas}
  end

  defp export(scope, canvas, sections) do
    {:ok, %{markdown: markdown}} = Markdown.build(scope, canvas.id, sections)
    markdown
  end

  test "the canvas section lists every cell, unsaved edits included", %{
    user: user,
    scope: scope,
    canvas: canvas
  } do
    {:ok, _event} =
      Canvas.apply_unstr_canvas_operation(canvas.id, user.id, %{
        "type" => "update_cell",
        "cell_key" => "r1_c2",
        "field" => "content",
        "value" => "Budget may slip"
      })

    assert {:ok, %{filename: "launch-plan.md", markdown: markdown}} =
             Markdown.build(scope, canvas.id, ["canvas"])

    assert markdown =~ "# Launch Plan!"
    assert markdown =~ "## Canvas"
    assert markdown =~ "### Problem\n\nTeams need a faster onboarding path"
    assert markdown =~ "### Risks\n\nBudget may slip"
    refute markdown =~ "## Notes"
  end

  test "sections follow the document order and unknown keys are ignored", %{
    scope: scope,
    canvas: canvas
  } do
    markdown = export(scope, canvas, ["info", "bogus", "notes"])

    assert [_, notes, info] = String.split(markdown, ~r/^## /m)
    assert notes =~ ~r/^Notes/
    assert info =~ ~r/^Info and settings/
    assert info =~ "- **Description:** Where we start"
    assert info =~ "- **Shared with:** Nobody"
  end

  test "notes are exported with their content", %{user: user, scope: scope, canvas: canvas} do
    {:ok, note} = Notes.create_note(canvas.id, user.id, %{title: "Interview"})
    {:ok, _note} = Notes.save_content_to_db(note.id, "Three teams said **yes**.")

    markdown = export(scope, canvas, ["notes"])

    assert markdown =~ "### Interview\n\nThree teams said **yes**."
  end

  test "agent chats are the exporter's own", %{user: user, scope: scope, canvas: canvas} do
    other = AccountsFixtures.user_fixture()
    {:ok, canvas} = Canvas.share_unstr_canvas_with(canvas, other.email)

    {:ok, mine} = Agent.create_session(user.id, %{canvas_id: canvas.id})
    {:ok, _message} = Agent.append_user_message(mine, "What is missing?")
    {:ok, reply} = Agent.start_assistant_message(mine)
    {:ok, _reply} = Agent.finish_message(reply, %{content: "The risks cell."})

    {:ok, theirs} = Agent.create_session(other.id, %{canvas_id: canvas.id})
    {:ok, _message} = Agent.append_user_message(theirs, "Private question")

    markdown = export(scope, canvas, ["agent"])

    # The first message names the chat.
    assert markdown =~ "### What is missing?"
    assert markdown =~ "**You:**\n\nWhat is missing?"
    assert markdown =~ "**Agent:**\n\nThe risks cell."
    refute markdown =~ "Private question"
  end

  test "analysis and history sections describe the canvas", %{scope: scope, canvas: canvas} do
    {:ok, _report} = Psc.Insights.run(scope, canvas, canvas.cells)

    markdown = export(scope, canvas, ["analysis", "history"])

    assert markdown =~ "### Overview"
    assert markdown =~ "- **Longest:** Problem"
    assert markdown =~ "### Findings"
    assert markdown =~ "Risks has no content yet"
    assert markdown =~ "## History"
    assert markdown =~ "(current)"
  end

  test "someone without access gets nothing", %{canvas: canvas} do
    stranger = Scope.for_user(AccountsFixtures.user_fixture())

    assert Markdown.build(stranger, canvas.id, ["canvas"]) == {:error, :not_found}
    assert Markdown.build(nil, canvas.id, ["canvas"]) == {:error, :not_found}
    assert Markdown.build(stranger, Ecto.UUID.generate(), ["canvas"]) == {:error, :not_found}
  end

  test "at least one known section is required", %{scope: scope, canvas: canvas} do
    assert Markdown.build(scope, canvas.id, []) == {:error, :no_sections}
    assert Markdown.build(scope, canvas.id, ["bogus"]) == {:error, :no_sections}
  end
end
