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
  alias Psc.Canvas.Problem
  alias Psc.Canvas.Leverage
  alias Psc.Canvas.SolutionCluster
  alias Psc.Canvas.Horizon
  alias Psc.Canvas.OuterEnvironment
  alias Psc.Canvas.InnerEnvironment
  alias Psc.Canvas.EvolvabilityCluster
  alias Psc.Canvas.Potential
  alias Psc.Canvas.Manifestations
  alias Psc.Canvas.Capabilities
  alias Psc.Canvas.MeritCluster
  alias Psc.Canvas.Mission
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
      Logger.info("[DB LOAD] Canvas #{id} loaded from database")
      Logger.info("[DB LOAD - PROBLEM] #{inspect(result.problem, label: "problem")}")
      Logger.info("[DB LOAD - LEVERAGE] #{inspect(result.leverage, label: "leverage")}")
      Logger.info("[DB LOAD - SOLUTION] #{inspect(result.solution_cluster, label: "solution_cluster")}")
      Logger.info("[DB LOAD - HORIZON] #{inspect(result.horizon, label: "horizon")}")
      Logger.info("[DB LOAD - OUTER_ENV] #{inspect(result.outer_environment, label: "outer_environment")}")
      Logger.info("[DB LOAD - INNER_ENV] #{inspect(result.inner_environment, label: "inner_environment")}")
      Logger.info("[DB LOAD - EVOLVABILITY] #{inspect(result.evolvability_cluster, label: "evolvability_cluster")}")
      Logger.info("[DB LOAD - POTENTIAL] #{inspect(result.potential, label: "potential")}")
      Logger.info("[DB LOAD - MANIFESTATIONS] #{inspect(result.manifestations, label: "manifestations")}")
      Logger.info("[DB LOAD - CAPABILITIES] #{inspect(result.capabilities, label: "capabilities")}")
      Logger.info("[DB LOAD - MERIT] #{inspect(result.merit_cluster, label: "merit_cluster")}")
      Logger.info("[DB LOAD - MISSION] #{inspect(result.mission, label: "mission")}")
    else
      Logger.warn("[DB LOAD] Canvas #{id} NOT FOUND in database")
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

    Logger.info("[DB SAVE - CREATE] Canvas attrs being saved: #{inspect(all_attrs, limit: :infinity)}")

    result =
      %Canvas{}
      |> Canvas.changeset(all_attrs)
      |> Repo.insert()

    case result do
      {:ok, canvas} ->
        Logger.info("[DB SAVE - CREATE SUCCESS] Canvas created: #{inspect(canvas, label: "created_canvas", limit: :infinity)}")
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
    Logger.info("[DB SAVE - UPDATE] Canvas ID: #{canvas.id}, cells being saved: #{inspect(Map.keys(attrs))}, full attrs: #{inspect(attrs, limit: :infinity)}")

    result =
      canvas
      |> Canvas.changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, updated_canvas} ->
        Logger.info("[DB SAVE - UPDATE SUCCESS] Canvas updated: #{inspect(updated_canvas, label: "updated_canvas", limit: :infinity)}")
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

  @doc """
  Get the next seq number for the given unstr_canvas
  """
  defp next_unstr_canvas_sequence(canvas_id) do
    case Repo.one(
           from(e in Psc.Canvas.UnstrCanvasEvent,
             where: e.unstr_canvas_id == ^canvas_id,
             select: max(e.seq)
           )
         ) do
      nil -> 1
      max_seq -> max_seq + 1
    end
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

    case Repo.insert(Psc.Canvas.UnstrCanvasEvent.changeset(%Psc.Canvas.UnstrCanvasEvent{}, event_attrs)) do
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

    case Repo.insert(Psc.Canvas.UnstrCanvasEvent.changeset(%Psc.Canvas.UnstrCanvasEvent{}, event_attrs)) do
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
    max_seq =
      Repo.one(
        from(e in Psc.Canvas.UnstrCanvasEvent,
          where: e.unstr_canvas_id == ^canvas_id,
          select: max(e.seq)
        )
      ) || 0

    canvas_id
    |> get_unstr_canvas()
    |> UnstrCanvas.changeset(%{cells: cells, snapshot_seq: max_seq})
    |> Repo.update()
  end
end
