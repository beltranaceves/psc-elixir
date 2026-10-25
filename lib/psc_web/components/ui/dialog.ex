defmodule PscWeb.Components.UI.Dialog do
  @moduledoc """
  Implement of Dialog components from https://ui.shadcn.com/docs/components/dialog

  ## Component events

  * `:on-open` - Maps the `open` event. Fired when dialog enters open state.
  * `:on-close` - Maps the `close` event. Fired when dialog enters closed state.

  ## Server commands

  * `"open"` - Opens the dialog.
  * `"close"` - Closes the dialog.
  """
  use PscWeb.Components.UI, :component

  @doc """
  Dialog component

  ## Component events

  * `:on-open` - Fired when the dialog opens.
  * `:on-close` - Fired when the dialog closes.

  ## Server commands

  * `"open"` - Opens the dialog.
  * `"close"` - Closes the dialog.

  ## Examples:

      <.dialog id="pro-dialog" open={true}>
        <.dialog_trigger>Click me</.dialog_trigger>
        <.dialog_content open={true} class="sm:max-w-[425px]">
          <.dialog_header>
            <.dialog_title>Edit profile</.dialog_title>
            <.dialog_description>
              Make changes to your profile here click save when you're done
            </.dialog_description>
          </.dialog_header>
          <div class_name="grid gap-4 py-4">
            <div class_name="grid grid-cols_4 items-center gap-4">
              <.label for="name" class-name="text-right">
                name
              </.label>
              <input id="name" value="pedro duarte" class-name="col-span-3" />
            </div>
            <div class="grid grid-cols-4 items_center gap-4">
              <.label for="username" class="text-right">
                username
              </.label>
              <input id="username" value="@peduarte" class="col-span-3" />
            </div>
          </div>
          <.dialog_footer>
            <.button type="submit">save changes</.button>
          </.dialog_footer>
        </.dialog_content>
      </.dialog>
  """

  attr :id, :string, required: true
  attr :open, :boolean, default: false
  attr :class, :string, default: nil
  attr :"close-on-outside-click", :boolean, default: true

  attr :"on-open", :any,
    default: nil,
    doc: "Handler for dialog open event. Support both server event handler and JS command struct"

  attr :"on-close", :any,
    default: nil,
    doc:
      "Handler for dialog closed event. Support both server event handler and JS command struct"

  slot :inner_block, required: true

  def dialog(assigns) do
    event_map = event_mappings(assigns)

    assigns =
      assigns
      |> assign(:event_map, json(event_map))
      |> assign(initial_state: if(assigns.open, do: "open", else: "closed"))
      |> assign(
        options:
          json(%{
            closeOnOutsideClick: assigns[:"close-on-outside-click"],
            animations: get_animation_config()
          })
      )

    ~H"""
    <div
      id={@id}
      tabindex="-1"
      class="absolute z-50 group/dialog"
      data-component="dialog"
      data-options={@options}
      data-open={to_string(@open)}
      data-state={@initial_state}
      data-event-mappings={@event_map}
      phx-hook="SaladUI"
      data-part="root"
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :class, :string, default: nil
  attr :as, :any, default: "div"
  slot :inner_block, required: true
  attr :rest, :global

  def dialog_trigger(assigns) do
    ~H"""
    <.dynamic data-part="trigger" data-action="open" tag={@as} class={classes(["", @class])} {@rest}>
      {render_slot(@inner_block)}
    </.dynamic>
    """
  end

  attr :class, :string, default: nil
  attr :close_class, :string, default: "right-4 top-4 rounded-xs"
  attr :close_icon_class, :string, default: "h-4 w-4"

  attr :open, :boolean,
    required: true,
    doc: """
    Whether the dialog is open. The state is rendered into the markup so a
    LiveView patch of the dialog's contents cannot strip it; the client keeps
    it in sync for transitions.
    """

  slot :inner_block, required: true

  def dialog_content(assigns) do
    ~H"""
    <div data-part="content" tabindex="0" hidden={not @open} data-state={state_name(@open)}>
      <div
        data-part="overlay"
        data-state={state_name(@open)}
        class="fixed inset-0 bg-black/80  data-[state=open]/dialog:animate-in data-[state=closed]/dialog:animate-out data-[state=closed]/dialog:fade-out-0 data-[state=open]/dialog:fade-in-0"
      />

      <div
        data-part="content-panel"
        data-state={state_name(@open)}
        class={
          classes([
            "fixed left-[50%] top-[50%] z-50 grid max-h-[calc(100dvh-2rem)] w-[calc(100%-2rem)] max-w-lg translate-x-[-50%] translate-y-[-50%] gap-4 overflow-y-auto overscroll-contain rounded-lg border border-border bg-background p-4 shadow-lg duration-200 data-[state=open]:animate-in data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=open]:fade-in-0 data-[state=closed]:zoom-out-95 data-[state=open]:zoom-in-95 sm:p-6",
            @class
          ])
        }
      >
        {render_slot(@inner_block)}

        <button
          type="button"
          data-part="close-trigger"
          data-action="close"
          class={
            classes([
              "absolute opacity-70 transition-opacity hover:opacity-100 focus:outline-hidden focus:ring-ring/50 focus:ring-[3px] disabled:pointer-events-none data-[state=open]/dialog:bg-accent data-[state=open]/dialog:text-muted-foreground",
              @close_class
            ])
          }
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            width="24"
            height="24"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
            class={classes(["lucide lucide-x", @close_icon_class])}
          >
            <path d="M18 6 6 18"></path>
            <path d="m6 6 12 12"></path>
          </svg>
          <span class="sr-only">Close</span>
        </button>
      </div>
    </div>
    """
  end

  attr :class, :string, default: nil
  slot :inner_block, required: true

  def dialog_header(assigns) do
    ~H"""
    <div class={classes(["flex flex-col space-y-1.5 text-center sm:text-left", @class])}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :class, :string, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def dialog_title(assigns) do
    ~H"""
    <h3
      data-part="title"
      class={classes(["text-lg font-semibold leading-none tracking-tight", @class])}
      {@rest}
    >
      {render_slot(@inner_block)}
    </h3>
    """
  end

  attr :class, :string, default: nil
  slot :inner_block, required: true

  def dialog_description(assigns) do
    ~H"""
    <p data-part="description" class={classes(["text-sm text-muted-foreground", @class])}>
      {render_slot(@inner_block)}
    </p>
    """
  end

  attr :class, :string, default: nil
  slot :inner_block, required: true

  def dialog_footer(assigns) do
    ~H"""
    <div class={classes(["flex flex-col-reverse sm:flex-row sm:justify-end sm:space-x-2", @class])}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  defp state_name(true), do: "open"
  defp state_name(false), do: "closed"

  defp get_animation_config do
    %{
      "open_to_closed" => %{
        duration: 130,
        target_part: "content"
      }
    }
  end
end
