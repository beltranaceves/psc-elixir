defmodule PscWeb.CanvasLayoutLive.New do
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
  def handle_event("create_layout", %{"name" => name, "description" => description, "layout_json" => layout_json}, socket) do
    attrs = %{"name" => name, "description" => description}

    layout_map =
      case Jason.decode(layout_json || "") do
        {:ok, map} when is_map(map) -> map
        _ -> %{}
      end

    attrs = Map.put(attrs, "layout_map", layout_map)

    case Canvas.create_canvas_layout(attrs) do
      {:ok, _layout} ->
        layouts = Canvas.list_canvas_layouts()
        {:noreply, socket |> assign(:layouts, layouts) |> put_flash(:info, "Layout created")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create layout")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="w-full max-w-3xl mx-auto px-4 py-8">
        <h1 class="text-2xl font-bold mb-4">Create Canvas Layout</h1>

        <div class="bg-white rounded-lg shadow p-6 mb-8">
          <.form for={@new_layout_form} id="new-layout-form" phx-submit="create_layout" class="space-y-4">
            <.input field={@new_layout_form[:name]} type="text" label="Layout Name" required />
            <.input field={@new_layout_form[:description]} type="textarea" label="Description" />
            <div>
              <label class="block text-sm font-medium text-gray-700">Layout JSON</label>
              <textarea name="layout_json" rows="8" class="mt-1 block w-full rounded border px-3 py-2" placeholder='{"layout": [["a","b"]], "a": {...}}'></textarea>
              <p class="text-xs text-gray-500 mt-1">Paste a JSON object describing the layout structure (columns, rows, layout and cell entries).</p>
            </div>

            <div>
              <button type="submit" class="px-4 py-2 bg-blue-600 text-white rounded">Create Layout</button>
            </div>
          </.form>
        </div>

        <div>
          <h2 class="text-lg font-semibold mb-2">Existing Layouts</h2>
          <%= if Enum.empty?(@layouts) do %>
            <p class="text-gray-600">No saved layouts yet.</p>
          <% else %>
            <ul class="space-y-2">
              <%= for l <- @layouts do %>
                <li class="p-2 border rounded">
                  <div class="flex items-center justify-between">
                    <div>
                      <div class="font-medium"><%= l.name %></div>
                      <div class="text-sm text-gray-600"><%= l.description %></div>
                    </div>
                    <div class="text-sm text-gray-500"><%= NaiveDateTime.to_string(l.inserted_at || ~N[1970-01-01 00:00:00]) %></div>
                  </div>
                </li>
              <% end %>
            </ul>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
