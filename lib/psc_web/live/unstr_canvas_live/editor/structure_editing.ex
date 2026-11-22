defmodule PscWeb.UnstrCanvasLive.Editor.StructureEditing do
  @moduledoc """
  Editing a canvas's structure in place: rows and columns, cell labels and
  fields, hints, accents and colours, and the confirmation before removing
  something that holds content. Renders that confirmation dialog.
  """
  use PscWeb, :html
  import Phoenix.LiveView
  import PscWeb.UnstrCanvasLive.Editor.Operations, only: [process_operation: 2]

  alias PscWeb.Components.UI.Button, as: UIButton
  alias PscWeb.Components.UI.Dialog, as: UIDialog

  @doc "Adds the structure editor's assigns and registers the hook."
  def attach(socket) do
    socket
    |> assign(:edit_structure?, false)
    |> assign(:structure_accent_picker, nil)
    |> assign(:structure_colors_picker, nil)
    |> assign(:hint_editor, nil)
    |> assign(:structure_remove_confirm, nil)
    |> attach_hook(__MODULE__, :handle_event, &handle_event/3)
  end

  ## Structure editing

  # Every structure event is available to anyone the canvas is shared with: a
  # canvas's access rule is the only gate. The operation is broadcast like any
  # other edit, so every open client applies it and the grid stays in step.

  def handle_event("toggle_structure", _params, socket) do
    {:halt,
     socket
     |> assign(:edit_structure?, not socket.assigns.edit_structure?)
     |> assign(:structure_accent_picker, nil)
     |> assign(:structure_colors_picker, nil)
     |> assign(:hint_editor, nil)
     |> assign(:structure_remove_confirm, nil)}
  end

  def handle_event("add_row", _params, socket) do
    {id, index} = next_structure_id("r", Map.get(socket.assigns.cells, "rows", []))

    {:halt,
     process_operation(socket, %{"type" => "add_row", "id" => id, "label" => "Row #{index}"})}
  end

  def handle_event("add_column", _params, socket) do
    {id, index} = next_structure_id("c", Map.get(socket.assigns.cells, "columns", []))

    {:halt,
     process_operation(
       socket,
       %{"type" => "add_column", "id" => id, "label" => "Column #{index}"}
     )}
  end

  def handle_event("update_row_label", %{"structure_id" => id, "label" => label}, socket) do
    {:halt,
     process_operation(socket, %{"type" => "update_row_label", "id" => id, "label" => label})}
  end

  def handle_event("update_column_label", %{"structure_id" => id, "label" => label}, socket) do
    {:halt,
     process_operation(socket, %{"type" => "update_column_label", "id" => id, "label" => label})}
  end

  def handle_event("set_row_accent", %{"id" => id, "accent" => accent}, socket) do
    {:halt,
     socket
     |> assign(:structure_accent_picker, nil)
     |> process_operation(%{
       "type" => "set_row_accent",
       "id" => id,
       "accent" => normalize_token(accent)
     })}
  end

  def handle_event("set_column_accent", %{"id" => id, "accent" => accent}, socket) do
    {:halt,
     socket
     |> assign(:structure_accent_picker, nil)
     |> process_operation(%{
       "type" => "set_column_accent",
       "id" => id,
       "accent" => normalize_token(accent)
     })}
  end

  def handle_event("toggle_structure_accent", %{"group" => group, "id" => id}, socket) do
    key =
      case group do
        "row" -> {:row, id}
        "card" -> {:card, id}
        _other -> {:column, id}
      end

    picker = if socket.assigns.structure_accent_picker == key, do: nil, else: key

    {:halt,
     assign(socket,
       structure_accent_picker: picker,
       structure_colors_picker: nil
     )}
  end

  def handle_event("toggle_cell_colors", %{"cell_key" => key}, socket) do
    picker = if socket.assigns.structure_colors_picker == key, do: nil, else: key

    {:halt,
     assign(socket,
       structure_colors_picker: picker,
       structure_accent_picker: nil
     )}
  end

  # An image board's text label has no room for an inline hint field, so its
  # tooltip text is edited in a small panel under the label.
  def handle_event("toggle_hint_editor", %{"cell_key" => key}, socket) do
    editor = if socket.assigns.hint_editor == key, do: nil, else: key
    {:halt, assign(socket, hint_editor: editor, structure_colors_picker: nil)}
  end

  # Hints are the tooltips of cells, rows and columns. Like a label, each one
  # is a whole value and the last write wins.
  def handle_event("update_cell_hint", %{"cell_key" => key, "hint" => hint}, socket) do
    {:halt,
     process_operation(socket, %{"type" => "update_cell_hint", "cell_key" => key, "hint" => hint})}
  end

  def handle_event("update_row_hint", %{"structure_id" => id, "hint" => hint}, socket) do
    {:halt, process_operation(socket, %{"type" => "update_row_hint", "id" => id, "hint" => hint})}
  end

  def handle_event("update_column_hint", %{"structure_id" => id, "hint" => hint}, socket) do
    {:halt,
     process_operation(socket, %{"type" => "update_column_hint", "id" => id, "hint" => hint})}
  end

  # A click outside the pickers closes them (the client hook reports it), so
  # the panel can be dismissed without finding its trigger again.
  def handle_event("dismiss_color_pickers", _params, socket) do
    {:halt,
     assign(socket,
       structure_colors_picker: nil,
       structure_accent_picker: nil,
       hint_editor: nil
     )}
  end

  # Choosing either colour keeps the panel open: the outline and the
  # background are usually set together.
  def handle_event("set_cell_background", %{"cell_key" => key} = params, socket) do
    {:halt,
     process_operation(socket, %{
       "type" => "set_cell_background",
       "cell_key" => key,
       "background" => normalize_token(params["background"])
     })}
  end

  def handle_event("request_remove_row", %{"id" => id}, socket) do
    request_structure_remove(socket, "row", id)
  end

  def handle_event("request_remove_column", %{"id" => id}, socket) do
    request_structure_remove(socket, "column", id)
  end

  def handle_event("confirm_remove_structure", _params, socket) do
    {socket, operation} =
      case socket.assigns.structure_remove_confirm do
        %{"type" => "row", "id" => id} ->
          {socket, %{"type" => "remove_row", "id" => id}}

        %{"type" => "column", "id" => id} ->
          {socket, %{"type" => "remove_column", "id" => id}}

        %{"type" => "card", "cell_key" => key} ->
          {socket, %{"type" => "remove_card", "cell_key" => key}}

        _other ->
          {socket, nil}
      end

    socket = assign(socket, :structure_remove_confirm, nil)

    if operation do
      {:halt, process_operation(socket, operation)}
    else
      {:halt, socket}
    end
  end

  def handle_event("dismiss_remove_structure", _params, socket) do
    {:halt, assign(socket, :structure_remove_confirm, nil)}
  end

  def handle_event("update_cell_label", %{"cell_key" => cell_key, "label" => label}, socket) do
    {:halt,
     process_operation(socket, %{
       "type" => "update_cell_label",
       "cell_key" => cell_key,
       "label" => label
     })}
  end

  def handle_event("add_cell_field", %{"cell_key" => cell_key, "field" => field}, socket) do
    field = String.trim(field)

    if field != "" and field not in Psc.Canvas.UnstrCanvasCRDT.reserved_cell_keys() do
      {:halt,
       process_operation(socket, %{
         "type" => "add_cell_field",
         "cell_key" => cell_key,
         "field" => field
       })}
    else
      {:halt, socket}
    end
  end

  def handle_event("remove_cell_field", %{"cell_key" => cell_key, "field" => field}, socket) do
    {:halt,
     process_operation(socket, %{
       "type" => "remove_cell_field",
       "cell_key" => cell_key,
       "field" => field
     })}
  end

  def handle_event(
        "update_cell_field_title",
        %{"cell_key" => cell_key, "field" => field, "title" => title},
        socket
      ) do
    {:halt,
     process_operation(socket, %{
       "type" => "update_cell_field_title",
       "cell_key" => cell_key,
       "field" => field,
       "title" => title
     })}
  end

  def handle_event(_event, _params, socket), do: {:cont, socket}

  # The next free "rN"/"cN" index, scanning the ids that are already there.
  # `length + 1` collides after a removal (add r1, r2; remove r1; the next
  # "r2" would duplicate the survivor).
  defp next_structure_id(prefix, defs) do
    taken =
      for %{"id" => id} <- defs,
          parts = Regex.run(~r/^#{prefix}(\d+)$/, id),
          n <- tl(parts) do
        String.to_integer(n)
      end

    index = Enum.max([0 | taken]) + 1
    {"#{prefix}#{index}", index}
  end

  # Removing a row or column that holds content asks first: the operation is
  # destructive, and the event log keeps the old values only until pruning
  # folds them. An empty one goes straight away.
  defp request_structure_remove(socket, type, id) do
    ref_key = if type == "row", do: "row", else: "column"
    list_key = if type == "row", do: "rows", else: "columns"

    if structure_has_content?(socket.assigns.cells, ref_key, id) do
      label =
        socket.assigns.cells
        |> Map.get(list_key, [])
        |> Enum.find(%{}, &(&1["id"] == id))
        |> Map.get("label", "")

      {:halt,
       assign(socket, :structure_remove_confirm, %{"type" => type, "id" => id, "label" => label})}
    else
      operation =
        if type == "row" do
          %{"type" => "remove_row", "id" => id}
        else
          %{"type" => "remove_column", "id" => id}
        end

      {:halt, process_operation(socket, operation)}
    end
  end

  defp structure_has_content?(cells, ref_key, ref_id) do
    Enum.any?(cells, fn
      {_key, data} when is_map(data) ->
        Map.get(data, ref_key) == ref_id and cell_has_content?(data)

      _pair ->
        false
    end)
  end

  def cell_has_content?(cell) do
    reserved = Psc.Canvas.UnstrCanvasCRDT.reserved_cell_keys()

    Enum.any?(cell, fn
      {field, value} ->
        field not in reserved and is_binary(value) and String.trim(value) != ""

      _pair ->
        false
    end)
  end

  def normalize_token(""), do: nil
  def normalize_token(token), do: token

  defp structure_remove_confirm(confirm, :type), do: confirm["type"]
  defp structure_remove_confirm(confirm, :label), do: confirm["label"] || ""

  # Removing a row, column or card that holds content asks first: the
  # operation is destructive, and the event log keeps the old values only
  # until pruning folds them.
  attr :confirm, :map, default: nil

  def remove_dialog(assigns) do
    ~H"""
    <UIDialog.dialog
      :if={@confirm}
      id="remove-structure-dialog"
      open
      on-close="dismiss_remove_structure"
    >
      <UIDialog.dialog_content open class="sm:max-w-md">
        <UIDialog.dialog_header>
          <UIDialog.dialog_title>
            Remove this {structure_remove_confirm(@confirm, :type)}?
          </UIDialog.dialog_title>

          <UIDialog.dialog_description>
            "{structure_remove_confirm(@confirm, :label)}" and everything
            written in it will be removed. This cannot be undone.
          </UIDialog.dialog_description>
        </UIDialog.dialog_header>

        <UIDialog.dialog_footer class="flex flex-row justify-end gap-2">
          <UIButton.button type="button" variant="outline" phx-click="dismiss_remove_structure">
            Keep it
          </UIButton.button>

          <UIButton.button
            type="button"
            variant="destructive"
            id="confirm-remove-structure"
            phx-click="confirm_remove_structure"
          >
            Remove
          </UIButton.button>
        </UIDialog.dialog_footer>
      </UIDialog.dialog_content>
    </UIDialog.dialog>
    """
  end
end
