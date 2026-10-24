defmodule Psc.Agent.ToolsTest do
  use Psc.DataCase, async: true

  alias Psc.Accounts.Scope
  alias Psc.AccountsFixtures
  alias Psc.Agent.Tools
  alias Psc.NotesFixtures

  setup do
    user = AccountsFixtures.user_fixture()
    %{user: user, context: %{scope: Scope.for_user(user)}}
  end

  test "list_canvases returns only what the scope can see", %{user: user, context: context} do
    NotesFixtures.canvas_fixture(%{:user => user, "name" => "Mine"})
    NotesFixtures.canvas_fixture(%{"name" => "Theirs"})

    assert {:ok, %{canvases: [canvas]}} = Tools.ListCanvases.run(%{}, context)
    assert canvas.name == "Mine"
    assert canvas.access == "owner"
  end

  test "get_canvas refuses a canvas owned by somebody else", %{context: context} do
    canvas = NotesFixtures.canvas_fixture(%{"name" => "Private"})

    assert {:error, message} = Tools.GetCanvas.run(%{id: canvas.id}, context)
    assert message =~ "that you can access"
  end

  test "get_canvas reports an unknown id and a malformed one", %{context: context} do
    assert {:error, missing} = Tools.GetCanvas.run(%{id: Ecto.UUID.generate()}, context)
    assert missing =~ "No canvas"

    assert {:error, malformed} = Tools.GetCanvas.run(%{id: "nope"}, context)
    assert malformed =~ "must be a UUID"
  end

  test "get_note returns the Markdown the editor shows", %{user: user, context: context} do
    note =
      NotesFixtures.note_fixture(%{
        user: user,
        title: "Brief",
        content: "# Brief\n\nShip it."
      })

    assert {:ok, result} = Tools.GetNote.run(%{note_id: note.id}, context)
    assert result.title == "Brief"
    assert result.content == "# Brief\n\nShip it."
  end

  test "list_notes lists titles only", %{user: user, context: context} do
    note =
      NotesFixtures.note_fixture(%{
        user: user,
        canvas: NotesFixtures.canvas_fixture(%{:user => user})
      })

    assert {:ok, %{notes: [listed]}} = Tools.ListNotes.run(%{canvas_id: note.canvas_id}, context)
    assert listed.id == note.id
    refute Map.has_key?(listed, :content)
  end

  test "a missing scope is an error, never a fallback user" do
    assert {:error, message} = Tools.ListCanvases.run(%{}, %{})
    assert message =~ "signed-in"
  end

  test "tool results carry deep links the chat can render", %{user: user, context: context} do
    canvas = NotesFixtures.canvas_fixture(%{:user => user, "name" => "Mine"})
    note = NotesFixtures.note_fixture(%{user: user, canvas: canvas, title: "Brief"})

    assert {:ok, %{refs: [canvas_ref]}} = Tools.ListCanvases.run(%{}, context)
    assert canvas_ref["url"] == "/canvas/#{canvas.id}?tab=editor"
    assert canvas_ref["label"] == "Mine"

    assert {:ok, %{refs: [note_ref]}} = Tools.ListNotes.run(%{canvas_id: canvas.id}, context)
    assert note_ref["url"] == "/canvas/#{canvas.id}?tab=notes&note=#{note.id}"
    assert note_ref["label"] == "Brief"

    assert {:ok, %{refs: [same_note]}} = Tools.GetNote.run(%{note_id: note.id}, context)
    assert same_note["url"] == note_ref["url"]

    assert {:ok, %{refs: [same_canvas]}} = Tools.GetCanvas.run(%{id: canvas.id}, context)
    assert same_canvas["url"] == canvas_ref["url"]
  end

  test "the MCP specs are derived from the action schemas" do
    specs = Tools.mcp_specs()

    assert Enum.map(specs, & &1["name"]) == [
             "list_templates",
             "list_canvases",
             "get_canvas",
             "list_notes",
             "get_note"
           ]

    get_canvas = Enum.find(specs, &(&1["name"] == "get_canvas"))
    assert get_canvas["inputSchema"]["type"] == "object"
    assert get_canvas["inputSchema"]["properties"]["id"]["type"] == "string"
    assert get_canvas["inputSchema"]["required"] == ["id"]

    # The description is prompt text: it has to teach the result shape, or the
    # model reads empty cells as "no access".
    for fact <- ["layout", "r<row>_c<col>", "filled_cell_count", "empty", "bento", "placement"] do
      assert get_canvas["description"] =~ fact
    end
  end
end
