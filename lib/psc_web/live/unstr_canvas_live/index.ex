defmodule PscWeb.UnstrCanvasLive.Index do
  use PscWeb, :live_view

  import PscWeb.CoreComponents, except: [button: 1]
  import PscWeb.Components.UI.Button
  import PscWeb.Components.TemplatePreview

  alias Psc.Canvas

  @impl true
  def mount(_params, _session, socket) do
    user_id = socket.assigns.current_scope.user.id
    user_email = socket.assigns.current_scope.user.email

    my_canvases = Canvas.list_user_unstr_canvases(user_id)
    shared_canvases = Canvas.list_shared_unstr_canvases(user_email)
    # Only templates this user may use: their own plus ones shared with them.
    templates = Canvas.list_templates(socket.assigns.current_scope.user)

    {:ok,
     socket
     |> assign(:my_canvases, my_canvases)
     |> assign(:shared_canvases, shared_canvases)
     |> assign(:new_canvas_form, to_form(%{}))
     |> assign(:templates, templates)
     |> assign(:selected_template_id, "")}
  end

  # Picking a starting point is a click on its card. The id lands in the form's
  # hidden input, so the submit carries it like a select's value would. Only
  # ids the picker offered are accepted - blank, or one of the templates the
  # user can access - so a forged one cannot sit in the draft waiting for a
  # submit. A built-in template's id is its stable slug.
  @impl true
  def handle_event("select_template", %{"id" => id}, socket) do
    if id == "" or Enum.any?(socket.assigns.templates, &(template_id(&1) == id)) do
      {:noreply, assign(socket, :selected_template_id, id)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("create_canvas", params, socket) do
    name = params["name"]
    description = params["description"]
    template_id = params["template_id"]

    user = socket.assigns.current_scope.user

    case create_canvas(user, name, description, template_id) do
      {:ok, canvas} ->
        # Creating is the start of work, not a list update: land the user in
        # the canvas they just asked for, the way the catalog's Use does.
        {:noreply,
         socket
         |> put_flash(:success, "Canvas created successfully")
         |> redirect(to: ~p"/canvas/#{canvas.id}")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You do not have access to that template")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create canvas")}
    end
  end

  @impl true
  def handle_event("delete_canvas", %{"id" => id}, socket) do
    user_id = socket.assigns.current_scope.user.id
    canvas = Canvas.get_unstr_canvas(id)

    if canvas && canvas.author_id == user_id do
      Canvas.delete_unstr_canvas(canvas)
      my_canvases = Canvas.list_user_unstr_canvases(user_id)

      {:noreply,
       socket
       |> assign(:my_canvases, my_canvases)
       |> put_flash(:success, "Canvas deleted")}
    else
      {:noreply, put_flash(socket, :error, "Unauthorized")}
    end
  end

  # The creation paths, routed by the picker's id: blank (the empty
  # structure) or a template instantiated through the context — which
  # transforms the template's nested cell metadata into the flat cell shape a
  # canvas expects; copying the template's layout_map verbatim is rejected by
  # the canvas changeset. The name/description typed in the form win over the
  # template's.
  defp create_canvas(user, name, description, template_id) do
    attrs = %{"name" => name, "description" => description || ""}

    case template_id do
      "" ->
        Canvas.create_unstr_canvas(user.id, Map.put(attrs, "cells", Canvas.blank_cells()))

      other ->
        case template_for(user, other) do
          {:ok, template} ->
            Canvas.instantiate_template(template, user.id, attrs)

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  # A picker id is a template's slug (built-ins) or its id (user templates).
  defp template_for(_user, template_id) when template_id in [nil, ""], do: :blank

  defp template_for(user, template_id) do
    template =
      Canvas.get_template_by_slug(template_id) || Canvas.get_template_with_author(template_id)

    cond do
      is_nil(template) ->
        {:error, :not_found}

      Canvas.can_access_template?(template, user.email) ->
        {:ok, template}

      true ->
        {:error, :unauthorized}
    end
  end

  defp template_id(template), do: template.slug || template.id

  # The picker card's states: the selected card carries the primary border and
  # tint, the rest stay quiet until hovered.
  defp picker_card_class(selected?) do
    [
      "flex w-40 shrink-0 flex-col gap-2 rounded-xl border p-3 text-left transition-colors",
      selected? && "border-primary/60 bg-primary/10",
      not selected? && "border-base-content/10 bg-base-200 hover:border-base-content/25"
    ]
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      header_title="Canvases"
      container_class="w-full mx-auto max-w-screen-xl"
    >
      <div class="mx-auto w-full max-w-6xl">
        <%!-- Start a canvas: templates first, so the structure is chosen before naming --%>
        <div class="mb-6 rounded-xl border border-base-content/10 bg-base-200 p-4 sm:p-6">
          <h2 class="mb-4 text-lg font-medium text-base-content">Start a canvas</h2>
          <.form
            for={@new_canvas_form}
            id="new-canvas-form"
            phx-submit="create_canvas"
            class="space-y-4"
          >
            <div>
              <span class="label mb-1">Start from</span>

              <%!-- The picker: the catalog first, then blank, then a card per
              template (the built-in defaults included). The choice is made with
              the eyes — a layout is the one thing a dropdown cannot show. The
              selected id rides to the submit in the hidden input below, the way
              a select's value would. --%>
              <div id="template-picker" class="canvas-grid-scroll flex gap-3 overflow-x-auto pb-1">
                <%!-- The catalog is a link, not a choice: a dashed card, like
                every other action card in the app, and it opens in a new tab
                so a name already typed is not lost. --%>
                <a
                  id="template-picker-catalog"
                  href={~p"/catalog"}
                  target="_blank"
                  rel="noopener"
                  class="flex w-40 shrink-0 flex-col gap-2 rounded-xl border border-dashed border-base-content/25 bg-base-200 p-3 text-left transition-colors hover:border-base-content/45 hover:bg-base-content/5"
                >
                  <span class="flex h-16 items-center justify-center">
                    <span class="flex size-10 items-center justify-center rounded-full bg-primary/10 text-primary">
                      <.icon name="hero-book-open" class="size-5" />
                    </span>
                  </span>

                  <span class="break-words text-sm font-medium text-base-content">
                    Browse the catalog
                  </span>
                  <span class="text-xs text-base-content/50">Public templates</span>
                </a>

                <button
                  type="button"
                  id="template-picker-blank"
                  phx-click="select_template"
                  phx-value-id=""
                  aria-pressed={to_string(@selected_template_id == "")}
                  aria-label="Start from a blank canvas"
                  class={picker_card_class(@selected_template_id == "")}
                >
                  <.mini_preview layout_map={%{"rows" => [], "columns" => []}} />

                  <span class="break-words text-sm font-medium text-base-content">
                    Blank canvas
                  </span>
                  <span class="text-xs text-base-content/50">Build it in place</span>
                </button>

                <button
                  :for={template <- @templates}
                  type="button"
                  id={"template-picker-#{template_id(template)}"}
                  phx-click="select_template"
                  phx-value-id={template_id(template)}
                  aria-pressed={to_string(@selected_template_id == template_id(template))}
                  aria-label={"Start from #{template.name}"}
                  class={picker_card_class(@selected_template_id == template_id(template))}
                >
                  <.mini_preview layout_map={template.layout_map} />

                  <span class="break-words text-sm font-medium text-base-content">
                    {template.name}
                  </span>
                  <span class="text-xs text-base-content/50">
                    {length(template.layout_map["rows"] || [])} × {length(
                      template.layout_map["columns"] || []
                    )}
                  </span>
                </button>
              </div>
            </div>

            <input type="hidden" name="template_id" value={@selected_template_id} />

            <.input
              field={@new_canvas_form[:name]}
              type="text"
              label="Canvas Name"
              placeholder="Enter canvas name..."
              required
            />
            <.input
              field={@new_canvas_form[:description]}
              type="textarea"
              label="Description"
              placeholder="Enter canvas description..."
            />
            <.button type="submit" phx-disable-with="Creating…">
              Create Canvas
            </.button>
          </.form>
        </div>

        <%!-- My Canvases --%>
        <div class="mb-12">
          <h2 class="text-lg font-medium text-base-content mb-4">My Canvases</h2>
          <%= if Enum.empty?(@my_canvases) do %>
            <div class="rounded-xl border border-base-content/10 bg-base-200 p-8 text-center">
              <p class="text-base-content/60">No canvases yet. Create one to get started!</p>
            </div>
          <% else %>
            <div id="my-canvases-grid" class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
              <%= for canvas <- @my_canvases do %>
                <div class="h-full rounded-xl border border-base-content/10 bg-base-200 p-6 hover:border-base-content/25 transition-colors flex flex-col">
                  <h3 class="font-medium text-base-content break-words">{canvas.name}</h3>
                  <p
                    :if={canvas.description not in [nil, ""]}
                    class="mt-2 text-sm text-base-content/60 break-words line-clamp-2"
                  >
                    {canvas.description}
                  </p>
                  <div class="mt-auto pt-4 flex gap-2">
                    <.link
                      navigate={~p"/canvas/#{canvas.id}"}
                      class="flex-1 px-4 py-2 bg-primary text-primary-content text-sm font-medium rounded-lg hover:opacity-90 transition-opacity text-center"
                    >
                      Edit
                    </.link>
                    <.button
                      variant="destructive"
                      phx-click="delete_canvas"
                      phx-value-id={canvas.id}
                      onclick="return confirm('Delete this canvas?')"
                    >
                      Delete
                    </.button>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>

        <%!-- Shared with Me --%>
        <%= if Enum.any?(@shared_canvases) do %>
          <div>
            <h2 class="text-lg font-medium text-base-content mb-4">Shared with Me</h2>
            <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
              <%= for canvas <- @shared_canvases do %>
                <div class="h-full rounded-xl border border-base-content/10 bg-base-200 p-6 hover:border-base-content/25 transition-colors flex flex-col">
                  <div class="flex items-start justify-between gap-2">
                    <h3 class="min-w-0 font-medium text-base-content break-words">
                      {canvas.name}
                    </h3>
                    <span class="shrink-0 rounded-full border border-primary/25 bg-primary/10 px-2 py-0.5 text-[11px] text-primary">
                      shared
                    </span>
                  </div>
                  <p class="mt-1 text-xs text-base-content/50">by {canvas.author.email}</p>
                  <p
                    :if={canvas.description not in [nil, ""]}
                    class="mt-2 text-sm text-base-content/60 break-words line-clamp-2"
                  >
                    {canvas.description}
                  </p>
                  <div class="mt-auto pt-4 flex gap-2">
                    <.link
                      navigate={~p"/canvas/#{canvas.id}"}
                      class="flex-1 px-4 py-2 bg-primary text-primary-content text-sm font-medium rounded-lg hover:opacity-90 transition-opacity text-center"
                    >
                      Open
                    </.link>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
