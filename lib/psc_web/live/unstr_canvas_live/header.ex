defmodule PscWeb.UnstrCanvasLive.Header do
  @moduledoc false

  use Phoenix.Component

  import PscWeb.Components.Accent, only: [swatch_class: 1]
  import PscWeb.Components.ShareDialog, only: [share_button: 1]
  import PscWeb.Components.StatusPill
  import PscWeb.CoreComponents, only: [icon: 1]

  alias Psc.Canvas.Fulcrums
  alias PscWeb.Components.FulcrumEditor
  alias PscWeb.Components.ShareDialog
  alias PscWeb.Components.UI.Button, as: UIButton
  alias PscWeb.Components.UI.Tooltip, as: UITooltip

  # The Fulcrums button shows the active fulcrums as colour dots. Hovering it (or
  # tabbing to it) opens the picker pills; a tap opens the selector dialog.
  # Hover only exists on pointer devices, so a phone never shows the pills.
  attr :cells, :map, required: true
  # The phone cluster has the button but no picker: a tap opens the dialog.
  attr :compact?, :boolean, default: false

  defp fulcrum_menu(assigns) do
    fulcrums = Fulcrums.list(assigns.cells)
    active = Fulcrums.active_ids(assigns.cells)

    assigns =
      assign(assigns,
        fulcrums: fulcrums,
        active: active,
        active_fulcrums: Enum.filter(fulcrums, &(&1["id"] in active)),
        mode: Fulcrums.mode(assigns.cells)
      )

    ~H"""
    <div class="group/fulcrums relative shrink-0">
      <UIButton.button
        type="button"
        id={if @compact?, do: "fulcrums-canvas-button-compact", else: "fulcrums-canvas-button"}
        phx-click="open_fulcrums"
        variant="outline"
        size="sm"
        class="gap-1.5"
        title="Fulcrums: pick which ones to highlight"
      >
        <.icon name="hero-swatch" class="size-4" /> <span class="hidden sm:inline">Fulcrums</span>
        <span
          :for={fulcrum <- @active_fulcrums}
          class={["size-2.5 rounded-full", swatch_class(fulcrum["color"])]}
          aria-hidden="true"
        ></span>
      </UIButton.button>

      <div
        :if={not @compact? and @fulcrums != [] and @mode != "off"}
        class={[
          "invisible absolute right-0 top-full z-50 w-max pt-1.5 opacity-0 transition-opacity",
          "group-hover/fulcrums:visible group-hover/fulcrums:opacity-100",
          "group-has-[:focus-visible]/fulcrums:visible group-has-[:focus-visible]/fulcrums:opacity-100"
        ]}
      >
        <div class="max-w-[min(90vw,28rem)] rounded-xl border border-base-content/10 bg-base-200 p-2 shadow-lg">
          <FulcrumEditor.picker fulcrums={@fulcrums} active_ids={@active} mode={@mode} />
        </div>
      </div>
    </div>
    """
  end

  # The Export button: hovering it (or focusing it, which a tap does) shows the
  # formats. Each one asks the LiveView to render the board off screen, and the
  # `CanvasExport` hook turns that render into a file.
  attr :compact?, :boolean, default: false

  defp export_menu(assigns) do
    assigns = assign(assigns, :suffix, if(assigns.compact?, do: "-compact", else: ""))

    ~H"""
    <div class="group/export relative shrink-0">
      <UIButton.button
        type="button"
        id={"export-canvas-button" <> @suffix}
        variant="outline"
        size={if @compact?, do: "icon", else: "sm"}
        class={if @compact?, do: "!size-8 rounded-full", else: "gap-1.5"}
        aria-haspopup="menu"
        aria-label="Export"
        title="Export this canvas"
      >
        <.icon name="hero-arrow-down-tray" class="size-4" />
        <span :if={!@compact?}>Export</span>
      </UIButton.button>

      <div class={[
        "invisible absolute right-0 top-full z-50 w-max pt-1.5 opacity-0 transition-opacity",
        "group-hover/export:visible group-hover/export:opacity-100",
        "group-focus-within/export:visible group-focus-within/export:opacity-100"
      ]}>
        <div
          role="menu"
          class="flex min-w-44 flex-col rounded-xl border border-base-content/10 bg-base-200 p-1 shadow-lg"
        >
          <button
            :for={{format, label, detail} <- export_formats()}
            type="button"
            role="menuitem"
            id={"export-" <> format <> @suffix}
            phx-click="export_canvas"
            phx-value-format={format}
            class="flex flex-col items-start rounded-lg px-3 py-1.5 text-left hover:bg-base-content/5 focus:bg-base-content/5 focus:outline-none"
          >
            <span class="text-sm font-medium text-base-content">{label}</span>
            <span class="text-xs text-base-content/55">{detail}</span>
          </button>

          <%!-- Markdown is a document, not a picture: a dialog asks which parts
          of the canvas to include. --%>
          <button
            type="button"
            role="menuitem"
            id={"export-markdown" <> @suffix}
            phx-click="open_markdown_export"
            class="flex flex-col items-start rounded-lg px-3 py-1.5 text-left hover:bg-base-content/5 focus:bg-base-content/5 focus:outline-none"
          >
            <span class="text-sm font-medium text-base-content">Markdown</span>
            <span class="text-xs text-base-content/55">Text, notes, analysis and more</span>
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp export_formats do
    [
      {"png", "PNG image", "A picture of the whole board"},
      {"svg", "SVG", "Sharp at any size; opens in browsers"}
    ]
  end

  attr :c_name, :string, required: true
  attr :presence, :map, required: true
  attr :status, :map, required: true
  attr :can_share?, :boolean, required: true
  # The canvas's cells: the fulcrum button reads its mode and active fulcrums.
  attr :cells, :map, default: nil

  @doc """
  The canvas row above the panels: the title, then presence, save state and
  the canvas actions (Pivot, Fulcrums, Export, Share, Split).

  They act on the whole canvas, not on one view, so they live here on every
  tab and in both panes of split view. A tab switch or a moved divider never
  moves them; only the viewport's width can wrap the row. On a phone the row
  holds the title alone: the app header carries the compact cluster.
  """
  def header(assigns) do
    ~H"""
    <div
      id="canvas-header"
      class="flex shrink-0 flex-wrap items-center gap-2 px-2 sm:px-0"
    >
      <div class="min-w-[8rem] flex-1">
        <.title_field c_name={@c_name} />
      </div>
      <div class="ml-auto hidden sm:flex">
        <.canvas_status
          presence={@presence}
          status={@status}
          can_share?={@can_share?}
          cells={@cells}
        />
      </div>
    </div>
    """
  end

  attr :presence, :map, required: true
  attr :status, :map, required: true
  attr :can_share?, :boolean, required: true
  attr :cells, :map, default: nil
  attr :class, :any, default: nil

  @doc """
  Presence, save state and the canvas actions, in the canvas row
  (`header/1`) from `sm` up.
  """
  def canvas_status(assigns) do
    ~H"""
    <div class={["flex min-w-0 items-center gap-2", @class]}>
      <%!-- Active users: truncated, with the full list in a hover tooltip --%>
      <div id="canvas-presence">
        <UITooltip.tooltip id="active-users-tooltip">
          <UITooltip.tooltip_trigger>
            <button
              type="button"
              class="inline-flex h-8 max-w-[13rem] items-center gap-2 rounded-full border border-base-content/10 px-3 text-xs text-base-content/70 transition-colors hover:border-base-content/20 hover:bg-base-content/5 hover:text-base-content focus:outline-none focus-visible:ring-2 focus-visible:ring-primary"
            >
              <span class="relative flex size-2 shrink-0">
                <span class="absolute inline-flex size-full rounded-full bg-success/50"></span>
                <span class="relative inline-flex size-2 rounded-full bg-success"></span>
              </span>
              <span class="truncate lg:hidden">{active_users_compact_label(@presence)}</span>
              <span class="hidden truncate lg:inline">
                {active_users_label(active_usernames(@presence))}
              </span>
            </button>
          </UITooltip.tooltip_trigger>
          <.active_users_list presence={@presence} />
        </UITooltip.tooltip>
      </div>

      <div id="canvas-save-state" class="shrink-0">
        <.status_pill
          id="canvas-save-state-pill"
          save_state={@status.state}
          save_stats={@status.stats}
          label={@status.label}
          others={@status.others}
        />
      </div>

      <div class="shrink-0">
        <UIButton.button
          type="button"
          id="pivot-canvas-button"
          phx-click="open_pivot"
          variant="outline"
          size="sm"
          class="gap-1.5"
          title="Save this version with the reason for the change"
        >
          <.icon name="hero-flag" class="size-4" /> <span>Pivot</span>
        </UIButton.button>
      </div>

      <.fulcrum_menu :if={@cells && Fulcrums.enabled?(@cells)} cells={@cells} />

      <.export_menu />

      <%= if @can_share? do %>
        <div class="shrink-0">
          <.share_button id="share-canvas-button" label="Share" />
        </div>
      <% end %>

      <.split_switch :if={Map.has_key?(@status, :split?)} on?={@status.split?} />
    </div>
    """
  end

  attr :on?, :boolean, required: true

  # Split view is a desktop layout, so the switch only shows from `lg` up. It
  # is server state: the knob moves once the layout comes back.
  defp split_switch(assigns) do
    ~H"""
    <button
      type="button"
      id="canvas-split-toggle"
      role="switch"
      aria-checked={to_string(@on?)}
      phx-click="toggle_split"
      title={if @on?, do: "Show one view", else: "Show two views side by side"}
      class={[
        "group hidden h-8 shrink-0 items-center gap-2 rounded-full border pl-3 pr-1.5 text-xs font-medium transition-colors lg:inline-flex",
        "focus:outline-none focus-visible:ring-2 focus-visible:ring-primary",
        if(@on?,
          do: "border-primary/40 text-base-content",
          else:
            "border-base-content/10 text-base-content/70 hover:border-base-content/20 hover:bg-base-content/5 hover:text-base-content"
        )
      ]}
    >
      <.icon name="hero-view-columns" class="size-4" />
      <span>Split</span>
      <span class={[
        "relative inline-flex h-5 w-9 shrink-0 items-center rounded-full transition-colors",
        if(@on?, do: "bg-primary", else: "bg-base-content/20")
      ]}>
        <span class={[
          "absolute left-0.5 size-4 rounded-full bg-base-100 shadow-sm transition-transform",
          @on? && "translate-x-4"
        ]}></span>
      </span>
    </button>
    """
  end

  attr :c_name, :string, required: true

  @doc """
  The canvas title, the first control of the canvas row (`header/1`).

  It keeps the `canvas-name-form` id and the `update_name` event; the Info tab
  renames the canvas too.
  """
  def title_field(assigns) do
    ~H"""
    <.form for={%{}} id="canvas-name-form" phx-change="update_name" class="min-w-0">
      <input
        name="value"
        type="text"
        value={@c_name}
        phx-debounce="1000"
        title={@c_name}
        aria-label="Canvas name"
        placeholder="Untitled canvas"
        class="field-sizing-content h-8 w-full min-w-0 rounded-lg border border-base-content/10 bg-base-200 px-3 text-sm font-semibold leading-8 text-base-content transition-colors placeholder-base-content/40 hover:border-base-content/20 focus:border-primary/50 focus:ring-2 focus:ring-primary/35 focus:ring-inset focus:outline-none sm:w-auto sm:min-w-[6rem] sm:max-w-[min(28rem,100%)]"
      />
    </.form>
    """
  end

  attr :presence, :map, required: true
  attr :status, :map, required: true
  attr :can_share?, :boolean, required: true
  attr :cells, :map, default: nil

  def actions(assigns) do
    ~H"""
    <div class="flex items-center gap-1 sm:hidden">
      <UITooltip.tooltip id="active-users-tooltip-compact">
        <UITooltip.tooltip_trigger>
          <button
            type="button"
            id="canvas-presence-compact"
            class="inline-flex h-8 items-center gap-1.5 rounded-full border border-base-content/10 px-2.5 text-xs tabular-nums text-base-content/70 transition-colors hover:bg-base-content/5"
            title={active_users_compact_label(@presence)}
            aria-label={active_users_compact_label(@presence)}
          >
            <span class="relative flex size-2 shrink-0">
              <span class="absolute inline-flex size-full rounded-full bg-success/50"></span>
              <span class="relative inline-flex size-2 rounded-full bg-success"></span>
            </span>
            <span>{active_user_count(@presence)}</span>
          </button>
        </UITooltip.tooltip_trigger>
        <.active_users_list presence={@presence} />
      </UITooltip.tooltip>

      <.fulcrum_menu :if={@cells && Fulcrums.enabled?(@cells)} cells={@cells} compact? />

      <.status_pill
        id="canvas-save-state-compact"
        save_state={@status.state}
        save_stats={@status.stats}
        label={@status.label}
        others={@status.others}
        compact
      />
      <.export_menu compact? />
      <%= if @can_share? do %>
        <UIButton.button
          type="button"
          id="share-canvas-button-compact"
          phx-click="open_share"
          variant="outline"
          size="icon"
          class="!size-8 rounded-full"
          aria-label="Share"
          title="Share"
        >
          <.icon name="hero-share" class="size-4" />
        </UIButton.button>
      <% end %>
    </div>
    """
  end

  attr :canvas, :map, required: true
  attr :share_open, :boolean, required: true
  attr :can_share?, :boolean, required: true

  def share_dialog(assigns) do
    ~H"""
    <ShareDialog.share_dialog
      id="share-canvas-dialog"
      open={@share_open}
      title="Share canvas"
      description="People with access can edit this canvas with you in real time."
      manage?={@can_share?}
      shared_with={@canvas.shared_with || []}
      share_event="share_canvas"
      remove_event="remove_access"
      on_close="share_closed"
    />
    """
  end

  attr :presence, :map, required: true

  defp active_users_list(assigns) do
    ~H"""
    <UITooltip.tooltip_content side="bottom" align="end" class="w-64 px-3 py-2.5">
      <p class="mb-1 text-[0.7rem] font-medium uppercase tracking-wide text-base-content/50">
        Active users
      </p>

      <ul class="space-y-1">
        <li
          :for={username <- active_usernames(@presence)}
          class="truncate text-sm text-base-content/80"
        >
          {username}
        </li>
      </ul>
    </UITooltip.tooltip_content>
    """
  end

  defp active_usernames(presence) do
    for {_user_id, %{metas: [meta | _]}} <- presence, do: meta[:username]
  end

  defp active_users_label([]), do: "No one online"
  defp active_users_label([username]), do: username
  defp active_users_label([username | rest]), do: "#{username} +#{length(rest)}"

  # A short presence label for narrow screens, where the full e-mail address
  # would not fit next to the other actions.
  defp active_users_compact_label(presence) do
    case active_usernames(presence) do
      [] -> "Offline"
      [_one] -> "1 online"
      many -> "#{length(many)} online"
    end
  end

  defp active_user_count(presence), do: length(active_usernames(presence))
end
