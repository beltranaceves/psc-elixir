defmodule PscWeb.CanvasLayoutLive.Index do
  use PscWeb, :live_view
  alias Psc.Canvas

  @impl true
  def mount(_params, _session, socket) do
    layouts = Canvas.list_canvas_layouts()

    {:ok,
     socket
     |> assign(:layouts, layouts)
     |> assign(:new_layout_form, to_form(%{}))}
  end

  @impl true
  def handle_event("create_layout", %{"name" => name, "description" => description}, socket) do
    attrs = %{"name" => name, "description" => description, "layout_map" => %{}}

    case Canvas.create_canvas_layout(attrs) do
      {:ok, _layout} ->
        layouts = Canvas.list_canvas_layouts()
        {:noreply, socket |> assign(:layouts, layouts) |> put_flash(:info, "Layout created")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create layout")}
    end
  end

  def handle_event("delete_layout", %{"id" => id}, socket) do
    case Canvas.get_canvas_layout(id) do
      %{} = layout ->
        Canvas.delete_canvas_layout(layout)
        layouts = Canvas.list_canvas_layouts()
        {:noreply, socket |> assign(:layouts, layouts) |> put_flash(:info, "Layout deleted")}

      _ ->
        {:noreply, put_flash(socket, :error, "Layout not found")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      container_class="w-full mx-auto max-w-screen-xl"
    >
      <div class="max-w-4xl mx-auto px-4 py-8">
        <div class="flex items-center justify-between mb-8">
          <h1 class="text-3xl font-bold text-gray-900">Canvas Layouts</h1>
          <.link navigate={~p"/canvas-layouts/new"} class="text-sm text-blue-600 hover:text-blue-700">
            New Layout
          </.link>
        </div>

        <div class="mb-8 bg-white rounded-lg shadow p-6">
          <h2 class="text-xl font-semibold text-gray-900 mb-4">Create New Layout</h2>
          <.form
            for={@new_layout_form}
            id="new-layout-form"
            phx-submit="create_layout"
            class="space-y-4"
          >
            <.input
              field={@new_layout_form[:name]}
              type="text"
              label="Layout Name"
              placeholder="Enter layout name..."
              required
            />

            <.input
              field={@new_layout_form[:description]}
              type="textarea"
              label="Description"
              placeholder="Enter layout description..."
            />

            <button
              type="submit"
              class="px-4 py-2 bg-blue-600 text-white font-medium rounded-lg hover:bg-blue-700 transition focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
            >
              Create Layout
            </button>
          </.form>
        </div>

        <div>
          <h2 class="text-2xl font-bold text-gray-900 mb-4">Existing Layouts</h2>
          <%= if Enum.empty?(@layouts) do %>
            <div class="bg-gray-50 rounded-lg p-8 text-center">
              <p class="text-gray-600">No layouts yet. Create one to get started!</p>
            </div>
          <% else %>
            <div class="grid grid-cols-1 gap-4">
              <%= for l <- @layouts do %>
                <div class="bg-white rounded-lg shadow p-4 flex items-start justify-between">
                  <div>
                    <div class="font-medium text-gray-900">{l.name}</div>
                    <div class="text-sm text-gray-600">{l.description}</div>
                  </div>
                  <div class="flex items-center gap-2">
                    <.link
                      navigate={~p"/canvas-layouts/#{l.id}"}
                      class="px-3 py-1 bg-indigo-600 text-white rounded text-sm"
                    >
                      Edit
                    </.link>
                    <button
                      phx-click="delete_layout"
                      phx-value-id={l.id}
                      onclick="return confirm('Delete this layout?')"
                      class="px-3 py-1 bg-red-600 text-white rounded text-sm focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-red-500"
                    >
                      Delete
                    </button>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
