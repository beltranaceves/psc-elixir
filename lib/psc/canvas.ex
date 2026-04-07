defmodule Psc.Canvas do
  @moduledoc """
  The Canvas context for managing strategic planning canvases.
  Supports collaborative editing with cell-level operations.
  """

  import Ecto.Query, warn: false
  alias Psc.Repo
  alias Psc.Canvas.Canvas

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
    Canvas
    |> preload(:author)
    |> Repo.get(id)
  end

  @doc """
  Create a new canvas.
  """
  def create_canvas(user_id, attrs \\ %{}) do
    Canvas.changeset(%Canvas{}, Map.merge(attrs, %{author_id: user_id}))
    |> Repo.insert()
  end

  @doc """
  Update a canvas.
  """
  def update_canvas(canvas, attrs) do
    canvas
    |> Canvas.changeset(attrs)
    |> Repo.update()
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
end
