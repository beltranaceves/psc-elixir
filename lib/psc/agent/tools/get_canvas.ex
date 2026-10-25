defmodule Psc.Agent.Tools.GetCanvas do
  @moduledoc """
  Reads one canvas, including its cell matrix.
  """

  use Jido.Action,
    name: "get_canvas",
    description:
      "Read one canvas by id: its name, description and the cell grid, bento board or image board the editor shows.\n" <>
        "\n" <>
        "Result shape:\n" <>
        "- `layout_mode` is `\"table\"` (a rows x columns matrix), `\"bento\"` (free-form cards on " <>
        "a fixed column grid, up to 16 columns) or `\"image\"` (floating cells over a backdrop " <>
        "picture).\n" <>
        "- `grid` is the board's size: `columns` and `rows` (a bento's rows include any empty " <>
        "rows the template reserved; a table's are its matrix size; an image board is " <>
        "`100 x 100`, because its unit is a percentage of the picture).\n" <>
        "- `cards` lists the reading order for every mode: `key`, `label`, and the rectangle it " <>
        "occupies (`x`, `y`, `w`, `h`, in grid units or image percentages, 0-based / " <>
        "0-100).\n" <>
        "- For a table, `cells` holds `rows` and `columns` (each with `id`, `label`, optional " <>
        "`accent`), `layout` and one entry per cell. `layout` is a matrix of cell KEYS, mostly " <>
        "`r<row>_c<col>` (e.g. [[\"r1_c1\", \"r1_c2\"], [\"r2_c1\", \"r2_c2\"]]). Follow a key into " <>
        "`cells` to read that cell.\n" <>
        "- For a bento or an image board, `cells` is flat: one entry per cell key, with a " <>
        "`placement` (`x`, `y`, `w`, `h`) and an optional `accent`. There are no row or column " <>
        "headers.\n" <>
        "- An image board also has `backdrop` (`url`, `fit`, optional `alt` and `aspect`), and " <>
        "each of its cells has a `kind`: `\"card\"` (a titled Markdown box) or `\"text\"` (a " <>
        "one-line label placed on the picture).\n" <>
        "- Each cell entry has `label` and `content` — `content` is the Markdown the user wrote in " <>
        "it.\n" <>
        "- `cell_count` is how many cells exist; `filled_cell_count` is how many have text.\n" <>
        "\n" <>
        "How to read it:\n" <>
        "- `content` of \"\" means the user has not written in that cell yet. Say the cell is empty; " <>
        "never say you cannot access it, and never invent text for it.\n" <>
        "- To quote a cell, use its `content` verbatim and name it by `label` plus its key.\n" <>
        "- If every cell is empty (`filled_cell_count` of 0), say the canvas has N cells and none " <>
        "are filled, then offer what the user could put there.",
    schema: [
      id: [type: :string, required: true, doc: "The canvas id (UUID)."]
    ]

  alias Psc.Agent.Tools.Ref
  alias Psc.Agent.Tools.Scope
  alias Psc.Canvas
  alias Psc.Canvas.Structure

  # One message for "missing" and "not yours": two different ones would let a
  # client probe which canvas ids exist.
  @not_found "No canvas or note with that id that you can access."

  @impl true
  def run(%{id: id}, context) do
    with {:ok, user} <- Scope.user(context),
         {:ok, id} <- Scope.uuid(id, "Canvas id"),
         %{} = canvas <- fetch(id),
         :ok <- authorize(canvas, user) do
      cells = canvas.cells || %{}

      # Tell the model how much writing there is. Without this it sees empty
      # `content` strings and reports "I can't access the cells", which reads like
      # a permissions failure rather than an empty canvas.
      structure = Structure.cards(cells)
      cell_keys = Enum.map(structure, & &1.key)
      filled = Enum.count(cell_keys, &filled?(cells[&1]))

      {:ok,
       %{
         id: canvas.id,
         name: canvas.name,
         description: canvas.description,
         layout_mode:
           case Structure.mode(cells) do
             :bento -> "bento"
             :image -> "image"
             :table -> "table"
           end,
         grid: Structure.bounds(cells),
         cells: cells,
         cards:
           Enum.map(structure, fn card ->
             %{key: card.key, label: card.label, x: card.x, y: card.y, w: card.w, h: card.h}
           end),
         cell_count: length(cell_keys),
         filled_cell_count: filled,
         updated_at: Scope.iso8601(canvas.updated_at),
         refs: [
           Ref.canvas(canvas.id, canvas.name, canvas.description)
           | cell_refs(canvas, cells, cell_keys)
         ]
       }}
    end
  end

  defp fetch(id), do: Canvas.get_unstr_canvas(id) || {:error, @not_found}

  defp filled?(%{"content" => content}), do: String.trim(to_string(content)) != ""
  defp filled?(_other), do: false

  # Only filled cells get a chip - an empty cell has nothing to show, and a
  # 4x4 canvas would otherwise bury the answer in twelve useless links.
  @max_cell_refs 8

  defp cell_refs(canvas, cells, cell_keys) do
    cell_keys
    |> Enum.filter(&filled?(cells[&1]))
    |> Enum.take(@max_cell_refs)
    |> Enum.map(fn key ->
      cell = cells[key] || %{}
      Ref.cell(canvas.id, key, cell["label"] || key, Ref.excerpt(cell["content"]))
    end)
  end

  defp authorize(canvas, user) do
    if Canvas.can_access_unstr_canvas?(canvas, user.email) do
      :ok
    else
      {:error, @not_found}
    end
  end
end
