defmodule PscWeb.UnstrCanvasLive.AnalysisPanel do
  @moduledoc """
  The Analysis view of a canvas: the latest `Psc.Insights.Report`, the findings
  it contains, and the controls that produce a new one.

  The panel is presentational. It reads the report and the cells, renders the
  cells' labels, and emits `run_analysis`, `analysis_filter`,
  `dismiss_insight`, `restore_insight` and `toggle_analysis_ai` to the editor.
  """

  use Phoenix.Component
  use PscWeb, :verified_routes

  import PscWeb.CoreComponents, only: [icon: 1]

  alias Psc.Insights.Finding
  alias PscWeb.Components.UI.Button, as: UIButton

  attr :canvas_id, :string, required: true
  attr :cells, :map, required: true
  attr :report, :any, default: nil
  attr :filter, :string, default: "all"
  attr :stale?, :boolean, default: false
  attr :ai_enabled?, :boolean, default: false
  attr :ai?, :boolean, default: false
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
      |> assign(:total_findings, total_findings(report))
      |> assign(:dismissed_count, if(report, do: length(report.dismissed), else: 0))

    ~H"""
    <div id="canvas-analysis" class="min-h-0 w-full flex-1 overflow-y-auto">
      <div class="mx-auto w-full max-w-2xl space-y-3 pb-6 md:max-w-3xl lg:max-w-4xl 2xl:max-w-5xl">
        <div class="flex flex-wrap items-start justify-between gap-2">
          <div class="min-w-0">
            <h2 class="text-sm font-medium uppercase tracking-wide text-base-content/50">
              Analysis
            </h2>

            <p id="canvas-analysis-summary" role="status" class="mt-0.5 text-xs text-base-content/50">
              {run_label(@report, @ai_running?)}
            </p>
          </div>

          <div class="flex flex-wrap items-center justify-end gap-2">
            <button
              :if={@ai_enabled?}
              type="button"
              id="canvas-analysis-ai"
              phx-click="toggle_analysis_ai"
              aria-pressed={to_string(@ai?)}
              disabled={@ai_running?}
              title="Send the canvas text to your provider for a second opinion"
              class={[
                "inline-flex items-center gap-1.5 rounded-lg border px-2.5 py-1.5 text-xs font-medium transition",
                "focus:outline-none focus-visible:ring-2 focus-visible:ring-primary/40",
                @ai? && "border-primary/30 bg-primary/15 text-primary",
                !@ai? && "border-base-content/10 bg-base-100 text-base-content/60 hover:bg-base-200",
                @ai_running? && "cursor-not-allowed opacity-50"
              ]}
            >
              <.icon name="hero-sparkles" class="size-3.5" /> Use AI
            </button>

            <button
              :if={@ai_enabled? and @ai?}
              type="button"
              id="canvas-analysis-notes"
              phx-click="toggle_analysis_notes"
              aria-pressed={to_string(@include_notes?)}
              disabled={@ai_running?}
              title="Include this canvas's notes in the AI review"
              class={[
                "inline-flex items-center gap-1.5 rounded-lg border px-2.5 py-1.5 text-xs font-medium transition",
                "focus:outline-none focus-visible:ring-2 focus-visible:ring-primary/40",
                @include_notes? && "border-primary/30 bg-primary/15 text-primary",
                !@include_notes? &&
                  "border-base-content/10 bg-base-100 text-base-content/60 hover:bg-base-200",
                @ai_running? && "cursor-not-allowed opacity-50"
              ]}
            >
              <.icon name="hero-document-text" class="size-3.5" /> Include notes
            </button>

            <button
              :if={@report}
              type="button"
              id="canvas-analysis-copy"
              title="Copy the report as Markdown"
              onclick="navigator.clipboard.writeText(document.getElementById('canvas-analysis-report-text').value)"
              class="inline-flex items-center gap-1.5 rounded-lg border border-base-content/10 bg-base-100 px-2.5 py-1.5 text-xs font-medium text-base-content/60 transition hover:bg-base-200 focus:outline-none focus-visible:ring-2 focus-visible:ring-primary/40"
            >
              <.icon name="hero-clipboard-document" class="size-3.5" /> Copy
            </button>

            <UIButton.button
              :if={@report}
              type="button"
              id="canvas-analysis-run"
              size="sm"
              phx-click="run_analysis"
              disabled={@ai_running?}
            >
              <.icon name="hero-arrow-path" class="size-4" /> Run again
            </UIButton.button>
          </div>
        </div>
        <textarea
          :if={@report}
          id="canvas-analysis-report-text"
          class="sr-only"
          aria-hidden="true"
          tabindex="-1"
          readonly
        >{report_markdown(@report, @labels, @cells)}</textarea>
        <p
          :if={!@ai_enabled?}
          id="canvas-analysis-ai-hint"
          class="text-xs leading-relaxed text-base-content/45"
        >
          Add a provider connection in settings to enable the optional AI review.
          <.link navigate={~p"/users/settings#agent-connections"} class="link link-primary">
            Open settings
          </.link>
        </p>

        <p
          :if={@ai_enabled? and @ai? and @ai_label}
          id="canvas-analysis-connection"
          class="flex items-center gap-1.5 text-xs leading-relaxed text-base-content/45"
        >
          <.icon name="hero-sparkles" class="size-3.5 shrink-0" />
          <span>The AI review will use {@ai_label}.</span>
        </p>

        <div
          :if={@stale? and @report}
          id="canvas-analysis-stale"
          class="flex items-start gap-2 rounded-xl border border-warning/25 bg-warning/10 px-3 py-2 text-xs leading-relaxed text-base-content/70"
        >
          <.icon name="hero-arrow-path" class="mt-0.5 size-4 shrink-0 text-warning" />
          <p>
            The canvas changed after this run. Run the analysis again to include the latest edits.
          </p>
        </div>

        <div
          :if={@ai_running?}
          id="canvas-analysis-progress"
          role="status"
          class="flex items-center gap-2 rounded-xl border border-base-content/10 bg-base-200 px-3 py-2 text-xs text-base-content/60"
        >
          <span class="size-3.5 animate-spin rounded-full border-2 border-current border-t-transparent"></span>
          <span>Asking the model for a second opinion…</span>
        </div>

        <div
          :if={is_nil(@report)}
          id="canvas-analysis-empty"
          class="flex flex-col items-center rounded-2xl border border-dashed border-base-content/20 bg-base-200/40 px-6 py-10 text-center"
        >
          <span class="flex size-14 items-center justify-center rounded-2xl bg-gradient-to-br from-primary/25 to-accent/20 text-primary ring-1 ring-primary/20 ring-inset">
            <.icon name="hero-chart-bar" class="size-7" />
          </span>

          <h2 class="mt-4 text-base font-semibold text-base-content">No analysis yet</h2>

          <p class="mx-auto mt-1.5 max-w-sm text-sm leading-relaxed text-base-content/55">
            Check this canvas for empty fields, stale cells, duplicates and content that drifts
            from the framing.
          </p>

          <UIButton.button
            type="button"
            id="canvas-analysis-run"
            class="mt-5"
            phx-click="run_analysis"
          >
            <.icon name="hero-play" class="size-4" /> Run analysis
          </UIButton.button>

          <p class="mt-3 max-w-xs text-xs leading-relaxed text-base-content/45">
            Heuristic checks run on this server. AI is optional and uses your own provider key.
          </p>
        </div>

        <div :if={@report} id="canvas-analysis-results" class="space-y-3">
          <div class="grid grid-cols-3 gap-2">
            <.stat label="Coverage" value={"#{@report.stats["coverage"] || 0}%"} />
            <.stat label="Empty cells" value={to_string(@report.stats["empty_cells"] || 0)} />
            <.stat label="Findings" value={to_string(@total_findings)} />
          </div>

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
                @filter == key &&
                  "border-primary/30 bg-primary/15 text-primary",
                @filter != key &&
                  "border-base-content/10 bg-base-100 text-base-content/55 hover:bg-base-200"
              ]}
            >
              {label} <span class="text-[10px] opacity-60">{count}</span>
            </button>
          </div>

          <ul id="canvas-analysis-findings" class="space-y-2">
            <li
              :for={finding <- @items}
              id={Finding.dom_id(finding)}
              class={[
                "flex flex-col gap-2 rounded-xl border px-4 py-3",
                severity_surface(finding)
              ]}
            >
              <div class="flex items-start gap-2">
                <span class={[
                  "mt-0.5 flex size-6 shrink-0 items-center justify-center rounded-lg",
                  severity_icon_surface(finding)
                ]}>
                  <.icon name={severity_icon(finding)} class="size-3.5" />
                </span>

                <div class="min-w-0 flex-1">
                  <div class="flex flex-wrap items-center gap-1.5">
                    <h3 class="text-sm font-medium text-base-content">{finding["title"]}</h3>

                    <span class={[
                      "rounded-full px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide",
                      severity_badge(finding)
                    ]}>
                      {finding["severity"]}
                    </span>
                  </div>

                  <p
                    :if={finding["detail"] != ""}
                    class="mt-1 text-xs leading-relaxed text-base-content/65"
                  >
                    {finding["detail"]}
                  </p>
                </div>
              </div>

              <div class="flex flex-wrap items-center justify-between gap-2 pl-8">
                <div class="flex flex-wrap gap-1">
                  <.link
                    :for={key <- finding["cell_keys"]}
                    navigate={~p"/canvas/#{@canvas_id}?tab=editor&cell=#{key}"}
                    id={"insight-cell-" <> sanitize(key)}
                    class="inline-flex items-center gap-1 rounded-full border border-base-content/10 bg-base-100 px-2 py-0.5 text-[11px] font-medium text-base-content/70 transition hover:border-base-content/25 hover:text-base-content"
                  >
                    <.icon name="hero-arrow-top-right-on-square" class="size-3" /> {cell_label(
                      @labels,
                      key
                    )}
                  </.link>
                </div>

                <div class="flex items-center gap-2">
                  <span class="text-[10px] uppercase tracking-wide text-base-content/40">
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
            </li>
          </ul>

          <div
            :if={@items == []}
            id="canvas-analysis-none"
            class="rounded-xl border border-dashed border-base-content/20 bg-base-200/40 px-4 py-6 text-center text-sm text-base-content/55"
          >
            <%= if @filter == "dismissed" do %>
              Nothing has been dismissed.
            <% else %>
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
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp stat(assigns) do
    ~H"""
    <div class="rounded-xl border border-base-content/10 bg-base-200 px-3 py-2">
      <p class="text-[10px] font-medium uppercase tracking-wide text-base-content/45">{@label}</p>

      <p class="mt-0.5 text-lg font-semibold text-base-content">{@value}</p>
    </div>
    """
  end

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

  defp total_findings(nil), do: 0

  defp total_findings(report) do
    Enum.count(report.findings, &(not dismissed?(report, &1)))
  end

  # The Markdown a user gets from the Copy button. It is the visible report:
  # dismissed findings are left out, AI findings keep their attribution.
  defp report_markdown(report, labels, cells) do
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

    Enum.join(heading, "\n") <> "\n\n" <> body <> "\n"
  end

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
  defp label_for("coverage"), do: "Coverage"
  defp label_for("contradiction"), do: "Contradictions"
  defp label_for(kind), do: String.capitalize(kind)

  defp run_label(nil, _ai_running?), do: "No analysis yet"

  defp run_label(%{computed_at: nil}, _ai_running?), do: "No analysis yet"

  defp run_label(%{computed_at: at, findings: findings} = report, ai_running?) do
    suffix = if report.mode == "assisted", do: " · AI", else: ""

    "#{relative(at)} · #{length(findings)} #{plural(length(findings), "finding")}#{suffix}" <>
      if(ai_running?, do: " · adding AI findings…", else: "")
  end

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

  defp severity_surface(%{"severity" => "critical"}),
    do: "border-error/25 bg-error/5"

  defp severity_surface(%{"severity" => "warning"}),
    do: "border-warning/25 bg-warning/5"

  defp severity_surface(_finding), do: "border-base-content/10 bg-base-200"

  defp severity_icon_surface(%{"severity" => "critical"}),
    do: "bg-error/10 text-error"

  defp severity_icon_surface(%{"severity" => "warning"}),
    do: "bg-warning/10 text-warning"

  defp severity_icon_surface(_finding), do: "bg-primary/10 text-primary"

  defp severity_badge(%{"severity" => "critical"}), do: "bg-error/10 text-error"
  defp severity_badge(%{"severity" => "warning"}), do: "bg-warning/10 text-warning"
  defp severity_badge(_finding), do: "bg-primary/10 text-primary"

  defp severity_icon(%{"severity" => "critical"}), do: "hero-exclamation-triangle"
  defp severity_icon(%{"severity" => "warning"}), do: "hero-exclamation-circle"
  defp severity_icon(_finding), do: "hero-information-circle"
end
