defmodule Psc.Agent.Tools.GetCanvas do
  @moduledoc """
  Reads one canvas, including its cell matrix.
  """

  use Jido.Action,
    name: "get_canvas",
    description:
      "Read one canvas by id: its name, description and the cell grid the editor shows.\n" <>
        "\n" <>
        "Result shape:\n" <>
        "- `cells` holds `rows` and `columns` (each with `id`, `label`, optional `accent`), " <>
        "`layout`, one entry per cell, and `$name`/`$description` (a copy of the header).\n" <>
        "- `layout` is a matrix of cell KEYS, e.g. [[\"r1_c1\", \"r1_c2\"], [\"r2_c1\", \"r2_c2\"]]. " <>
        "The keys are not objects: follow a key into `cells` to read that cell.\n" <>
        "- Each cell entry, keyed `r<row>_c<col>` (e.g. `r1_c1`), has `label` and `content` — " <>
        "`content` is the Markdown the user wrote in it.\n" <>
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
      cell_keys = Enum.filter(Map.keys(cells), &String.match?(&1, ~r/^r\d+_c\d+$/))
      filled = Enum.count(cell_keys, &filled?(cells[&1]))

      {:ok,
       %{
         id: canvas.id,
         name: canvas.name,
         description: canvas.description,
         cells: cells,
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
