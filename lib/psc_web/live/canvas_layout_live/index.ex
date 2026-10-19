defmodule PscWeb.CanvasLayoutLive.Index do
  use PscWeb, :live_view

  # Qualified SaladUI aliases (house pattern) — CoreComponents' button/1 etc.
  # would collide with unqualified imports.
  alias PscWeb.Components.UI.Button, as: UIButton
  alias PscWeb.Components.UI.Input, as: UIInput
  alias PscWeb.Components.UI.Badge, as: UIBadge
  alias PscWeb.Components.UI.Helpers, as: UIHelpers

  alias Psc.Canvas

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    templates = Canvas.list_templates(user)

    {:ok,
     socket
     |> assign(:templates, templates)
     |> assign(:delete_confirm_id, nil)
     |> assign(:share_form_for, nil)}
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
        <div class="flex items-center justify-between gap-3">
          <h1 class="text-2xl font-semibold text-base-content">Templates</h1>
          <.link
            navigate={~p"/templates/new"}
            class={[UIHelpers.button_variant(%{variant: "default", size: "sm"}), "gap-1.5"]}
          >
            <.icon name="hero-plus" class="size-4" /> New Template
          </.link>
        </div>

        <div>
          <h2 class="mb-3 text-sm font-medium uppercase tracking-wide text-base-content/50">
            Available templates
          </h2>
          <%= if Enum.empty?(@templates) do %>
            <div class="rounded-xl border border-dashed border-base-content/20 bg-base-200 p-8 text-center">
              <p class="text-base-content/60">No templates yet.</p>
              <p class="mt-1 text-sm text-base-content/45">
                A template defines the grid and cells a canvas starts from.
              </p>
            </div>
          <% else %>
            <div class="grid grid-cols-1 gap-4 md:grid-cols-2 lg:grid-cols-3">
              <%= for template <- @templates do %>
                <.template_card
                  template={template}
                  current_user={@current_scope.user}
                  delete_confirm_id={@delete_confirm_id}
                  share_form_for={@share_form_for}
                />
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :template, :map, required: true
  attr :current_user, :map, required: true
  attr :delete_confirm_id, :any, required: true
  attr :share_form_for, :any, required: true

  defp template_card(assigns) do
    ~H"""
    <div class="rounded-xl border border-base-content/10 bg-base-200 p-4 flex flex-col">
      <div class="flex items-start justify-between gap-2 mb-2">
        <h3 class="font-medium text-base-content">{@template.name}</h3>
        <%= if @template.author_id == @current_user.id do %>
          <UIBadge.badge variant="outline" class="shrink-0 text-xs">Owner</UIBadge.badge>
        <% else %>
          <UIBadge.badge variant="secondary" class="shrink-0 text-xs">Shared</UIBadge.badge>
        <% end %>
      </div>

      <p
        :if={@template.description not in [nil, ""]}
        class="mb-3 text-sm text-base-content/60 line-clamp-2"
      >
        {@template.description}
      </p>

      <div class="flex items-center gap-2 text-xs text-base-content/50 mb-4">
        <span>{length(@template.layout_map["rows"] || [])} rows</span>
        <span>&times;</span>
        <span>{length(@template.layout_map["columns"] || [])} columns</span>
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
          Edit
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
