defmodule Psc.CanvasFixtures do
  @moduledoc """
  Test helpers for creating canvases and canvas layouts via the `Psc.Canvas` context.
  """

  alias Psc.AccountsFixtures
  alias Psc.Canvas

  @doc """
  Creates a canvas authored by a new user (or the one given as `:user`).

  `create_canvas/2` initializes all twelve PSC cell embeds, so the returned
  struct always has every cell present.
  """
  def canvas_fixture(attrs \\ %{}) do
    {user, attrs} =
      case Map.pop(attrs, :user) do
        {nil, attrs} -> {AccountsFixtures.user_fixture(), attrs}
        {user, attrs} -> {user, attrs}
      end

    attrs =
      Enum.into(attrs, %{
        name: "Canvas #{System.unique_integer([:positive])}",
        description: "A test canvas"
      })

    {:ok, canvas} = Canvas.create_canvas(user.id, attrs)
    canvas
  end

  @doc """
  Creates a canvas layout (the template/configurator record).
  """
  def canvas_layout_fixture(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        name: "Layout #{System.unique_integer([:positive])}",
        description: "A test layout",
        layout_map: %{}
      })

    {:ok, layout} = Canvas.create_canvas_layout(attrs)
    layout
  end
end
