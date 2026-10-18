defmodule PscWeb.Components.ShareDialog do
  @moduledoc """
  Sharing UI shared by templates, canvases and documents.

  `share_button/1` is the combo trigger (share icon + current label);
  `share_dialog/1` is the modal it opens, containing the invite form, the list of
  people with access, and an optional copy-link row.

  The owning LiveView supplies the event names so each context keeps its own
  handlers (`share_template`/`unshare_template`, `share_canvas`/`remove_access`,
  ...) and owns the `@share_open` assign.
  """

  use Phoenix.Component

  import PscWeb.CoreComponents, only: [icon: 1]

  alias PscWeb.Components.UI.Button, as: UIButton
  alias PscWeb.Components.UI.Dialog, as: UIDialog
  alias PscWeb.Components.UI.Input, as: UIInput

  @doc """
  Combo trigger: the classic share icon next to the current button text.
  """
  attr :id, :string, required: true
  attr :label, :string, default: "Share"
  attr :event, :string, default: "open_share"
  attr :variant, :string, default: "outline"
  attr :size, :string, default: "sm"
  attr :class, :string, default: nil

  def share_button(assigns) do
    ~H"""
    <UIButton.button
      type="button"
      id={@id}
      phx-click={@event}
      variant={@variant}
      size={@size}
      class={["gap-1.5", @class]}
    >
      <.icon name="hero-share" class="size-4" /> <span>{@label}</span>
    </UIButton.button>
    """
  end

  @doc """
  The sharing modal.

  * `:manage?` — owner only controls (invite form and remove buttons).
  * `:shared_with` — emails already granted access.
  * `:share_event` / `:remove_event` — server events handled by the caller.
  * `:on_close` — event pushed when the dialog closes (Escape/outside/×/Done).
  * `:link` — optional URL to copy.
  """
  attr :id, :string, required: true
  attr :open, :boolean, default: false
  attr :title, :string, default: "Share"
  attr :description, :string, default: nil
  attr :manage?, :boolean, default: false
  attr :shared_with, :list, default: []
  attr :share_event, :string, required: true
  attr :remove_event, :string, required: true
  attr :on_close, :string, default: "share_closed"
  attr :link, :string, default: nil
  attr :empty_text, :string, default: "Only you have access right now."

  def share_dialog(assigns) do
    ~H"""
    <UIDialog.dialog id={@id} open={@open} on-close={@on_close}>
      <UIDialog.dialog_content class="sm:max-w-md">
        <UIDialog.dialog_header>
          <UIDialog.dialog_title>{@title}</UIDialog.dialog_title>

          <UIDialog.dialog_description :if={@description}>{@description}</UIDialog.dialog_description>
        </UIDialog.dialog_header>

        <div class="space-y-4">
          <form
            :if={@manage?}
            id={"#{@id}-form"}
            phx-submit={@share_event}
            class="flex gap-2"
          >
            <UIInput.input
              type="email"
              name="email"
              placeholder="user@example.com"
              required
              class="flex-1"
            /> <UIButton.button type="submit" size="sm">Share</UIButton.button>
          </form>

          <div>
            <p class="mb-2 text-xs font-medium uppercase tracking-wide text-base-content/50">
              People with access
            </p>

            <p :if={@shared_with == []} class="text-sm text-base-content/50">
              {@empty_text}
            </p>

            <ul :if={@shared_with != []} class="space-y-1.5">
              <li
                :for={email <- @shared_with}
                data-email={email}
                class="flex items-center justify-between gap-2 rounded-lg border border-base-content/10 bg-base-200 px-3 py-2"
              >
                <span class="truncate text-sm text-base-content/80">{email}</span>
                <button
                  :if={@manage?}
                  type="button"
                  phx-click={@remove_event}
                  phx-value-email={email}
                  class="inline-flex size-5 shrink-0 items-center justify-center rounded-md border border-error/40 text-error transition-colors hover:border-error hover:bg-error/10"
                  title={"Remove access for #{email}"}
                  aria-label={"Remove access for #{email}"}
                >
                  <.icon name="hero-x-mark" class="size-3" />
                </button>
              </li>
            </ul>
          </div>

          <div :if={@link}>
            <p class="mb-2 text-xs font-medium uppercase tracking-wide text-base-content/50">
              Share link
            </p>

            <div class="flex gap-2">
              <input
                type="text"
                readonly
                id={"#{@id}-link"}
                value={@link}
                class="min-w-0 flex-1 rounded-lg border border-base-content/10 bg-base-300 px-3 py-2 font-mono text-xs text-base-content/70"
              />
              <button
                type="button"
                id={"#{@id}-copy"}
                onclick={"navigator.clipboard.writeText('#{@link}')"}
                class="rounded-lg bg-primary px-3 py-2 text-xs font-medium text-primary-content transition-opacity hover:opacity-90"
              >
                Copy
              </button>
            </div>
          </div>
        </div>

        <UIDialog.dialog_footer>
          <UIButton.button type="button" variant="outline" phx-click={@on_close}>
            Done
          </UIButton.button>
        </UIDialog.dialog_footer>
      </UIDialog.dialog_content>
    </UIDialog.dialog>
    """
  end
end
