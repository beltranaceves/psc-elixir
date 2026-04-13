defmodule PscWeb.CanvasLayoutLive.New do
  use PscWeb, :live_view
  alias Psc.Canvas

  @impl true
  def mount(_params, _session, socket) do
    layouts = Canvas.list_canvas_layouts()

    # initialize an empty editor layout structure
    layout_map = %{
      "columns" => [],
      "rows" => [],
      "layout" => []
    }

    layout_map = ensure_matrix_keys(layout_map)

    {:ok,
     socket
     |> assign(:layouts, layouts)
     |> assign(:new_layout_form, to_form(%{}))
     |> assign(:layout_map, layout_map)}
  end

  @impl true
  def handle_event("add_column", _params, socket) do
    layout = socket.assigns.layout_map
    cols = layout["columns"] || []
    idx = length(cols) + 1
    id = "col_#{idx}"
    new_col = %{"id" => id, "label" => "Column #{idx}"}
    new_cols = cols ++ [new_col]

    # extend each row in layout matrix
    matrix = layout["layout"] || []
    new_matrix =
      if matrix == [] do
        [[id]]
      else
        Enum.map(matrix, fn row -> row ++ [nil] end)
      end

    new_layout = layout |> Map.put("columns", new_cols) |> Map.put("layout", new_matrix)
    new_layout = ensure_matrix_keys(new_layout)
    {:noreply, assign(socket, :layout_map, new_layout)}
  end

  def handle_event("remove_column", %{"index" => index}, socket) do
    idx = String.to_integer(index)
    layout = socket.assigns.layout_map
    cols = layout["columns"] || []
    new_cols = List.delete_at(cols, idx)
    matrix = layout["layout"] || []
    new_matrix = Enum.map(matrix, fn row -> List.delete_at(row, idx) end)
    new_layout = layout |> Map.put("columns", new_cols) |> Map.put("layout", new_matrix)
    {:noreply, assign(socket, :layout_map, new_layout)}
  end

  def handle_event("update_column_label", %{"index" => index, "label" => label}, socket) do
    idx = String.to_integer(index)
    layout = socket.assigns.layout_map
    cols = layout["columns"] || []
    new_cols = List.update_at(cols, idx, fn col -> Map.put(col, "label", label) end)
    {:noreply, assign(socket, :layout_map, Map.put(layout, "columns", new_cols))}
  end

  def handle_event("add_row", _params, socket) do
    layout = socket.assigns.layout_map
    rows = layout["rows"] || []
    idx = length(rows) + 1
    id = "row_#{idx}"
    new_row_meta = %{"id" => id, "label" => "Row #{idx}"}

    cols_len = length(layout["columns"] || [])
    new_row = List.duplicate(nil, cols_len)

    new_rows = rows ++ [new_row_meta]
    new_matrix = (layout["layout"] || []) ++ [new_row]
    new_layout = layout |> Map.put("rows", new_rows) |> Map.put("layout", new_matrix)
    new_layout = ensure_matrix_keys(new_layout)
    {:noreply, assign(socket, :layout_map, new_layout)}
  end

  def handle_event("remove_row", %{"index" => index}, socket) do
    idx = String.to_integer(index)
    layout = socket.assigns.layout_map
    rows = layout["rows"] || []
    new_rows = List.delete_at(rows, idx)
    matrix = layout["layout"] || []
    new_matrix = List.delete_at(matrix, idx)
    new_layout = layout |> Map.put("rows", new_rows) |> Map.put("layout", new_matrix)
    {:noreply, assign(socket, :layout_map, new_layout)}
  end

  def handle_event("update_row_label", %{"index" => index, "label" => label}, socket) do
    idx = String.to_integer(index)
    layout = socket.assigns.layout_map
    rows = layout["rows"] || []
    new_rows = List.update_at(rows, idx, fn r -> Map.put(r, "label", label) end)
    {:noreply, assign(socket, :layout_map, Map.put(layout, "rows", new_rows))}
  end

  def handle_event("set_cell_key", %{"row" => r, "col" => c, "cell_key" => cell_key}, socket) do
    ri = String.to_integer(r)
    ci = String.to_integer(c)
    layout = socket.assigns.layout_map
    matrix = layout["layout"] || []
    # ensure row exists
    updated_matrix = List.update_at(matrix, ri, fn row -> List.replace_at(row, ci, if(cell_key == "", do: nil, else: cell_key)) end)

    # ensure cell entry exists
    new_layout = layout |> Map.put("layout", updated_matrix)
    new_layout = if cell_key != "" and not Map.has_key?(new_layout, cell_key), do: Map.put(new_layout, cell_key, %{}), else: new_layout

    {:noreply, assign(socket, :layout_map, new_layout)}
  end

  # Ensure every position in the layout matrix has a cell key
  defp ensure_matrix_keys(layout) do
    cols = layout["columns"] || []
    rows = layout["rows"] || []
    matrix = layout["layout"] || []

    {updated_matrix, cell_entries} =
      matrix
      |> Enum.with_index()
      |> Enum.map_reduce(%{}, fn {row_list, ri}, acc ->
        new_row =
          row_list
          |> Enum.with_index()
          |> Enum.map_reduce(acc, fn {cell_key, ci}, acc2 ->
            if cell_key && cell_key != "" do
              {cell_key, acc2}
            else
              row_meta = Enum.at(rows, ri, %{"id" => "r#{ri}"})
              col_meta = Enum.at(cols, ci, %{"id" => "c#{ci}"})
              gen_key = "#{col_meta["id"]}_#{row_meta["id"]}"
              {gen_key, Map.put(acc2, gen_key, %{})}
            end
          end)

        # new_row is {row_values, acc_after_row}
        {elem(new_row, 0), elem(new_row, 1)}
      end)

    # updated_matrix is a list of rows; cell_entries contains newly added empty maps
    merged = Map.merge(layout, %{"layout" => updated_matrix})

    # ensure we have empty maps for all cell keys
    cell_entries = Enum.into(cell_entries, %{})
    merged = Enum.reduce(cell_entries, merged, fn {k, v}, acc -> Map.put_new(acc, k, v) end)

    merged
  end

  def handle_event("update_cell_field", %{"cell_key" => cell_key, "field" => field, "value" => value}, socket) do
    layout = socket.assigns.layout_map
    cell = Map.get(layout, cell_key, %{})
    new_cell = Map.put(cell, field, value)
    new_layout = Map.put(layout, cell_key, new_cell)
    {:noreply, assign(socket, :layout_map, new_layout)}
  end

  def handle_event("add_cell_field", params, socket) do
    cell_key = Map.get(params, "cell_key", "") |> to_string()
    new_field = String.trim(to_string(Map.get(params, "new_field", "")))
    row_idx = Map.get(params, "row")
    col_idx = Map.get(params, "col")

    if new_field == "" do
      {:noreply, put_flash(socket, :error, "Field name required")}
    else
      layout = socket.assigns.layout_map

      {cell_key, layout} =
        if cell_key == "" do
          # generate a key from row/col meta ids when missing and write it into the matrix
          if row_idx && col_idx do
            ri = String.to_integer(row_idx)
            ci = String.to_integer(col_idx)
            row_meta = Enum.at(layout["rows"] || [], ri, %{"id" => "r#{ri}"})
            col_meta = Enum.at(layout["columns"] || [], ci, %{"id" => "c#{ci}"})
            generated = "#{col_meta["id"]}_#{row_meta["id"]}"

            matrix = layout["layout"] || []
            updated_matrix = List.update_at(matrix, ri, fn row -> List.replace_at(row, ci, generated) end)
            {generated, Map.put(layout, "layout", updated_matrix)}
          else
            {cell_key, layout}
          end
        else
          {cell_key, layout}
        end

      cell = Map.get(layout, cell_key, %{})
      cell = Map.put_new(cell, new_field, "")
      new_layout = Map.put(layout, cell_key, cell)
      {:noreply, assign(socket, :layout_map, new_layout)}
    end
  end

  def handle_event("remove_cell_field", %{"cell_key" => cell_key, "field" => field}, socket) do
    layout = socket.assigns.layout_map
    cell = Map.get(layout, cell_key, %{})
    new_cell = Map.drop(cell, [field])
    new_layout = Map.put(layout, cell_key, new_cell)
    {:noreply, assign(socket, :layout_map, new_layout)}
  end

  def handle_event("save_layout", %{"name" => name, "description" => description}, socket) do
    attrs = %{"name" => name, "description" => description, "layout_map" => socket.assigns.layout_map}

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
      <div class="w-full max-w-4xl mx-auto px-4 py-8">
        <h1 class="text-2xl font-bold mb-4 text-gray-900">Graphical Layout Editor</h1>

        <div class="bg-white rounded-lg shadow p-6 mb-6">
          <.form for={@new_layout_form} id="new-layout-form" phx-submit="save_layout" class="space-y-4">
            <.input
              field={@new_layout_form[:name]}
              type="text"
              label="Layout Name"
              class="mt-1 block w-full rounded border px-3 py-2 text-gray-900 bg-white"
              error_class="border-red-500"
              required
            />

            <.input
              field={@new_layout_form[:description]}
              type="textarea"
              label="Description"
              class="mt-1 block w-full rounded border px-3 py-2 text-gray-900 bg-white"
              error_class="border-red-500"
            />

            <div class="flex gap-2">
              <button type="button" phx-click="add_column" class="px-3 py-1 bg-blue-600 text-white rounded">Add Column</button>
              <button type="button" phx-click="add_row" class="px-3 py-1 bg-green-600 text-white rounded">Add Row</button>
              <button type="submit" class="ml-auto px-4 py-1 bg-indigo-600 text-white rounded">Save Layout</button>
            </div>
          </.form>
        </div>

        <div class="bg-white rounded-lg shadow p-6 mb-8 overflow-auto">
          <h2 class="font-semibold mb-4">Editor</h2>
          <div class="mb-4">
            <h3 class="text-sm font-medium mb-2 text-gray-900">Columns</h3>
            <div class="flex gap-2 items-start">
              <%= for {col, idx} <- Enum.with_index(@layout_map["columns"] || []) do %>
                <div class="flex items-center gap-2 p-2 border rounded bg-gray-50">
                  <input type="text" value={col["label"]} phx-change="update_column_label" phx-debounce="300" phx-value-index={idx} name="label" class="px-2 py-1 border rounded text-gray-900 bg-white" />
                  <button type="button" phx-click="remove_column" phx-value-index={idx} class="text-sm text-red-600">Remove</button>
                </div>
              <% end %>
            </div>
          </div>

          <div>
            <h3 class="text-sm font-medium mb-2 text-gray-900">Rows & Grid</h3>
            <table class="w-full border-collapse table-fixed">
              <thead>
                <tr>
                  <th class="w-40 p-2 border bg-gray-100 text-gray-900"></th>
                  <%= for col <- @layout_map["columns"] || [] do %>
                    <th class="p-2 border text-center bg-gray-100 text-gray-900"><%= col["label"] %></th>
                  <% end %>
                </tr>
              </thead>
              <tbody>
                <%= for {row_meta, r_idx} <- Enum.with_index(@layout_map["rows"] || []) do %>
                  <tr>
                    <td class="p-2 border align-top bg-gray-50">
                      <input type="text" value={row_meta["label"]} phx-change="update_row_label" phx-debounce="300" phx-value-index={r_idx} name="label" class="px-2 py-1 border rounded w-full text-gray-900 bg-white" />
                      <div class="mt-2">
                        <button type="button" phx-click="remove_row" phx-value-index={r_idx} class="text-sm text-red-600">Remove Row</button>
                      </div>
                    </td>
                    <%= for {cell_key, c_idx} <- Enum.with_index(Enum.at(@layout_map["layout"] || [], r_idx, [])) do %>
                      <td class="p-2 border align-top bg-white text-gray-900">
                        <div class="text-xs text-gray-700 mb-1">Key:</div>
                        <input type="text" value={cell_key || ""} phx-change="set_cell_key" phx-debounce="300" phx-value-row={r_idx} phx-value-col={c_idx} name="cell_key" class="px-2 py-1 border rounded w-full text-gray-900 bg-white" />

                        <div class="mt-2">
                          <h4 class="text-xs font-semibold text-gray-900">Fields</h4>
                          <%= if cell_key do %>
                            <%= for {field, value} <- Map.get(@layout_map, cell_key, %{}) do %>
                              <div class="mt-1 flex items-center gap-2">
                                <input type="text" value={field} disabled class="px-2 py-1 border rounded w-1/3 mr-2 bg-gray-200 text-gray-800" />
                                <input type="text" value={value} phx-change="update_cell_field" phx-debounce="300" phx-value-cell_key={cell_key} phx-value-field={field} name="value" class="px-2 py-1 border rounded w-2/3 text-gray-900 bg-white" />
                                <button type="button" phx-click="remove_cell_field" phx-value-cell_key={cell_key} phx-value-field={field} class="text-sm text-red-600">Remove</button>
                              </div>
                            <% end %>
                          <% else %>
                            <div class="text-sm text-gray-600">No key assigned to this cell yet — add a field to create one.</div>
                          <% end %>

                          <form phx-submit="add_cell_field" class="mt-2 flex gap-2">
                            <input type="hidden" name="cell_key" value={cell_key || ""} />
                            <input type="hidden" name="row" value={to_string(r_idx)} />
                            <input type="hidden" name="col" value={to_string(c_idx)} />
                            <input name="new_field" placeholder="New field name" class="px-2 py-1 border rounded w-2/3" />
                            <button type="submit" class="px-2 py-1 bg-blue-600 text-white rounded">Add</button>
                          </form>
                        </div>
                      </td>
                    <% end %>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
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
