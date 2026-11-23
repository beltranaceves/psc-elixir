defmodule PscWeb.UnstrCanvasLive.Tabs do
  @moduledoc false

  # The canvas editor is a tabbed surface: the grid is one of several views on
  # the same canvas. Each tab has its own panel module; `analysis` reads the
  # cached `Psc.Insights` report, the rest are live views on the canvas itself.
  @tabs [
    {"analysis", "Analysis", "hero-chart-bar",
     "Insights over the canvas: relevance, staleness and content coverage."},
    {"notes", "Notes", "hero-document-text", "Shared notes attached to this canvas."},
    {"editor", "Editor", "hero-pencil-square", "The canvas grid."},
    {"agent", "Agent", "hero-sparkles", "Talk to a read-only agent about this canvas."},
    {"history", "History", "hero-clock", "Pivots: saved versions and why they changed."},
    {"info", "Info", "hero-information-circle", "Canvas details, sharing and settings."}
  ]

  use Phoenix.Component

  import PscWeb.CoreComponents, only: [icon: 1]

  def tabs, do: @tabs

  def find(id) do
    Enum.find(@tabs, fn {tab_id, _label, _icon, _blurb} -> tab_id == id end) ||
      Enum.find(@tabs, fn {tab_id, _label, _icon, _blurb} -> tab_id == "editor" end)
  end

  @doc "Whether `id` names a tab."
  def tab?(id), do: Enum.any?(@tabs, fn {tab_id, _, _, _} -> tab_id == id end)

  # Split view (desktop only): two panes, `primary` on the left and `split` on
  # the right, each showing one tab. A tab is in at most one pane, because every
  # panel is rendered once and its ids are test hooks. The `CanvasTabs` hook
  # mirrors these rules so a click switches panes before the server confirms.

  @doc """
  Shows `tab` in `pane` (`"primary"` or `"split"`) and returns the new
  `{primary, split}` pair. A tab that is already in the other pane swaps with
  what `pane` showed.
  """
  def place(_primary, nil, _pane, tab), do: {tab, nil}

  def place(primary, split, "split", tab) do
    if tab == primary, do: {split, tab}, else: {primary, tab}
  end

  def place(primary, split, _pane, tab) do
    if tab == split, do: {tab, primary}, else: {tab, split}
  end

  @doc "The tab a new split pane opens with: the agent, or the editor beside it."
  def default_split("agent"), do: "editor"
  def default_split(_primary), do: "agent"

  @doc "The pane that shows `tab`, or nil when it is hidden."
  def pane_of(tab, primary, _split) when tab == primary, do: "primary"
  def pane_of(tab, _primary, split) when tab == split, do: "split"
  def pane_of(_tab, _primary, _split), do: nil

  # The header strip marks the tab in the focused pane; in split view every open
  # tab also names its pane in `data-pane-badge`. The thumbs behind the tabs
  # show it: the `CanvasTabs` hook slides them under the tab each pane shows.
  defp strip_selected?(tab_id, primary, nil, _focus), do: tab_id == primary
  defp strip_selected?(tab_id, primary, split, "split"), do: tab_id == (split || primary)
  defp strip_selected?(tab_id, primary, _split, _focus), do: tab_id == primary

  defp strip_badge(_tab_id, _primary, nil), do: nil

  defp strip_badge(tab_id, primary, split) do
    case pane_of(tab_id, primary, split) do
      "primary" -> "L"
      "split" -> "R"
      nil -> nil
    end
  end

  attr :tabs, :list, required: true
  attr :active_tab, :string, required: true
  attr :split_tab, :string, default: nil
  attr :focus_pane, :string, default: "primary"

  def strip(assigns) do
    ~H"""
    <nav
      id="canvas-tabs"
      role="tablist"
      aria-label="Canvas views"
      data-split={to_string(not is_nil(@split_tab))}
      class="relative hidden items-center gap-0.5 rounded-lg border border-base-content/25 bg-base-content/5 px-1 py-0.5 lg:flex"
    >
      <%!-- One thumb per pane. Drag a thumb (by its tab or its tag) to show
      another tab in that pane; a click moves the focused pane's thumb. --%>
      <span
        :for={{pane, tag} <- [{"primary", "L"}, {"split", "R"}]}
        id={"canvas-tab-thumb-#{pane}"}
        class="canvas-tab-thumb"
        data-pane={pane}
        aria-hidden="true"
      >
        <span class="canvas-tab-thumb-tag" title="Drag to show another tab in this pane">
          {tag}
        </span>
      </span>
      <button
        :for={{tab_id, label, icon, _blurb} <- @tabs}
        type="button"
        role="tab"
        id={"canvas-tab-#{tab_id}"}
        data-tab={tab_id}
        data-pane-badge={strip_badge(tab_id, @active_tab, @split_tab)}
        aria-selected={to_string(strip_selected?(tab_id, @active_tab, @split_tab, @focus_pane))}
        aria-controls={"canvas-panel-#{tab_id}"}
        aria-label={label}
        title={label}
        phx-click="select_tab"
        phx-value-tab={tab_id}
        class="relative z-[1] flex shrink-0 items-center gap-1.5 rounded-md px-2.5 py-1.5 text-sm font-medium transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-primary"
      >
        <.icon name={icon} class="size-4" />
        <%!-- The names are dropped when the header gives the strip less room
        than it needs, so the tabs never overflow into a scrollbar. --%>
        <span class="@max-[28rem]:hidden">{label}</span>
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
        data-pane="primary"
        phx-click="select_tab"
        phx-value-tab={tab_id}
        phx-value-pane="primary"
        class="flex flex-1 shrink-0 flex-col items-center justify-center gap-0.5 rounded-lg px-2 py-1.5 text-[0.7rem] font-medium transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-primary"
      >
        <.icon name={icon} class="size-5" /> <span>{label}</span>
      </button>
    </nav>
    """
  end
end
