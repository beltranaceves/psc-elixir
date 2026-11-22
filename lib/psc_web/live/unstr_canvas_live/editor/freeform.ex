defmodule PscWeb.UnstrCanvasLive.Editor.Freeform do
  @moduledoc """
  Bento cards and image-board cells: adding, removing, moving and resizing
  them (by drag or by arrow keys), the board's grid size, card accents and
  the backdrop picture.
  """
  use PscWeb, :html
  import Phoenix.LiveView
  import PscWeb.UnstrCanvasLive.Editor.Operations, only: [process_operation: 2]

  alias Psc.Canvas.Structure
  alias PscWeb.Components.ImageBoard, as: ImageFrame
  alias PscWeb.UnstrCanvasLive.Editor.StructureEditing

  @doc "Registers the free-form board's hook."
  def attach(socket) do
    attach_hook(socket, __MODULE__, :handle_event, &handle_event/3)
  end

  ## Free-form cells (bento cards and image-board cells)

  def handle_event("add_card", _params, socket) do
    cells = socket.assigns.cells

    cond do
      Structure.image?(cells) ->
        key = next_cell_key(cells, "cell")
        count = length(Structure.cards(cells)) + 1

        {:halt,
         process_operation(socket, %{
           "type" => "add_card",
           "cell_key" => key,
           "label" => "Card #{count}"
         })}

      Structure.bento?(cells) ->
        key = next_cell_key(cells, "card")
        count = length(Structure.cards(cells)) + 1

        {:halt,
         process_operation(socket, %{
           "type" => "add_card",
           "cell_key" => key,
           "label" => "Card #{count}"
         })}

      true ->
        {:halt, socket}
    end
  end

  # A bare text label on an image board. It is an ordinary cell from the start:
  # one `add_card` carries the kind, so adding it is a single event.
  def handle_event("add_text", _params, socket) do
    if Structure.image?(socket.assigns.cells) do
      key = next_cell_key(socket.assigns.cells, "text")
      count = length(Structure.cards(socket.assigns.cells)) + 1

      {:halt,
       process_operation(socket, %{
         "type" => "add_card",
         "cell_key" => key,
         "label" => "Text #{count}",
         "kind" => "text"
       })}
    else
      {:halt, socket}
    end
  end

  # The backdrop is part of the canvas, so changing it is an operation like any
  # other and every open client sees the new picture.
  def handle_event("set_backdrop", params, socket) when is_map(params) do
    if Structure.image?(socket.assigns.cells) do
      {:halt,
       process_operation(socket, %{
         "type" => "set_backdrop",
         "backdrop" => ImageFrame.backdrop_attrs(params)
       })}
    else
      {:halt, socket}
    end
  end

  def handle_event("set_cell_kind", %{"cell_key" => key, "kind" => kind}, socket) do
    {:halt,
     process_operation(socket, %{"type" => "set_cell_kind", "cell_key" => key, "kind" => kind})}
  end

  def handle_event("request_remove_card", %{"cell_key" => key}, socket) do
    case Map.get(Structure.cells(socket.assigns.cells), key) do
      nil ->
        {:halt, socket}

      cell ->
        if StructureEditing.cell_has_content?(cell) do
          {:halt,
           assign(socket, :structure_remove_confirm, %{
             "type" => if(Structure.image?(socket.assigns.cells), do: "cell", else: "card"),
             "cell_key" => key,
             "label" => cell["label"] || key
           })}
        else
          {:halt, process_operation(socket, %{"type" => "remove_card", "cell_key" => key})}
        end
    end
  end

  # The board's own grid. A value outside the allowed range is ignored rather
  # than clamped, so typing "1" on the way to "12" does not resize the board.
  def handle_event("set_bento_columns", %{"value" => value}, socket) do
    case parse_size(value) do
      count when is_integer(count) ->
        if count in Structure.column_range() do
          {:halt, process_operation(socket, %{"type" => "set_bento_columns", "columns" => count})}
        else
          {:halt, socket}
        end

      _other ->
        {:halt, socket}
    end
  end

  def handle_event("set_bento_rows", %{"value" => value}, socket) do
    case parse_size(value) do
      count when is_integer(count) ->
        if count in Structure.row_range() do
          {:halt, process_operation(socket, %{"type" => "set_bento_rows", "rows" => count})}
        else
          {:halt, socket}
        end

      _other ->
        {:halt, socket}
    end
  end

  def handle_event("set_card_accent", %{"cell_key" => key, "accent" => accent}, socket) do
    {:halt,
     process_operation(socket, %{
       "type" => "set_card_accent",
       "cell_key" => key,
       "accent" => StructureEditing.normalize_token(accent)
     })}
  end

  # One operation per completed gesture: the drag hook pushes the final cell,
  # and the arrow keys push one step at a time.
  def handle_event("move_card", %{"cell_key" => key} = params, socket) do
    with x when is_number(x) <- to_number(params["x"]),
         y when is_number(y) <- to_number(params["y"]) do
      {:halt,
       process_operation(socket, %{"type" => "move_card", "cell_key" => key, "x" => x, "y" => y})}
    else
      _other -> {:halt, socket}
    end
  end

  def handle_event("resize_card", %{"cell_key" => key} = params, socket) do
    with w when is_number(w) <- to_number(params["w"]),
         h when is_number(h) <- to_number(params["h"]) do
      {:halt,
       process_operation(socket, %{
         "type" => "resize_card",
         "cell_key" => key,
         "w" => w,
         "h" => h
       })}
    else
      _other -> {:halt, socket}
    end
  end

  # Arrow keys on the card's drag grip move it by one unit; holding shift
  # resizes it. The grip is a button, so the handler never competes with an
  # arrow key pressed inside a Markdown editor.
  def handle_event("nudge_card", %{"key" => key, "cell_key" => cell_key} = params, socket) do
    resize? = params["shiftKey"] == true

    case nudge_delta(key) do
      nil -> {:halt, socket}
      {dx, dy} -> {:halt, nudge_card(socket, cell_key, dx, dy, resize?)}
    end
  end

  def handle_event(_event, _params, socket), do: {:cont, socket}

  # The next free "<prefix>N" key, scanning the keys that are already there so
  # a removal never makes the next cell collide with a survivor.
  defp next_cell_key(cells, prefix) do
    taken =
      for key <- Structure.cell_keys(cells),
          parts = Regex.run(~r/^#{prefix}(\d+)$/, key),
          n <- tl(parts) do
        String.to_integer(n)
      end

    "#{prefix}#{Enum.max([0 | taken]) + 1}"
  end

  defp nudge_delta("ArrowLeft"), do: {-1, 0}
  defp nudge_delta("ArrowRight"), do: {1, 0}
  defp nudge_delta("ArrowUp"), do: {0, -1}
  defp nudge_delta("ArrowDown"), do: {0, 1}
  defp nudge_delta(_key), do: nil

  defp nudge_card(socket, key, dx, dy, resize?) do
    case Structure.card(socket.assigns.cells, key) do
      nil ->
        socket

      card ->
        # Position and size share one step: half a grid unit on a bento, half a
        # percent of the picture on an image board.
        step =
          if Structure.image?(socket.assigns.cells),
            do: Structure.image_step(),
            else: Structure.min_size()

        operation =
          if resize? do
            %{
              "type" => "resize_card",
              "cell_key" => key,
              "w" => card.w + dx * step,
              "h" => card.h + dy * step
            }
          else
            %{
              "type" => "move_card",
              "cell_key" => key,
              "x" => card.x + dx * step,
              "y" => card.y + dy * step
            }
          end

        process_operation(socket, operation)
    end
  end

  defp parse_size(value) do
    case Integer.parse(to_string(value)) do
      {int, ""} -> int
      _other -> nil
    end
  end

  # A coordinate keeps its half: 6.5 columns must not become 6.
  defp to_number(value) when is_integer(value) or is_float(value), do: value

  defp to_number(value) when is_binary(value) do
    case Float.parse(value) do
      {number, _rest} -> number
      :error -> nil
    end
  end

  defp to_number(_other), do: nil
end
