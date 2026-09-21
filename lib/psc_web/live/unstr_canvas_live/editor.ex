defmodule PscWeb.UnstrCanvasLive.Editor do
  use PscWeb, :live_view
  alias Psc.Canvas
  alias PscWeb.Presence
  require Logger

  @idle_save_interval 1500
  @periodic_save_interval 10000

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    canvas = Canvas.get_unstr_canvas_with_author(id)
    user_email = socket.assigns.current_scope.user.email

    if canvas && Canvas.can_access_unstr_canvas?(canvas, user_email) do
      # Make sure cells are completely up to date with events
      cells = Canvas.get_unstr_canvas_content(id)

      # For text attributes tracked in CRDT map, merge if present
      c_name = Map.get(cells, "$name", canvas.name)
      c_desc = Map.get(cells, "$description", canvas.description)

      socket =
        socket
        |> assign(:canvas, canvas)
        |> assign(:canvas_id, id)
        |> assign(:client_id, Integer.to_string(:erlang.unique_integer([:positive])))
        |> assign(:user_id, socket.assigns.current_scope.user.id)
        |> assign(:username, user_email)
        |> assign(:cells, cells)
        |> assign(:c_name, c_name)
        |> assign(:c_desc, c_desc)
        |> assign(:presence, %{})
        |> assign(:page_title, c_name)
        |> assign(:last_saved_cells, cells)
        |> assign(:idle_timer_ref, nil)
        |> subscribe_to_canvas(id)

      if connected?(socket) do
        Process.send_after(self(), :periodic_save, @periodic_save_interval)
      end

      {:ok, socket}
    else
      {:ok,
       socket
       |> put_flash(:error, "Canvas not found")
       |> redirect(to: ~p"/canvas-designer")}
    end
  end

  defp subscribe_to_canvas(socket, canvas_id) do
    if connected?(socket) do
      topic = Canvas.pubsub_topic_unstr(canvas_id)
      :ok = Phoenix.PubSub.subscribe(Psc.PubSub, topic)
      :ok = Phoenix.PubSub.subscribe(Psc.PubSub, "presence_unstr:#{canvas_id}")
      Logger.debug("[UnstrCanvasLive] subscribed pid=#{inspect(self())} topic=#{topic}")

      Presence.track(self(), "presence_unstr:#{canvas_id}", socket.assigns.user_id, %{
        username: socket.assigns.username,
        cursor_pos: nil
      })

      handle_presence_change(socket, canvas_id)
    else
      socket
    end
  end

  defp process_operation(socket, operation) do
    Canvas.apply_unstr_canvas_operation(
      socket.assigns.canvas_id,
      socket.assigns.user_id,
      socket.assigns.client_id,
      operation
    )

    cells = Psc.Canvas.UnstrCanvasCRDT.apply_operation(operation, socket.assigns.cells)

    Logger.debug(
      "[UnstrCanvasLive] applied operation: canvas_id=#{socket.assigns.canvas_id} user_id=#{socket.assigns.user_id} op=#{inspect(operation)} resulting_cells_sample=#{inspect(Map.take(cells, ["cells", "layout", "columns", "rows"]))}"
    )

    c_name = Map.get(cells, "$name", socket.assigns.c_name)
    c_desc = Map.get(cells, "$description", socket.assigns.c_desc)

    socket =
      if socket.assigns.idle_timer_ref do
        Process.cancel_timer(socket.assigns.idle_timer_ref)
        assign(socket, idle_timer_ref: nil)
      else
        socket
      end

    idle_timer_ref = Process.send_after(self(), :idle_save, @idle_save_interval)

    socket
    |> assign(:cells, cells)
    |> assign(:c_name, c_name)
    |> assign(:c_desc, c_desc)
    |> assign(:idle_timer_ref, idle_timer_ref)
  end

  @impl true
  def handle_event("share_canvas", %{"email" => email}, socket) do
    if socket.assigns.canvas.author_id == socket.assigns.user_id do
      case Canvas.share_unstr_canvas_with(socket.assigns.canvas, email) do
        {:ok, updated_canvas} ->
          {:noreply,
           socket
           |> assign(:canvas, updated_canvas)
           |> put_flash(:info, "Canvas shared with #{email}")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to share canvas")}
      end
    else
      {:noreply, put_flash(socket, :error, "Only canvas owner can share")}
    end
  end

  @impl true
  def handle_event("remove_access", %{"email" => email}, socket) do
    if socket.assigns.canvas.author_id == socket.assigns.user_id do
      case Canvas.unshare_unstr_canvas(socket.assigns.canvas, email) do
        {:ok, updated_canvas} ->
          {:noreply,
           socket
           |> assign(:canvas, updated_canvas)
           |> put_flash(:info, "Access removed for #{email}")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to remove access")}
      end
    else
      {:noreply, put_flash(socket, :error, "Only canvas owner can remove access")}
    end
  end

  @impl true
  def handle_event("update_name", %{"value" => name}, socket) do
    operation = %{"type" => "update_name", "value" => name}
    socket = process_operation(socket, operation)
    {:noreply, socket}
  end

  @impl true
  def handle_event("update_description", %{"value" => description}, socket) do
    operation = %{"type" => "update_description", "value" => description}
    socket = process_operation(socket, operation)
    {:noreply, socket}
  end

  @impl true
  def handle_event("update_cell", %{"cell_key" => cell_key, "values" => values}, socket) do
    socket =
      values
      |> Enum.reject(fn {field, _value} -> String.starts_with?(field, "_unused_") end)
      |> Enum.reduce(socket, fn {field, value}, acc ->
        operation = %{
          "type" => "update_cell",
          "cell_key" => cell_key,
          "field" => field,
          "value" => value
        }

        process_operation(acc, operation)
      end)

    {:noreply, socket}
  end

  def handle_event(
        "update_cell",
        %{"cell_key" => cell_key, "field" => field, "value" => value},
        socket
      ) do
    operation = %{
      "type" => "update_cell",
      "cell_key" => cell_key,
      "field" => field,
      "value" => value
    }

    socket = process_operation(socket, operation)
    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "render_field",
        %{"cell_key" => cell_key, "field" => field, "value" => value},
        socket
      ) do
    html =
      case value do
        nil ->
          ""

        v ->
          trimmed = String.trim(v || "")

          if trimmed == "" do
            # placeholder HTML for empty fields (keeps area clickable)
            "<div class=\"p-2 rounded bg-gray-50 text-gray-400\">Click to edit</div>"
          else
            try do
              Earmark.as_html!(v || "")
            rescue
              _ -> Phoenix.HTML.html_escape(v || "") |> Phoenix.HTML.safe_to_string()
            end
          end
      end

    socket = push_event(socket, "field_rendered", %{cell_key: cell_key, field: field, html: html})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:operation, user_id, client_id, operation, _seq}, socket) do
    # New broadcasts include a per-client id so multiple tabs by same user get updates
    if client_id != socket.assigns.client_id do
      Logger.debug(
        "[UnstrCanvasLive] received broadcast operation from user_id=#{user_id} client_id=#{client_id}: #{inspect(operation)}"
      )

      cells = Psc.Canvas.UnstrCanvasCRDT.apply_operation(operation, socket.assigns.cells)
      c_name = Map.get(cells, "$name", socket.assigns.c_name)
      c_desc = Map.get(cells, "$description", socket.assigns.c_desc)

      Logger.debug(
        "[UnstrCanvasLive] after broadcast apply resulting_cells_sample=#{inspect(Map.take(cells, ["cells"]))}"
      )

      # If this operation updated a cell field, notify the client-side hooks
      socket =
        case operation do
          %{"type" => "update_cell", "cell_key" => cell_key, "field" => field, "value" => _value} ->
            new_value =
              get_in(cells, ["cells", cell_key, field]) ||
                (cells[cell_key] && Map.get(cells[cell_key], field)) || ""

            push_event(socket, "cell_updated", %{
              cell_key: cell_key,
              field: field,
              new_value: new_value,
              from_user_id: user_id
            })

          _ ->
            socket
        end

      {:noreply,
       socket
       |> assign(:cells, cells)
       |> assign(:c_name, c_name)
       |> assign(:c_desc, c_desc)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:operation, user_id, operation, _seq}, socket) do
    # Backwards-compatible handler for broadcasts without client_id
    if user_id != socket.assigns.user_id do
      Logger.debug(
        "[UnstrCanvasLive] received legacy broadcast operation from user_id=#{user_id}: #{inspect(operation)}"
      )

      cells = Psc.Canvas.UnstrCanvasCRDT.apply_operation(operation, socket.assigns.cells)
      c_name = Map.get(cells, "$name", socket.assigns.c_name)
      c_desc = Map.get(cells, "$description", socket.assigns.c_desc)

      Logger.debug(
        "[UnstrCanvasLive] after legacy apply resulting_cells_sample=#{inspect(Map.take(cells, ["cells"]))}"
      )

      # Notify client-side hooks for cell updates (legacy broadcasts)
      socket =
        case operation do
          %{"type" => "update_cell", "cell_key" => cell_key, "field" => field, "value" => _value} ->
            new_value =
              get_in(cells, ["cells", cell_key, field]) ||
                (cells[cell_key] && Map.get(cells[cell_key], field)) || ""

            push_event(socket, "cell_updated", %{
              cell_key: cell_key,
              field: field,
              new_value: new_value,
              from_user_id: user_id
            })

          _ ->
            socket
        end

      {:noreply,
       socket
       |> assign(:cells, cells)
       |> assign(:c_name, c_name)
       |> assign(:c_desc, c_desc)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:noreply, handle_presence_change(socket, socket.assigns.canvas_id)}
  end

  @impl true
  def handle_info(:idle_save, socket) do
    if socket.assigns.cells != socket.assigns.last_saved_cells do
      Canvas.update_unstr_canvas(socket.assigns.canvas, %{
        name: socket.assigns.c_name,
        description: socket.assigns.c_desc
      })

      Canvas.save_unstr_canvas_content_to_db(socket.assigns.canvas_id, socket.assigns.cells)

      {:noreply,
       socket
       |> assign(:last_saved_cells, socket.assigns.cells)
       |> assign(:idle_timer_ref, nil)}
    else
      {:noreply, assign(socket, idle_timer_ref: nil)}
    end
  end

  @impl true
  def handle_info(:periodic_save, socket) do
    if socket.assigns.cells != socket.assigns.last_saved_cells do
      Canvas.update_unstr_canvas(socket.assigns.canvas, %{
        name: socket.assigns.c_name,
        description: socket.assigns.c_desc
      })

      Canvas.save_unstr_canvas_content_to_db(socket.assigns.canvas_id, socket.assigns.cells)
      socket = assign(socket, :last_saved_cells, socket.assigns.cells)

      Process.send_after(self(), :periodic_save, @periodic_save_interval)
      {:noreply, socket}
    else
      Process.send_after(self(), :periodic_save, @periodic_save_interval)
      {:noreply, socket}
    end
  end

  defp handle_presence_change(socket, canvas_id) do
    presence_list = Presence.list("presence_unstr:#{canvas_id}")
    assign(socket, presence: presence_list)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      container_class="w-full mx-auto max-w-screen-xl space-y-4"
    >
      <div class="w-full max-w-screen-xl mx-auto px-4 py-8">
        <%!-- Header --%>
        <div class="flex items-center justify-between mb-8">
          <div class="flex-1">
            <.form for={%{}} phx-change="update_name">
              <input
                name="value"
                type="text"
                value={@c_name}
                phx-debounce="1000"
                class="text-3xl font-bold text-gray-900 bg-transparent border-b-2 border-transparent hover:border-gray-300 focus:border-blue-500 focus:outline-none w-full"
                placeholder="Canvas name"
              />
            </.form>
          </div>
          <.link navigate={~p"/canvas-designer"} class="text-sm text-blue-600 hover:text-blue-700">
            Back to Canvases
          </.link>
        </div>

        <%!-- Presence Sidebar --%>
        <div class="flex flex-col gap-4 mb-4 bg-white p-4 rounded-lg shadow-sm border border-gray-200">
          <div>
            <div class="text-xs text-gray-500 self-center mr-2 mb-2">Active Users:</div>
            <div class="flex gap-2">
              <%= for {_user_id, %{metas: metas}} <- @presence do %>
                <% meta = List.first(metas) %>
                <div class="text-sm font-medium px-2 py-1 bg-blue-100 text-blue-800 rounded-md">
                  {meta[:username]}
                </div>
              <% end %>
            </div>
          </div>

          <div class="pt-4 border-t border-gray-200">
            <h4 class="font-semibold text-gray-900 mb-3">Share Canvas</h4>

            <%= if @canvas.author_id == @user_id do %>
              <.form for={%{}} id="share-form" phx-submit="share_canvas" class="flex gap-2 mb-4">
                <input
                  type="email"
                  name="email"
                  placeholder="Enter email..."
                  class="flex-1 text-xs px-3 py-2 bg-white border border-gray-300 rounded-lg text-gray-900 placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-500"
                />
                <button
                  type="submit"
                  class="px-3 py-2 bg-green-600 text-white text-xs font-medium rounded-lg hover:bg-green-700 transition"
                >
                  Share
                </button>
              </.form>
            <% end %>

            <%= if @canvas.shared_with && Enum.any?(@canvas.shared_with) do %>
              <div class="mb-4">
                <p class="text-xs font-medium text-gray-600 mb-2">Shared with:</p>
                <div class="space-y-1">
                  <%= for email <- @canvas.shared_with do %>
                    <div class="text-xs text-gray-700 px-3 py-2 bg-green-50 rounded border border-green-200 flex items-center justify-between">
                      <span>{email}</span>
                      <%= if @canvas.author_id == @user_id do %>
                        <button
                          phx-click="remove_access"
                          phx-value-email={email}
                          class="ml-2 px-2 py-1 text-white text-xs font-bold bg-red-600 border border-red-700 rounded hover:bg-red-700 transition"
                        >
                          ×
                        </button>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>
        </div>

        <%!-- Description --%>
        <div class="mb-8">
          <.form for={%{}} phx-change="update_description">
            <textarea
              name="value"
              phx-debounce="1000"
              class="w-full px-4 py-2 border border-gray-300 rounded-lg text-gray-600 focus:outline-none focus:ring-2 focus:ring-blue-500"
              placeholder="Canvas description..."
              rows="2"
            ><%= @c_desc %></textarea>
          </.form>
        </div>
        <div class="bg-white rounded-lg shadow p-8 w-full">
          <h2 class="text-2xl font-bold text-gray-900 mb-6">Canvas Structure</h2>

          <%!-- Display columns and rows --%>
          <div class="mb-8">
            <h3 class="text-lg font-semibold text-gray-900 mb-4">Columns</h3>
            <div class="flex flex-wrap gap-2">
              <%= for column <- @cells["columns"] || [] do %>
                <div class="px-3 py-2 bg-blue-100 text-blue-800 rounded-lg text-sm font-medium">
                  {column["label"]}
                </div>
              <% end %>
            </div>
          </div>

          <div class="mb-8">
            <h3 class="text-lg font-semibold text-gray-900 mb-4">Rows</h3>
            <div class="flex flex-wrap gap-2">
              <%= for row <- @cells["rows"] || [] do %>
                <div class="px-3 py-2 bg-green-100 text-green-800 rounded-lg text-sm font-medium">
                  {row["label"]}
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
                  <%= for column <- @cells["columns"] || [] do %>
                    <th class="px-4 py-2 border border-gray-300 bg-gray-100 font-semibold text-gray-900">
                      {column["label"]}
                    </th>
                  <% end %>
                </tr>
              </thead>
              <tbody>
                <%= for {row, row_index} <- Enum.with_index(@cells["rows"] || []) do %>
                  <tr>
                    <td class="px-4 py-2 border border-gray-300 bg-gray-100 font-semibold text-gray-900">
                      {row["label"]}
                    </td>
                    <%= for {_column, col_index} <- Enum.with_index(@cells["columns"] || []) do %>
                      <% layout = @cells["layout"] || [] %>
                      <% cell_key = Enum.at(Enum.at(layout, row_index, []), col_index) %>
                      <td class="px-4 py-2 border border-gray-300">
                        <%= if cell_key do %>
                          <% cell_data =
                            get_in(@cells, ["cells", cell_key]) || @cells[cell_key] || %{} %>
                          <% title =
                            Map.get(cell_data, "name") || Map.get(cell_data, "title") || cell_key %>

                          <div class="bg-white p-3 rounded-md shadow-sm">
                            <div class="mb-2">
                              <div class="text-base font-semibold text-gray-900">{title}</div>
                              <div class="text-xs text-gray-500">{cell_key}</div>
                            </div>

                            <.form for={%{}} phx-change="update_cell">
                              <input type="hidden" name="cell_key" value={cell_key} />

                              <div class="mt-2 grid gap-2 text-sm">
                                <%= for {field, value} <- cell_data do %>
                                  <%= if field not in ["row", "column"] do %>
                                    <div class="flex flex-col">
                                      <label class="text-xs font-medium text-gray-600 uppercase tracking-wide mb-1">
                                        {field}
                                      </label>

                                      <div
                                        id={"md-" <> cell_key <> "-" <> field}
                                        phx-hook="MarkdownField"
                                        phx-update="ignore"
                                        data-cell-key={cell_key}
                                        data-field={field}
                                        data-current-user-id={@user_id}
                                        class="w-full"
                                      >
                                        <div
                                          id={"md-render-" <> cell_key <> "-" <> field}
                                          class="md-render prose prose-sm prose-stone dark:prose-invert break-words mb-1 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 p-2 rounded"
                                          phx-update="ignore"
                                        >
                                          {value}
                                        </div>
                                        <textarea
                                          name={"values[" <> field <> "]"}
                                          phx-debounce="150"
                                          class="hidden w-full px-2 py-1 border border-gray-200 rounded-md text-gray-900 dark:text-gray-100 bg-white dark:bg-gray-800 dark:border-gray-700 placeholder-gray-400 dark:placeholder-gray-400 focus:ring-1 focus:ring-blue-500 resize-none"
                                          placeholder="Enter value..."
                                          rows="3"
                                        ><%= value %></textarea>
                                      </div>
                                    </div>
                                  <% end %>
                                <% end %>
                              </div>
                            </.form>
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
