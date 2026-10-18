defmodule PscWeb.UnstrCanvasLive.Index do
  use PscWeb, :live_view

  import PscWeb.CoreComponents, except: [button: 1]
  import PscWeb.Components.UI.Button

  alias Psc.Canvas

  @impl true
  def mount(_params, _session, socket) do
    user_id = socket.assigns.current_scope.user.id
    user_email = socket.assigns.current_scope.user.email

    my_canvases = Canvas.list_user_unstr_canvases(user_id)
    shared_canvases = Canvas.list_shared_unstr_canvases(user_email)
    # Only templates this user may use: their own plus ones shared with them.
    templates = Canvas.list_templates(socket.assigns.current_scope.user)
    template_options = [{"Blank canvas", ""} | Enum.map(templates, &{&1.name, &1.id})]

    {:ok,
     socket
     |> assign(:my_canvases, my_canvases)
     |> assign(:shared_canvases, shared_canvases)
     |> assign(:new_canvas_form, to_form(%{}))
     |> assign(:templates, templates)
     |> assign(:template_options, template_options)}
  end

  @impl true
  def handle_event("create_canvas", params, socket) do
    name = params["name"]
    description = params["description"]
    template_id = params["template_id"]

    user = socket.assigns.current_scope.user

    case create_canvas(user, name, description, template_id) do
      {:ok, _canvas} ->
        my_canvases = Canvas.list_user_unstr_canvases(user.id)

        {:noreply,
         socket
         |> assign(:my_canvases, my_canvases)
         |> put_flash(:info, "Canvas created successfully")}

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
       |> put_flash(:info, "Canvas deleted")}
    else
      {:noreply, put_flash(socket, :error, "Unauthorized")}
    end
  end

  # A template is instantiated through the context, which transforms the
  # template's nested cell metadata into the flat cell shape a canvas expects —
  # copying the template's layout_map verbatim is rejected by the canvas
  # changeset. The name/description typed in the form win over the template's.
  defp create_canvas(user, name, description, template_id) do
    case template_for(user, template_id) do
      {:ok, template} ->
        Canvas.instantiate_template(template, user.id, %{
          "name" => name,
          "description" => description || ""
        })

      :blank ->
        Canvas.create_unstr_canvas(user.id, %{"name" => name, "description" => description})

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp template_for(_user, template_id) when template_id in [nil, ""], do: :blank

  defp template_for(user, template_id) do
    # get_template_with_author/1 preloads :author, which can_access_template?/2 reads
    case Canvas.get_template_with_author(template_id) do
      nil ->
        {:error, :not_found}

      template ->
        if Canvas.can_access_template?(template, user.email) do
          {:ok, template}
        else
          {:error, :unauthorized}
        end
    end
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
      <div class="max-w-6xl mx-auto px-4 py-8">
        <div class="mb-8">
          <h1 class="text-2xl font-semibold text-base-content">Canvases</h1>
        </div>

        <%!-- Create New Canvas Form --%>
        <div class="mb-8 rounded-xl border border-base-content/10 bg-base-200 p-6">
          <h2 class="text-lg font-medium text-base-content mb-4">Create New Canvas</h2>
          <.form
            for={@new_canvas_form}
            id="new-canvas-form"
            phx-submit="create_canvas"
            class="space-y-4"
          >
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
            <.input
              field={@new_canvas_form[:template_id]}
              type="select"
              options={@template_options}
              label="Template"
            />
            <.button type="submit">
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
            <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
              <%= for canvas <- @my_canvases do %>
                <div class="rounded-xl border border-base-content/10 bg-base-200 p-6 hover:border-base-content/25 transition-colors">
                  <h3 class="font-medium text-base-content">{canvas.name}</h3>
                  <p class="text-sm text-base-content/60 mt-2">{canvas.description}</p>
                  <div class="mt-4 flex gap-2">
                    <.link
                      navigate={~p"/canvases/#{canvas.id}"}
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
                <div class="rounded-xl border border-primary/20 bg-primary/5 p-6 hover:border-primary/40 transition-colors">
                  <div class="flex items-start justify-between">
                    <div>
                      <h3 class="font-medium text-base-content">{canvas.name}</h3>
                      <p class="text-sm text-base-content/60 mt-1">by {canvas.author.email}</p>
                    </div>
                  </div>
                  <p class="text-sm text-base-content/60 mt-2">{canvas.description}</p>
                  <div class="mt-4">
                    <.link
                      navigate={~p"/canvases/#{canvas.id}"}
                      class="block w-full px-4 py-2 bg-primary text-primary-content text-sm font-medium rounded-lg hover:opacity-90 transition-opacity text-center"
                    >
                      View
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
