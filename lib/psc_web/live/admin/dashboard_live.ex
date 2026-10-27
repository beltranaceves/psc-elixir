defmodule PscWeb.Admin.DashboardLive do
  @moduledoc """
  The administration landing page: instance figures, row-budget pressure,
  recent activity and quick links.

  It uses Backpex's app shell for continuity with the resource pages, but the
  content is a plain LiveView — Backpex is a CRUD layer, not a dashboard
  framework. Everything here is read-only and every figure is a bounded
  aggregate, so the page stays inside the free-tier row limits.

  Figures refresh on demand and once a minute while the page is connected.
  """

  use PscWeb, :live_view

  alias Psc.Admin

  @refresh_interval :timer.minutes(1)

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(@refresh_interval, self(), :refresh)

    {:ok, load(socket)}
  end

  @impl true
  def handle_event("refresh", _params, socket), do: {:noreply, load(socket)}

  @impl true
  def handle_info(:refresh, socket), do: {:noreply, load(socket)}
  def handle_info(_message, socket), do: {:noreply, socket}

  defp load(socket) do
    assign(socket,
      stats: Admin.stats(),
      trends: Admin.trends(),
      recent: Admin.recent(),
      budget: Admin.row_budget(),
      version: Admin.version(),
      loaded_at: DateTime.utc_now()
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin
      flash={@flash}
      socket={@socket}
      current_scope={@current_scope}
      live_resource={nil}
      current_url={Map.get(assigns, :current_url)}
      sidebar_open={Map.get(assigns, :sidebar_open, true)}
      sidebar_section_states={Map.get(assigns, :sidebar_section_states, %{})}
      preferences_manifest={Map.get(assigns, :preferences_manifest)}
    >
      <div id="admin-dashboard" class="mx-auto w-full max-w-7xl space-y-10 p-4 sm:p-6 lg:p-8">
        <header class="flex flex-wrap items-start justify-between gap-4">
          <div>
            <h1 class="text-2xl font-semibold tracking-tight text-base-content">Administration</h1>

            <p class="mt-1 max-w-2xl text-sm text-base-content/60">
              Instance overview. Content is edited in the app; this surface is for
              accounts, templates and moderation.
            </p>
          </div>

          <div class="flex items-center gap-3">
            <time
              id="admin-loaded-at"
              datetime={DateTime.to_iso8601(@loaded_at)}
              title={Calendar.strftime(@loaded_at, "%d %b %Y, %H:%M UTC")}
              class="text-xs text-base-content/50"
            >
              updated {relative_time(@loaded_at)}
            </time>

            <button
              id="admin-refresh"
              type="button"
              phx-click="refresh"
              class="inline-flex items-center gap-1.5 rounded-lg border border-base-content/15 px-2.5 py-1.5 text-xs font-medium text-base-content/70 transition-colors hover:bg-base-content/5 hover:text-base-content"
            >
              <.icon name="hero-arrow-path" class="size-3.5" /> Refresh
            </button>
          </div>
        </header>

        <section aria-label="Instance figures" class="space-y-3">
          <div class="flex flex-wrap items-baseline justify-between gap-2">
            <h2 class="text-xs font-semibold uppercase tracking-widest text-base-content/40">
              At a glance
            </h2>

            <p class="text-[11px] text-base-content/40">
              14-day sparklines · badges compare the last 7 days with the 7 before
            </p>
          </div>

          <div class="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            <.stat_card
              label="Users"
              value={@stats.users}
              hint={"#{pluralize(@stats.admins, "admin")} · #{pluralize(@stats.unconfirmed_users, "unconfirmed account")}"}
              icon="hero-users"
              trend={@trends.users}
            />
            <.stat_card
              label="Templates"
              value={@stats.templates}
              hint={"#{@stats.built_in_templates} built-in · #{@stats.public_templates} public"}
              icon="hero-rectangle-group"
              trend={@trends.templates}
            />
            <.stat_card
              label="Canvases"
              value={@stats.canvases}
              hint="across all users"
              icon="hero-table-cells"
              trend={@trends.canvases}
            />
            <.stat_card
              label="Notes"
              value={@stats.notes}
              hint={notes_hint(@stats)}
              icon="hero-document-text"
              trend={@trends.notes}
            />
          </div>
        </section>

        <section aria-label="Needs attention" class="space-y-3">
          <h2 class="text-xs font-semibold uppercase tracking-widest text-base-content/40">
            Needs attention
          </h2>

          <div class="grid gap-4 lg:grid-cols-3">
            <div class="rounded-xl border border-base-content/10 bg-base-200 p-4 lg:col-span-2">
              <div class="flex flex-wrap items-baseline justify-between gap-2">
                <h3 class="text-sm font-medium text-base-content">Event log</h3>

                <span class="text-xs text-base-content/50">
                  ceiling {format_number(@budget)} rows per table
                </span>
              </div>

              <div class="mt-4 space-y-4">
                <.budget_row label="Canvas events" used={@stats.canvas_events} budget={@budget} />
                <.budget_row label="Note events" used={@stats.note_events} budget={@budget} />
              </div>

              <p class="mt-4 text-xs text-base-content/50">
                A save folds events into the snapshot and deletes the covered rows. The sweeper
                runs on its own; this is only the pressure gauge.
              </p>
            </div>

            <div class="rounded-xl border border-base-content/10 bg-base-200 p-4">
              <h3 class="text-sm font-medium text-base-content">Alerts</h3>

              <ul class="mt-3 space-y-2 text-sm">
                <li :if={@stats.unconfirmed_users > 0} class="flex items-start gap-2 text-warning">
                  <.icon name="hero-exclamation-triangle" class="mt-0.5 size-4 shrink-0" />
                  <span>{pluralize(@stats.unconfirmed_users, "unconfirmed account")}</span>
                </li>

                <li
                  :if={@stats.built_in_templates == 0}
                  class="flex items-start gap-2 text-warning"
                >
                  <.icon name="hero-exclamation-triangle" class="mt-0.5 size-4 shrink-0" />

                  <span>
                    No built-in templates are seeded.
                    <code class="rounded bg-base-content/10 px-1">Psc.Release.setup/0</code>
                    seeds them on boot.
                  </span>
                </li>

                <li
                  :if={@stats.unconfirmed_users == 0 and @stats.built_in_templates > 0}
                  class="flex items-start gap-2 text-success"
                >
                  <.icon name="hero-check-badge" class="mt-0.5 size-4 shrink-0" />
                  <span>Nothing needs attention.</span>
                </li>
              </ul>
            </div>
          </div>
        </section>

        <section aria-label="Recent activity" class="space-y-3">
          <div class="flex flex-wrap items-baseline justify-between gap-2">
            <h2 class="text-xs font-semibold uppercase tracking-widest text-base-content/40">
              Recent activity
            </h2>

            <.link navigate={~p"/catalog"} class="text-xs font-medium text-primary hover:underline">
              Browse the catalog →
            </.link>
          </div>

          <div
            :if={@stats.canvases == 0}
            class="rounded-xl border border-dashed border-base-content/20 bg-base-200/50 p-4"
          >
            <p class="text-sm font-medium text-base-content">Nothing has been created yet.</p>

            <p class="mt-1 text-sm text-base-content/60">
              The built-in templates are ready to start from, and new accounts can register
              straight away.
            </p>
          </div>

          <div class="grid gap-4 lg:grid-cols-2">
            <.recent_list
              kind={:canvas}
              title="Latest canvases"
              items={@recent.canvases}
              empty="No canvases yet."
            />

            <.recent_list
              kind={:template}
              title="Latest templates"
              items={@recent.templates}
              empty="No templates yet."
            />
          </div>
        </section>

        <section aria-label="Resources" class="space-y-3">
          <h2 class="text-xs font-semibold uppercase tracking-widest text-base-content/40">
            Resources
          </h2>

          <div class="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
            <.resource_link
              navigate={~p"/admin/users"}
              icon="hero-users"
              title="Users"
              body="Accounts and roles"
              count={@stats.users}
            />
            <.resource_link
              navigate={~p"/admin/templates"}
              icon="hero-rectangle-group"
              title="Templates"
              body="Library and built-in defaults"
              count={@stats.templates}
            />
            <.resource_link
              navigate={~p"/admin/canvases"}
              icon="hero-table-cells"
              title="Canvases"
              body="Read-only, with owners"
              count={@stats.canvases}
            />
            <.resource_link
              navigate={~p"/admin/notes"}
              icon="hero-document-text"
              title="Notes"
              body="Read-only, titles and owners"
              count={@stats.notes}
            />
          </div>
        </section>

        <details
          id="admin-system"
          class="group rounded-xl border border-base-content/10 bg-base-200/50"
        >
          <summary class="flex cursor-pointer list-none items-center justify-between gap-2 px-4 py-3 text-sm font-medium text-base-content">
            <span class="flex items-center gap-2">
              <.icon name="hero-cog-6-tooth" class="size-4 text-base-content/50" /> System
            </span>

            <.icon
              name="hero-chevron-down"
              class="size-4 text-base-content/50 transition-transform group-open:rotate-180"
            />
          </summary>

          <div class="space-y-3 border-t border-base-content/10 px-4 py-3 text-sm text-base-content/60">
            <dl class="grid gap-2 sm:grid-cols-3">
              <div class="flex items-baseline justify-between gap-3 sm:block">
                <dt class="text-xs uppercase tracking-wide text-base-content/40">Version</dt>
                <dd class="tabular-nums text-base-content">{@version}</dd>
              </div>
              <div class="flex items-baseline justify-between gap-3 sm:block">
                <dt class="text-xs uppercase tracking-wide text-base-content/40">Row budget</dt>
                <dd class="tabular-nums text-base-content">{format_number(@budget)}</dd>
              </div>
              <div class="flex items-baseline justify-between gap-3 sm:block">
                <dt class="text-xs uppercase tracking-wide text-base-content/40">Built-ins</dt>
                <dd class="text-base-content">
                  {if @stats.built_in_templates > 0, do: "seeded", else: "missing"}
                </dd>
              </div>
            </dl>

            <p>
              Admins are configured with
              <code class="rounded bg-base-content/10 px-1">ADMIN_EMAILS</code>
              and the release task promotes them on boot. Adding an address there and redeploying
              is the supported way to create another admin; the Users table can demote, but not
              promote an address it has never seen.
            </p>
          </div>
        </details>
      </div>
    </Layouts.admin>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :hint, :string, required: true
  attr :icon, :string, required: true
  attr :trend, :list, required: true, doc: "per-day counts, oldest first"

  defp stat_card(assigns) do
    assigns =
      assign(assigns,
        delta: weekly_delta(assigns.trend),
        points: sparkline_points(assigns.trend)
      )

    ~H"""
    <article class="rounded-xl border border-base-content/10 bg-base-200 p-4">
      <div class="flex items-start justify-between gap-3">
        <div class="min-w-0">
          <div class="flex items-center gap-2 text-base-content/60">
            <.icon name={@icon} class="size-4" />
            <span class="truncate text-xs font-medium uppercase tracking-wide">{@label}</span>
          </div>

          <p class="mt-2 text-3xl font-semibold tabular-nums text-base-content">{@value}</p>
        </div>

        <span
          class={[
            "inline-flex shrink-0 items-center gap-1 rounded-full px-2 py-0.5 text-[11px] font-medium tabular-nums",
            delta_class(@delta)
          ]}
          title="New rows in the last 7 days compared with the 7 days before"
        >
          <.icon name={delta_icon(@delta)} class="size-3" />{delta_label(@delta)}
        </span>
      </div>

      <svg
        viewBox="0 0 100 28"
        preserveAspectRatio="none"
        class="mt-3 h-8 w-full text-primary"
        aria-hidden="true"
      >
        <polyline
          points={@points}
          fill="none"
          stroke="currentColor"
          stroke-width="1.5"
          stroke-linecap="round"
          stroke-linejoin="round"
          vector-effect="non-scaling-stroke"
        />
      </svg>

      <p class="mt-2 text-xs text-base-content/50">{@hint}</p>
    </article>
    """
  end

  attr :label, :string, required: true
  attr :used, :integer, required: true
  attr :budget, :integer, required: true

  defp budget_row(assigns) do
    percent = if assigns.budget > 0, do: round(assigns.used / assigns.budget * 100), else: 0

    assigns =
      assign(assigns,
        percent: percent,
        width: min(percent, 100),
        tone: budget_tone(percent)
      )

    ~H"""
    <div>
      <div class="flex items-baseline justify-between gap-3 text-sm">
        <span class="text-base-content/80">{@label}</span>

        <span class="text-xs tabular-nums text-base-content/60">
          {format_number(@used)} / {format_number(@budget)} · {@percent}%
        </span>
      </div>

      <div class="mt-1.5 h-2 w-full overflow-hidden rounded-full bg-base-content/10">
        <div class={["h-full rounded-full transition-[width]", @tone]} style={"width: #{@width}%"}>
        </div>
      </div>
    </div>
    """
  end

  attr :kind, :atom, required: true, values: [:canvas, :template]
  attr :title, :string, required: true
  attr :items, :list, required: true
  attr :empty, :string, required: true

  defp recent_list(assigns) do
    ~H"""
    <div class="overflow-hidden rounded-xl border border-base-content/10 bg-base-200">
      <div class="flex items-center justify-between gap-2 border-b border-base-content/10 px-4 py-2.5">
        <h3 class="text-sm font-medium text-base-content">{@title}</h3>

        <.link navigate={recent_index_path(@kind)} class="text-xs text-primary hover:underline">
          View all
        </.link>
      </div>

      <ul class="divide-y divide-base-content/10">
        <li :for={item <- @items}>
          <.link
            navigate={recent_path(@kind, item)}
            class="flex items-center justify-between gap-3 px-4 py-2.5 transition-colors hover:bg-base-content/5"
          >
            <span class="min-w-0">
              <span class="block truncate text-sm font-medium text-base-content">
                {item.name || "Untitled"}
              </span>

              <span class="block truncate text-xs text-base-content/50">
                {owner_label(@kind, item)}
              </span>
            </span>

            <span class="shrink-0 text-xs text-base-content/50">
              {relative_time(item.updated_at)}
            </span>
          </.link>
        </li>

        <li :if={@items == []} class="px-4 py-8 text-center text-sm text-base-content/50">
          {@empty}
        </li>
      </ul>
    </div>
    """
  end

  attr :navigate, :string, required: true
  attr :title, :string, required: true
  attr :body, :string, required: true
  attr :icon, :string, required: true
  attr :count, :integer, required: true

  defp resource_link(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class="group flex items-center gap-3 rounded-xl border border-base-content/10 bg-base-200 p-3 transition-colors hover:border-base-content/25 hover:bg-base-content/5"
    >
      <span class="flex size-9 shrink-0 items-center justify-center rounded-full bg-primary/10 text-primary">
        <.icon name={@icon} class="size-4" />
      </span>

      <span class="min-w-0 flex-1">
        <span class="block text-sm font-medium text-base-content">{@title}</span>
        <span class="block truncate text-xs text-base-content/50">{@body}</span>
      </span>

      <span class="shrink-0 text-sm font-semibold tabular-nums text-base-content/70">
        {format_number(@count)}
      </span>
    </.link>
    """
  end

  defp recent_path(:canvas, item), do: ~p"/admin/canvases/#{item.id}/show"
  defp recent_path(:template, item), do: ~p"/admin/templates/#{item.id}/show"

  defp recent_index_path(:canvas), do: ~p"/admin/canvases"
  defp recent_index_path(:template), do: ~p"/admin/templates"

  defp weekly_delta(values) do
    {previous, recent} = Enum.split(values, max(length(values) - 7, 0))
    Enum.sum(recent) - Enum.sum(previous)
  end

  defp delta_label(delta) when delta > 0, do: "+#{delta}"
  defp delta_label(0), do: "±0"
  defp delta_label(delta), do: Integer.to_string(delta)

  defp delta_icon(delta) when delta > 0, do: "hero-arrow-trending-up"
  defp delta_icon(delta) when delta < 0, do: "hero-arrow-trending-down"
  defp delta_icon(_delta), do: "hero-minus"

  defp delta_class(delta) when delta > 0, do: "bg-success/10 text-success"
  defp delta_class(delta) when delta < 0, do: "bg-base-content/10 text-base-content/60"
  defp delta_class(_delta), do: "bg-base-content/5 text-base-content/40"

  defp budget_tone(percent) when percent >= 90, do: "bg-error"
  defp budget_tone(percent) when percent >= 75, do: "bg-warning"
  defp budget_tone(_percent), do: "bg-primary"

  # Sparklines have no axes, so the shape is what matters: normalise against the
  # window's own maximum and keep a flat line when everything is zero.
  defp sparkline_points(values) do
    max = values |> Enum.max(fn -> 1 end) |> Kernel.max(1)
    last = max(length(values) - 1, 1)

    values
    |> Enum.with_index()
    |> Enum.map(fn {value, index} ->
      x = Float.round(index * 100 / last, 2)
      y = Float.round(26 - value / max * 22, 2)
      "#{x},#{y}"
    end)
    |> Enum.join(" ")
  end

  defp notes_hint(%{canvases: 0}), do: "attached to canvases"

  defp notes_hint(%{canvases: canvases, notes: notes}),
    do: "#{Float.round(notes / canvases, 1)} per canvas"

  defp pluralize(1, singular), do: "1 #{singular}"
  defp pluralize(count, singular), do: "#{count} #{singular}s"

  defp owner_label(:template, %{built_in: true}), do: "built-in template"
  defp owner_label(_kind, item), do: author_label(item.author)

  defp author_label(%{email: email}), do: email
  defp author_label(_author), do: "unknown author"

  defp relative_time(%DateTime{} = at),
    do: relative_time(DateTime.diff(DateTime.utc_now(), at), at)

  defp relative_time(%NaiveDateTime{} = at),
    do: relative_time(NaiveDateTime.diff(NaiveDateTime.utc_now(), at), at)

  defp relative_time(seconds, _at) when seconds < 60, do: "just now"
  defp relative_time(seconds, _at) when seconds < 3_600, do: "#{div(seconds, 60)}m ago"
  defp relative_time(seconds, _at) when seconds < 86_400, do: "#{div(seconds, 3_600)}h ago"
  defp relative_time(seconds, _at) when seconds < 2_592_000, do: "#{div(seconds, 86_400)}d ago"
  defp relative_time(_seconds, at), do: Calendar.strftime(at, "%d %b %Y")

  defp format_number(number) do
    number
    |> Integer.to_string()
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.map_join(",", &Enum.join/1)
    |> String.reverse()
  end
end
