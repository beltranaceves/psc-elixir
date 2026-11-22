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

  attr :presence, :map, required: true
  attr :status, :map, required: true
  attr :can_share?, :boolean, required: true
  # The canvas's cells: the fulcrum button reads its mode and active fulcrums.
  attr :cells, :map, default: nil
  attr :controls?, :boolean, default: true

  def header(assigns) do
    ~H"""
    <div
      id="canvas-header"
      class={[
        "shrink-0 items-center justify-end gap-2 px-2 sm:px-0",
        @controls? && "hidden sm:flex",
        not @controls? && "hidden"
      ]}
    >
      <.canvas_status
        :if={@controls?}
        presence={@presence}
        status={@status}
        can_share?={@can_share?}
        cells={@cells}
      />
    </div>
    """
  end

  attr :presence, :map, required: true
  attr :status, :map, required: true
  attr :can_share?, :boolean, required: true
  attr :cells, :map, default: nil
  attr :class, :any, default: nil

  @doc """
  Presence, save state and Share.

  One instance is rendered at a time: the editor toolbar hosts it on the
  Editor tab (from `sm` up), the Agent panel's own top bar hosts it from `sm`
  up while a chat is open, and the header row above the panels hosts it on the
  other tabs (and on the Agent start screen). Both use the same ids, so the
  tests and the hooks do not need to know where it lives.
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

      <%= if @can_share? do %>
        <div class="shrink-0">
          <.share_button id="share-canvas-button" label="Share" />
        </div>
      <% end %>
    </div>
    """
  end

  attr :c_name, :string, required: true

  @doc """
  The canvas title, rendered as the first control of the layout toolbar.

  It keeps the `canvas-name-form` id and the `update_name` event, so the
  title is renamed where it is read: in the grid, the bento board or the
  image board. On a phone the field takes the toolbar's first line and the
  structure controls wrap below it.
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
        class="field-sizing-content h-8 w-full min-w-0 rounded-lg border border-base-content/10 bg-base-200 px-3 text-sm font-semibold leading-8 text-base-content transition-colors placeholder-base-content/40 hover:border-base-content/20 focus:border-primary/50 focus:ring-2 focus:ring-primary/35 focus:ring-inset focus:outline-none sm:w-auto sm:min-w-[6rem] sm:max-w-[28rem]"
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
