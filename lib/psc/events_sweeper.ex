defmodule Psc.EventsSweeper do
  @moduledoc """
  Periodically deletes event rows that are already folded into their owner's
  saved state (`seq <= snapshot_seq`).

  Saves prune the events they cover, but only for rows that belong to a
  document/canvas being edited right then — anything abandoned before its first
  idle save keeps its tail forever. This sweep reclaims that dead weight, which
  matters because the deployed free-tier Postgres caps tables at 10k rows.

  Runs once at boot and then every `:interval` (default 6 hours).
  """

  use GenServer
  require Logger

  @default_interval :timer.hours(6)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    opts = Keyword.merge(Application.get_env(:psc, __MODULE__, []), opts)

    if Keyword.get(opts, :enabled, true) do
      interval = Keyword.get(opts, :interval, @default_interval)
      # Sweep shortly after boot rather than waiting a full interval
      Process.send_after(self(), :sweep, Keyword.get(opts, :initial_delay, :timer.seconds(5)))
      {:ok, %{interval: interval}}
    else
      :ignore
    end
  end

  @impl true
  def handle_info(:sweep, state) do
    sweep()
    Process.send_after(self(), :sweep, state.interval)
    {:noreply, state}
  end

  @doc """
  Run one sweep over every event table. Returns the counts deleted.
  """
  def sweep do
    canvas_events = Psc.Canvas.sweep_folded_events()
    note_events = Psc.Notes.sweep_folded_events()

    if canvas_events + note_events > 0 do
      Logger.info(
        "EventsSweeper pruned #{canvas_events} unstr_canvas_events and " <>
          "#{note_events} note_events rows"
      )
    end

    {canvas_events, note_events}
  end
end
