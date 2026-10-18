defmodule Psc.Canvas do
  @moduledoc """
  The Canvas context for managing strategic planning canvases.
  Supports collaborative editing with cell-level operations.
  """

  require Logger
  import Ecto.Query, warn: false
  alias Psc.Repo
  alias Psc.Canvas.Canvas
  alias Psc.Canvas.UnstrCanvas
  alias Psc.Canvas.Layout

  @doc """
  List all canvases authored by a user.
  """
  def list_user_canvases(user_id) do
    from(c in Canvas, where: c.author_id == ^user_id, order_by: [desc: c.updated_at])
    |> preload(:author)
    |> Repo.all()
  end

  @doc """
  List all canvases shared with a user by email.
  """
  def list_shared_canvases(user_email) do
    from(c in Canvas,
      where: fragment("? = ANY(?)", ^user_email, c.shared_with),
      order_by: [desc: c.updated_at]
    )
    |> preload(:author)
    |> Repo.all()
  end

  @doc """
  Get a single canvas by id.
  """
  def get_canvas(id) do
    Repo.get(Canvas, id)
  end

  @doc """
  Get a canvas with author preloaded.
  """
  def get_canvas_with_author(id) do
    result =
      Canvas
      |> preload(:author)
      |> Repo.get(id)

    if result do
      Logger.debug(fn ->
        "[DB LOAD] Canvas #{id} loaded: #{inspect(result, limit: :infinity)}"
      end)
    else
      Logger.warning("[DB LOAD] Canvas #{id} NOT FOUND in database")
    end

    result
  end

  @doc """
  Create a new canvas with all cell structs initialized.
  """
  def create_canvas(user_id, attrs \\ %{}) do
    # Explicitly initialize all cells and include them in attrs so they're persisted
    cell_attrs = %{
      problem: %{},
      leverage: %{},
      solution_cluster: %{},
      horizon: %{},
      outer_environment: %{},
      inner_environment: %{},
      evolvability_cluster: %{},
      potential: %{},
      manifestations: %{},
      capabilities: %{},
      merit_cluster: %{},
      mission: %{}
    }

    all_attrs =
      Map.merge(cell_attrs, attrs)
      |> Map.put(:author_id, user_id)

    Logger.debug(fn -> "[DB SAVE - CREATE] attrs: #{inspect(all_attrs, limit: :infinity)}" end)

    result =
      %Canvas{}
      |> Canvas.changeset(all_attrs)
      |> Repo.insert()

    case result do
      {:ok, canvas} ->
        Logger.debug(fn -> "[DB SAVE - CREATE SUCCESS] #{inspect(canvas, limit: :infinity)}" end)
        {:ok, canvas}

      {:error, changeset} ->
        Logger.error("[DB SAVE - CREATE FAILED] Changeset error: #{inspect(changeset)}")
        {:error, changeset}
    end
  end

  @doc """
  Update a canvas.
  """
  def update_canvas(canvas, attrs) do
    Logger.debug(fn ->
      "[DB SAVE - UPDATE] Canvas ID: #{canvas.id}, cells: #{inspect(Map.keys(attrs))}, attrs: #{inspect(attrs, limit: :infinity)}"
    end)

    result =
      canvas
      |> Canvas.changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, updated_canvas} ->
        Logger.debug(fn ->
          "[DB SAVE - UPDATE SUCCESS] #{inspect(updated_canvas, limit: :infinity)}"
        end)

        {:ok, updated_canvas}

      {:error, changeset} ->
        Logger.error("[DB SAVE - UPDATE FAILED] Changeset error: #{inspect(changeset)}")
        {:error, changeset}
    end
  end

  @doc """
  Update a single cell in a canvas.
  """
  def update_cell(canvas, cell_name, cell_data) do
    canvas
    |> Canvas.changeset(%{String.to_atom(cell_name) => cell_data})
    |> Repo.update()
  end

  @doc """
  Share a canvas with a user by email.
  """
  def share_canvas_with(canvas, email) do
    new_shared_with =
      (canvas.shared_with || [])
      |> Enum.uniq()
      |> then(&(&1 ++ [email]))
      |> Enum.uniq()

    canvas
    |> Canvas.changeset(%{shared_with: new_shared_with})
    |> Repo.update()
  end

  @doc """
  Remove a user's access to a canvas.
  """
  def unshare_canvas(canvas, email) do
    new_shared_with =
      canvas.shared_with
      |> Enum.reject(&(&1 == email))

    canvas
    |> Canvas.changeset(%{shared_with: new_shared_with})
    |> Repo.update()
  end

  @doc """
  Check if a user can access a canvas (author or shared with them).
  """
  def can_access_canvas?(canvas, user_email) do
    canvas = Repo.preload(canvas, :author)
    canvas.author.email == user_email || Enum.any?(canvas.shared_with, &(&1 == user_email))
  end

  @doc """
  Delete a canvas.
  """
  def delete_canvas(canvas) do
    Repo.delete(canvas)
  end

  ## Unstructured Canvas Functions

  @doc """
  List saved canvas layouts.
  """
  def list_canvas_layouts do
    Layout
    |> order_by([l], desc: l.inserted_at)
    |> Repo.all()
  end

  @doc """
  Get a single canvas layout by id.
  """
  def get_canvas_layout(id) do
    Repo.get(Layout, id)
  end

  @doc """
  Create a canvas layout.
  """
  def create_canvas_layout(attrs \\ %{}) do
    %Layout{}
    |> Layout.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Update a canvas layout.
  """
  def update_canvas_layout(layout, attrs) do
    layout
    |> Layout.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Delete a canvas layout.
  """
  def delete_canvas_layout(layout) do
    Repo.delete(layout)
  end

  # ─── Template functions ───

  @doc """
  List all templates a user can access (authored or shared with them).
  """
  def list_templates(user) do
    from(l in Layout,
      where: l.author_id == ^user.id or fragment("? = ANY(?)", ^user.email, l.shared_with),
      order_by: [desc: l.updated_at]
    )
    |> preload(:author)
    |> Repo.all()
  end

  @doc """
  Get a template with author preloaded.
  """
  def get_template_with_author(id) do
    Layout
    |> preload(:author)
    |> Repo.get(id)
  end

  @doc """
  Create a template authored by the given user.
  """
  def create_template(user_id, attrs \\ %{}) do
    %Layout{author_id: user_id}
    |> Layout.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Update a template.
  """
  def update_template(template, attrs) do
    template
    |> Layout.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Delete a template.
  """
  def delete_template(template) do
    Repo.delete(template)
  end

  @doc """
  Share a template with a user by email (idempotent).
  """
  def share_template_with(template, email) do
    shared_with = template.shared_with || []
    new_shared_with = Enum.uniq([email | shared_with])
    update_template(template, %{"shared_with" => new_shared_with})
  end

  @doc """
  Remove a user's access to a template.
  """
  def unshare_template(template, email) do
    shared_with = template.shared_with || []
    new_shared_with = List.delete(shared_with, email)
    update_template(template, %{"shared_with" => new_shared_with})
  end

  @doc """
  Check if a user can access a template (author or shared).
  """
  def can_access_template?(template, user_email) do
    author = template.author

    cond do
      author && author.email == user_email -> true
      user_email in (template.shared_with || []) -> true
      true -> false
    end
  end

  @doc """
  Instantiate a canvas from a template.

  Transforms the template's layout_map (cells nested under "cells" with
  label/semantics/fields/defaults metadata) into the canvas cells shape
  (flat cell keys with row/column metadata and field values), per the
  editor spec.

  `overrides` lets the caller supply a user-chosen name/description; anything
  not given falls back to the template's own values.
  """
  def instantiate_template(template, user_id, overrides \\ %{}) do
    lm = template.layout_map || %{}
    rows = lm["rows"] || []
    columns = lm["columns"] || []
    layout = lm["layout"] || []
    template_cells = lm["cells"] || %{}

    cells =
      %{"rows" => rows, "columns" => columns, "layout" => layout}
      |> put_instantiated_cells(template_cells, layout, rows, columns)
      |> Map.put("relations", lm["relations"] || [])

    attrs =
      %{
        "name" => template.name,
        "description" => template.description || "",
        "cells" => cells
      }
      |> Map.merge(Map.reject(overrides || %{}, fn {_k, v} -> is_nil(v) or v == "" end))

    create_unstr_canvas(user_id, attrs)
  end

  defp put_instantiated_cells(cells, template_cells, layout, rows, columns) do
    layout
    |> Enum.with_index()
    |> Enum.reduce(cells, fn {row_keys, ri}, acc ->
      row_keys
      |> Enum.with_index()
      |> Enum.reduce(acc, fn
        {nil, _ci}, a ->
          a

        {key, ci}, a ->
          meta = template_cells[key] || %{}
          row_id = Enum.at(rows, ri, %{"id" => "r#{ri}"})["id"]
          column_id = Enum.at(columns, ci, %{"id" => "c#{ci}"})["id"]

          data =
            (meta["fields"] || ["content"])
            |> Map.new(fn field -> {field, Map.get(meta["defaults"] || %{}, field, "")} end)
            |> Map.merge(%{
              "row" => row_id,
              "column" => column_id,
              "label" => meta["label"] || key,
              "semantics" => meta["semantics"] || "free"
            })

          Map.put(a, key, data)
      end)
    end)
  end

  @doc """
  List all unstructured canvases authored by a user.
  """
  def list_user_unstr_canvases(user_id) do
    from(c in UnstrCanvas, where: c.author_id == ^user_id, order_by: [desc: c.updated_at])
    |> preload(:author)
    |> Repo.all()
  end

  @doc """
  List all unstructured canvases shared with a user by email.
  """
  def list_shared_unstr_canvases(user_email) do
    from(c in UnstrCanvas,
      where: fragment("? = ANY(?)", ^user_email, c.shared_with),
      order_by: [desc: c.updated_at]
    )
    |> preload(:author)
    |> Repo.all()
  end

  @doc """
  Get a single unstructured canvas by id.
  """
  def get_unstr_canvas(id) do
    Repo.get(UnstrCanvas, id)
  end

  @doc """
  Get an unstructured canvas with author preloaded.
  """
  def get_unstr_canvas_with_author(id) do
    UnstrCanvas
    |> preload(:author)
    |> Repo.get(id)
  end

  @doc """
  Create a new unstructured canvas with default PSC structure.
  """
  def create_unstr_canvas(user_id, attrs \\ %{}) do
    # Ensure params use string keys (avoid mixing atom and string keys)
    all_attrs =
      attrs
      |> Map.put("author_id", user_id)

    %UnstrCanvas{}
    |> UnstrCanvas.changeset(all_attrs)
    |> Repo.insert()
  end

  @doc """
  Update an unstructured canvas.
  """
  def update_unstr_canvas(canvas, attrs) do
    canvas
    |> UnstrCanvas.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Delete an unstructured canvas.
  """
  def delete_unstr_canvas(canvas) do
    Repo.delete(canvas)
  end

  @doc """
  Share an unstructured canvas with a user by email.
  """
  def share_unstr_canvas_with(canvas, email) do
    new_shared_with =
      (canvas.shared_with || [])
      |> Enum.uniq()
      |> then(&(&1 ++ [email]))
      |> Enum.uniq()

    canvas
    |> UnstrCanvas.changeset(%{shared_with: new_shared_with})
    |> Repo.update()
  end

  @doc """
  Remove a user's access to an unstructured canvas.
  """
  def unshare_unstr_canvas(canvas, email) do
    new_shared_with =
      canvas.shared_with
      |> Enum.reject(&(&1 == email))

    canvas
    |> UnstrCanvas.changeset(%{shared_with: new_shared_with})
    |> Repo.update()
  end

  @doc """
  Check if a user can access an unstructured canvas (author or shared with them).
  """
  def can_access_unstr_canvas?(canvas, user_email) do
    canvas = Repo.preload(canvas, :author)
    canvas.author.email == user_email || Enum.any?(canvas.shared_with, &(&1 == user_email))
  end

  # Get the next seq number for the given unstr_canvas.
  #
  # Floored at snapshot_seq: events at or below the snapshot are pruned
  # (see save_unstr_canvas_content_to_db/2), so max(seq) alone restarts at 1
  # after pruning and would place new events below the snapshot point,
  # where get_unstr_canvas_content/1 never replays them.
  defp next_unstr_canvas_sequence(canvas_id) do
    max_event_seq =
      Repo.one(
        from(e in Psc.Canvas.UnstrCanvasEvent,
          where: e.unstr_canvas_id == ^canvas_id,
          select: max(e.seq)
        )
      ) || 0

    snapshot_seq =
      Repo.one(from(c in UnstrCanvas, where: c.id == ^canvas_id, select: c.snapshot_seq)) || 0

    max(max_event_seq, snapshot_seq) + 1
  end

  def pubsub_topic_unstr(canvas_id), do: "unstr_canvas:#{canvas_id}"

  def get_unstr_canvas_content(canvas_id) do
    canvas = Repo.get!(UnstrCanvas, canvas_id)
    cells = canvas.cells || %{}
    snapshot_seq = canvas.snapshot_seq || 0

    events =
      from(e in Psc.Canvas.UnstrCanvasEvent,
        where: e.unstr_canvas_id == ^canvas_id and e.seq > ^snapshot_seq,
        order_by: [asc: e.seq]
      )
      |> Repo.all()

    Enum.reduce(events, cells, &Psc.Canvas.UnstrCanvasCRDT.apply_operation/2)
  end

  def apply_unstr_canvas_operation(canvas_id, user_id, operation) do
    seq = next_unstr_canvas_sequence(canvas_id)

    event_attrs = %{
      operation: operation,
      seq: seq,
      unstr_canvas_id: canvas_id,
      user_id: user_id
    }

    case Repo.insert(
           Psc.Canvas.UnstrCanvasEvent.changeset(%Psc.Canvas.UnstrCanvasEvent{}, event_attrs)
         ) do
      {:ok, _event} ->
        Phoenix.PubSub.broadcast(
          Psc.PubSub,
          pubsub_topic_unstr(canvas_id),
          {:operation, user_id, operation, seq}
        )

        {:ok, seq}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Apply operation and broadcast with a per-client id.
  """
  def apply_unstr_canvas_operation(canvas_id, user_id, client_id, operation) do
    seq = next_unstr_canvas_sequence(canvas_id)

    event_attrs = %{
      operation: operation,
      seq: seq,
      unstr_canvas_id: canvas_id,
      user_id: user_id
    }

    case Repo.insert(
           Psc.Canvas.UnstrCanvasEvent.changeset(%Psc.Canvas.UnstrCanvasEvent{}, event_attrs)
         ) do
      {:ok, _event} ->
        Phoenix.PubSub.broadcast(
          Psc.PubSub,
          pubsub_topic_unstr(canvas_id),
          {:operation, user_id, client_id, operation, seq}
        )

        {:ok, seq}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def save_unstr_canvas_content_to_db(canvas_id, cells) do
    canvas = get_unstr_canvas(canvas_id)

    # Floored at the stored snapshot_seq for the same reason as
    # next_unstr_canvas_sequence/1: events at or below it are already pruned,
    # so a save with no pending events sees max(seq) = nil and would otherwise
    # write 0 back over the marker.
    max_seq =
      max(
        Repo.one(
          from(e in Psc.Canvas.UnstrCanvasEvent,
            where: e.unstr_canvas_id == ^canvas_id,
            select: max(e.seq)
          )
        ) || 0,
        canvas.snapshot_seq || 0
      )

    result =
      canvas
      |> UnstrCanvas.changeset(%{cells: cells, snapshot_seq: max_seq})
      |> Repo.update()

    # Prune events already folded into the snapshot. The snapshot fully
    # captures state through max_seq and loading replays only seq >
    # snapshot_seq, so pruned rows are dead weight. This keeps the event
    # table small (free-tier Postgres is limited to 10k rows per table). Only
    # prune once the marker is durably stored, so a failed update can never
    # drop events that are not yet represented in the saved snapshot.
    with {:ok, _canvas} <- result do
      Repo.delete_all(
        from(e in Psc.Canvas.UnstrCanvasEvent,
          where: e.unstr_canvas_id == ^canvas_id and e.seq <= ^max_seq
        )
      )
    end

    result
  end

  @doc """
  Delete canvas events already folded into the saved `cells`.

  The counterpart to `Documents.sweep_folded_events/0` for canvases: pruning
  only happens on save, so canvases abandoned before their first save keep
  their event tail forever. Returns the number of deleted rows.
  """
  def sweep_folded_events do
    {deleted, _} =
      Repo.delete_all(
        from(e in Psc.Canvas.UnstrCanvasEvent,
          join: c in UnstrCanvas,
          on: c.id == e.unstr_canvas_id,
          where: e.seq <= c.snapshot_seq
        )
      )

    deleted
  end
end
