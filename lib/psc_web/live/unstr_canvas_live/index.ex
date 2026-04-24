defmodule PscWeb.UnstrCanvasLive.Index do
  use PscWeb, :live_view
  alias Psc.Canvas

  @impl true
  def mount(_params, _session, socket) do
    user_id = socket.assigns.current_scope.user.id
    user_email = socket.assigns.current_scope.user.email

    my_canvases = Canvas.list_user_unstr_canvases(user_id)
    shared_canvases = Canvas.list_shared_unstr_canvases(user_email)
    layouts = Canvas.list_canvas_layouts()
    layout_options = [{"Default", ""} | Enum.map(layouts, fn l -> {l.name, l.id} end)]

    {:ok,
     socket
     |> assign(:my_canvases, my_canvases)
     |> assign(:shared_canvases, shared_canvases)
      |> assign(:new_canvas_form, to_form(%{}))
      |> assign(:layouts, layouts)
      |> assign(:layout_options, layout_options)}
  end

  @impl true
  def handle_event("create_canvas", params, socket) do
    name = params["name"]
    description = params["description"]
    layout_id = params["layout_id"]

    user_id = socket.assigns.current_scope.user.id

    attrs = %{"name" => name, "description" => description}

    attrs =
      if is_binary(layout_id) and layout_id != "" do
        case Canvas.get_canvas_layout(layout_id) do
          %{} = layout -> Map.put(attrs, "cells", layout.layout_map || %{})
          _ -> attrs
        end
      else
        attrs
      end

    case Canvas.create_unstr_canvas(user_id, attrs) do
      {:ok, _canvas} ->
        my_canvases = Canvas.list_user_unstr_canvases(user_id)
        {:noreply,
         socket
         |> assign(:my_canvases, my_canvases)
         |> put_flash(:info, "Canvas created successfully")}

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

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} container_class={"w-full mx-auto max-w-screen-xl"}>
      <div class="max-w-6xl mx-auto px-4 py-8">
        <div class="flex items-center justify-between mb-8">
          <h1 class="text-3xl font-bold text-gray-900">Canvas Designer</h1>
          <.link navigate={~p"/documents"} class="text-sm text-blue-600 hover:text-blue-700">
            Back to Documents
          </.link>
        </div>

        <%!-- Create New Canvas Form --%>
        <div class="mb-8 bg-white rounded-lg shadow p-6">
          <h2 class="text-xl font-semibold text-gray-900 mb-4">Create New Canvas</h2>
          <.form for={@new_canvas_form} id="new-canvas-form" phx-submit="create_canvas" class="space-y-4">
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
              field={@new_canvas_form[:layout_id]}
              type="select"
              options={@layout_options}
              label="Layout"
            />
            <button
              type="submit"
              class="px-4 py-2 bg-blue-600 text-white font-medium rounded-lg hover:bg-blue-700 transition focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
            >
              Create Canvas
            </button>
          </.form>
        </div>

        <%!-- My Canvases --%>
        <div class="mb-12">
          <h2 class="text-2xl font-bold text-gray-900 mb-4">My Canvases</h2>
          <%= if Enum.empty?(@my_canvases) do %>
            <div class="bg-gray-50 rounded-lg p-8 text-center">
              <p class="text-gray-600">No canvases yet. Create one to get started!</p>
            </div>
          <% else %>
            <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
              <%= for canvas <- @my_canvases do %>
                <div class="bg-white rounded-lg shadow hover:shadow-md transition p-6">
                  <h3 class="text-lg font-semibold text-gray-900"><%= canvas.name %></h3>
                  <p class="text-sm text-gray-600 mt-2"><%= canvas.description %></p>
                  <div class="mt-4 flex gap-2">
                    <.link
                      navigate={~p"/canvas-designer/#{canvas.id}"}
                      class="flex-1 px-4 py-2 bg-blue-600 text-white text-sm font-medium rounded-lg hover:bg-blue-700 transition text-center"
                    >
                      Edit
                    </.link>
                    <button
                      phx-click="delete_canvas"
                      phx-value-id={canvas.id}
                      onclick="return confirm('Delete this canvas?')"
                      class="px-4 py-2 bg-red-600 text-white text-sm font-medium rounded-lg hover:bg-red-700 transition focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-red-500"
                    >
                      Delete
                    </button>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>

        <%!-- Shared with Me --%>
        <%= if Enum.any?(@shared_canvases) do %>
          <div>
            <h2 class="text-2xl font-bold text-gray-900 mb-4">Shared with Me</h2>
            <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
              <%= for canvas <- @shared_canvases do %>
                <div class="bg-white rounded-lg shadow hover:shadow-md transition p-6 border-l-4 border-green-500">
                  <div class="flex items-start justify-between">
                    <div>
                      <h3 class="text-lg font-semibold text-gray-900"><%= canvas.name %></h3>
                      <p class="text-sm text-gray-600 mt-1">by <%= canvas.author.email %></p>
                    </div>
                  </div>
                  <p class="text-sm text-gray-600 mt-2"><%= canvas.description %></p>
                  <div class="mt-4">
                    <.link
                      navigate={~p"/canvas-designer/#{canvas.id}"}
                      class="block w-full px-4 py-2 bg-green-600 text-white text-sm font-medium rounded-lg hover:bg-green-700 transition text-center"
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
