defmodule PscWeb.Components.Section do
  @moduledoc """
  A collapsible section of the template designer.

  The section is a native `<details>` element, so it opens and closes without
  any JavaScript, is reachable from the keyboard, and announces itself as a
  disclosure to a screen reader.

  The open state belongs to the browser, not to the server. LiveView patches
  the page on every keystroke, and a patched `<details>` would snap back to
  whatever the server last rendered — so the `open` attribute is marked as
  ignored (`Phoenix.LiveView.JS.ignore_attributes/2`) and the browser keeps
  the state it has. The server's `open` is only the state a section starts in.

  Nothing interactive belongs in the summary: a button inside it would toggle
  the section as well as run its own action.
  """

  use Phoenix.Component

  import PscWeb.CoreComponents, only: [icon: 1]

  alias Phoenix.LiveView.JS

  @doc """
  Renders a collapsible section.

  ## Examples

      <.section id="notes" title="Notes" hint="2 notes" open>
        ...
      </.section>
  """
  attr :id, :string, required: true, doc: "The id of the section"
  attr :title, :string, required: true, doc: "The section title, shown in the summary"
  attr :hint, :string, default: nil, doc: "A short summary of the section's content"
  attr :open, :boolean, default: true, doc: "Whether the section starts open"
  attr :class, :string, default: nil, doc: "Additional classes for the section"

  slot :inner_block, required: true, doc: "The section content"

  def section(assigns) do
    ~H"""
    <details
      id={@id}
      open={@open}
      phx-mounted={JS.ignore_attributes(["open"])}
      class={[
        "group overflow-hidden rounded-xl border border-base-content/10 bg-base-200",
        @class
      ]}
    >
      <summary class="flex cursor-pointer list-none items-center gap-3 px-4 py-3 transition-colors hover:bg-base-content/5 [&::-webkit-details-marker]:hidden">
        <h2 class="text-sm font-medium text-base-content">{@title}</h2>
        <span :if={@hint} class="truncate text-xs text-base-content/50">{@hint}</span>
        <.icon
          name="hero-chevron-down"
          class="ml-auto size-4 shrink-0 text-base-content/40 transition-transform duration-200 group-open:rotate-180"
        />
      </summary>

      <div class="border-t border-base-content/10 px-4 py-4 sm:px-6">
        {render_slot(@inner_block)}
      </div>
    </details>
    """
  end
end
