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
  When `:author_id` is given, creates it through the template API so
  ownership/sharing semantics apply.
  """
  def canvas_layout_fixture(attrs \\ %{}) do
    base = %{
      name: "Layout #{System.unique_integer([:positive])}",
      description: "A test layout",
      layout_map: template_layout_map_fixture()
    }

    attrs = Enum.into(attrs, base)

    {:ok, layout} =
      case Map.pop(attrs, :author_id) do
        {nil, attrs} -> Canvas.create_canvas_layout(attrs)
        {author_id, attrs} -> Canvas.create_template(author_id, stringify_keys(attrs))
      end

    layout
  end

  @doc """
  A minimal valid template layout_map: 2x2 grid, one "content" field per cell.
  """
  def template_layout_map_fixture do
    cell = fn label ->
      %{
        "label" => label,
        "semantics" => "free",
        "fields" => ["content"],
        "defaults" => %{"content" => ""}
      }
    end

    %{
      "rows" => [%{"id" => "r1", "label" => "Row 1"}, %{"id" => "r2", "label" => "Row 2"}],
      "columns" => [
        %{"id" => "c1", "label" => "Column 1"},
        %{"id" => "c2", "label" => "Column 2"}
      ],
      "layout" => [
        ["r1_c1", "r1_c2"],
        ["r2_c1", "r2_c2"]
      ],
      "cells" => %{
        "r1_c1" => cell.("Cell 1"),
        "r1_c2" => cell.("Cell 2"),
        "r2_c1" => cell.("Cell 3"),
        "r2_c2" => cell.("Cell 4")
      },
      "relations" => []
    }
  end

  defp stringify_keys(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {to_string(k), v}
      {k, v} -> {k, v}
    end)
  end
end
