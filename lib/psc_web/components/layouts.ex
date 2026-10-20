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
    default: "mx-auto w-full max-w-2xl space-y-4",
    doc: "the CSS class used for the main container; override to change width"

  attr :main_class, :string,
    default: "px-4 py-6 sm:px-6 lg:px-8",
    doc: "the padding applied to the main element; reduce it for dense, full-height pages"

  attr :fill_height, :boolean,
    default: false,
    doc:
      "fills the viewport and lets the page content flex into the remaining height instead of scrolling the window"

  attr :header_title, :string,
    default: nil,
    doc: "route context shown in the app header (e.g. the current section name)"

  slot :header_nav,
    doc:
      "navigation rendered in the free space of the app header; pages that need a different placement on small screens (e.g. a bottom app bar) style it themselves"

  slot :header_actions,
    doc:
      "page actions rendered next to the section navigation in the app header (e.g. a minimal presence/share cluster on phones)"

  attr :header_section, :string,
    default: nil,
    doc:
      "nav item to highlight when it differs from the header title (e.g. \"Designer\" inside the Templates section)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class={[
      "flex flex-col",
      @fill_height && "h-dvh overflow-hidden",
      !@fill_height && "min-h-dvh"
    ]}>
      <header class="h-14 shrink-0 border-b border-base-content/10 bg-base-200/60 px-4 sm:px-6 lg:px-8 flex items-center gap-3 sm:gap-6">
        <.link navigate={~p"/"} class="flex shrink-0 items-center gap-2 text-base-content">
          <span class="flex size-7 items-center justify-center rounded-md bg-primary text-primary-content text-sm font-bold">
            P
          </span>
          <span class="hidden text-sm font-semibold tracking-tight sm:inline">PSC</span>
        </.link>

        <h1
          :if={@header_title}
          id="header-page-title"
          class="min-w-0 flex-1 truncate text-base font-semibold tracking-tight text-base-content sm:text-lg md:flex-none"
        >
          {@header_title}
        </h1>

        <%!-- The slot holds the free space between the page title and the
        section navigation. It is a container so that its content can react to
        the room it actually gets (see the canvas tab strip) instead of
        guessing with viewport breakpoints. --%>
        <div class="@container flex min-w-0 items-center justify-center lg:flex-1">
          {render_slot(@header_nav)}
        </div>

        <div class="flex shrink-0 items-center gap-2">
          {render_slot(@header_actions)}
        </div>

        <div class="ml-auto flex items-center gap-3 sm:gap-4">
          <%!-- Private sections: only advertised to signed-in users. --%>
          <nav :if={@current_scope && @current_scope.user} class="hidden items-center gap-1 md:flex">
            <.link
              navigate={~p"/canvas"}
              aria-current={nav_current(@header_title, @header_section, "Canvases")}
              class={[
                "px-3 py-1.5 rounded-lg text-sm transition-colors",
                nav_item_class(@header_title, @header_section, "Canvases")
              ]}
            >
              Canvases
            </.link>
            <.link
              navigate={~p"/templates"}
              aria-current={nav_current(@header_title, @header_section, "Templates")}
              class={[
                "px-3 py-1.5 rounded-lg text-sm transition-colors",
                nav_item_class(@header_title, @header_section, "Templates")
              ]}
            >
              Templates
            </.link>
          </nav>

          <div class="flex items-center gap-3 sm:gap-4">
            <%!-- The theme switch lives in the menu until there is room for it
            in the bar (large screens); on phones and tablets the menu owns it. --%>
            <div class="hidden xl:block">
              <.theme_toggle />
            </div>
            <%= if @current_scope && @current_scope.user do %>
              <div class="hidden items-center gap-3 text-sm xl:flex">
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

              <%!-- Mobile and tablet: navigation, theme and account actions live
              behind one menu. --%>
              <details class="relative xl:hidden" data-menu>
                <summary
                  class="flex size-9 cursor-pointer list-none items-center justify-center rounded-lg text-base-content/70 transition-colors hover:bg-base-content/5 hover:text-base-content [&::-webkit-details-marker]:hidden"
                  aria-label="Menu"
                >
                  <.icon name="hero-bars-3" class="size-5" />
                </summary>
                <div class="absolute right-0 z-50 mt-2 w-56 rounded-lg border border-base-content/10 bg-base-200 p-1 shadow-lg">
                  <p class="truncate px-3 py-2 text-xs text-base-content/50">
                    {@current_scope.user.email}
                  </p>
                  <div class="my-1 h-px bg-base-content/10"></div>
                  <.link
                    navigate={~p"/canvas"}
                    class="block rounded px-3 py-2 text-sm text-base-content/80 transition-colors hover:bg-base-content/5 hover:text-base-content md:hidden"
                  >
                    Canvases
                  </.link>
                  <.link
                    navigate={~p"/templates"}
                    class="block rounded px-3 py-2 text-sm text-base-content/80 transition-colors hover:bg-base-content/5 hover:text-base-content md:hidden"
                  >
                    Templates
                  </.link>
                  <div class="my-1 h-px bg-base-content/10"></div>
                  <.theme_menu />
                  <div class="my-1 h-px bg-base-content/10"></div>
                  <.link
                    href={~p"/users/settings"}
                    class="block rounded px-3 py-2 text-sm text-base-content/80 transition-colors hover:bg-base-content/5 hover:text-base-content"
                  >
                    Settings
                  </.link>
                  <.link
                    href={~p"/users/log-out"}
                    method="delete"
                    class="block rounded px-3 py-2 text-sm text-base-content/80 transition-colors hover:bg-base-content/5 hover:text-base-content"
                  >
                    Log out
                  </.link>
                </div>
              </details>
            <% else %>
              <div class="hidden items-center gap-3 text-sm xl:flex">
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

              <%!-- Guests get the same menu, with the theme switch inside. --%>
              <details class="relative xl:hidden" data-menu>
                <summary
                  class="flex size-9 cursor-pointer list-none items-center justify-center rounded-lg text-base-content/70 transition-colors hover:bg-base-content/5 hover:text-base-content [&::-webkit-details-marker]:hidden"
                  aria-label="Menu"
                >
                  <.icon name="hero-bars-3" class="size-5" />
                </summary>
                <div class="absolute right-0 z-50 mt-2 w-56 rounded-lg border border-base-content/10 bg-base-200 p-1 shadow-lg">
                  <.theme_menu />
                  <div class="my-1 h-px bg-base-content/10"></div>
                  <.link
                    href={~p"/users/register"}
                    class="block rounded px-3 py-2 text-sm text-base-content/80 transition-colors hover:bg-base-content/5 hover:text-base-content"
                  >
                    Register
                  </.link>
                  <.link
                    href={~p"/users/log-in"}
                    class="block rounded px-3 py-2 text-sm text-base-content/80 transition-colors hover:bg-base-content/5 hover:text-base-content"
                  >
                    Log in
                  </.link>
                </div>
              </details>
            <% end %>
          </div>
        </div>
      </header>

      <main class={[
        "flex min-h-0 flex-1 flex-col bg-transparent text-base-content",
        @main_class,
        @fill_height && "overflow-y-auto"
      ]}>
        <div class={@container_class}>
          {render_slot(@inner_block)}
        </div>
      </main>

      <.flash_group flash={@flash} />
    </div>
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
    <div
      id={@id}
      aria-live="polite"
      class="pointer-events-none fixed inset-x-3 bottom-[calc(4.5rem+env(safe-area-inset-bottom))] z-50 flex flex-col items-stretch gap-3 sm:inset-x-auto sm:right-6 sm:w-96 sm:items-end lg:top-16 lg:bottom-auto"
    >
      <.flash kind={:success} flash={@flash} />
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
  attr :class, :string,
    default: nil,
    doc: "extra classes for the toggle (e.g. w-full inside a menu)"

  def theme_toggle(assigns) do
    ~H"""
    <div class={[
      "card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full",
      @class
    ]}>
      <%!-- The thumb is decoration only: it must not swallow the clicks of the
      segment it sits on (that is the segment of the current theme). --%>
      <div class="pointer-events-none absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        type="button"
        class="flex w-1/3 cursor-pointer items-center justify-center p-2"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
        aria-label="System theme"
        title="System theme"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        type="button"
        class="flex w-1/3 cursor-pointer items-center justify-center p-2"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        aria-label="Light theme"
        title="Light theme"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        type="button"
        class="flex w-1/3 cursor-pointer items-center justify-center p-2"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        aria-label="Dark theme"
        title="Dark theme"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end

  # The theme switch as a menu entry: a label plus the full-width toggle.
  defp theme_menu(assigns) do
    ~H"""
    <p class="px-3 pt-1 pb-1.5 text-[0.7rem] font-medium uppercase tracking-wide text-base-content/50">
      Theme
    </p>
    <div class="px-1 pb-1.5">
      <.theme_toggle class="w-full" />
    </div>
    """
  end

  # The header title doubles as the active-section marker for the nav, unless a
  # page sets a more specific header_section (e.g. "Designer" in Templates).
  defp nav_section(header_title, header_section), do: header_section || header_title

  defp nav_item_class(header_title, header_section, section) do
    if nav_section(header_title, header_section) == section do
      "bg-base-content/10 font-medium text-base-content"
    else
      "text-base-content/70 hover:text-base-content hover:bg-base-content/5"
    end
  end

  defp nav_current(header_title, header_section, section) do
    if nav_section(header_title, header_section) == section, do: "page", else: nil
  end
end
