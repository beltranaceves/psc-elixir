defmodule PscWeb.UnstrCanvasLive.Header do
  @moduledoc false

  use Phoenix.Component

  import PscWeb.Components.ShareDialog, only: [share_button: 1]
  import PscWeb.Components.StatusPill
  import PscWeb.CoreComponents, only: [icon: 1]

  alias PscWeb.Components.ShareDialog
  alias PscWeb.Components.UI.Button, as: UIButton
  alias PscWeb.Components.UI.Tooltip, as: UITooltip

  attr :presence, :map, required: true
  attr :status, :map, required: true
  attr :can_share?, :boolean, required: true

  def header(assigns) do
    ~H"""
    <div
      id="canvas-header"
      class="hidden shrink-0 items-center justify-end gap-2 px-2 sm:flex sm:px-0"
    >
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

      <%= if @can_share? do %>
        <div>
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
        class="field-sizing-content h-8 w-full min-w-0 border-b-2 border-transparent bg-transparent text-base font-semibold leading-8 text-base-content transition-colors hover:border-base-content/20 focus:border-primary focus:outline-none sm:w-auto sm:min-w-[6rem] sm:max-w-[28rem]"
      />
    </.form>
    """
  end

  attr :presence, :map, required: true
  attr :status, :map, required: true
  attr :can_share?, :boolean, required: true

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
