defmodule PscWeb.Components.EmptySection do
  @moduledoc """
  An empty state for a section whose content has not been built yet.

  A planned-but-unbuilt section is rendered as a dashed frame rather than
  omitted or left blank: a missing section looks like an oversight, a blank one
  looks broken, and a dashed frame reads as "this is coming". The frame keeps
  the section's place in the layout so the designer's shape does not shift when
  the content lands.

  ## Examples

      <.empty_section
        id="template-analysis-placeholder"
        icon="hero-chart-bar"
        title="Nothing here yet"
        description="Analysis settings for this template are coming soon."
      />
  """

  use Phoenix.Component

  import PscWeb.CoreComponents, only: [icon: 1]

  attr :id, :string, required: true, doc: "The id of the placeholder"
  attr :icon, :string, default: nil, doc: "A heroicon name shown beside the title"
  attr :title, :string, default: "Nothing here yet", doc: "The empty state's title"
  attr :description, :string, default: nil, doc: "One line explaining what is coming"

  def empty_section(assigns) do
    ~H"""
    <div
      id={@id}
      class="flex items-center gap-3 rounded-lg border border-dashed border-base-content/15 bg-base-200/50 px-4 py-5"
    >
      <.icon :if={@icon} name={@icon} class="size-5 shrink-0 text-base-content/30" />
      <div class="min-w-0">
        <p class="text-sm font-medium text-base-content/70">{@title}</p>
        <p :if={@description} class="mt-0.5 text-xs text-base-content/45">{@description}</p>
      </div>
    </div>
    """
  end
end
