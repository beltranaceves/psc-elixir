defmodule PscWeb.Components.StatusPill do
  @moduledoc """
  The save-status pill: the current state, with a tooltip that reports what
  the editor has been doing.

  Hovering opens the tooltip on a desktop; a tap opens it on a phone, where
  there is no hover. The phone rendering is the *same badge* as the desktop one
  with the label dropped, so the state colours cannot drift apart: **Saved** is
  primary, **Saving** secondary and **Unsaved** the warning colour (ADR-028).

  The statistics are the caller's: a canvas's pill counts the canvas's writes,
  a note's pill counts the note's.
  """

  use Phoenix.Component

  import PscWeb.CoreComponents, only: [icon: 1]

  alias PscWeb.Components.UI.Badge, as: UIBadge
  alias PscWeb.Components.UI.Tooltip, as: UITooltip

  @doc """
  The status pill.

  * `:id` — the id of the pill element.
  * `:save_state` — `:saving`, `:saved` or anything else (unsaved).
  * `:save_stats` — the statistics the tooltip reports: `writes`, `failures`,
    `last_saved_at` and `last_write_ms`.
  * `:compact` — render the icon-only form, for a narrow header.
  """
  attr :id, :string, required: true
  attr :save_state, :atom, required: true
  attr :save_stats, :map, required: true
  attr :label, :string, default: nil
  attr :others, :list, default: []
  attr :compact, :boolean, default: false

  def status_pill(assigns) do
    assigns = assign(assigns, :sections, sections(assigns))

    ~H"""
    <UITooltip.tooltip id={"#{@id}-tooltip"}>
      <UITooltip.tooltip_trigger>
        <UIBadge.badge
          id={@id}
          variant={status_variant(@save_state)}
          class={status_pill_class(@save_state, @compact)}
          role={@compact && "img"}
          aria-label={@compact && save_state_label(@save_state)}
        >
          <%= if @save_state == :saving do %>
            <span class="size-3.5 rounded-full border-2 border-current border-t-transparent animate-spin"></span>
          <% else %>
            <.icon name={status_icon(@save_state)} class="size-5" />
          <% end %>
          <span :if={!@compact}>{save_state_pill_label(@save_state)}</span>
        </UIBadge.badge>
      </UITooltip.tooltip_trigger>

      <UITooltip.tooltip_content side="bottom" align="end" class="w-64 px-3 py-2.5">
        <p class="mb-2 flex items-center gap-1.5 text-sm font-medium text-base-content">
          <.icon name={status_icon(@save_state)} class={status_icon_class(@save_state)} /> {save_state_label(
            @save_state
          )}
        </p>

        <%= for {section, index} <- Enum.with_index(@sections) do %>
          <dl class={[
            "space-y-1 text-xs text-base-content/70",
            index > 0 && "mt-2 border-t border-base-content/10 pt-2"
          ]}>
            <p
              :if={length(@sections) > 1}
              class="mb-1 text-[0.7rem] font-medium uppercase tracking-wide text-base-content/50"
            >
              {section.label}
            </p>

            <div class="flex items-baseline justify-between gap-3">
              <dt>Last saved</dt>

              <dd class="text-right text-base-content">
                {last_saved_label(section.stats)}
              </dd>
            </div>

            <div class="flex items-baseline justify-between gap-3">
              <dt>Writes this session</dt>

              <dd class="text-right text-base-content">{section.stats.writes}</dd>
            </div>

            <div :if={section.stats.failures > 0} class="flex items-baseline justify-between gap-3">
              <dt class="text-error">Failed writes</dt>

              <dd class="text-right text-error">{section.stats.failures}</dd>
            </div>

            <div :if={section.stats.last_write_ms} class="flex items-baseline justify-between gap-3">
              <dt>Last write took</dt>

              <dd class="text-right text-base-content">{section.stats.last_write_ms} ms</dd>
            </div>
          </dl>
        <% end %>
      </UITooltip.tooltip_content>
    </UITooltip.tooltip>
    """
  end

  # The primary source, plus any other surface whose figures are reported
  # alongside it. A section is `%{label: ..., state: ..., stats: ...}`.
  defp sections(assigns) do
    primary = %{
      label: assigns.label,
      state: assigns.save_state,
      stats: assigns.save_stats
    }

    [primary | assigns.others]
  end

  # The terse label for the pill itself; the descriptive one is for the
  # tooltip and for screen readers.
  defp save_state_pill_label(:saving), do: "Saving..."
  defp save_state_pill_label(:saved), do: "Saved"
  defp save_state_pill_label(_), do: "Unsaved"

  defp save_state_label(:saving), do: "Saving..."
  defp save_state_label(:saved), do: "Saved"
  defp save_state_label(_), do: "Unsaved changes"

  defp status_icon(:saving), do: "hero-arrow-path"
  defp status_icon(:saved), do: "hero-check-circle"
  defp status_icon(_), do: "hero-exclamation-circle"

  # The state colours, used where the icon stands on its own (the tooltip's
  # heading). Inside the badge the icon inherits the badge's colour.
  defp status_icon_class(:saving), do: "size-5 animate-spin text-secondary"
  defp status_icon_class(:saved), do: "size-5 text-primary"
  defp status_icon_class(_), do: "size-5 text-warning"

  defp status_variant(:saving), do: "secondary"
  defp status_variant(:saved), do: "default"
  defp status_variant(_), do: "outline"

  # The badge classes for the pill. The phone renders the same badge as the
  # desktop — only the label is dropped — so the two can never drift apart.
  defp status_pill_class(state, compact) do
    [
      "shrink-0",
      if(compact, do: "!size-8 justify-center !p-0", else: "h-8"),
      # "Unsaved" is the one state the outline variant gives no colour of its
      # own, so the warning token goes on top of it. The `!` prefix is needed:
      # the variant sets a text colour of its own.
      if(state in [:saved, :saving], do: "", else: "!text-warning !border-warning/40")
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end

  # "just now" / "2 min ago" — how long ago the last write landed.
  defp last_saved_label(%{last_saved_at: nil}), do: "not yet"

  defp last_saved_label(%{last_saved_at: at}) do
    seconds = DateTime.diff(DateTime.utc_now(), at, :second)

    cond do
      seconds < 5 -> "just now"
      seconds < 60 -> "#{seconds} seconds ago"
      seconds < 3600 -> "#{div(seconds, 60)} min ago"
      seconds < 86_400 -> "#{div(seconds, 3600)} h ago"
      true -> "#{div(seconds, 86_400)} d ago"
    end
  end
end
