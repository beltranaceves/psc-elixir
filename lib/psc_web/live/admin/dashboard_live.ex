defmodule PscWeb.Admin.DashboardLive do
  @moduledoc """
  The administration landing page: instance figures and quick links.

  It uses Backpex's app shell for continuity with the resource pages, but the
  content is a plain LiveView — Backpex is a CRUD layer, not a dashboard
  framework.
  """

  use PscWeb, :live_view

  alias Psc.Admin

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :stats, Admin.stats())}
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
      <div class="mx-auto w-full max-w-6xl space-y-8 p-4 sm:p-6 lg:p-8">
        <header>
          <h1 class="text-2xl font-semibold tracking-tight text-base-content">Administration</h1>

          <p class="mt-1 max-w-2xl text-sm text-base-content/60">
            Instance overview. Content is edited in the app; this surface is for
            accounts, templates and moderation.
          </p>
        </header>

        <section aria-label="Instance figures" class="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
          <.stat_card
            label="Users"
            value={@stats.users}
            hint={"#{@stats.admins} admin(s)"}
            icon="hero-users"
          />
          <.stat_card
            label="Templates"
            value={@stats.templates}
            hint={"#{@stats.built_in_templates} built-in · #{@stats.public_templates} public"}
            icon="hero-rectangle-group"
          />
          <.stat_card
            label="Canvases"
            value={@stats.canvases}
            hint="across all users"
            icon="hero-table-cells"
          />
          <.stat_card
            label="Notes"
            value={@stats.notes}
            hint="attached to canvases"
            icon="hero-document-text"
          />
        </section>

        <section class="grid gap-4 lg:grid-cols-2">
          <.link_card
            navigate={~p"/admin/users"}
            title="Users"
            body="Review accounts and grant or revoke the admin role. The last admin cannot be demoted."
            icon="hero-users"
          />
          <.link_card
            navigate={~p"/admin/templates"}
            title="Templates"
            body="Manage the library and the built-in defaults: publish, unpublish, rename or inspect usage."
            icon="hero-rectangle-group"
          />
          <.link_card
            navigate={~p"/admin/canvases"}
            title="Canvases"
            body="Read-only view of every canvas, its owner, note mode and last update."
            icon="hero-table-cells"
          />
          <.link_card
            navigate={~p"/admin/notes"}
            title="Notes"
            body="Read-only view of the notes attached to canvases. Bodies stay in the canvas Notes view."
            icon="hero-document-text"
          />
        </section>

        <section class="rounded-xl border border-base-content/10 bg-base-200/50 p-4 sm:p-5">
          <h2 class="text-sm font-semibold text-base-content">Bootstrap</h2>

          <p class="mt-1 text-sm text-base-content/60">
            Admins are configured with
            <code class="rounded bg-base-content/10 px-1">ADMIN_EMAILS</code>
            and the release task promotes them on boot. Adding an address there and redeploying is
            the supported way to create another admin; the Users table can demote, but not promote
            an address it has never seen.
          </p>

          <p class="mt-2 text-sm text-base-content/60">
            The event log currently holds <strong>{@stats.canvas_events}</strong>
            canvas event rows. Pruning keeps that bounded.
          </p>
        </section>
      </div>
    </Layouts.admin>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :hint, :string, required: true
  attr :icon, :string, required: true

  defp stat_card(assigns) do
    ~H"""
    <div class="rounded-xl border border-base-content/10 bg-base-200 p-4">
      <div class="flex items-center gap-2 text-base-content/60">
        <.icon name={@icon} class="size-4" />
        <span class="text-xs font-medium uppercase tracking-wide">{@label}</span>
      </div>

      <p class="mt-2 text-3xl font-semibold tabular-nums text-base-content">{@value}</p>

      <p class="mt-1 text-xs text-base-content/50">{@hint}</p>
    </div>
    """
  end

  attr :navigate, :string, required: true
  attr :title, :string, required: true
  attr :body, :string, required: true
  attr :icon, :string, required: true

  defp link_card(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class="group flex gap-4 rounded-xl border border-base-content/10 bg-base-200 p-4 transition-colors hover:border-base-content/25 hover:bg-base-content/5"
    >
      <span class="flex size-10 shrink-0 items-center justify-center rounded-full bg-primary/10 text-primary">
        <.icon name={@icon} class="size-5" />
      </span>

      <span class="min-w-0">
        <span class="block font-medium text-base-content">{@title}</span>
        <span class="mt-1 block text-sm text-base-content/60">{@body}</span>
      </span>
    </.link>
    """
  end
end
