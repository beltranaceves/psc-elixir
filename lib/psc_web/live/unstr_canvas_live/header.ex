defmodule PscWeb.UnstrCanvasLive.Header do
  @moduledoc false

  use Phoenix.Component

  import PscWeb.Components.ShareDialog, only: [share_button: 1]
  import PscWeb.Components.StatusPill
  import PscWeb.CoreComponents, only: [icon: 1]

  alias PscWeb.Components.ShareDialog
  alias PscWeb.Components.UI.Button, as: UIButton
  alias PscWeb.Components.UI.Tooltip, as: UITooltip

  attr :canvas, :map, required: true
  attr :c_name, :string, required: true
  attr :c_desc, :string, default: ""
  attr :presence, :map, required: true
  attr :status, :map, required: true
  attr :user_id, :integer, required: true
  attr :can_share?, :boolean, required: true

  def header(assigns) do
    ~H"""
    <div id="canvas-header" class="flex shrink-0 flex-col gap-2 px-2 sm:px-0">
      <div class="flex flex-wrap items-center gap-x-3 gap-y-2 sm:items-start">
        <.form
          for={%{}}
          id="canvas-name-form"
          phx-change="update_name"
          class="order-1 min-w-0 flex-1 sm:flex-none"
        >
          <input
            name="value"
            type="text"
            value={@c_name}
            phx-debounce="1000"
            class="field-sizing-content h-8 w-full min-w-0 border-b-2 border-transparent bg-transparent text-lg font-semibold leading-8 text-base-content transition-colors hover:border-base-content/20 focus:border-primary focus:outline-none sm:w-auto sm:min-w-[6rem] sm:max-w-[24rem]"
            placeholder="Canvas name"
          />
        </.form>

        <%!-- Save state: beside the title on phones, with the other
        actions on larger screens. The badge keeps the same height as the
        other header controls so they line up on one line. Below `sm` the
        app header carries a minimal version instead (see actions/1). --%>
        <div id="canvas-save-state" class="order-2 hidden shrink-0 sm:order-4 sm:block">
          <.status_pill
            id="canvas-save-state-pill"
            save_state={@status.state}
            save_stats={@status.stats}
            label={@status.label}
            others={@status.others}
          />
        </div>

        <.form
          for={%{}}
          id="canvas-description-form"
          phx-change="update_description"
          class="order-3 w-full min-w-0 sm:order-2 sm:w-auto sm:flex-1"
        >
          <textarea
            name="value"
            phx-debounce="1000"
            class="field-sizing-content box-content max-h-12 min-h-8 w-full resize-none overflow-y-auto border-b-2 border-transparent bg-transparent p-0 text-sm leading-6 text-base-content/60 transition-colors placeholder-base-content/35 hover:border-base-content/20 focus:border-primary focus:text-base-content/85 focus:outline-none sm:max-h-16 sm:leading-8"
            placeholder="Add a description..."
            rows="1"
          ><%= @c_desc %></textarea>
        </.form>
        <%!-- Active users: truncated, with the full list in a hover tooltip --%>
        <div id="canvas-presence" class="order-4 hidden sm:order-3 sm:block">
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

        <%= if @can_share? do %>
          <div class="order-5 ml-auto hidden sm:ml-0 sm:block">
            <.share_button id="share-canvas-button" label="Share" />
          </div>
        <% end %>
      </div>
    </div>
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
