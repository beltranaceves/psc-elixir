defmodule Psc.NotesFixtures do
  @moduledoc """
  Test helpers for creating notes via the `Psc.Notes` context.
  """

  alias Psc.AccountsFixtures
  alias Psc.Canvas
  alias Psc.Notes
  alias Psc.Repo

  @doc """
  Returns a map of valid note attributes, with a unique title.
  """
  def valid_note_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      title: "Note #{System.unique_integer([:positive])}"
    })
  end

  @doc """
  Creates a note on a canvas owned by a new user (or the one given as `:user`).

  Returns the note struct.
  """
  def note_fixture(attrs \\ %{}) do
    {user, attrs} =
      case Map.pop(attrs, :user) do
        {nil, attrs} -> {AccountsFixtures.user_fixture(), attrs}
        {user, attrs} -> {user, attrs}
      end

    {canvas, attrs} =
      case Map.pop(attrs, :canvas) do
        {nil, attrs} ->
          {canvas_fixture(%{user: user}), attrs}

        {canvas, attrs} ->
          {canvas, attrs}
      end

    {:ok, note} =
      Notes.create_note(canvas.id, user.id, valid_note_attributes(attrs))

    note
  end

  @doc """
  Creates a canvas owned by a new user, or the one given as `:user`.
  """
  def canvas_fixture(attrs \\ %{}) do
    {user, attrs} =
      case Map.pop(attrs, :user) do
        {nil, attrs} -> {AccountsFixtures.user_fixture(), attrs}
        {user, attrs} -> {user, attrs}
      end

    attrs = Enum.into(attrs, %{"name" => "Canvas #{System.unique_integer([:positive])}"})

    {:ok, canvas} = Canvas.create_unstr_canvas(user.id, attrs)
    canvas
  end

  @doc """
  Creates a note with its `:created_by` association preloaded.
  """
  def note_with_author_fixture(attrs \\ %{}) do
    attrs
    |> note_fixture()
    |> Repo.preload(:created_by)
  end
end
