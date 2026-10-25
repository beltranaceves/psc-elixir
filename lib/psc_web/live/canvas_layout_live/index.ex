defmodule PscWeb.CanvasLayoutLive.Index do
  use PscWeb, :live_view

  # Qualified SaladUI aliases (house pattern) — CoreComponents' button/1 etc.
  # would collide with unqualified imports.
  alias PscWeb.Components.UI.Button, as: UIButton
  alias PscWeb.Components.UI.Input, as: UIInput
  alias PscWeb.Components.UI.Badge, as: UIBadge
  alias PscWeb.Components.UI.Dialog, as: UIDialog
  alias PscWeb.Components.UI.Helpers, as: UIHelpers

  import PscWeb.Components.TemplatePreview

  alias Psc.Canvas

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    templates = Canvas.list_templates(user)

    {:ok,
     socket
     |> assign(:templates, templates)
     |> assign(:delete_confirm_id, nil)
     |> assign(:share_form_for, nil)
     |> assign(:new_template_open, false)}
  end

  @impl true
  def handle_event("open_new_template", _params, socket) do
    {:noreply, assign(socket, :new_template_open, true)}
  end

  def handle_event("new_template_closed", _params, socket) do
    {:noreply, assign(socket, :new_template_open, false)}
  end

  @impl true
  def handle_event("confirm_delete", %{"id" => id}, socket) do
    {:noreply, assign(socket, :delete_confirm_id, id)}
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :delete_confirm_id, nil)}
  end

  @impl true
  def handle_event("delete_template", %{"id" => id}, socket) do
    user = socket.assigns.current_scope.user

    with %{} = template <- Canvas.get_canvas_layout(id),
         true <- template.author_id == user.id,
         {:ok, _} <- Canvas.delete_template(template) do
      {:noreply,
       socket
       |> assign(:templates, Canvas.list_templates(user))
       |> assign(:delete_confirm_id, nil)
       |> put_flash(:success, "Template deleted")}
    else
      false -> {:noreply, put_flash(socket, :error, "Only the template owner can delete")}
      _ -> {:noreply, put_flash(socket, :error, "Template not found")}
    end
  end

  @impl true
  def handle_event("show_share_form", %{"id" => id}, socket) do
    {:noreply, assign(socket, :share_form_for, id)}
  end

  def handle_event("hide_share_form", _params, socket) do
    {:noreply, assign(socket, :share_form_for, nil)}
  end

  @impl true
  def handle_event("share_template", %{"id" => id, "email" => email}, socket) do
    user = socket.assigns.current_scope.user

    with %{} = template <- Canvas.get_canvas_layout(id),
         true <- template.author_id == user.id,
         {:ok, _} <- Canvas.share_template_with(template, String.downcase(email)) do
      {:noreply,
       socket
       |> assign(:templates, Canvas.list_templates(user))
       |> assign(:share_form_for, nil)
       |> put_flash(:success, "Template shared with #{email}")}
    else
      false -> {:noreply, put_flash(socket, :error, "Only the template owner can share")}
      _ -> {:noreply, put_flash(socket, :error, "Failed to share template")}
    end
  end

  @impl true
  def handle_event("unshare_template", %{"id" => id, "email" => email}, socket) do
    user = socket.assigns.current_scope.user

    with %{} = template <- Canvas.get_canvas_layout(id),
         true <- template.author_id == user.id,
         {:ok, _} <- Canvas.unshare_template(template, email) do
      {:noreply,
       socket
       |> assign(:templates, Canvas.list_templates(user))
       |> put_flash(:success, "Access removed for #{email}")}
    else
      false -> {:noreply, put_flash(socket, :error, "Only the template owner can manage access")}
      _ -> {:noreply, put_flash(socket, :error, "Failed to remove access")}
    end
  end

  @impl true
  def handle_event("instantiate", %{"id" => id}, socket) do
    user = socket.assigns.current_scope.user

    case Canvas.get_canvas_layout(id) do
      %{} = template ->
        case Canvas.instantiate_template(template, user.id) do
          {:ok, canvas} ->
            {:noreply,
             socket
             |> put_flash(:success, "Canvas created from template")
             |> redirect(to: ~p"/canvas/#{canvas.id}")}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Failed to create canvas from template")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Template not found")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      header_title="Templates"
      container_class="w-full"
    >
      <div class="mx-auto flex w-full max-w-6xl min-w-0 flex-col gap-4">
        <div>
          <h2 class="mb-3 text-sm font-medium uppercase tracking-wide text-base-content/50">
            Available templates
          </h2>
          <%!-- Equal rows: the create tiles and the template cards read as one
          grid even when their descriptions wrap to different heights. --%>
          <div
            id="template-grid"
            class="grid auto-rows-fr grid-cols-1 gap-4 md:grid-cols-2 lg:grid-cols-3"
          >
            <%!-- The create action is the first tile of the library: same size
            as a template card, so the list reads as one grid. The catalog
            follows it, so the two ways to get a template lead the page. --%>
            <.new_template_card />
            <.catalog_card />

            <%= for template <- @templates do %>
              <.template_card
                template={template}
                current_user={@current_scope.user}
                delete_confirm_id={@delete_confirm_id}
                share_form_for={@share_form_for}
              />
            <% end %>

            <%= if Enum.empty?(@templates) do %>
              <div
                id="template-empty-state"
                class="rounded-xl border border-dashed border-base-content/20 bg-base-200 p-8 text-center md:col-span-2 lg:col-span-3"
              >
                <p class="text-base-content/60">No templates yet.</p>
                <p class="mt-1 text-sm text-base-content/45">
                  A template defines the structure and cells a canvas starts from.
                </p>
              </div>
            <% end %>
          </div>
        </div>

        <.new_template_dialog new_template_open={@new_template_open} />
      </div>
    </Layouts.app>
    """
  end

  # The first tile of the library: a dashed card that opens the type picker.
  # The picker is a modal rather than three tiles, so creating a template is
  # one decision (what kind of structure?) instead of three competing buttons.
  defp new_template_card(assigns) do
    ~H"""
    <button
      type="button"
      id="new-template-card"
      phx-click="open_new_template"
      class="flex flex-col items-center justify-center gap-3 rounded-xl border border-dashed border-base-content/25 bg-base-200 p-4 text-center transition-colors hover:border-base-content/45 hover:bg-base-content/5 focus:outline-none focus-visible:ring-2 focus-visible:ring-primary"
    >
      <span class="flex size-10 items-center justify-center rounded-full bg-primary/10 text-primary">
        <.icon name="hero-plus" class="size-5" />
      </span>
      <span class="flex flex-col gap-1">
        <span class="font-medium text-base-content">New Template</span>
        <span class="text-sm text-base-content/50">Choose a grid, a board or a picture</span>
      </span>
    </button>
    """
  end

  # The picker itself. Each option previews the structure it creates, using the
  # same thumbnails the library and the canvas picker use, so the choice is
  # made against a picture rather than a description alone.
  attr :new_template_open, :boolean, required: true

  defp new_template_dialog(assigns) do
    ~H"""
    <UIDialog.dialog
      :if={@new_template_open}
      id="new-template-dialog"
      open
      on-close="new_template_closed"
    >
      <UIDialog.dialog_content
        class="sm:max-w-2xl"
        close_class="right-2 top-2 rounded-md p-2"
        close_icon_class="size-5"
      >
        <UIDialog.dialog_header>
          <UIDialog.dialog_title>New template</UIDialog.dialog_title>

          <UIDialog.dialog_description>
            Pick the structure a canvas from this template will use. You name it and
            fill in its cells next.
          </UIDialog.dialog_description>
        </UIDialog.dialog_header>

        <div class="grid gap-3 sm:grid-cols-3">
          <.new_template_option mode={:table} />
          <.new_template_option mode={:bento} />
          <.new_template_option mode={:image} />
        </div>

        <UIDialog.dialog_footer class="flex justify-end">
          <UIButton.button
            type="button"
            variant="outline"
            id="cancel-new-template"
            phx-click="new_template_closed"
          >
            Cancel
          </UIButton.button>
        </UIDialog.dialog_footer>
      </UIDialog.dialog_content>
    </UIDialog.dialog>
    """
  end

  attr :mode, :atom, required: true

  defp new_template_option(assigns) do
    assigns =
      assigns
      |> assign(:id, "new-template-mode-#{assigns.mode}")
      |> assign(:preview, new_template_preview(assigns.mode))
      |> assign(:path, new_template_path(assigns.mode))
      |> assign(:title, new_template_title(assigns.mode))
      |> assign(:blurb, new_template_blurb(assigns.mode))

    ~H"""
    <.link
      id={@id}
      navigate={@path}
      class="group flex min-w-0 flex-col gap-2 rounded-xl border border-base-content/10 bg-base-100 p-3 text-left transition-colors hover:border-primary/50 hover:bg-base-content/5 focus:outline-none focus-visible:ring-2 focus-visible:ring-primary"
    >
      <div class="pointer-events-none rounded-lg border border-base-content/10 bg-base-200 p-2">
        <.mini_preview layout_map={@preview} size={:lg} />
      </div>
      <span class="flex flex-col gap-0.5">
        <span class="text-sm font-medium text-base-content">{@title}</span>
        <span class="text-xs leading-4 text-base-content/55">{@blurb}</span>
      </span>
    </.link>
    """
  end

  defp new_template_preview(:table), do: Canvas.psc_layout_map()
  defp new_template_preview(:bento), do: Canvas.bento_layout_map()
  defp new_template_preview(:image), do: Canvas.image_layout_map()

  defp new_template_path(:table), do: ~p"/templates/new"
  defp new_template_path(:bento), do: ~p"/templates/new?mode=bento"
  defp new_template_path(:image), do: ~p"/templates/new?mode=image"

  defp new_template_title(:table), do: "Table grid"
  defp new_template_title(:bento), do: "Bento board"
  defp new_template_title(:image), do: "Image board"

  defp new_template_blurb(:table), do: "Rows and columns, with a cell in every position."
  defp new_template_blurb(:bento), do: "Free-form cards on a 12-column board."
  defp new_template_blurb(:image), do: "Notes and labels pinned to a picture."

  # The second tile of the library: the same dashed card, pointing at the
  # catalog, where the templates other people published are ranked.
  defp catalog_card(assigns) do
    ~H"""
    <.link
      id="catalog-card"
      navigate={~p"/catalog"}
      class="flex flex-col items-center justify-center gap-3 rounded-xl border border-dashed border-base-content/25 bg-base-200 p-4 text-center transition-colors hover:border-base-content/45 hover:bg-base-content/5"
    >
      <span class="flex size-10 items-center justify-center rounded-full bg-primary/10 text-primary">
        <.icon name="hero-book-open" class="size-5" />
      </span>
      <span class="flex flex-col gap-1">
        <span class="font-medium text-base-content">Open Catalog</span>
        <span class="text-sm text-base-content/50">Browse the public templates</span>
      </span>
    </.link>
    """
  end

  attr :template, :map, required: true
  attr :current_user, :map, required: true
  attr :delete_confirm_id, :any, required: true
  attr :share_form_for, :any, required: true

  defp template_card(assigns) do
    ~H"""
    <div
      id={"template-card-#{@template.id}"}
      class="rounded-xl border border-base-content/10 bg-base-200 p-4 flex flex-col"
    >
      <div class="flex items-start justify-between gap-2 mb-2">
        <h3 class="font-medium text-base-content break-words">{@template.name}</h3>
        <%= cond do %>
          <% @template.built_in -> %>
            <UIBadge.badge variant="outline" class="shrink-0 text-xs">Default</UIBadge.badge>
          <% @template.author_id == @current_user.id -> %>
            <UIBadge.badge variant="outline" class="shrink-0 text-xs">Owner</UIBadge.badge>
          <% true -> %>
            <UIBadge.badge variant="secondary" class="shrink-0 text-xs">Shared</UIBadge.badge>
        <% end %>
      </div>

      <p
        :if={@template.description not in [nil, ""]}
        class="mb-3 text-sm text-base-content/60 break-words line-clamp-2"
      >
        {@template.description}
      </p>

      <div class="flex items-center gap-2 text-xs text-base-content/50 mb-4">
        <span>{PscWeb.Components.TemplatePreview.structure_size(@template.layout_map)}</span>
      </div>

      <div class="flex flex-wrap items-center gap-2 mt-auto">
        <UIButton.button
          variant="default"
          size="sm"
          phx-click="instantiate"
          phx-value-id={@template.id}
        >
          Use Template
        </UIButton.button>
        <.link
          navigate={~p"/templates/#{@template.id}"}
          class={[UIHelpers.button_variant(%{variant: "outline", size: "sm"}), "gap-1.5"]}
        >
          {if @template.built_in, do: "View", else: "Edit"}
        </.link>
        <%= if @template.author_id == @current_user.id do %>
          <UIButton.button
            variant="outline"
            size="sm"
            phx-click="show_share_form"
            phx-value-id={@template.id}
          >
            Share
          </UIButton.button>
          <%= if @delete_confirm_id == @template.id do %>
            <span class="flex items-center gap-1 text-xs">
              <span class="text-base-content/60">Delete?</span>
              <UIButton.button
                variant="destructive"
                size="sm"
                phx-click="delete_template"
                phx-value-id={@template.id}
              >
                Yes
              </UIButton.button>
              <UIButton.button
                variant="outline"
                size="sm"
                phx-click="cancel_delete"
              >
                No
              </UIButton.button>
            </span>
          <% else %>
            <UIButton.button
              variant="outline"
              size="sm"
              class="text-error hover:text-error"
              phx-click="confirm_delete"
              phx-value-id={@template.id}
            >
              Delete
            </UIButton.button>
          <% end %>
        <% end %>
      </div>

      <%= if @share_form_for == @template.id do %>
        <div class="mt-4 pt-4 border-t border-base-content/10">
          <form phx-submit="share_template" phx-value-id={@template.id} class="flex gap-2">
            <UIInput.input
              type="email"
              name="email"
              placeholder="user@example.com"
              required
              class="flex-1"
            />
            <UIButton.button type="submit" size="sm">Share</UIButton.button>
          </form>
          <%= if length(@template.shared_with || []) > 0 do %>
            <ul class="mt-3 space-y-1">
              <%= for email <- @template.shared_with do %>
                <li class="flex items-center justify-between text-xs text-base-content/60">
                  <span>{email}</span>
                  <button
                    type="button"
                    phx-click="unshare_template"
                    phx-value-id={@template.id}
                    phx-value-email={email}
                    class="text-error hover:underline"
                  >
                    Remove
                  </button>
                </li>
              <% end %>
            </ul>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end
