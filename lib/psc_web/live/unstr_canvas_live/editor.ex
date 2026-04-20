defmodule PscWeb.UnstrCanvasLive.Editor do
  use PscWeb, :live_view
  alias Psc.Canvas

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    canvas = Canvas.get_unstr_canvas_with_author(id)
    user_email = socket.assigns.current_scope.user.email

    if canvas && Canvas.can_access_unstr_canvas?(canvas, user_email) do
      {:ok,
       socket
       |> assign(:canvas, canvas)
       |> assign(:page_title, canvas.name)}
    else
      {:ok,
       socket
       |> put_flash(:error, "Canvas not found")
       |> redirect(to: ~p"/canvas-designer")}
    end
  end

  @impl true
  def handle_event("update_name", %{"value" => name}, socket) do
    canvas = socket.assigns.canvas

    case Canvas.update_unstr_canvas(canvas, %{name: name}) do
      {:ok, updated_canvas} ->
        {:noreply,
         socket
         |> assign(:canvas, updated_canvas)
         |> put_flash(:info, "Canvas name updated")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update canvas")}
    end
  end

  @impl true
  def handle_event("update_description", %{"value" => description}, socket) do
    canvas = socket.assigns.canvas

    case Canvas.update_unstr_canvas(canvas, %{description: description}) do
      {:ok, updated_canvas} ->
        {:noreply,
         socket
         |> assign(:canvas, updated_canvas)
         |> put_flash(:info, "Canvas description updated")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update canvas")}
    end
  end

  @impl true
  def handle_event("update_cell", %{"cell_key" => cell_key, "field" => field, "value" => value}, socket) do
    canvas = socket.assigns.canvas
    cells = canvas.cells || %{}
    cell_data = cells[cell_key] || %{}

    updated_cell = Map.put(cell_data, field, value)
    updated_cells = Map.put(cells, cell_key, updated_cell)

    case Canvas.update_unstr_canvas(canvas, %{cells: updated_cells}) do
      {:ok, updated_canvas} ->
        {:noreply,
         socket
         |> assign(:canvas, updated_canvas)
         |> put_flash(:info, "Cell updated")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update cell")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} container_class={"w-full mx-auto max-w-screen-xl space-y-4"}>
      <div class="w-full max-w-screen-xl mx-auto px-4 py-8">
        <%!-- Header --%>
        <div class="flex items-center justify-between mb-8">
          <div class="flex-1">
            <input
              type="text"
              value={@canvas.name}
              phx-change="update_name"
              phx-debounce="1000"
              class="text-3xl font-bold text-gray-900 bg-transparent border-b-2 border-transparent hover:border-gray-300 focus:border-blue-500 focus:outline-none w-full"
              placeholder="Canvas name"
            />
          </div>
          <.link navigate={~p"/canvas-designer"} class="text-sm text-blue-600 hover:text-blue-700">
            Back to Canvases
          </.link>
        </div>

        <%!-- Description --%>
        <div class="mb-8">
          <textarea
            phx-change="update_description"
            phx-debounce="1000"
            class="w-full px-4 py-2 border border-gray-300 rounded-lg text-gray-600 focus:outline-none focus:ring-2 focus:ring-blue-500"
            placeholder="Canvas description..."
            rows="2"
          ><%= @canvas.description %></textarea>
        </div>

        <%!-- Canvas Grid --%>
        <div class="bg-white rounded-lg shadow p-8 w-full">
          <h2 class="text-2xl font-bold text-gray-900 mb-6">Canvas Structure</h2>

          <%!-- Display columns and rows --%>
          <div class="mb-8">
            <h3 class="text-lg font-semibold text-gray-900 mb-4">Columns</h3>
            <div class="flex flex-wrap gap-2">
              <%= for column <- @canvas.cells["columns"] || [] do %>
                <div class="px-3 py-2 bg-blue-100 text-blue-800 rounded-lg text-sm font-medium">
                  <%= column["label"] %>
                </div>
              <% end %>
            </div>
          </div>

          <div class="mb-8">
            <h3 class="text-lg font-semibold text-gray-900 mb-4">Rows</h3>
            <div class="flex flex-wrap gap-2">
              <%= for row <- @canvas.cells["rows"] || [] do %>
                <div class="px-3 py-2 bg-green-100 text-green-800 rounded-lg text-sm font-medium">
                  <%= row["label"] %>
                </div>
              <% end %>
            </div>
          </div>

          <%!-- Grid Layout --%>
          <div class="overflow-x-auto">
            <table class="w-full border-collapse">
              <thead>
                <tr>
                  <th class="px-4 py-2 border border-gray-300 bg-gray-100"></th>
                  <%= for column <- @canvas.cells["columns"] || [] do %>
                    <th class="px-4 py-2 border border-gray-300 bg-gray-100 font-semibold text-gray-900">
                      <%= column["label"] %>
                    </th>
                  <% end %>
                </tr>
              </thead>
              <tbody>
                <%= for {row, row_index} <- Enum.with_index(@canvas.cells["rows"] || []) do %>
                  <tr>
                    <td class="px-4 py-2 border border-gray-300 bg-gray-100 font-semibold text-gray-900">
                      <%= row["label"] %>
                    </td>
                    <%= for {_column, col_index} <- Enum.with_index(@canvas.cells["columns"] || []) do %>
                      <% layout = @canvas.cells["layout"] || [] %>
                      <% cell_key = Enum.at(Enum.at(layout, row_index, []), col_index) %>
                      <td class="px-4 py-2 border border-gray-300">
                        <%= if cell_key do %>
                          <div class="text-sm font-medium text-gray-900">
                            <%= cell_key %>
                          </div>
                          <% cell_data = @canvas.cells[cell_key] || %{} %>
                          <div class="mt-2 space-y-2 text-xs">
                            <%= for {field, value} <- cell_data do %>
                              <%= if field not in ["row", "column"] do %>
                                <div>
                                  <label class="block text-gray-600"><%= field %>:</label>
                                  <input
                                    type="text"
                                    value={value}
                                    phx-change="update_cell"
                                    phx-value-cell_key={cell_key}
                                    phx-value-field={field}
                                    class="w-full px-2 py-1 border border-gray-300 rounded text-gray-900"
                                    placeholder="Enter value..."
                                  />
                                </div>
                              <% end %>
                            <% end %>
                          </div>
                        <% end %>
                      </td>
                    <% end %>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
