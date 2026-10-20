defmodule PscWeb.UnstrCanvasLive.Editor do
  use PscWeb, :live_view

  # SaladUI badge/button/input are called qualified (UIBadge/UIButton/UIInput)
  # because CoreComponents is imported globally via html_helpers and defines
  # the same names — unqualified imports would conflict.
  alias PscWeb.Components.UI.Badge, as: UIBadge
  alias PscWeb.Components.UI.Button, as: UIButton
  alias PscWeb.Components.UI.Tooltip, as: UITooltip

  import PscWeb.Components.Accent
  import PscWeb.Components.ShareDialog

  alias Psc.Canvas
  alias PscWeb.Markdown
  alias PscWeb.Presence
  require Logger

  @idle_save_interval 1500
  @periodic_save_interval 10000

  # The canvas editor is a tabbed surface: the grid is one of several views on
  # the same canvas. Everything but the editor is a placeholder for now.
  @tabs [
    {"analysis", "Analysis", "hero-chart-bar",
     "Insights over the canvas: relevance, staleness and content coverage."},
    {"notes", "Notes", "hero-document-text", "Shared notes attached to this canvas."},
    {"editor", "Editor", "hero-pencil-square", "The canvas grid."},
    {"agent", "Agent", "hero-sparkles", "Talk to an agent that can read and edit this canvas."}
  ]

  defp find_tab(id) do
    Enum.find(@tabs, fn {tab_id, _label, _icon, _blurb} -> tab_id == id end) ||
      Enum.find(@tabs, fn {tab_id, _label, _icon, _blurb} -> tab_id == "editor" end)
  end

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
        |> assign(:active_tab, "editor")
        |> assign(:tabs, @tabs)
        |> subscribe_to_canvas(id)

      if connected?(socket) do
        Process.send_after(self(), :periodic_save, @periodic_save_interval)
      end

      {:ok, socket}
    else
      {:ok,
       socket
       |> put_flash(:error, "Canvas not found")
       |> redirect(to: ~p"/canvas")}
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
  def handle_event("select_tab", %{"tab" => tab}, socket) do
    {:noreply, push_patch(socket, to: ~p"/canvas/#{socket.assigns.canvas_id}?tab=#{tab}")}
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
           |> put_flash(:success, "Canvas shared with #{email}")}

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
           |> put_flash(:success, "Access removed for #{email}")}

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
  def handle_params(%{"tab" => tab}, _url, socket) do
    {:noreply, assign(socket, :active_tab, find_tab(tab) |> elem(0))}
  end

  def handle_params(_params, _url, socket) do
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

  # Every data column may shrink to this width before the table stops fitting
  # the viewport and scrolls horizontally.
  @min_column_width_rem 12

  defp table_min_width(cells) do
    columns = length(cells["columns"] || [])
    "calc(#{row_label_width(cells)} + #{columns * @min_column_width_rem}rem)"
  end

  # The row-label column only takes as much room as its longest label needs
  # (~0.85ch per character plus the cell's horizontal padding); labels are
  # truncated rather than allowed to spill into the neighbouring cell.
  defp row_label_width(cells) do
    longest =
      cells["rows"]
      |> List.wrap()
      |> Enum.map(fn row -> row |> Map.get("label", "") |> String.length() end)
      |> Enum.max(fn -> 0 end)

    "#{Float.ceil(longest * 0.85 + 4) |> trunc()}ch"
  end

  defp active_usernames(presence) do
    for {_user_id, %{metas: [meta | _]}} <- presence, do: meta[:username]
  end

  defp active_users_label([]), do: "No one online"
  defp active_users_label([username]), do: username
  defp active_users_label([username | rest]), do: "#{username} +#{length(rest)}"

  # A short presence label for narrow screens, where the full e-mail address
  # would not fit next to the other actions.
  defp active_users_compact_label(presence) do
    case active_usernames(presence) do
      [] -> "Offline"
      [_one] -> "1 online"
      many -> "#{length(many)} online"
    end
  end

  defp active_user_count(presence), do: length(active_usernames(presence))

  defp save_state_label(:saving), do: "Saving..."
  defp save_state_label(:saved), do: "Saved"
  defp save_state_label(_), do: "Unsaved changes"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      header_title="Canvas Editor"
      fill_height
      main_class="px-2 py-2 sm:px-6 lg:px-8"
      container_class="mx-auto flex min-h-0 w-full max-w-none flex-1 flex-col gap-3"
    >
      <:header_nav>
        <.tab_strip tabs={@tabs} active_tab={@active_tab} />
      </:header_nav>
      <:header_actions>
        <.header_actions
          presence={@presence}
          save_state={@save_state}
          can_share?={@canvas.author_id == @user_id}
        />
      </:header_actions>
      <div id="canvas-workspace" class="flex min-h-0 w-full flex-1 flex-col gap-3 pb-16 lg:pb-0">
        <%!-- Header: title, description, presence and actions --%>
        <div id="canvas-header" class="flex shrink-0 flex-col gap-2 px-2 sm:px-0">
          <div class="flex flex-wrap items-center gap-x-3 gap-y-2 sm:items-start">
            <.form
              for={%{}}
              id="canvas-name-form"
              phx-change="update_name"
              class="order-1 min-w-0 flex-1 sm:flex-none"
            >
              <input
                name="value"
                type="text"
                value={@c_name}
                phx-debounce="1000"
                class="field-sizing-content h-8 w-full min-w-0 border-b-2 border-transparent bg-transparent text-lg font-semibold leading-8 text-base-content transition-colors hover:border-base-content/20 focus:border-primary focus:outline-none sm:w-auto sm:min-w-[6rem] sm:max-w-[24rem]"
                placeholder="Canvas name"
              />
            </.form>

            <%!-- Save state: beside the title on phones, with the other
            actions on larger screens. The badge keeps the same height as the
            other header controls so they line up on one line. Below `sm` the
            app header carries a minimal version instead (see header_actions). --%>
            <div id="canvas-save-state" class="order-2 hidden shrink-0 sm:order-4 sm:block">
              <%= cond do %>
                <% @save_state == :saving -> %>
                  <UIBadge.badge variant="secondary" class="h-8 shrink-0">
                    <div class="w-3 h-3 rounded-full border-2 border-current border-t-transparent animate-spin">
                    </div>
                    <span>Saving...</span>
                  </UIBadge.badge>
                <% @save_state == :saved -> %>
                  <UIBadge.badge variant="default" class="h-8 shrink-0">
                    <.icon name="hero-check-circle" class="w-4 h-4" />
                    <span>Saved</span>
                  </UIBadge.badge>
                <% true -> %>
                  <UIBadge.badge variant="outline" class="h-8 shrink-0">
                    <.icon name="hero-exclamation-circle" class="w-4 h-4" />
                    <span>Unsaved</span>
                  </UIBadge.badge>
              <% end %>
            </div>

            <.form
              for={%{}}
              id="canvas-description-form"
              phx-change="update_description"
              class="order-3 w-full min-w-0 sm:order-2 sm:w-auto sm:flex-1"
            >
              <textarea
                name="value"
                phx-debounce="1000"
                class="field-sizing-content box-content max-h-12 min-h-8 w-full resize-none overflow-y-auto border-b-2 border-transparent bg-transparent p-0 text-sm leading-6 text-base-content/60 transition-colors placeholder-base-content/35 hover:border-base-content/20 focus:border-primary focus:text-base-content/85 focus:outline-none sm:max-h-16 sm:leading-8"
                placeholder="Add a description..."
                rows="1"
              ><%= @c_desc %></textarea>
            </.form>

            <%!-- Active users: truncated, with the full list in a hover tooltip --%>
            <div id="canvas-presence" class="order-4 hidden sm:order-3 sm:block">
              <UITooltip.tooltip id="active-users-tooltip">
                <UITooltip.tooltip_trigger>
                  <button
                    type="button"
                    class="inline-flex h-8 max-w-[13rem] items-center gap-2 rounded-full border border-base-content/10 px-3 text-xs text-base-content/70 transition-colors hover:border-base-content/20 hover:bg-base-content/5 hover:text-base-content focus:outline-none focus-visible:ring-2 focus-visible:ring-primary"
                  >
                    <span class="relative flex size-2 shrink-0">
                      <span class="absolute inline-flex size-full rounded-full bg-success/50"></span>
                      <span class="relative inline-flex size-2 rounded-full bg-success"></span>
                    </span>
                    <span class="truncate lg:hidden">{active_users_compact_label(@presence)}</span>
                    <span class="hidden truncate lg:inline">
                      {active_users_label(active_usernames(@presence))}
                    </span>
                  </button>
                </UITooltip.tooltip_trigger>

                <.active_users_list presence={@presence} />
              </UITooltip.tooltip>
            </div>
            <%= if @canvas.author_id == @user_id do %>
              <div class="order-5 ml-auto hidden sm:ml-0 sm:block">
                <.share_button id="share-canvas-button" label="Share" />
              </div>
            <% end %>
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

        <div
          id="canvas-tabpanel"
          role="tabpanel"
          aria-labelledby={"canvas-tab-#{@active_tab}"}
          class="flex min-h-0 w-full flex-1 flex-col"
        >
          <%= if @active_tab == "editor" do %>
            <div
              id="canvas-grid"
              class="flex min-h-0 w-full flex-1 flex-col overflow-hidden rounded-xl border border-base-content/20 bg-base-200"
            >
              <%!-- Grid Layout — accents come from the template and are read-only here --%>
              <div class="canvas-grid-scroll flex min-h-0 flex-1 flex-col overflow-auto">
                <table
                  class="h-full min-h-0 w-full flex-1 table-fixed border-collapse"
                  style={"min-width: #{table_min_width(@cells)}"}
                >
                  <colgroup>
                    <col style={"width: #{row_label_width(@cells)}"} />
                    <%= for _column <- @cells["columns"] || [] do %>
                      <col />
                    <% end %>
                  </colgroup>
                  <thead>
                    <tr>
                      <th class="px-2 py-1 border border-base-content/20 bg-base-content/5"></th>
                      <%= for column <- @cells["columns"] || [] do %>
                        <th class="border border-base-content/20 bg-base-content/5 p-0 align-bottom font-medium text-base-content/70 text-sm">
                          <div class="flex flex-col">
                            <.accent_bar
                              id={"accent-bar-column-#{column["id"]}"}
                              token={column["accent"]}
                            />
                            <div class="px-2 py-1">
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
                        <td class="relative border border-base-content/20 bg-base-content/5 p-0 align-top">
                          <.accent_bar
                            id={"accent-bar-row-#{row["id"]}"}
                            token={row["accent"]}
                            orientation={:left}
                          />
                          <div class="truncate px-2 py-1 font-medium text-base-content/70 text-sm">
                            {row["label"]}
                          </div>
                        </td>
                        <%= for {column, col_index} <- Enum.with_index(@cells["columns"] || []) do %>
                          <% layout = @cells["layout"] || [] %>
                          <% cell_key = Enum.at(Enum.at(layout, row_index, []), col_index) %>
                          <td class="relative border border-base-content/20 align-top">
                            <%= if cell_key do %>
                              <% cell_data =
                                get_in(@cells, ["cells", cell_key]) || @cells[cell_key] || %{} %>
                              <% title =
                                Map.get(cell_data, "label") || Map.get(cell_data, "name") ||
                                  Map.get(cell_data, "title") || cell_key %>

                              <div
                                id={"cell-card-" <> cell_key}
                                phx-hook="CellFocus"
                                data-cell-key={cell_key}
                                class="canvas-cell cursor-text bg-base-300 transition-shadow focus-within:ring-2 focus-within:ring-primary/35 focus-within:ring-inset"
                              >
                                <%!-- The colour combination of this cell (column on top,
                            row on the left) is only shown in the mobile fullscreen
                            view, where there is room for it. --%>
                                <.accent_bar
                                  id={"accent-bar-cell-#{cell_key}-column"}
                                  token={column["accent"]}
                                  class="cell-accent absolute inset-x-0 top-0 h-1 z-10"
                                />
                                <.accent_bar
                                  id={"accent-bar-cell-#{cell_key}-row"}
                                  token={row["accent"]}
                                  orientation={:left}
                                  class="cell-accent z-10"
                                />

                                <div class="cell-body p-2">
                                  <div class="mb-1">
                                    <div class="text-sm font-medium text-base-content break-words">
                                      {title}
                                    </div>
                                  </div>

                                  <.form
                                    for={%{}}
                                    id={"cell-form-#{cell_key}"}
                                    phx-change="update_cell"
                                  >
                                    <input type="hidden" name="cell_key" value={cell_key} />

                                    <div class="mt-1 grid min-w-0 gap-1 text-sm">
                                      <%= for {field, value} <- cell_data do %>
                                        <%!-- "semantics" is tolerated in older canvases but is
                                  no longer authored or shown; "titles" holds labels. --%>
                                        <%= if field not in ["row", "column", "label", "semantics", "titles"] do %>
                                          <% field_title = Psc.Canvas.field_title(cell_data, field) %>
                                          <div class="flex min-w-0 flex-col">
                                            <label
                                              :if={field_title != ""}
                                              class="text-xs font-medium text-base-content/50 uppercase tracking-wide mb-0.5 break-words"
                                            >
                                              {field_title}
                                            </label>

                                            <div
                                              id={"md-" <> cell_key <> "-" <> field}
                                              phx-hook="MarkdownField"
                                              phx-update="ignore"
                                              data-cell-key={cell_key}
                                              data-field={field}
                                              data-field-wrapper
                                              data-current-user-id={@user_id}
                                              class="w-full"
                                            >
                                              <div
                                                id={"md-render-" <> cell_key <> "-" <> field}
                                                class="md-render prose prose-sm dark:prose-invert break-words mb-0.5 bg-base-300 text-base-content p-1"
                                                phx-update="ignore"
                                              >
                                                {value}
                                              </div>
                                              <textarea
                                                name={"values[" <> field <> "]"}
                                                phx-debounce="150"
                                                class="field-sizing-content hidden max-h-[60vh] w-full resize-none overflow-y-auto bg-base-300 px-1.5 py-0.5 text-base-content placeholder-base-content/40 focus:outline-none"
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

                                <button
                                  type="button"
                                  data-cell-exit="true"
                                  class="cell-exit fixed bottom-5 right-5 z-[70] size-12 shrink-0 items-center justify-center rounded-full bg-primary text-primary-content shadow-lg transition-transform hover:scale-105 focus:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2 focus-visible:ring-offset-base-300"
                                  aria-label="Close full screen"
                                >
                                  <.icon name="hero-x-mark" class="size-5" />
                                </button>
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
          <% else %>
            <div
              id={"canvas-placeholder-" <> @active_tab}
              class="flex min-h-0 w-full flex-1 flex-col items-center justify-center gap-3 rounded-xl border border-dashed border-base-content/20 bg-base-200/40 p-8 text-center"
            >
              <span class="flex size-12 items-center justify-center rounded-full bg-base-content/5 text-base-content/40">
                <.icon name={placeholder_icon(@active_tab)} class="size-6" />
              </span>
              <h2 class="text-lg font-medium text-base-content">
                {placeholder_label(@active_tab)}
              </h2>
              <p class="max-w-sm text-sm text-base-content/60">
                {placeholder_blurb(@active_tab)}
              </p>
              <p class="text-xs text-base-content/40">Coming soon.</p>
            </div>
          <% end %>
        </div>
      </div>

      <%!-- Below the header breakpoint the tabs live at the bottom of the
      screen, like a native app. --%>
      <.tab_bar tabs={@tabs} active_tab={@active_tab} />
    </Layouts.app>
    """
  end

  defp placeholder_icon(tab) do
    case find_tab(tab) do
      {_id, _label, icon, _blurb} -> icon
    end
  end

  # On phones the canvas header gives its vertical space back to the grid: the
  # presence, the save state and Share move into the app header as icons.
  attr :presence, :map, required: true
  attr :save_state, :atom, required: true
  attr :can_share?, :boolean, required: true

  defp header_actions(assigns) do
    ~H"""
    <div class="flex items-center gap-1 sm:hidden">
      <UITooltip.tooltip id="active-users-tooltip-compact">
        <UITooltip.tooltip_trigger>
          <button
            type="button"
            id="canvas-presence-compact"
            class="inline-flex h-8 items-center gap-1.5 rounded-full border border-base-content/10 px-2.5 text-xs tabular-nums text-base-content/70 transition-colors hover:bg-base-content/5"
            title={active_users_compact_label(@presence)}
            aria-label={active_users_compact_label(@presence)}
          >
            <span class="relative flex size-2 shrink-0">
              <span class="absolute inline-flex size-full rounded-full bg-success/50"></span>
              <span class="relative inline-flex size-2 rounded-full bg-success"></span>
            </span>
            <span>{active_user_count(@presence)}</span>
          </button>
        </UITooltip.tooltip_trigger>

        <.active_users_list presence={@presence} />
      </UITooltip.tooltip>

      <span
        id="canvas-save-state-compact"
        class="inline-flex size-8 items-center justify-center"
        role="img"
        aria-label={save_state_label(@save_state)}
        title={save_state_label(@save_state)}
      >
        <%= case @save_state do %>
          <% :saving -> %>
            <.icon name="hero-arrow-path" class="size-4 animate-spin text-base-content/50" />
          <% :saved -> %>
            <.icon name="hero-check-circle" class="size-4 text-base-content/40" />
          <% _ -> %>
            <.icon name="hero-exclamation-circle" class="size-4 text-warning" />
        <% end %>
      </span>

      <%= if @can_share? do %>
        <UIButton.button
          type="button"
          id="share-canvas-button-compact"
          phx-click="open_share"
          variant="outline"
          size="icon"
          class="!size-8 rounded-full"
          aria-label="Share"
          title="Share"
        >
          <.icon name="hero-share" class="size-4" />
        </UIButton.button>
      <% end %>
    </div>
    """
  end

  # The people currently on the canvas, as shown in the presence tooltip.
  attr :presence, :map, required: true

  defp active_users_list(assigns) do
    ~H"""
    <UITooltip.tooltip_content side="bottom" align="end" class="w-64 px-3 py-2.5">
      <p class="mb-1 text-[0.7rem] font-medium uppercase tracking-wide text-base-content/50">
        Active users
      </p>
      <ul class="space-y-1">
        <li
          :for={username <- active_usernames(@presence)}
          class="truncate text-sm text-base-content/80"
        >
          {username}
        </li>
      </ul>
    </UITooltip.tooltip_content>
    """
  end

  # The tab strip lives in the app header on large screens. When the header
  # runs out of room the same tabs become a bottom app bar, the way native
  # apps switch sections.
  attr :tabs, :list, required: true
  attr :active_tab, :string, required: true

  defp tab_strip(assigns) do
    ~H"""
    <nav
      id="canvas-tabs"
      role="tablist"
      aria-label="Canvas views"
      class="hidden items-center gap-0.5 rounded-lg border border-base-content/25 bg-base-content/5 px-1 py-0.5 lg:flex"
    >
      <button
        :for={{tab_id, label, icon, _blurb} <- @tabs}
        type="button"
        role="tab"
        id={"canvas-tab-#{tab_id}"}
        aria-selected={to_string(@active_tab == tab_id)}
        aria-controls="canvas-tabpanel"
        aria-label={label}
        title={label}
        phx-click="select_tab"
        phx-value-tab={tab_id}
        class={[
          "flex shrink-0 items-center gap-1.5 rounded-md px-2.5 py-1.5 text-sm font-medium transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-primary",
          @active_tab == tab_id && "bg-base-content/10 text-base-content",
          @active_tab != tab_id &&
            "text-base-content/60 hover:bg-base-content/5 hover:text-base-content"
        ]}
      >
        <.icon name={icon} class="size-4" />
        <%!-- The names are dropped when the header gives the strip less room
        than it needs, so the tabs never overflow into a scrollbar. --%>
        <span class="@max-[23rem]:hidden">{label}</span>
      </button>
    </nav>
    """
  end

  defp tab_bar(assigns) do
    ~H"""
    <nav
      id="canvas-tabs-bar"
      role="tablist"
      aria-label="Canvas views"
      class="fixed inset-x-0 bottom-0 z-40 flex items-stretch justify-around gap-1 border-t border-base-content/10 bg-base-200/95 px-1 py-1 backdrop-blur lg:hidden"
    >
      <button
        :for={{tab_id, label, icon, _blurb} <- @tabs}
        type="button"
        role="tab"
        id={"canvas-tab-bar-#{tab_id}"}
        aria-selected={to_string(@active_tab == tab_id)}
        aria-controls="canvas-tabpanel"
        aria-label={label}
        title={label}
        phx-click="select_tab"
        phx-value-tab={tab_id}
        class={[
          "flex flex-1 shrink-0 flex-col items-center justify-center gap-0.5 rounded-lg px-2 py-1.5 text-[0.7rem] font-medium transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-primary",
          @active_tab == tab_id && "text-primary",
          @active_tab != tab_id && "text-base-content/55"
        ]}
      >
        <.icon name={icon} class="size-5" />
        <span>{label}</span>
      </button>
    </nav>
    """
  end

  defp placeholder_label(tab) do
    case find_tab(tab) do
      {_id, label, _icon, _blurb} -> label
    end
  end

  defp placeholder_blurb(tab) do
    case find_tab(tab) do
      {_id, _label, _icon, blurb} -> blurb
    end
  end
end
