defmodule PscWeb.UnstrCanvasLive.Save do
  @moduledoc false

  # The save outcome used to be discarded by the caller, which then assigned
  # `:saved` and advanced the dirty fingerprint unconditionally. A failed write
  # therefore looked saved and was not retried. This module owns both: only a
  # successful write clears the dirty state and advances the fingerprint.

  import Phoenix.Component, only: [assign: 3]

  @spec commit(Phoenix.LiveView.Socket.t(), :canvas | :note, (-> {:ok, term()} | {:error, term()})) ::
          Phoenix.LiveView.Socket.t()
  def commit(socket, surface, save) when surface in [:canvas, :note] do
    started = System.monotonic_time(:millisecond)
    result = save.()
    elapsed = System.monotonic_time(:millisecond) - started

    case result do
      {:ok, _value} -> succeeded(socket, surface, elapsed)
      {:error, _reason} -> failed(socket, surface)
    end
  end

  defp succeeded(socket, :canvas, elapsed) do
    stats = socket.assigns.save_stats

    socket
    |> assign(:save_state, :saved)
    |> assign(:last_saved_cells, socket.assigns.cells)
    |> assign(:save_stats, bump_success(stats, elapsed))
  end

  defp succeeded(socket, :note, elapsed) do
    stats = socket.assigns.note_save_stats

    socket
    |> assign(:note_save_state, :saved)
    |> assign(:note_last_saved_content, socket.assigns.note_content)
    |> assign(:note_save_stats, bump_success(stats, elapsed))
  end

  defp failed(socket, :canvas) do
    stats = socket.assigns.save_stats
    socket |> assign(:save_state, :unsaved) |> assign(:save_stats, bump_failure(stats))
  end

  defp failed(socket, :note) do
    stats = socket.assigns.note_save_stats
    socket |> assign(:note_save_state, :unsaved) |> assign(:note_save_stats, bump_failure(stats))
  end

  defp bump_success(stats, elapsed) do
    %{
      stats
      | writes: stats.writes + 1,
        last_saved_at: DateTime.utc_now(),
        last_write_ms: elapsed
    }
  end

  defp bump_failure(stats), do: %{stats | failures: stats.failures + 1}
end
