defmodule Psc.Export.ImportTest do
  use Psc.DataCase, async: true

  alias Psc.Accounts.Scope
  alias Psc.AccountsFixtures
  alias Psc.{Canvas, Notes}
  alias Psc.Agent.Files, as: AgentFiles
  alias Psc.Export.{Data, Import, Markdown}
  alias Psc.InsightsFixtures

  @all ~w(canvas notes analysis agent history info)

  setup do
    user = AccountsFixtures.user_fixture()

    {:ok, canvas} =
      Canvas.create_unstr_canvas(user.id, %{
        "name" => "Round trip",
        "description" => "Exported and back",
        "cells" =>
          InsightsFixtures.cells([
            {"Problem", "Slow onboarding --> lost week"},
            # Text that looks like the data block's marker must not confuse it.
            {"Risks", "<!-- psc-canvas-data v1\nnot data"}
          ])
      })

    %{user: user, scope: Scope.for_user(user), canvas: canvas}
  end

  defp export(scope, canvas, sections \\ @all) do
    {:ok, %{markdown: markdown}} = Markdown.build(scope, canvas.id, sections)
    markdown
  end

  defp edit(canvas, user, key, value) do
    {:ok, _event} =
      Canvas.apply_unstr_canvas_operation(canvas.id, user.id, %{
        "type" => "update_cell",
        "cell_key" => key,
        "field" => "content",
        "value" => value
      })
  end

  test "a full export comes back as a new canvas for the importer", %{
    user: user,
    scope: scope,
    canvas: canvas
  } do
    {:ok, note} = Notes.create_note(canvas.id, user.id, %{title: "Interview"})
    {:ok, _note} = Notes.save_content_to_db(note.id, "Three teams said **yes**.")

    {:ok, canvas} =
      Canvas.update_agent_config(canvas, %{"prompt" => "Be brief."}, [
        %{"path" => "docs/brief.md", "content" => "The brief"}
      ])

    # A second version, which the canvas holds, with an unsaved edit on top.
    {:ok, {:created, draft}} = Canvas.start_draft(canvas.id, user.id)
    edit(canvas, user, "r1_c1", "Onboarding takes a week")
    {:ok, _named} = Canvas.name_pivot(canvas.id, draft.id, %{name: "Sharper", rationale: "Why"})
    edit(canvas, user, "r1_c2", "Budget")

    importer = AccountsFixtures.user_fixture()
    assert {:ok, copy} = Import.import_markdown(Scope.for_user(importer), export(scope, canvas))

    assert copy.id != canvas.id
    assert copy.author_id == importer.id
    assert copy.name == "Round trip"
    assert copy.description == "Exported and back"
    assert copy.shared_with == []
    assert Canvas.get_unstr_canvas_content(copy.id) == Canvas.get_unstr_canvas_content(canvas.id)
    assert copy.agent_config["prompt"] == "Be brief."

    assert [%{title: "Interview"} = copied_note] = Notes.list_notes(copy.id)
    assert Notes.get_note_content(copied_note.id) == "Three teams said **yes**."

    assert [%{path: "docs/brief.md", content: "The brief"}] = AgentFiles.list_canvas(copy.id)

    assert [root, sharper] = Canvas.list_pivots(copy.id)
    assert root.name == "Initial version"
    assert sharper.name == "Sharper"
    assert sharper.parent_id == root.id
    assert sharper.author_id == importer.id
    assert copy.head_pivot_id == sharper.id
    # The held version's snapshot is the live content, unsaved edit included.
    assert sharper.cells["r1_c2"]["content"] == "Budget"
  end

  test "only the exported sections come back", %{scope: scope, canvas: canvas, user: user} do
    {:ok, _note} = Notes.create_note(canvas.id, user.id, %{title: "Left out"})

    assert {:ok, copy} = Import.import_markdown(scope, export(scope, canvas, ["canvas"]))

    assert Notes.list_notes(copy.id) == []
    assert [%{name: "Imported"}] = Canvas.list_pivots(copy.id)
  end

  test "a file without the Canvas section has nothing to import", %{scope: scope, canvas: canvas} do
    assert Import.import_markdown(scope, export(scope, canvas, ["notes"])) == {:error, :missing}
    assert Import.import_markdown(scope, "# Just notes") == {:error, :missing}
  end

  test "hand edits to the readable text are ignored", %{scope: scope, canvas: canvas} do
    markdown =
      scope
      |> export(canvas, ["canvas"])
      |> String.replace("### Problem\n\nSlow onboarding", "### Problem\n\nEdited by hand")

    assert {:ok, copy} = Import.import_markdown(scope, markdown)
    assert copy.cells["r1_c1"]["content"] == "Slow onboarding --> lost week"
  end

  test "damaged, foreign and newer data is refused", %{scope: scope, canvas: canvas} do
    data = Data.build(canvas, canvas.cells, ["canvas"])

    assert Import.import_markdown(scope, Data.embed(Map.put(data, "version", 2))) ==
             {:error, :unsupported}

    assert Import.import_markdown(scope, Data.embed(%{"format" => "other"})) ==
             {:error, :invalid}

    assert Import.import_markdown(scope, "<!-- psc-canvas-data v1\n{not json\n-->") ==
             {:error, :invalid}

    bad_cells = put_in(data, ["canvas", "cells"], %{"layout_mode" => "bento", "a" => %{}})

    assert {:error, {:invalid_cells, _message}} =
             Import.import_markdown(scope, Data.embed(bad_cells))

    bad_version =
      Map.put(data, "history", %{
        "head_id" => "x",
        "pivots" => [%{"id" => "x", "cells" => %{"layout_mode" => "bento", "a" => %{}}}]
      })

    assert {:error, {:invalid_cells, _message}} =
             Import.import_markdown(scope, Data.embed(bad_version))

    assert Import.import_markdown(scope, String.duplicate("x", Import.max_bytes() + 1)) ==
             {:error, :too_large}
  end

  test "a failed import creates nothing", %{scope: scope, canvas: canvas, user: user} do
    data =
      canvas
      |> Data.build(canvas.cells, ["canvas"])
      |> Map.put("notes", [%{"title" => "Fine"}, "not a note"])

    before = length(Canvas.list_user_unstr_canvases(user.id))

    assert Import.import_markdown(scope, Data.embed(data)) == {:error, :invalid}
    assert length(Canvas.list_user_unstr_canvases(user.id)) == before
  end

  test "without a user there is no import", %{scope: scope, canvas: canvas} do
    assert Import.import_markdown(nil, export(scope, canvas)) == {:error, :unauthorized}
  end
end
