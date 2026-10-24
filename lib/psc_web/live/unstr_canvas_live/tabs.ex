defmodule PscWeb.UnstrCanvasLive.Tabs do
  @moduledoc false

  # The canvas editor is a tabbed surface: the grid is one of several views on
  # the same canvas. Everything but the editor is a placeholder for now.
  @tabs [
    {"analysis", "Analysis", "hero-chart-bar",
     "Insights over the canvas: relevance, staleness and content coverage."},
    {"notes", "Notes", "hero-document-text", "Shared notes attached to this canvas."},
    {"editor", "Editor", "hero-pencil-square", "The canvas grid."},
    {"agent", "Agent", "hero-sparkles", "Talk to an agent that can read and edit this canvas."}
  ]

  use Phoenix.Component

  import PscWeb.CoreComponents, only: [icon: 1]

  def tabs, do: @tabs

  def find(id) do
    Enum.find(@tabs, fn {tab_id, _label, _icon, _blurb} -> tab_id == id end) ||
      Enum.find(@tabs, fn {tab_id, _label, _icon, _blurb} -> tab_id == "editor" end)
  end

  attr :tabs, :list, required: true
  attr :active_tab, :string, required: true

  def strip(assigns) do
    ~H"""
    <nav
      id="canvas-tabs"
      role="tablist"
      aria-label="Canvas views"
      class="hidden items-center gap-0.5 rounded-lg border border-base-content/25 bg-base-content/5 px-1 py-0.5 lg:flex"
    >
      <button
        :for={{tab_id, label, icon, _blurb} <- @tabs}
        type="button"
        role="tab"
        id={"canvas-tab-#{tab_id}"}
        data-tab={tab_id}
        aria-selected={to_string(@active_tab == tab_id)}
        aria-controls={"canvas-panel-#{tab_id}"}
        aria-label={label}
        title={label}
        phx-click="select_tab"
        phx-value-tab={tab_id}
        class="flex shrink-0 items-center gap-1.5 rounded-md px-2.5 py-1.5 text-sm font-medium transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-primary"
      >
        <.icon name={icon} class="size-4" />
        <%!-- The names are dropped when the header gives the strip less room
        than it needs, so the tabs never overflow into a scrollbar. --%>
        <span class="@max-[23rem]:hidden">{label}</span>
      </button>
    </nav>
    """
  end

  attr :tabs, :list, required: true
  attr :active_tab, :string, required: true

  def bar(assigns) do
    ~H"""
    <nav
      id="canvas-tabs-bar"
      role="tablist"
      aria-label="Canvas views"
      class="fixed inset-x-0 bottom-0 z-40 flex h-[calc(var(--canvas-tab-bar-height)+env(safe-area-inset-bottom))] items-stretch justify-around gap-1 border-t border-base-content/10 bg-base-200/95 px-1 py-1 pb-[env(safe-area-inset-bottom)] backdrop-blur lg:hidden"
    >
      <button
        :for={{tab_id, label, icon, _blurb} <- @tabs}
        type="button"
        role="tab"
        id={"canvas-tab-bar-#{tab_id}"}
        data-tab={tab_id}
        aria-selected={to_string(@active_tab == tab_id)}
        aria-controls={"canvas-panel-#{tab_id}"}
        aria-label={label}
        title={label}
        phx-click="select_tab"
        phx-value-tab={tab_id}
        class="flex flex-1 shrink-0 flex-col items-center justify-center gap-0.5 rounded-lg px-2 py-1.5 text-[0.7rem] font-medium transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-primary"
      >
        <.icon name={icon} class="size-5" /> <span>{label}</span>
      </button>
    </nav>
    """
  end
end
