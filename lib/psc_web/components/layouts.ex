defmodule PscWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use PscWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :container_class, :string,
    default: "mx-auto max-w-2xl space-y-4",
    doc: "the CSS class used for the main container; override to change width"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="h-14 shrink-0 border-b border-white/10 bg-base-200/60 px-4 sm:px-6 lg:px-8 flex items-center gap-6">
      <.link navigate={~p"/"} class="flex items-center gap-2 text-base-content">
        <span class="flex size-7 items-center justify-center rounded-md bg-primary text-primary-content text-sm font-bold">
          P
        </span>
        <span class="text-sm font-semibold tracking-tight">PSC</span>
      </.link>

      <nav class="flex items-center gap-1">
        <.link
          navigate={~p"/documents"}
          class="px-3 py-1.5 rounded-lg text-sm text-base-content/70 hover:text-base-content hover:bg-white/5 transition-colors"
        >
          Documents
        </.link>
        <.link
          navigate={~p"/canvases"}
          class="px-3 py-1.5 rounded-lg text-sm text-base-content/70 hover:text-base-content hover:bg-white/5 transition-colors"
        >
          Canvases
        </.link>
        <.link
          navigate={~p"/templates"}
          class="px-3 py-1.5 rounded-lg text-sm text-base-content/70 hover:text-base-content hover:bg-white/5 transition-colors"
        >
          Templates
        </.link>
      </nav>

      <div class="ml-auto flex items-center gap-4">
        <.theme_toggle />
        <%= if @current_scope && @current_scope.user do %>
          <div class="flex items-center gap-3 text-sm">
            <span class="text-base-content/60">{@current_scope.user.email}</span>
            <.link
              href={~p"/users/settings"}
              class="text-base-content/70 hover:text-base-content transition-colors"
            >
              Settings
            </.link>
            <.link
              href={~p"/users/log-out"}
              method="delete"
              class="text-base-content/70 hover:text-base-content transition-colors"
            >
              Log out
            </.link>
          </div>
        <% else %>
          <div class="flex items-center gap-3 text-sm">
            <.link
              href={~p"/users/register"}
              class="text-base-content/70 hover:text-base-content transition-colors"
            >
              Register
            </.link>
            <.link
              href={~p"/users/log-in"}
              class="px-3 py-1.5 rounded-lg bg-primary text-primary-content hover:opacity-90 transition-opacity"
            >
              Log in
            </.link>
          </div>
        <% end %>
      </div>
    </header>

    <main class="px-4 py-8 sm:px-6 lg:px-8 bg-transparent text-base-content">
      <div class={@container_class}>
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
