defmodule PscWeb.UnstrCanvasLive.Editor do
  use PscWeb, :live_view

  # SaladUI badge/button/input are called qualified (UIBadge/UIButton/UIInput)
  # because CoreComponents is imported globally via html_helpers and defines
  # the same names — unqualified imports would conflict.
  alias PscWeb.Components.UI.Badge, as: UIBadge
  alias PscWeb.Components.UI.Tooltip, as: UITooltip

  import PscWeb.Components.Accent
  import PscWeb.Components.ShareDialog

  alias Psc.Canvas
  alias PscWeb.Markdown
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
        |> assign(:save_state, :saved)
        |> assign(:share_open, false)
        |> subscribe_to_canvas(id)

      if connected?(socket) do
        Process.send_after(self(), :periodic_save, @periodic_save_interval)
      end

      {:ok, socket}
    else
      {:ok,
       socket
       |> put_flash(:error, "Canvas not found")
       |> redirect(to: ~p"/canvases")}
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
    |> assign(:save_state, :unsaved)
  end

  @impl true
  def handle_event("open_share", _params, socket) do
    {:noreply, assign(socket, :share_open, true)}
  end

  @impl true
  def handle_event("share_closed", _params, socket) do
    {:noreply, assign(socket, :share_open, false)}
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
    html = Markdown.render(value)

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
      socket = assign(socket, save_state: :saving)

      Canvas.update_unstr_canvas(socket.assigns.canvas, %{
        name: socket.assigns.c_name,
        description: socket.assigns.c_desc
      })

      Canvas.save_unstr_canvas_content_to_db(socket.assigns.canvas_id, socket.assigns.cells)

      {:noreply,
       socket
       |> assign(:last_saved_cells, socket.assigns.cells)
       |> assign(:idle_timer_ref, nil)
       |> assign(:save_state, :saved)}
    else
      {:noreply, assign(socket, idle_timer_ref: nil)}
    end
  end

  @impl true
  def handle_info(:periodic_save, socket) do
    socket =
      if socket.assigns.cells != socket.assigns.last_saved_cells do
        socket = assign(socket, save_state: :saving)

        Canvas.update_unstr_canvas(socket.assigns.canvas, %{
          name: socket.assigns.c_name,
          description: socket.assigns.c_desc
        })

        Canvas.save_unstr_canvas_content_to_db(socket.assigns.canvas_id, socket.assigns.cells)

        socket
        |> assign(:last_saved_cells, socket.assigns.cells)
        |> assign(:save_state, :saved)
      else
        socket
      end

    Process.send_after(self(), :periodic_save, @periodic_save_interval)
    {:noreply, socket}
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
      header_title="Canvases"
      container_class="mx-auto w-full max-w-none space-y-4 lg:w-[85vw]"
    >
      <div id="canvas-workspace" class="w-full">
        <%!-- Header --%>
        <div id="canvas-header" class="flex items-start justify-between gap-4 mb-8">
          <div class="min-w-0 flex-1">
            <.form for={%{}} id="canvas-name-form" phx-change="update_name">
              <input
                name="value"
                type="text"
                value={@c_name}
                phx-debounce="1000"
                class="text-2xl font-semibold text-base-content bg-transparent border-b-2 border-transparent hover:border-base-content/20 focus:border-primary focus:outline-none w-full"
                placeholder="Canvas name"
              />
            </.form>

            <.form for={%{}} id="canvas-description-form" phx-change="update_description">
              <textarea
                name="value"
                phx-debounce="1000"
                class="mt-1 w-full resize-none border-0 bg-transparent p-0 text-sm text-base-content/60 placeholder-base-content/35 focus:outline-none focus:text-base-content/85 transition-colors"
                placeholder="Add a description..."
                rows="2"
              ><%= @c_desc %></textarea>
            </.form>
          </div>
          <div class="flex shrink-0 items-center">
            <%= cond do %>
              <% @save_state == :saving -> %>
                <UIBadge.badge variant="secondary" class="shrink-0">
                  <div class="w-3 h-3 rounded-full border-2 border-current border-t-transparent animate-spin">
                  </div>
                  <span>Saving...</span>
                </UIBadge.badge>
              <% @save_state == :saved -> %>
                <UIBadge.badge variant="default" class="shrink-0">
                  <.icon name="hero-check-circle" class="w-4 h-4" />
                  <span>Saved</span>
                </UIBadge.badge>
              <% true -> %>
                <UIBadge.badge variant="outline" class="shrink-0">
                  <.icon name="hero-exclamation-circle" class="w-4 h-4" />
                  <span>Unsaved</span>
                </UIBadge.badge>
            <% end %>
            <%= if @canvas.author_id == @user_id do %>
              <.share_button id="share-canvas-button" label="Share" class="ml-4" />
            <% end %>
            <.link
              navigate={~p"/canvases"}
              class="ml-4 shrink-0 text-sm text-base-content/60 hover:text-base-content transition-colors"
            >
              Back to Canvases
            </.link>
          </div>
        </div>

        <%!-- Presence + sharing --%>
        <div class="flex flex-col gap-4 mb-4 rounded-xl border border-base-content/10 bg-base-200 p-4">
          <div>
            <div class="text-xs text-base-content/50 self-center mr-2 mb-2">Active Users:</div>
            <div class="flex gap-2">
              <%= for {_user_id, %{metas: metas}} <- @presence do %>
                <% meta = List.first(metas) %>
                <UIBadge.badge variant="secondary">
                  {meta[:username]}
                </UIBadge.badge>
              <% end %>
            </div>
          </div>
        </div>

        <.share_dialog
          id="share-canvas-dialog"
          open={@share_open}
          title="Share canvas"
          description="People with access can edit this canvas with you in real time."
          manage?={@canvas.author_id == @user_id}
          shared_with={@canvas.shared_with || []}
          share_event="share_canvas"
          remove_event="remove_access"
          on_close="share_closed"
        />

        <div class="rounded-xl border border-base-content/10 bg-base-200 p-8 w-full">
          <div class="mb-6 flex items-center justify-between gap-4">
            <h2 class="text-lg font-medium text-base-content">Canvas Structure</h2>

            <UITooltip.tooltip id="canvas-structure-tooltip">
              <UITooltip.tooltip_trigger>
                <button
                  type="button"
                  class="inline-flex items-center gap-1.5 rounded-lg border border-base-content/10 px-2.5 py-1 text-xs font-medium text-base-content/60 transition-colors hover:border-base-content/25 hover:bg-base-content/5 hover:text-base-content focus:outline-none focus-visible:ring-2 focus-visible:ring-primary"
                >
                  <.icon name="hero-information-circle" class="w-4 h-4" />
                  <span>Rows &amp; columns</span>
                </button>
              </UITooltip.tooltip_trigger>

              <UITooltip.tooltip_content side="bottom" align="end" class="w-64 px-3 py-2.5">
                <div class="space-y-2.5">
                  <div>
                    <p class="mb-1 text-[0.7rem] font-medium uppercase tracking-wide text-base-content/50">
                      Columns
                    </p>
                    <div class="flex flex-wrap gap-1">
                      <%= for column <- @cells["columns"] || [] do %>
                        <span class="rounded bg-primary/10 px-1.5 py-0.5 text-xs font-medium text-primary">
                          {column["label"]}
                        </span>
                      <% end %>
                    </div>
                  </div>
                  <div>
                    <p class="mb-1 text-[0.7rem] font-medium uppercase tracking-wide text-base-content/50">
                      Rows
                    </p>
                    <div class="flex flex-wrap gap-1">
                      <%= for row <- @cells["rows"] || [] do %>
                        <span class="rounded bg-success/10 px-1.5 py-0.5 text-xs font-medium text-success">
                          {row["label"]}
                        </span>
                      <% end %>
                    </div>
                  </div>
                </div>
              </UITooltip.tooltip_content>
            </UITooltip.tooltip>
          </div>

          <%!-- Grid Layout — accents come from the template and are read-only here --%>
          <div class="overflow-x-auto">
            <table class="w-full border-collapse">
              <thead>
                <tr>
                  <th class="px-4 py-2 border border-base-content/10 bg-base-content/5"></th>
                  <%= for column <- @cells["columns"] || [] do %>
                    <th class="border border-base-content/10 bg-base-content/5 p-0 align-bottom font-medium text-base-content/70 text-sm">
                      <div class="flex flex-col">
                        <.accent_bar
                          id={"accent-bar-column-#{column["id"]}"}
                          token={column["accent"]}
                        />
                        <div class="px-4 py-2">
                          {column["label"]}
                        </div>
                      </div>
                    </th>
                  <% end %>
                </tr>
              </thead>
              <tbody>
                <%= for {row, row_index} <- Enum.with_index(@cells["rows"] || []) do %>
                  <tr>
                    <td class="relative border border-base-content/10 bg-base-content/5 p-0 align-top">
                      <.accent_bar
                        id={"accent-bar-row-#{row["id"]}"}
                        token={row["accent"]}
                        orientation={:left}
                      />
                      <div class="px-4 py-2 font-medium text-base-content/70 text-sm">
                        {row["label"]}
                      </div>
                    </td>
                    <%= for {_column, col_index} <- Enum.with_index(@cells["columns"] || []) do %>
                      <% layout = @cells["layout"] || [] %>
                      <% cell_key = Enum.at(Enum.at(layout, row_index, []), col_index) %>
                      <td class="px-4 py-2 border border-base-content/10 align-top">
                        <%= if cell_key do %>
                          <% cell_data =
                            get_in(@cells, ["cells", cell_key]) || @cells[cell_key] || %{} %>
                          <% title =
                            Map.get(cell_data, "label") || Map.get(cell_data, "name") ||
                              Map.get(cell_data, "title") || cell_key %>

                          <div class="bg-base-300 p-3 rounded-lg">
                            <div class="mb-2">
                              <div class="text-sm font-medium text-base-content">{title}</div>
                              <div class="text-xs text-base-content/40">{cell_key}</div>
                            </div>

                            <.form for={%{}} id={"cell-form-#{cell_key}"} phx-change="update_cell">
                              <input type="hidden" name="cell_key" value={cell_key} />

                              <div class="mt-2 grid gap-2 text-sm">
                                <%= for {field, value} <- cell_data do %>
                                  <%!-- "semantics" is tolerated in older canvases but is
                                  no longer authored or shown. --%>
                                  <%= if field not in ["row", "column", "label", "semantics"] do %>
                                    <div class="flex flex-col">
                                      <label class="text-xs font-medium text-base-content/50 uppercase tracking-wide mb-1">
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
                                          class="md-render prose prose-sm dark:prose-invert break-words mb-1 bg-base-300 text-base-content p-2 rounded"
                                          phx-update="ignore"
                                        >
                                          {value}
                                        </div>
                                        <textarea
                                          name={"values[" <> field <> "]"}
                                          phx-debounce="150"
                                          class="hidden w-full px-2 py-1 border border-base-content/10 rounded-md text-base-content bg-base-300 placeholder-base-content/40 focus:ring-1 focus:ring-primary resize-none"
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
