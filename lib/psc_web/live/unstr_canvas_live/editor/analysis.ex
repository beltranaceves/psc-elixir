defmodule PscWeb.UnstrCanvasLive.Editor.Analysis do
  @moduledoc """
  The Analysis tab: the overview and heuristic checks that run when it opens,
  the on-demand AI review (a background task), dismissing findings, and
  keeping the report's staleness in step with edits.
  """
  use PscWeb, :html
  import Phoenix.LiveView

  alias Psc.Insights

  @doc "Adds the Analysis tab's assigns and registers its hooks."
  def attach(socket) do
    user = socket.assigns.current_scope.user

    socket
    |> assign(:insight_report, nil)
    |> assign(:insight_filter, "all")
    |> assign(:insight_ai_enabled?, Insights.ai_available?(user))
    |> assign(:insight_ai_label, Insights.ai_connection_label(user))
    |> assign(:insight_ai_running?, false)
    |> assign(:insight_include_notes?, false)
    |> assign(:insight_stale?, false)
    |> assign(:insight_ai_stale?, false)
    |> assign(:insight_overview, nil)
    |> assign(:insight_touch_map, socket.assigns.canvas.touch_map || %{})
    |> attach_hook(__MODULE__, :handle_event, &handle_event/3)
    |> attach_hook(__MODULE__, :handle_async, &handle_async/3)
  end

  # ─── Analysis tab ───

  # The overview and the heuristic checks are cheap and run whenever the tab
  # opens; Refresh reruns both on demand. The AI review only runs when asked.
  def handle_event("refresh_analysis", _params, socket) do
    {:halt, socket |> load_overview() |> run_heuristics()}
  end

  def handle_event("run_ai_review", _params, %{assigns: %{insight_ai_running?: true}} = socket) do
    {:halt, socket}
  end

  def handle_event("run_ai_review", _params, socket) do
    socket =
      if socket.assigns.insight_report, do: socket, else: run_heuristics(socket)

    cond do
      not socket.assigns.insight_ai_enabled? ->
        {:halt, put_flash(socket, :error, ai_error(:no_connection))}

      is_nil(socket.assigns.insight_report) ->
        {:halt, socket}

      true ->
        {:halt, start_ai_review(socket)}
    end
  end

  def handle_event("toggle_analysis_notes", _params, socket) do
    if socket.assigns.insight_ai_enabled? do
      {:halt, assign(socket, :insight_include_notes?, not socket.assigns.insight_include_notes?)}
    else
      {:halt, socket}
    end
  end

  def handle_event("analysis_filter", %{"filter" => filter}, socket) do
    if filter in ["all", "dismissed" | Psc.Insights.Finding.kinds()] do
      {:halt, assign(socket, :insight_filter, filter)}
    else
      {:halt, socket}
    end
  end

  def handle_event("dismiss_insight", %{"id" => id}, socket) do
    case Insights.dismiss(socket.assigns.current_scope, socket.assigns.canvas_id, id) do
      {:ok, report} -> {:halt, assign(socket, :insight_report, report)}
      {:error, _reason} -> {:halt, put_flash(socket, :error, "Could not dismiss the finding")}
    end
  end

  def handle_event("restore_insight", %{"id" => id}, socket) do
    case Insights.restore(socket.assigns.current_scope, socket.assigns.canvas_id, id) do
      {:ok, report} -> {:halt, assign(socket, :insight_report, report)}
      {:error, _reason} -> {:halt, put_flash(socket, :error, "Could not restore the finding")}
    end
  end

  def handle_event(_event, _params, socket), do: {:cont, socket}

  # Opening the Analysis view rebuilds the overview and, when the canvas has
  # changed since the stored report, reruns the heuristic checks. The AI review
  # is never started here: it costs the user money.
  def load_insights(socket) do
    report = Insights.get_report(socket.assigns.current_scope, socket.assigns.canvas_id)

    socket =
      socket
      |> assign(:insight_report, report)
      |> load_overview()

    if is_nil(report) or Insights.stale?(report, socket.assigns.cells) do
      run_heuristics(socket)
    else
      assign(socket,
        insight_stale?: false,
        insight_ai_stale?: Insights.ai_stale?(report, socket.assigns.cells)
      )
    end
  end

  defp load_overview(socket) do
    case Insights.overview(
           socket.assigns.current_scope,
           socket.assigns.canvas,
           socket.assigns.cells,
           socket.assigns.insight_touch_map
         ) do
      {:ok, overview} -> assign(socket, :insight_overview, overview)
      {:error, _reason} -> assign(socket, :insight_overview, nil)
    end
  end

  defp run_heuristics(socket) do
    case Insights.run(
           socket.assigns.current_scope,
           socket.assigns.canvas,
           socket.assigns.cells,
           touch_map: socket.assigns.insight_touch_map
         ) do
      {:ok, report} ->
        assign(socket,
          insight_report: report,
          insight_stale?: false,
          insight_ai_stale?: Insights.ai_stale?(report, socket.assigns.cells)
        )

      {:error, _reason} ->
        put_flash(socket, :error, "Could not run the analysis")
    end
  end

  # ─── Analysis: the AI pass runs asynchronously ───

  defp start_ai_review(socket) do
    scope = socket.assigns.current_scope
    canvas = socket.assigns.canvas
    cells = socket.assigns.cells
    report = socket.assigns.insight_report
    include_notes = socket.assigns.insight_include_notes?

    socket
    |> assign(:insight_ai_running?, true)
    |> start_async(:insights_ai, fn ->
      Insights.enhance(scope, canvas, cells, report, include_notes: include_notes)
    end)
  end

  def handle_async(:insights_ai, {:ok, {:ok, report}}, socket) do
    {:halt,
     socket
     |> assign(:insight_report, report)
     |> assign(:insight_ai_stale?, Insights.ai_stale?(report, socket.assigns.cells))
     |> assign(:insight_ai_running?, false)}
  end

  def handle_async(:insights_ai, {:ok, {:error, reason}}, socket) do
    {:halt,
     socket
     |> assign(:insight_ai_running?, false)
     |> put_flash(:error, ai_error(reason))}
  end

  def handle_async(:insights_ai, {:exit, _reason}, socket) do
    {:halt,
     socket
     |> assign(:insight_ai_running?, false)
     |> put_flash(:error, "The AI review did not finish")}
  end

  def handle_async(_name, _result, socket), do: {:cont, socket}

  defp ai_error(:no_connection), do: "Add a provider connection to use the AI review"
  defp ai_error(reason) when is_binary(reason), do: "AI review failed: #{reason}"
  defp ai_error(_reason), do: "AI review failed"

  # Keep the Analysis tab honest while the canvas is being edited: the stored
  # report is a snapshot, so every real change either invalidates it or makes a
  # cell look freshly touched. The fingerprint check runs only when a report
  # exists; the touch map is cheap and always kept in step.
  def track_insight_change(socket, %{"type" => "update_cell", "cell_key" => key}) do
    socket
    |> assign(
      :insight_touch_map,
      Map.put(socket.assigns.insight_touch_map, key, DateTime.to_iso8601(DateTime.utc_now()))
    )
    |> mark_insight_stale()
  end

  def track_insight_change(socket, _operation), do: mark_insight_stale(socket)

  defp mark_insight_stale(%{assigns: %{insight_report: nil}} = socket), do: socket

  defp mark_insight_stale(socket) do
    report = socket.assigns.insight_report

    assign(socket,
      insight_stale?: Insights.stale?(report, socket.assigns.cells),
      insight_ai_stale?: Insights.ai_stale?(report, socket.assigns.cells)
    )
  end
end
