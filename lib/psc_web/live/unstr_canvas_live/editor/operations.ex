defmodule PscWeb.UnstrCanvasLive.Editor.Operations do
  @moduledoc """
  The canvas editor's write path, shared by every feature: an operation is
  applied to the in-memory cells, recorded in the event log and scheduled for
  the idle save. Features call `process_operation/2` instead of touching the
  cells themselves.
  """
  use PscWeb, :html
  import Phoenix.LiveView

  alias Psc.Canvas
  alias Psc.Canvas.Structure
  alias PscWeb.UnstrCanvasLive.Editor.{Analysis, History}
  require Logger

  @idle_save_interval 1500

  # What the status pill reports: how many writes this session made, how many
  # of them failed, when the last one landed and how long it took.
  @initial_save_stats %{
    writes: 0,
    failures: 0,
    last_saved_at: nil,
    last_write_ms: nil
  }

  @doc "How long the editor waits after an edit before saving."
  def idle_save_interval, do: @idle_save_interval

  @doc "The save statistics a canvas or note starts with."
  def initial_save_stats, do: @initial_save_stats

  def process_operation(socket, operation) do
    cells = Psc.Canvas.UnstrCanvasCRDT.apply_operation(operation, socket.assigns.cells)

    # A blur can send the value that was already there (the cell hook does this
    # for every field), and structure edits are idempotent. Recording those
    # would create an event row and flip the pill to Unsaved for no change.
    if cells == socket.assigns.cells do
      socket
    else
      socket = socket |> record_operation(operation) |> History.maybe_start_draft(operation)

      Logger.debug(fn ->
        "[UnstrCanvasLive] applied operation: canvas_id=#{socket.assigns.canvas_id} user_id=#{socket.assigns.user_id} op=#{inspect(operation)} resulting_cells_sample=#{inspect(Map.take(cells, ["cells", "layout", "columns", "rows"]))}"
      end)

      c_name = Map.get(cells, "$name", socket.assigns.c_name)
      c_desc = Map.get(cells, "$description", socket.assigns.c_desc)

      socket =
        if socket.assigns.idle_timer_ref do
          Process.cancel_timer(socket.assigns.idle_timer_ref)
          assign(socket, idle_timer_ref: nil)
        else
          socket
        end

      idle_timer_ref = Process.send_after(self(), :idle_save, @idle_save_interval)

      socket
      |> assign(:cells, cells)
      |> assign(:c_name, c_name)
      |> assign(:c_desc, c_desc)
      |> assign(:idle_timer_ref, idle_timer_ref)
      |> assign(:save_state, :unsaved)
      |> Analysis.track_insight_change(operation)
    end
  end

  defp record_operation(socket, operation) do
    case Canvas.apply_unstr_canvas_operation(
           socket.assigns.canvas_id,
           socket.assigns.user_id,
           socket.assigns.client_id,
           operation
         ) do
      {:ok, _seq} ->
        socket

      {:error, _changeset} ->
        Logger.error(
          "[UnstrCanvasLive] operation was not recorded: canvas_id=#{socket.assigns.canvas_id} op=#{inspect(operation["type"])}"
        )

        put_flash(
          socket,
          :error,
          "Could not record the change. It will be saved with the next snapshot."
        )
    end
  end

  # The cell fields are owned by the client hooks (`phx-update="ignore"`), so a
  # re-render does not change them; only what is pushed does. A restore
  # replaces every value at once, so each field is pushed, with `-1` marking a
  # resync rather than somebody's edit (see `Editor.Notes` for the note).
  def push_cells_resync(socket) do
    cells = socket.assigns.cells

    for key <- Structure.cell_keys(cells),
        cell = Structure.cell(cells, key),
        field <- Structure.field_names(cell),
        reduce: socket do
      socket ->
        push_event(socket, "cell_updated", %{
          cell_key: key,
          field: field,
          new_value: cell[field] || "",
          from_user_id: -1
        })
    end
  end
end
