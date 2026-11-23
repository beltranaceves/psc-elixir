defmodule PscWeb.UnstrCanvasLive.Editor do
  @moduledoc """
  The canvas editor: one LiveView with a tab per view of the canvas.

  This module owns what every tab shares: the canvas and its cells, presence,
  sharing, the save loop and the operations other editors broadcast. Each
  feature lives in its own module under `PscWeb.UnstrCanvasLive.Editor` and is
  attached in `mount/3` with `attach_hook/4`: it adds its own assigns and
  handles its own events (and messages), halting them; anything it does not
  handle continues to the next module and finally to this one. Writes go
  through `Editor.Operations.process_operation/2`.
  """
  use PscWeb, :live_view

  import PscWeb.UnstrCanvasLive.Board, only: [canvas_board: 1]

  import PscWeb.UnstrCanvasLive.Editor.Operations,
    only: [process_operation: 2, push_cells_resync: 1]

  alias Psc.Canvas
  alias Psc.Canvas.Fulcrums
  alias Psc.Canvas.NotesMode
  alias Psc.Canvas.Structure
  alias PscWeb.Markdown
  alias PscWeb.Presence
  alias PscWeb.UnstrCanvasLive.AgentPanel
  alias PscWeb.UnstrCanvasLive.AnalysisPanel
  alias PscWeb.UnstrCanvasLive.Editor
  alias PscWeb.UnstrCanvasLive.Header
  alias PscWeb.UnstrCanvasLive.InfoPanel
  alias PscWeb.UnstrCanvasLive.NotesPanel
  alias PscWeb.UnstrCanvasLive.PivotPanel
  alias PscWeb.UnstrCanvasLive.Save
  alias PscWeb.UnstrCanvasLive.Tabs
  require Logger

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
        |> assign(:save_stats, Editor.Operations.initial_save_stats())
        |> assign(:share_open, false)
        |> assign(:active_tab, "editor")
        |> assign(:split_tab, nil)
        |> assign(:focus_pane, "primary")
        |> assign(:tabs, Tabs.tabs())
        |> Editor.StructureEditing.attach()
        |> Editor.Freeform.attach()
        |> Editor.Fulcrums.attach()
        |> Editor.Export.attach()
        |> Editor.Notes.attach()
        |> Editor.Analysis.attach()
        |> Editor.AgentChat.attach()
        |> Editor.AgentSettings.attach()
        |> Editor.History.attach()
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

  @impl true
  def handle_event("open_share", _params, socket) do
    {:noreply, assign(socket, :share_open, true)}
  end

  @impl true
  def handle_event("select_tab", %{"tab" => tab} = params, socket) do
    %{active_tab: active, split_tab: split, focus_pane: focus} = socket.assigns
    pane = if split, do: params["pane"] || focus, else: "primary"

    if Tabs.tab?(tab) do
      {active, split} = Tabs.place(active, split, pane, tab)
      {:noreply, socket |> assign(:focus_pane, pane) |> patch_layout(active, split)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("toggle_split", _params, socket) do
    %{active_tab: active, split_tab: split} = socket.assigns
    split = if split, do: nil, else: Tabs.default_split(active)

    {:noreply, socket |> assign(:focus_pane, "primary") |> patch_layout(active, split)}
  end

  def handle_event("focus_pane", %{"pane" => pane}, socket)
      when pane in ["primary", "split"] do
    {:noreply,
     assign(socket, :focus_pane, if(socket.assigns.split_tab, do: pane, else: "primary"))}
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

  # The URL carries the layout; `handle_params/3` applies it and loads what came
  # into view. A URL without `split` keeps split view open (see
  # `layout_from_params/3`), so closing it clears `split_tab` first.
  defp patch_layout(socket, active, split) do
    id = socket.assigns.canvas_id

    if split do
      push_patch(socket, to: ~p"/canvas/#{id}?tab=#{active}&split=#{split}", replace: true)
    else
      socket
      |> assign(:split_tab, nil)
      |> push_patch(to: ~p"/canvas/#{id}?tab=#{active}", replace: true)
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    previous = visible_tabs(socket.assigns[:active_tab], socket.assigns[:split_tab])

    tab = Tabs.find(params["tab"]) |> elem(0)

    # A snippet chip links to ?tab=editor&cell=r1_c1: open the editor tab and mark
    # the cell so it is obvious which one the agent meant.
    tab = if params["cell"], do: "editor", else: tab

    {active, split, focus} = layout_from_params(params, tab, socket.assigns)

    socket =
      socket
      |> assign(active_tab: active, split_tab: split, focus_pane: focus)
      |> assign(:focus_cell, params["cell"])

    # A tab loads when it comes into view, and again when the URL names it (a
    # note link, say). A tab that stays open in the other pane is left alone, so
    # switching one pane does not reset the other.
    socket =
      visible_tabs(active, split)
      |> Enum.filter(&(&1 == tab or &1 not in previous))
      |> Enum.reduce(socket, &load_tab(&2, &1, params))

    {:noreply, socket}
  end

  # `split` in the URL sets the layout. A URL with only `tab` (a link inside a
  # panel, such as a note) keeps split view and shows the tab in a pane.
  defp layout_from_params(%{"split" => split}, tab, assigns) do
    if Tabs.tab?(split) and split != tab,
      do: {tab, split, assigns[:focus_pane] || "primary"},
      else: {tab, nil, "primary"}
  end

  defp layout_from_params(_params, tab, %{split_tab: split} = assigns) when is_binary(split) do
    %{active_tab: active, focus_pane: focus} = assigns

    case Tabs.pane_of(tab, active, split) do
      nil ->
        {active, split} = Tabs.place(active, split, focus, tab)
        {active, split, focus}

      pane ->
        {active, split, pane}
    end
  end

  defp layout_from_params(_params, tab, _assigns), do: {tab, nil, "primary"}

  defp visible_tabs(active, split), do: Enum.reject([active, split], &is_nil/1)

  defp load_tab(socket, "notes", params) do
    socket
    |> Editor.Notes.load_notes()
    |> Editor.Notes.load_note(params["note"])
  end

  defp load_tab(socket, "agent", _params), do: Editor.AgentChat.load_agent(socket)
  defp load_tab(socket, "analysis", _params), do: Editor.Analysis.load_insights(socket)
  defp load_tab(socket, "history", _params), do: Editor.History.load_pivots(socket)
  defp load_tab(socket, _tab, _params), do: socket

  def handle_info({:operation, user_id, client_id, operation, _seq}, socket) do
    apply_remote_operation(socket, user_id, client_id, operation)
  end

  # Backwards-compatible shape for operations applied straight through the
  # context (no client id). The user is the only identity available, so an echo
  # from the same account cannot be distinguished from another tab.
  def handle_info({:operation, user_id, operation, _seq}, socket) do
    apply_remote_operation(socket, user_id, nil, operation)
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff", topic: topic}, socket) do
    # The same process listens to two presence topics: the canvas's, and the
    # open note's (which shares the note's operation topic).
    if topic == socket.assigns.note_topic do
      {:noreply, assign(socket, :note_presence, Presence.list(topic))}
    else
      {:noreply, handle_presence_change(socket, socket.assigns.canvas_id)}
    end
  end

  @impl true
  def handle_info(:idle_save, socket) do
    if socket.assigns.cells != socket.assigns.last_saved_cells do
      socket =
        socket
        |> assign(:save_state, :saving)
        |> update_canvas_meta()
        |> save_cells()

      {:noreply, assign(socket, :idle_timer_ref, nil)}
    else
      {:noreply, assign(socket, idle_timer_ref: nil)}
    end
  end

  @impl true
  def handle_info(:periodic_save, socket) do
    socket =
      if socket.assigns.cells != socket.assigns.last_saved_cells do
        socket
        |> assign(:save_state, :saving)
        |> update_canvas_meta()
        |> save_cells()
      else
        socket
      end

    Process.send_after(self(), :periodic_save, @periodic_save_interval)
    {:noreply, socket}
  end

  defp apply_remote_operation(socket, user_id, client_id, operation) do
    # The client id, not the user id, identifies the writer: another tab of the
    # same account is a different client and must still apply the operation.
    if client_id == socket.assigns.client_id or
         (is_nil(client_id) and user_id == socket.assigns.user_id) do
      {:noreply, socket}
    else
      Logger.debug(fn ->
        "[UnstrCanvasLive] received broadcast operation user_id=#{user_id} client_id=#{inspect(client_id)}: #{inspect(operation)}"
      end)

      cells = Psc.Canvas.UnstrCanvasCRDT.apply_operation(operation, socket.assigns.cells)
      c_name = Map.get(cells, "$name", socket.assigns.c_name)
      c_desc = Map.get(cells, "$description", socket.assigns.c_desc)

      # If this operation updated a cell field, notify the client-side hooks.
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

      socket =
        socket
        |> assign(:cells, cells)
        |> assign(:c_name, c_name)
        |> assign(:c_desc, c_desc)
        |> Editor.Analysis.track_insight_change(operation)

      # A restore by another editor replaces every field at once.
      if operation["type"] == "replace_cells",
        do: {:noreply, push_cells_resync(socket)},
        else: {:noreply, socket}
    end
  end

  # Persist the cells through the context. `Save.commit/3` advances the dirty
  # fingerprint only when the write succeeded, so a failure is retried by the
  # next idle/periodic tick and the status pill can tell the truth.
  defp save_cells(socket) do
    socket =
      Save.commit(socket, :canvas, fn ->
        Canvas.save_unstr_canvas_content_to_db(socket.assigns.canvas_id, socket.assigns.cells)
      end)

    if socket.assigns.save_state == :unsaved do
      Logger.error("[UnstrCanvasLive] save failed: canvas_id=#{socket.assigns.canvas_id}")
    end

    Editor.History.maybe_prompt_pivot(socket)
  end

  # The name and description are a separate row update from the cells snapshot.
  # A stale or invalid row must not take the socket down (or hide the cell
  # save); the snapshot itself still carries `$name`/`$description`.
  defp update_canvas_meta(socket) do
    case Canvas.update_unstr_canvas(socket.assigns.canvas, %{
           name: socket.assigns.c_name,
           description: socket.assigns.c_desc
         }) do
      {:ok, canvas} ->
        assign(socket, :canvas, canvas)

      {:error, _changeset} ->
        Logger.error(
          "[UnstrCanvasLive] canvas metadata update failed: canvas_id=#{socket.assigns.canvas_id}"
        )

        socket
    end
  end

  defp handle_presence_change(socket, canvas_id) do
    presence_list = Presence.list("presence_unstr:#{canvas_id}")
    assign(socket, presence: presence_list)
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :status, status_source(assigns))

    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      header_title="Canvas Editor"
      fill_height
      main_class={
        # A freeform board (bento or image) grows with its content on a desktop,
        # and the Analysis tab does at every width, so the page is their one
        # scroller. Everywhere else every panel scrolls inside itself and the
        # page must not scroll too.
        cond do
          # Split view: each pane scrolls inside itself, the page never does.
          @split_tab ->
            "px-2 pt-2 sm:px-6 sm:pt-3 lg:px-8 lg:pt-3"

          @active_tab == "analysis" ->
            "canvas-page-scroll px-2 pt-2 sm:px-6 sm:pt-3 lg:px-8 lg:pt-3 overflow-y-auto"

          @active_tab == "editor" and Structure.freeform?(@cells) ->
            "px-2 pt-2 sm:px-6 sm:pt-3 lg:px-8 lg:pt-3 lg:overflow-y-auto"

          true ->
            "px-2 pt-2 sm:px-6 sm:pt-3 lg:px-8 lg:pt-3"
        end
      }
      container_class="mx-auto flex min-h-0 w-full max-w-none flex-1 flex-col gap-3"
    >
      <:header_nav>
        <Tabs.strip
          tabs={@tabs}
          active_tab={@active_tab}
          split_tab={@split_tab}
          focus_pane={@focus_pane}
        />
      </:header_nav>

      <:header_actions>
        <Header.actions
          presence={@presence}
          status={@status}
          can_share?={@canvas.author_id == @user_id}
          cells={@cells}
        />
      </:header_actions>

      <div
        id="canvas-workspace"
        phx-hook="DismissPicker"
        data-picker-open={
          to_string(
            not is_nil(@structure_colors_picker) or not is_nil(@structure_accent_picker) or
              not is_nil(@hint_editor)
          )
        }
        class={
          [
            "flex w-full flex-col gap-2 pb-[calc(var(--canvas-tab-bar-height)+var(--canvas-tab-bar-gap)+env(safe-area-inset-bottom))] lg:pb-2",
            # The Analysis tab grows with its content and the page scrolls, so the
            # bottom padding stays below the last row instead of under the tab bar.
            if(@active_tab == "analysis" and is_nil(@split_tab),
              do: "flex-none",
              else: "min-h-0 flex-1"
            )
          ]
        }
      >
        <Header.header
          c_name={@c_name}
          presence={@presence}
          status={@status}
          can_share?={@canvas.author_id == @user_id}
          cells={@cells}
        />
        <Header.share_dialog
          canvas={@canvas}
          share_open={@share_open}
          can_share?={@canvas.author_id == @user_id}
        />
        <PivotPanel.pivot_dialog form={@pivot_form} />
        <PivotPanel.load_dialog pivot={@pending_load} />
        <PivotPanel.fork_dialog pivot={@pending_fork} form={@fork_form} />
        <Editor.Fulcrums.fulcrums_dialog open={@fulcrums_open} cells={@cells} />
        <Editor.Export.markdown_export_dialog form={@markdown_export_form} canvas_id={@canvas_id} />
        <Editor.Fulcrums.fulcrums_edit_dialog draft={@fulcrum_draft} cells={@cells} />
        <Editor.StructureEditing.remove_dialog confirm={@structure_remove_confirm} />

        <div
          id="canvas-tabpanel"
          phx-hook="CanvasTabs"
          data-active-tab={@active_tab}
          data-split-tab={@split_tab}
          data-focus-pane={@focus_pane}
          data-split={to_string(not is_nil(@split_tab))}
          class={[
            "flex w-full flex-col",
            if(@active_tab == "analysis" and is_nil(@split_tab),
              do: "flex-none",
              else: "min-h-0 flex-1"
            )
          ]}
        >
          <%!-- Split view (desktop): app.css lays the panes out on a grid and
          places each visible panel by its `data-pane`; the header strip's
          thumbs pick their tabs. Below `lg` only the left pane shows. --%>
          <div
            :if={@split_tab}
            id="canvas-split-divider"
            role="separator"
            aria-orientation="vertical"
            aria-label="Resize panes"
            aria-valuemin="25"
            aria-valuemax="75"
            tabindex="0"
            class="canvas-split-divider hidden"
          >
            <span></span>
          </div>

          <%!-- Every view is rendered so the client can switch instantly; the
          inactive ones are hidden. The server confirms the choice a moment
          later and owns the URL. --%>
          <div
            id="canvas-panel-editor"
            data-pane={pane(assigns, "editor")}
            data-fulcrums-active={to_string(Fulcrums.active_ids(@cells) != [])}
            role="tabpanel"
            aria-labelledby="canvas-tab-editor"
            class={
              [
                "flex min-h-0 w-full flex-1 flex-col",
                # A bento or image board grows with its content on a desktop
                # (the page scrolls); the table keeps filling the viewport. A
                # phone keeps the inner scroll for all three.
                Structure.freeform?(@cells) && "lg:flex-none",
                is_nil(pane(assigns, "editor")) && "hidden"
              ]
            }
          >
            <.canvas_board
              cells={@cells}
              c_name={@c_name}
              edit_structure?={@edit_structure?}
              structure_accent_picker={@structure_accent_picker}
              colors_picker={@structure_colors_picker}
              hint_editor={@hint_editor}
              presence={@presence}
              can_share?={@canvas.author_id == @user_id}
              focus_cell={@focus_cell}
              user_id={@user_id}
            />
          </div>

          <div
            id="canvas-panel-analysis"
            data-pane={pane(assigns, "analysis")}
            role="tabpanel"
            aria-labelledby="canvas-tab-analysis"
            class={[
              "flex w-full flex-col",
              is_nil(pane(assigns, "analysis")) && "hidden"
            ]}
          >
            <AnalysisPanel.panel
              canvas_id={@canvas_id}
              cells={@cells}
              report={@insight_report}
              filter={@insight_filter}
              stale?={@insight_stale?}
              ai_enabled?={@insight_ai_enabled?}
              ai_stale?={@insight_ai_stale?}
              overview={@insight_overview}
              ai_label={@insight_ai_label}
              include_notes?={@insight_include_notes?}
              ai_running?={@insight_ai_running?}
            />
          </div>

          <div
            id="canvas-panel-notes"
            data-pane={pane(assigns, "notes")}
            role="tabpanel"
            aria-labelledby="canvas-tab-notes"
            class={[
              "flex min-h-0 w-full flex-1 flex-col",
              is_nil(pane(assigns, "notes")) && "hidden"
            ]}
          >
            <NotesPanel.panel
              notes={@notes}
              note={@note}
              note_content={@note_content}
              note_html={@note_html}
              note_save_state={@note_save_state}
              note_save_stats={@note_save_stats}
              note_presence={@note_presence}
              user_id={@user_id}
              is_owner={@canvas.author_id == @user_id}
              scratchpad?={NotesMode.single?(@canvas.notes_mode)}
            />
          </div>

          <div
            id="canvas-panel-agent"
            data-pane={pane(assigns, "agent")}
            role="tabpanel"
            aria-labelledby="canvas-tab-agent"
            phx-window-focus="agent_refresh"
            class={[
              "flex min-h-0 w-full flex-1 flex-col",
              is_nil(pane(assigns, "agent")) && "hidden"
            ]}
          >
            <AgentPanel.panel
              agent_session={@agent_session}
              agent_messages={@agent_messages}
              agent_turn_pid={@agent_turn_pid}
              agent_sessions={@agent_sessions}
              agent_list_open={@agent_list_open}
              agent_menu_session={@agent_menu_session}
              agent_phase={@agent_phase}
              agent_enabled?={@agent_enabled?}
              agent_roles={@agent_roles}
              agent_role={@agent_role}
              agent_missing={@agent_missing}
              agent_composer={@agent_composer}
              agent_connections={@agent_connections}
              agent_connection={@agent_connection}
              agent_connection_list_open={@agent_connection_list_open}
            />
          </div>

          <div
            id="canvas-panel-history"
            data-pane={pane(assigns, "history")}
            role="tabpanel"
            aria-labelledby="canvas-tab-history"
            class={[
              "flex min-h-0 w-full flex-1 flex-col",
              is_nil(pane(assigns, "history")) && "hidden"
            ]}
          >
            <PivotPanel.panel
              pivots={@pivots}
              selected_id={@selected_pivot_id}
              head_id={@head_id}
            >
              <%!-- The current version is the live canvas; any other version
              is its stored snapshot. --%>
              <:preview :let={pivot}>
                <.canvas_board
                  cells={if pivot.id == @head_id, do: @cells, else: pivot.cells}
                  c_name={@c_name}
                  edit_structure?={false}
                  presence={@presence}
                  can_share?={false}
                  user_id={@user_id}
                  read_only?
                />
              </:preview>
            </PivotPanel.panel>
          </div>

          <%!-- The Info view scrolls inside its panel, like Notes and Agent. Its
          sections are taller than the phone viewport, and a panel that merely
          overflowed the workspace painted its last rows under the bottom bar:
          the workspace's reservation sits inside the box the content spills
          out of. --%>
          <div
            id="canvas-panel-info"
            data-pane={pane(assigns, "info")}
            role="tabpanel"
            aria-labelledby="canvas-tab-info"
            class={[
              "flex min-h-0 w-full flex-1 flex-col overflow-y-auto",
              is_nil(pane(assigns, "info")) && "hidden"
            ]}
          >
            <InfoPanel.panel
              canvas={@canvas}
              cells={@cells}
              c_name={@c_name}
              c_desc={@c_desc}
              can_share?={@canvas.author_id == @user_id}
              agent_config={@agent_config}
              agent_files={@agent_files}
              agent_uploads={@uploads}
              agent_can_edit?={true}
              agent_source_name={@agent_source_template && @agent_source_template.name}
              agent_drift?={@agent_config_drift?}
              agent_dirty?={@agent_config_dirty?}
            />
          </div>
        </div>
      </div>

      <%!-- Below the header breakpoint the tabs live at the bottom of the
      screen, like a native app. --%>
      <Tabs.bar tabs={@tabs} active_tab={@active_tab} />

      <Editor.Export.export_board
        :if={@export_format}
        format={@export_format}
        canvas_id={@canvas.id}
        cells={@cells}
        c_name={@c_name}
        c_desc={@c_desc}
        user_id={@user_id}
      />
    </Layouts.app>
    """
  end

  # The pane a tab is shown in ("primary", "split") or nil when it is hidden.
  defp pane(assigns, tab), do: Tabs.pane_of(tab, assigns.active_tab, assigns.split_tab)

  @doc false
  defdelegate export_filename(name, format), to: Editor.Export

  # One status pill reports whichever surface the user is on: the canvas's cells
  # on the Editor tab, the open note on the Notes tab. The other surface's
  # figures are listed alongside, so nothing is lost.
  defp status_source(assigns) do
    # In split view the pill follows the pane the user is working in.
    focused = if assigns.split_tab, do: assigns.focus_pane, else: "primary"
    note_open? = pane(assigns, "notes") == focused and assigns.note

    canvas = %{label: "Canvas", state: assigns.save_state, stats: assigns.save_stats}

    # The toolbar that shows the pill also holds the split view switch.
    status =
      if note_open? do
        %{
          label: "Note",
          state: assigns.note_save_state,
          stats: assigns.note_save_stats,
          others: [canvas]
        }
      else
        %{label: "Canvas", state: canvas.state, stats: canvas.stats, others: []}
      end

    Map.put(status, :split?, not is_nil(assigns.split_tab))
  end
end
