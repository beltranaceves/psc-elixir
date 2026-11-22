defmodule PscWeb.UnstrCanvasLive.Editor.Fulcrums do
  @moduledoc """
  Fulcrums on a canvas (ADR-044): picking which ones to highlight, the
  canvas's fulcrum mode, and editing the definitions from the Info tab. Also
  renders the two fulcrum dialogs.
  """
  use PscWeb, :html
  import Phoenix.LiveView
  import PscWeb.UnstrCanvasLive.Editor.Operations, only: [process_operation: 2]

  alias Psc.Canvas.Fulcrums
  alias PscWeb.Components.FulcrumEditor
  alias PscWeb.Components.UI.Button, as: UIButton
  alias PscWeb.Components.UI.Dialog, as: UIDialog

  @doc "Adds the fulcrum dialogs' assigns and registers the hook."
  def attach(socket) do
    socket
    |> assign(:fulcrums_open, false)
    |> assign(:fulcrum_draft, nil)
    |> attach_hook(__MODULE__, :handle_event, &handle_event/3)
  end

  # ─── Fulcrums ───
  #
  # Highlighting is a shared view choice (`set_active_fulcrums`, never a new
  # version). The canvas only picks from the fulcrums its template defined;
  # defining them is the template designer's job, so nothing here edits them.

  # With fulcrums off (a template setting) the canvas neither highlights nor
  # opens the picker; the controls are hidden and these events are ignored.
  def handle_event("toggle_fulcrum", %{"id" => id}, socket) do
    if Fulcrums.enabled?(socket.assigns.cells) do
      ids = Fulcrums.toggle_active(socket.assigns.cells, id)
      {:halt, process_operation(socket, %{"type" => "set_active_fulcrums", "ids" => ids})}
    else
      {:halt, socket}
    end
  end

  def handle_event("open_fulcrums", _params, socket) do
    if Fulcrums.enabled?(socket.assigns.cells),
      do: {:halt, assign(socket, :fulcrums_open, true)},
      else: {:halt, socket}
  end

  # The canvas's own setting (Info tab): off, one at a time or several. It
  # starts as the template's; changing it is not a versioned edit.
  def handle_event("set_fulcrum_mode", %{"mode" => mode}, socket) do
    if mode in Fulcrums.modes(),
      do: {:halt, process_operation(socket, %{"type" => "set_fulcrum_mode", "mode" => mode})},
      else: {:halt, socket}
  end

  def handle_event("close_fulcrums", _params, socket) do
    {:halt, assign(socket, :fulcrums_open, false)}
  end

  # The Info tab edits the definitions. The edit works on a draft and is saved
  # as one `set_fulcrums` operation, which starts a version like any edit.
  def handle_event("edit_fulcrums", _params, socket) do
    if Fulcrums.enabled?(socket.assigns.cells),
      do: {:halt, assign(socket, :fulcrum_draft, Fulcrums.list(socket.assigns.cells))},
      else: {:halt, socket}
  end

  def handle_event("cancel_edit_fulcrums", _params, socket) do
    {:halt, assign(socket, :fulcrum_draft, nil)}
  end

  def handle_event("save_fulcrums", _params, socket) do
    op = %{"type" => "set_fulcrums", "fulcrums" => socket.assigns.fulcrum_draft || []}
    {:halt, socket |> assign(:fulcrum_draft, nil) |> process_operation(op)}
  end

  def handle_event("fulcrum_add", _params, socket),
    do: {:halt, update_fulcrum_draft(socket, &Fulcrums.add/1)}

  def handle_event("fulcrum_remove", %{"id" => id}, socket),
    do: {:halt, update_fulcrum_draft(socket, &Fulcrums.remove(&1, id))}

  def handle_event("fulcrum_rename", %{"fulcrum_id" => id, "name" => name}, socket),
    do: {:halt, update_fulcrum_draft(socket, &Fulcrums.rename(&1, id, name))}

  def handle_event("fulcrum_color", %{"id" => id, "color" => color}, socket),
    do: {:halt, update_fulcrum_draft(socket, &Fulcrums.set_color(&1, id, color))}

  def handle_event("fulcrum_toggle_cell", %{"id" => id, "key" => key}, socket),
    do: {:halt, update_fulcrum_draft(socket, &Fulcrums.toggle_cell(&1, id, key))}

  def handle_event(_event, _params, socket), do: {:cont, socket}

  defp update_fulcrum_draft(%{assigns: %{fulcrum_draft: nil}} = socket, _fun), do: socket

  defp update_fulcrum_draft(socket, fun),
    do: assign(socket, :fulcrum_draft, fun.(socket.assigns.fulcrum_draft))

  # Editing the canvas's fulcrums, from the Info tab: names, colours and cells.
  # Works on a draft; Save applies it as one versioned operation.
  attr :draft, :any, required: true
  attr :cells, :map, required: true

  def fulcrums_edit_dialog(assigns) do
    ~H"""
    <UIDialog.dialog :if={@draft} id="fulcrums-edit-dialog" open on-close="cancel_edit_fulcrums">
      <UIDialog.dialog_content open class="max-h-[85vh] overflow-y-auto sm:max-w-lg">
        <UIDialog.dialog_header>
          <UIDialog.dialog_title>Edit fulcrums</UIDialog.dialog_title>
          <UIDialog.dialog_description>
            Named sets of cells that can be highlighted together. {Fulcrums.blurb(
              Fulcrums.mode(@cells)
            )}
          </UIDialog.dialog_description>
        </UIDialog.dialog_header>

        <FulcrumEditor.editor id="canvas-fulcrums" fulcrums={@draft} cells={@cells} />

        <UIDialog.dialog_footer class="flex flex-row justify-end gap-2 pt-2">
          <UIButton.button type="button" variant="outline" phx-click="cancel_edit_fulcrums">
            Cancel
          </UIButton.button>
          <UIButton.button type="button" id="fulcrums-save" phx-click="save_fulcrums">
            Save fulcrums
          </UIButton.button>
        </UIDialog.dialog_footer>
      </UIDialog.dialog_content>
    </UIDialog.dialog>
    """
  end

  # Picking the fulcrums to highlight. Choosing one is the same toggle as the
  # picker chips, so it applies at once and needs no save. Defining them is
  # the template designer's job.
  attr :open, :boolean, required: true
  attr :cells, :map, required: true

  def fulcrums_dialog(assigns) do
    ~H"""
    <UIDialog.dialog :if={@open} id="fulcrums-dialog" open on-close="close_fulcrums">
      <UIDialog.dialog_content open class="max-h-[85vh] overflow-y-auto sm:max-w-md">
        <UIDialog.dialog_header>
          <UIDialog.dialog_title>Fulcrums</UIDialog.dialog_title>
          <UIDialog.dialog_description>
            Pick a fulcrum to highlight its cells for everyone on this canvas. {Fulcrums.blurb(
              Fulcrums.mode(@cells)
            )}
          </UIDialog.dialog_description>
        </UIDialog.dialog_header>

        <FulcrumEditor.selector
          fulcrums={Fulcrums.list(@cells)}
          active_ids={Fulcrums.active_ids(@cells)}
        />

        <UIDialog.dialog_footer class="flex flex-row justify-end gap-2 pt-2">
          <UIButton.button type="button" id="fulcrums-done" phx-click="close_fulcrums">
            Done
          </UIButton.button>
        </UIDialog.dialog_footer>
      </UIDialog.dialog_content>
    </UIDialog.dialog>
    """
  end
end
