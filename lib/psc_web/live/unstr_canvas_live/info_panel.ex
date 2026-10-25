defmodule PscWeb.UnstrCanvasLive.InfoPanel do
  @moduledoc """
  The Info view of a canvas: the details that are not part of the editing
  surface (name, description), who the canvas is shared with, and the
  read-only facts about it.

  The name keeps its own form id here, because the editor toolbar renders the
  same value under `canvas-name-form`. Both forms send `update_name`, both are
  bound to the LiveView's `c_name`, and only one panel is visible at a time.
  """

  use Phoenix.Component

  import PscWeb.Components.Section, only: [section: 1]
  import PscWeb.CoreComponents, only: [icon: 1]

  alias Psc.Canvas.Structure
  alias PscWeb.Components.UI.Button, as: UIButton

  attr :canvas, :map, required: true
  attr :cells, :map, required: true
  attr :c_name, :string, required: true
  attr :c_desc, :string, default: ""
  attr :can_share?, :boolean, required: true

  def panel(assigns) do
    ~H"""
    <div id="canvas-info" class="min-h-0 w-full flex-1 overflow-y-auto">
      <div class="mx-auto w-full max-w-2xl space-y-3 pb-2">
        <.section id="canvas-info-details" title="Details" hint="Name and description">
          <div class="space-y-4">
            <.form for={%{}} id="canvas-info-name-form" phx-change="update_name">
              <label
                for="canvas-info-name"
                class="mb-1 block text-xs font-medium uppercase tracking-wide text-base-content/50"
              >
                Name
              </label>

              <input
                id="canvas-info-name"
                name="value"
                type="text"
                value={@c_name}
                phx-debounce="1000"
                placeholder="Untitled canvas"
                class="w-full rounded-lg border border-base-content/15 bg-base-100 px-3 py-2 text-sm text-base-content transition-colors placeholder-base-content/35 focus:border-primary focus:outline-none"
              />
            </.form>

            <.form for={%{}} id="canvas-description-form" phx-change="update_description">
              <label
                for="canvas-info-description"
                class="mb-1 block text-xs font-medium uppercase tracking-wide text-base-content/50"
              >
                Description
              </label>
              <textarea
                id="canvas-info-description"
                name="value"
                rows="4"
                phx-debounce="1000"
                placeholder="What is this canvas for?"
                class="w-full resize-y rounded-lg border border-base-content/15 bg-base-100 px-3 py-2 text-sm leading-6 text-base-content transition-colors placeholder-base-content/35 focus:border-primary focus:outline-none"
              ><%= @c_desc %></textarea>
            </.form>
          </div>
        </.section>

        <.section
          id="canvas-info-sharing"
          title="Sharing"
          hint={shared_hint(@canvas.shared_with || [])}
        >
          <div class="flex flex-col gap-3">
            <ul
              :if={@canvas.shared_with != []}
              id="canvas-info-shared-with"
              class="divide-y divide-base-content/10 rounded-lg border border-base-content/10 bg-base-100"
            >
              <li
                :for={email <- @canvas.shared_with}
                class="truncate px-3 py-2 text-sm text-base-content/80"
              >
                {email}
              </li>
            </ul>

            <p :if={@canvas.shared_with == []} class="text-sm text-base-content/60">
              Only you have access. Anyone you share with can edit this canvas with you in
              real time.
            </p>

            <div>
              <UIButton.button
                :if={@can_share?}
                type="button"
                id="info-share-button"
                variant="outline"
                size="sm"
                phx-click="open_share"
              >
                <.icon name="hero-users" class="size-4" /> Manage access
              </UIButton.button>

              <p :if={!@can_share?} class="text-xs text-base-content/50">
                Only the canvas owner can change access.
              </p>
            </div>
          </div>
        </.section>

        <.section id="canvas-info-about" title="About" hint="Layout, notes and ownership">
          <dl class="grid grid-cols-[minmax(5rem,auto)_1fr] items-baseline gap-x-4 gap-y-2 text-sm">
            <dt class="text-base-content/50">Layout</dt>

            <dd class="text-base-content">{layout_label(@cells)}</dd>

            <dt class="text-base-content/50">Notes</dt>

            <dd class="text-base-content">{notes_label(@canvas.notes_mode)}</dd>

            <dt :if={@canvas.author} class="text-base-content/50">Owner</dt>

            <dd :if={@canvas.author} class="truncate text-base-content">
              {@canvas.author.email}
            </dd>

            <dt class="text-base-content/50">Created</dt>

            <dd class="text-base-content">{created_at_label(@canvas.inserted_at)}</dd>
          </dl>
        </.section>
      </div>
    </div>
    """
  end

  defp shared_hint([]), do: "Only you"
  defp shared_hint([_email]), do: "1 person"
  defp shared_hint(emails), do: "#{length(emails)} people"

  defp layout_label(cells) do
    case Structure.mode(cells) do
      :bento -> "Bento board"
      :image -> "Image board"
      _ -> "Table"
    end
  end

  defp notes_label("single"), do: "Scratchpad (single note)"
  defp notes_label(_mode), do: "Multiple notes"

  defp created_at_label(nil), do: "—"
  defp created_at_label(%DateTime{} = at), do: Calendar.strftime(at, "%b %-d, %Y")
  defp created_at_label(%NaiveDateTime{} = at), do: Calendar.strftime(at, "%b %-d, %Y")
end
