defmodule PscWeb.UnstrCanvasLive.AnalysisPanel do
  @moduledoc """
  The Analysis view of a canvas, in two parts.

  * **Overview** — simple facts rebuilt whenever the tab opens
    (`Psc.Insights.Overview`): the oldest, most changed, longest and shortest
    cells, and who edited most, least, and added or removed the most text.
  * **Insights** — the stored `Psc.Insights.Report`: heuristic findings that
    rerun when the canvas has changed, and AI findings that run only on demand.
    Each finding is a collapsible row.

  The panel is presentational. It emits `refresh_analysis`, `run_ai_review`,
  `toggle_analysis_notes`, `analysis_filter`, `dismiss_insight` and
  `restore_insight` to the editor.
  """

  use Phoenix.Component
  use PscWeb, :verified_routes

  import PscWeb.CoreComponents, only: [icon: 1]

  alias Phoenix.LiveView.JS
  alias Psc.Insights.Finding
  alias PscWeb.Components.UI.Button, as: UIButton

  attr :canvas_id, :string, required: true
  attr :cells, :map, required: true
  attr :report, :any, default: nil
  attr :overview, :map, default: nil
  attr :filter, :string, default: "all"
  attr :stale?, :boolean, default: false
  attr :ai_stale?, :boolean, default: false
  attr :ai_enabled?, :boolean, default: false
  attr :ai_label, :string, default: nil
  attr :include_notes?, :boolean, default: false
  attr :ai_running?, :boolean, default: false

  def panel(assigns) do
    report = assigns.report

    assigns =
      assigns
      |> assign(:labels, labels(assigns.cells))
      |> assign(:filters, filters(report))
      |> assign(:items, visible_findings(report, assigns.filter))
      |> assign(:dismissed_count, if(report, do: length(report.dismissed), else: 0))

    ~H"""
    <div id="canvas-analysis" class="min-h-0 w-full flex-1 overflow-y-auto">
      <div class="mx-auto w-full max-w-2xl space-y-8 pb-6 md:max-w-3xl lg:max-w-4xl 2xl:max-w-5xl">
        <section id="canvas-analysis-overview" aria-labelledby="canvas-analysis-overview-title">
          <div class="mb-3 flex flex-wrap items-start justify-between gap-2">
            <div class="min-w-0">
              <h2
                id="canvas-analysis-overview-title"
                class="text-sm font-medium uppercase tracking-wide text-base-content/50"
              >
                Overview
              </h2>

              <p id="canvas-analysis-since" class="mt-0.5 text-xs text-base-content/50">
                {since_label(@overview)}
              </p>
            </div>

            <div class="flex flex-wrap items-center justify-end gap-2">
              <span
                :if={@stale?}
                id="canvas-analysis-changed"
                class="rounded-full bg-warning/10 px-2 py-0.5 text-[11px] font-medium text-warning"
              >
                Canvas changed
              </span>

              <button
                :if={@report}
                type="button"
                id="canvas-analysis-copy"
                title="Copy the report as Markdown"
                onclick="navigator.clipboard.writeText(document.getElementById('canvas-analysis-report-text').value)"
                class={quiet_button()}
              >
                <.icon name="hero-clipboard-document" class="size-3.5" /> Copy
              </button>

              <button
                type="button"
                id="canvas-analysis-refresh"
                phx-click="refresh_analysis"
                title="Recount the overview and rerun the checks"
                class={quiet_button()}
              >
                <.icon name="hero-arrow-path" class="size-3.5" /> Refresh
              </button>
            </div>
          </div>

          <div
            :if={@overview}
            id="canvas-analysis-tiles"
            class="grid grid-cols-2 gap-2 sm:grid-cols-4"
          >
            <.tile :for={tile <- @overview.tiles} tile={tile} canvas_id={@canvas_id} />
          </div>

          <p :if={@report} id="canvas-analysis-coverage" class="mt-2 text-xs text-base-content/45">
            {@report.stats["coverage"] || 0}% of fields filled · {@report.stats["empty_cells"] || 0} empty {plural(
              @report.stats["empty_cells"] || 0,
              "cell"
            )}
          </p>
        </section>

        <section id="canvas-analysis-insights" aria-labelledby="canvas-analysis-insights-title">
          <div class="mb-3 flex flex-wrap items-start justify-between gap-2">
            <div class="min-w-0">
              <h2
                id="canvas-analysis-insights-title"
                class="text-sm font-medium uppercase tracking-wide text-base-content/50"
              >
                Insights
              </h2>

              <p
                id="canvas-analysis-summary"
                role="status"
                class="mt-0.5 text-xs text-base-content/50"
              >
                {summary_label(@report, @ai_running?)}
              </p>
            </div>

            <div :if={@ai_enabled?} class="flex flex-wrap items-center justify-end gap-2">
              <button
                type="button"
                id="canvas-analysis-notes"
                phx-click="toggle_analysis_notes"
                aria-pressed={to_string(@include_notes?)}
                disabled={@ai_running?}
                title="Include this canvas's notes in the AI review"
                class={[
                  quiet_button(),
                  @include_notes? && "!border-primary/30 !bg-primary/15 !text-primary",
                  @ai_running? && "cursor-not-allowed opacity-50"
                ]}
              >
                <.icon name="hero-document-text" class="size-3.5" /> Include notes
              </button>

              <UIButton.button
                type="button"
                id="canvas-analysis-ai-run"
                size="sm"
                phx-click="run_ai_review"
                disabled={@ai_running?}
              >
                <.icon name="hero-sparkles" class="size-4" />
                {if ai_ran?(@report), do: "Run AI review again", else: "Run AI review"}
              </UIButton.button>
            </div>
          </div>

          <p
            :if={!@ai_enabled?}
            id="canvas-analysis-ai-hint"
            class="mb-3 text-xs leading-relaxed text-base-content/45"
          >
            Add a provider connection in settings to run the optional AI review.
            <.link navigate={~p"/users/settings#agent-connections"} class="link link-primary">
              Open settings
            </.link>
          </p>

          <p
            :if={@ai_enabled? and @ai_label}
            id="canvas-analysis-connection"
            class="mb-3 flex items-center gap-1.5 text-xs leading-relaxed text-base-content/45"
          >
            <.icon name="hero-sparkles" class="size-3.5 shrink-0" />
            <span>The AI review uses {@ai_label} and sends it this canvas's text.</span>
          </p>

          <div
            :if={@ai_stale?}
            id="canvas-analysis-stale"
            class="mb-3 flex items-start gap-2 rounded-xl border border-warning/25 bg-warning/10 px-3 py-2 text-xs leading-relaxed text-base-content/70"
          >
            <.icon name="hero-arrow-path" class="mt-0.5 size-4 shrink-0 text-warning" />
            <p>The canvas changed after the AI review. Run it again to include the latest edits.</p>
          </div>

          <div
            :if={@ai_running?}
            id="canvas-analysis-progress"
            role="status"
            class="mb-3 flex items-center gap-2 rounded-xl border border-base-content/10 bg-base-200 px-3 py-2 text-xs text-base-content/60"
          >
            <span class="size-3.5 animate-spin rounded-full border-2 border-current border-t-transparent"></span>
            <span>Asking the model for a second opinion…</span>
          </div>

          <div :if={@report} id="canvas-analysis-results" class="space-y-3">
            <div id="canvas-analysis-filters" class="flex flex-wrap gap-1.5">
              <button
                :for={{key, label, count} <- @filters}
                type="button"
                id={"canvas-analysis-filter-" <> key}
                phx-click="analysis_filter"
                phx-value-filter={key}
                aria-pressed={to_string(@filter == key)}
                class={[
                  "inline-flex items-center gap-1 rounded-full border px-2.5 py-1 text-xs font-medium transition",
                  "focus:outline-none focus-visible:ring-2 focus-visible:ring-primary/40",
                  @filter == key && "border-primary/30 bg-primary/15 text-primary",
                  @filter != key &&
                    "border-base-content/10 bg-base-100 text-base-content/55 hover:bg-base-200"
                ]}
              >
                {label} <span class="text-[10px] opacity-60">{count}</span>
              </button>
            </div>

            <ul
              :if={@items != []}
              id="canvas-analysis-findings"
              class="divide-y divide-base-content/10 overflow-hidden rounded-xl border border-base-content/10 bg-base-100"
            >
              <li :for={finding <- @items} id={Finding.dom_id(finding)}>
                <details
                  class="group"
                  phx-mounted={JS.ignore_attributes(["open"])}
                >
                  <summary class="flex cursor-pointer list-none items-center gap-2.5 px-3 py-2.5 transition hover:bg-base-200/60 [&::-webkit-details-marker]:hidden">
                    <.icon
                      name="hero-chevron-right"
                      class="size-3.5 shrink-0 text-base-content/40 transition group-open:rotate-90"
                    />
                    <span class={[
                      "shrink-0 rounded-full px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide",
                      severity_badge(finding)
                    ]}>
                      {finding["severity"]}
                    </span>
                    <span class="min-w-0 flex-1 truncate text-sm font-medium text-base-content">
                      {finding["title"]}
                    </span>
                    <span class={[
                      "shrink-0 text-[10px] uppercase tracking-wide",
                      finding["source"] == "ai" && "text-primary",
                      finding["source"] != "ai" && "text-base-content/40"
                    ]}>
                      {if finding["source"] == "ai", do: "AI", else: "Heuristic"}
                    </span>
                  </summary>

                  <div class="space-y-2 px-3 pb-3 pl-9">
                    <p
                      :if={finding["detail"] != ""}
                      class="text-xs leading-relaxed text-base-content/65"
                    >
                      {finding["detail"]}
                    </p>

                    <div class="flex flex-wrap items-center justify-between gap-2">
                      <div class="flex flex-wrap gap-1">
                        <.link
                          :for={key <- finding["cell_keys"]}
                          navigate={~p"/canvas/#{@canvas_id}?tab=editor&cell=#{key}"}
                          id={"insight-cell-" <> sanitize(finding["id"]) <> "-" <> sanitize(key)}
                          class="inline-flex items-center gap-1 rounded-full border border-base-content/10 bg-base-100 px-2 py-0.5 text-[11px] font-medium text-base-content/70 transition hover:border-base-content/25 hover:text-base-content"
                        >
                          <.icon name="hero-arrow-top-right-on-square" class="size-3" />
                          {cell_label(@labels, key)}
                        </.link>
                      </div>

                      <div class="flex items-center gap-2">
                        <span
                          :if={finding["source"] == "ai"}
                          class="text-[10px] uppercase tracking-wide text-base-content/40"
                        >
                          {source_label(finding)}
                        </span>

                        <button
                          :if={dismissed?(@report, finding)}
                          type="button"
                          phx-click="restore_insight"
                          phx-value-id={finding["id"]}
                          class="text-[11px] font-medium text-primary hover:underline"
                        >
                          Restore
                        </button>

                        <button
                          :if={!dismissed?(@report, finding)}
                          type="button"
                          phx-click="dismiss_insight"
                          phx-value-id={finding["id"]}
                          class="text-[11px] font-medium text-base-content/45 hover:text-base-content hover:underline"
                        >
                          Dismiss
                        </button>
                      </div>
                    </div>
                  </div>
                </details>
              </li>
            </ul>

            <div
              :if={@items == []}
              id="canvas-analysis-none"
              class="rounded-xl border border-dashed border-base-content/20 bg-base-200/40 px-4 py-6 text-center text-sm text-base-content/55"
            >
              <%= cond do %>
                <% @filter == "dismissed" -> %>
                  Nothing has been dismissed.
                <% @filter == "all" -> %>
                  No findings. The checks found nothing to flag on this canvas.
                <% true -> %>
                  Nothing matches this filter.
              <% end %>
            </div>

            <p
              :if={@dismissed_count > 0 and @filter != "dismissed"}
              class="text-xs text-base-content/40"
            >
              {@dismissed_count} dismissed {plural(@dismissed_count, "finding")}. Use the Dismissed filter to review.
            </p>
          </div>
        </section>

        <textarea
          :if={@report}
          id="canvas-analysis-report-text"
          class="sr-only"
          aria-hidden="true"
          tabindex="-1"
          readonly
        >{report_markdown(@report, @labels, @cells, @overview)}</textarea>
      </div>
    </div>
    """
  end

  attr :tile, :map, required: true
  attr :canvas_id, :string, required: true

  defp tile(assigns) do
    ~H"""
    <.link
      :if={@tile.cell_key}
      id={"overview-" <> @tile.id}
      navigate={~p"/canvas/#{@canvas_id}?tab=editor&cell=#{@tile.cell_key}"}
      title="Open this cell in the editor"
      class="group block min-w-0 rounded-xl border border-base-content/10 bg-base-200 px-3 py-2.5 transition hover:border-base-content/25"
    >
      <.tile_body tile={@tile} />
    </.link>
    <div
      :if={!@tile.cell_key}
      id={"overview-" <> @tile.id}
      class="min-w-0 rounded-xl border border-base-content/10 bg-base-200 px-3 py-2.5"
    >
      <.tile_body tile={@tile} />
    </div>
    """
  end

  attr :tile, :map, required: true

  defp tile_body(assigns) do
    ~H"""
    <p class="flex items-center gap-1.5 text-[11px] font-medium text-base-content/50">
      <.icon name={@tile.icon} class="size-3.5 shrink-0" />
      <span class="truncate">{@tile.label}</span>
    </p>

    <p class={[
      "mt-1 truncate text-sm font-semibold",
      @tile.value && "text-base-content",
      !@tile.value && "text-base-content/30"
    ]}>
      {@tile.value || "—"}
    </p>

    <p class={[
      "mt-0.5 truncate text-[11px]",
      @tile.tone == :positive && "text-success",
      @tile.tone == :negative && "text-error",
      @tile.tone == :neutral && "text-base-content/45"
    ]}>
      {@tile.detail}
    </p>
    """
  end

  defp quiet_button do
    "inline-flex items-center gap-1.5 rounded-lg border border-base-content/10 bg-base-100 px-2.5 py-1.5 text-xs font-medium text-base-content/60 transition hover:bg-base-200 focus:outline-none focus-visible:ring-2 focus-visible:ring-primary/40"
  end

  defp since_label(%{since: %DateTime{} = since}),
    do: "Edit counts since #{Calendar.strftime(since, "%b %-d, %Y")}"

  defp since_label(_overview), do: "Edit counts start with the next save"

  defp ai_ran?(%{ai_computed_at: %DateTime{}}), do: true
  defp ai_ran?(_report), do: false

  defp summary_label(nil, _ai_running?), do: "No findings yet"

  defp summary_label(report, ai_running?) do
    count = Enum.count(report.findings, &(not dismissed?(report, &1)))
    base = "#{count} #{plural(count, "finding")}"

    ai =
      case report do
        %{ai_computed_at: %DateTime{} = at} ->
          " · AI review #{relative(at)}" <>
            case attribution(report) do
              nil -> ""
              label -> " · #{label}"
            end

        _other ->
          " · AI review not run"
      end

    base <> ai <> if(ai_running?, do: " · adding AI findings…", else: "")
  end

  defp attribution(%{provider: nil}), do: nil
  defp attribution(%{provider: provider, model: nil}), do: provider
  defp attribution(%{provider: provider, model: model}), do: "#{provider} · #{model}"

  defp labels(cells) do
    cells
    |> Psc.Canvas.Structure.cards()
    |> Map.new(fn card -> {card.key, card.label} end)
  end

  defp cell_label(labels, key), do: Map.get(labels, key, key)

  defp sanitize(value), do: String.replace(value, ~r/[^a-zA-Z0-9]+/, "-")

  defp filters(nil), do: []

  defp filters(report) do
    active = Enum.reject(report.findings, &dismissed?(report, &1))

    by_kind =
      Finding.kinds()
      |> Enum.map(fn kind ->
        {kind, label_for(kind), Enum.count(active, &(&1["kind"] == kind))}
      end)
      |> Enum.reject(fn {_kind, _label, count} -> count == 0 end)

    all = [{"all", "All", length(active)}]
    dismissed = [{"dismissed", "Dismissed", length(report.dismissed)}]

    all ++ by_kind ++ if(length(report.dismissed) > 0, do: dismissed, else: [])
  end

  defp visible_findings(nil, _filter), do: []

  defp visible_findings(report, "dismissed") do
    Enum.filter(report.findings, &dismissed?(report, &1))
  end

  defp visible_findings(report, "all") do
    Enum.reject(report.findings, &dismissed?(report, &1))
  end

  defp visible_findings(report, kind) do
    Enum.filter(report.findings, &(&1["kind"] == kind and not dismissed?(report, &1)))
  end

  defp dismissed?(%{dismissed: dismissed}, finding), do: finding["id"] in dismissed
  defp dismissed?(_report, _finding), do: false

  # The Markdown a user gets from the Copy button. It is the visible report:
  # dismissed findings are left out, AI findings keep their attribution.
  defp report_markdown(report, labels, cells, overview) do
    name = cells["$name"] || "Canvas"
    findings = Enum.reject(report.findings, &dismissed?(report, &1))
    stamp = report.computed_at && Calendar.strftime(report.computed_at, "%Y-%m-%d %H:%M UTC")

    heading = [
      "# Analysis — #{name}",
      "",
      "#{length(findings)} #{plural(length(findings), "finding")} · #{report.stats["coverage"] || 0}% filled" <>
        if(stamp, do: " · #{stamp}", else: "")
    ]

    body = Enum.map_join(findings, "\n", &markdown_finding(&1, labels))

    Enum.join(heading, "\n") <>
      "\n\n" <> markdown_overview(overview) <> body <> "\n"
  end

  defp markdown_overview(%{tiles: tiles}) do
    lines =
      Enum.map_join(tiles, "\n", fn tile ->
        "- #{tile.label}: #{tile.value || "—"} (#{tile.detail})"
      end)

    "## Overview\n" <> lines <> "\n\n"
  end

  defp markdown_overview(_overview), do: ""

  defp markdown_finding(finding, labels) do
    cells =
      finding["cell_keys"]
      |> Enum.map_join(", ", &"#{cell_label(labels, &1)} (`#{&1}`)")

    [
      "## #{finding["title"]} (#{finding["severity"]})",
      finding["detail"],
      if(cells != "", do: "Cells: #{cells}", else: nil),
      "Source: #{source_label(finding)}"
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp label_for("empty"), do: "Empty"
  defp label_for("stale"), do: "Stale"
  defp label_for("duplicate"), do: "Duplicates"
  defp label_for("relevance"), do: "Relevance"
  defp label_for("contradiction"), do: "Contradictions"
  defp label_for(kind), do: String.capitalize(kind)

  defp relative(%DateTime{} = at) do
    diff = DateTime.diff(DateTime.utc_now(), at, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)} min ago"
      diff < 86_400 -> "#{div(diff, 3600)} h ago"
      true -> "#{div(diff, 86_400)} d ago"
    end
  end

  defp plural(1, word), do: word
  defp plural(_count, word), do: word <> "s"

  defp source_label(%{"source" => "ai"} = finding) do
    attribution = finding["attribution"] || %{}

    ["AI", attribution["provider"], attribution["model"]]
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" · ")
  end

  defp source_label(_finding), do: "Heuristic"

  defp severity_badge(%{"severity" => "critical"}), do: "bg-error/10 text-error"
  defp severity_badge(%{"severity" => "warning"}), do: "bg-warning/10 text-warning"
  defp severity_badge(_finding), do: "bg-primary/10 text-primary"
end
