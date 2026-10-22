defmodule PscWeb.UnstrCanvasLive.Editor do
  use PscWeb, :live_view

  # SaladUI button/input are called qualified (UIButton/UIInput) because
  # CoreComponents is imported globally via html_helpers and defines the same
  # names — unqualified imports would conflict.
  alias PscWeb.Components.UI.Button, as: UIButton
  alias PscWeb.Components.UI.Dialog, as: UIDialog
  alias PscWeb.Components.UI.Tooltip, as: UITooltip

  import PscWeb.Components.Accent
  import PscWeb.Components.MarkdownEditor
  import PscWeb.Components.ShareDialog
  import PscWeb.Components.StatusPill

  alias Psc.Canvas
  alias Psc.Canvas.NotesMode
  alias Psc.Notes
  alias PscWeb.Markdown
  alias PscWeb.Presence
  require Logger

  @idle_save_interval 1500
  @periodic_save_interval 10000

  # What the status pill reports: how many writes this session made, how many
  # of them failed, when the last one landed and how long it took.
  @initial_save_stats %{
    writes: 0,
    failures: 0,
    last_saved_at: nil,
    last_write_ms: nil
  }

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
        |> assign(:save_stats, @initial_save_stats)
        |> assign(:share_open, false)
        |> assign(:active_tab, "editor")
        |> assign(:tabs, @tabs)
        |> assign(:agent_session, nil)
        |> assign(:agent_messages, [])
        |> assign(:agent_turn_pid, nil)
        |> assign(:agent_subscribed, nil)
        |> assign(:agent_sessions, [])
        |> assign(:agent_list_open, false)
        |> assign(:agent_menu_session, nil)
        |> assign(:agent_phase, nil)
        |> assign(:focus_cell, nil)
        |> assign(:agent_composer, to_form(%{"content" => ""}, as: :message))
        |> assign(:agent_enabled?, Psc.Agent.enabled?())
        |> assign(:notes, [])
        |> assign(:note, nil)
        |> assign(:note_content, "")
        |> assign(:note_last_saved_content, "")
        |> assign(:note_idle_timer_ref, nil)
        |> assign(:note_save_state, :saved)
        |> assign(:note_save_stats, @initial_save_stats)
        |> assign(:note_topic, nil)
        |> assign(:note_presence, %{})
        |> assign(:is_owner, canvas.author_id == socket.assigns.current_scope.user.id)
        |> assign(:edit_structure?, false)
        |> assign(:structure_accent_picker, nil)
        |> assign(:structure_remove_confirm, nil)
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
  def handle_event("agent_new", _params, socket) do
    user = socket.assigns.current_scope.user

    case Psc.Agent.create_session(user.id, %{canvas_id: socket.assigns.canvas.id}) do
      {:ok, session} ->
        {:noreply,
         socket
         |> subscribe_agent(session)
         |> assign(:agent_session, session)
         |> assign(
           :agent_sessions,
           Psc.Agent.list_sessions_for_canvas(session.canvas_id, session.user_id)
         )
         |> assign(:agent_messages, [])
         |> assign(:agent_composer, to_form(%{"content" => ""}, as: :message))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not start a chat.")}
    end
  end

  def handle_event("agent_send", %{"message" => %{"content" => content}}, socket) do
    content = String.trim(content)
    session = socket.assigns.agent_session

    cond do
      content == "" ->
        {:noreply, socket}

      is_nil(session) ->
        {:noreply, put_flash(socket, :error, "Start a chat first.")}

      not Psc.Agent.enabled?(socket.assigns.current_scope.user) ->
        {:noreply, put_flash(socket, :error, "Add your API key in settings first.")}

      socket.assigns.agent_turn_pid ->
        {:noreply, put_flash(socket, :error, "Wait for the current answer to finish.")}

      true ->
        # Settings live in another tab: the socket's user was loaded at mount, so
        # a key or model saved since then is not on this struct. Re-read it so a
        # change takes effect without reloading the canvas.
        scope = fresh_scope(socket.assigns.current_scope)
        session = session

        # Subscribe before the turn starts: the first deltas can arrive within
        # milliseconds, and a late subscription loses them.
        socket = subscribe_agent(socket, session)

        {:ok, user_message} = Psc.Agent.append_user_message(session, content)
        {:ok, assistant} = Psc.Agent.start_assistant_message(session)
        {:ok, pid} = Psc.Agent.Turn.start(session, assistant, scope)

        {:noreply,
         socket
         |> assign(:agent_session, Psc.Agent.get_session(session.id, session.user_id))
         |> assign(:agent_messages, socket.assigns.agent_messages ++ [user_message, assistant])
         |> assign(:agent_turn_pid, pid)
         |> assign(:agent_enabled?, Psc.Agent.enabled?(scope.user))
         |> assign(:agent_composer, to_form(%{"content" => ""}, as: :message))}
    end
  end

  def handle_event("agent_chat_menu", %{"session" => session_id}, socket) do
    open = if socket.assigns.agent_menu_session == session_id, do: nil, else: session_id
    {:noreply, assign(socket, :agent_menu_session, open)}
  end

  def handle_event("agent_rename", %{"session" => session_id, "title" => title}, socket) do
    user = socket.assigns.current_scope.user

    case Psc.Agent.get_session(session_id, user.id) do
      nil ->
        {:noreply, put_flash(socket, :error, "That chat is no longer available.")}

      session ->
        case Psc.Agent.rename_session(session, title) do
          {:ok, renamed} ->
            current =
              if socket.assigns.agent_session && socket.assigns.agent_session.id == renamed.id,
                do: renamed,
                else: socket.assigns.agent_session

            {:noreply,
             socket
             |> assign(:agent_session, current)
             |> assign(
               :agent_sessions,
               Psc.Agent.list_sessions_for_canvas(renamed.canvas_id, user.id)
             )
             |> assign(:agent_menu_session, nil)}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "A title is required.")}
        end
    end
  end

  def handle_event("agent_duplicate", %{"session" => session_id}, socket) do
    user = socket.assigns.current_scope.user

    case Psc.Agent.get_session(session_id, user.id) do
      nil ->
        {:noreply, put_flash(socket, :error, "That chat is no longer available.")}

      session ->
        {:ok, copy} = Psc.Agent.duplicate_session(session)

        {:noreply,
         socket
         |> subscribe_agent(copy)
         |> assign(:agent_session, copy)
         |> assign(:agent_messages, Psc.Agent.list_messages(copy))
         |> assign(:agent_sessions, Psc.Agent.list_sessions_for_canvas(copy.canvas_id, user.id))
         |> assign(:agent_turn_pid, nil)
         |> assign(:agent_phase, nil)
         |> assign(:agent_menu_session, nil)}
    end
  end

  def handle_event("agent_delete", %{"session" => session_id}, socket) do
    user = socket.assigns.current_scope.user

    case Psc.Agent.get_session(session_id, user.id) do
      nil ->
        {:noreply, socket}

      session ->
        {:ok, _} = Psc.Agent.delete_session(session)
        sessions = Psc.Agent.list_sessions_for_canvas(session.canvas_id, user.id)

        deleted_current? =
          socket.assigns.agent_session && socket.assigns.agent_session.id == session.id

        socket =
          if deleted_current? do
            case List.first(sessions) do
              nil ->
                socket
                |> assign(:agent_session, nil)
                |> assign(:agent_messages, [])

              next ->
                socket
                |> subscribe_agent(next)
                |> assign(:agent_session, next)
                |> assign(:agent_messages, Psc.Agent.list_messages(next))
            end
          else
            socket
          end

        {:noreply,
         socket
         |> assign(:agent_sessions, sessions)
         |> assign(:agent_menu_session, nil)
         |> assign(:agent_turn_pid, nil)
         |> assign(:agent_phase, nil)}
    end
  end

  def handle_event("agent_close_lists", _params, socket) do
    {:noreply, assign(socket, agent_list_open: false, agent_menu_session: nil)}
  end

  def handle_event("agent_toggle_list", _params, socket) do
    {:noreply, assign(socket, :agent_list_open, not socket.assigns.agent_list_open)}
  end

  def handle_event("agent_select", %{"session" => session_id}, socket) do
    user = socket.assigns.current_scope.user

    case Psc.Agent.get_session(session_id, user.id) do
      nil ->
        {:noreply, put_flash(socket, :error, "That chat is no longer available.")}

      session ->
        Psc.Agent.cancel_stale_streaming(session)

        {:noreply,
         socket
         |> subscribe_agent(session)
         |> assign(:agent_session, session)
         |> assign(:agent_messages, Psc.Agent.list_messages(session))
         |> assign(:agent_phase, nil)
         |> assign(:agent_turn_pid, nil)
         |> assign(:agent_list_open, false)}
    end
  end

  def handle_event("agent_stop", _params, socket) do
    case socket.assigns.agent_turn_pid do
      nil ->
        {:noreply, socket}

      pid ->
        Task.Supervisor.terminate_child(Psc.Agent.TurnSupervisor, pid)

        socket =
          case Enum.find(socket.assigns.agent_messages, &(&1.status == :streaming)) do
            nil -> socket
            message -> update_agent_message(socket, message.id, &Psc.Agent.cancel_message/1)
          end

        {:noreply, assign(socket, :agent_turn_pid, nil)}
    end
  end

  @impl true
  def handle_event("open_share", _params, socket) do
    {:noreply, assign(socket, :share_open, true)}
  end

  @impl true
  def handle_event("select_tab", %{"tab" => tab}, socket) do
    {:noreply,
     push_patch(socket, to: ~p"/canvas/#{socket.assigns.canvas_id}?tab=#{tab}", replace: true)}
  end

  @impl true
  def handle_event("select_note", %{"note" => note_id}, socket) do
    {:noreply,
     push_patch(
       socket,
       to: ~p"/canvas/#{socket.assigns.canvas_id}?tab=notes&note=#{note_id}",
       replace: true
     )}
  end

  @impl true
  def handle_event("create_note", _params, socket) do
    if NotesMode.single?(socket.assigns.canvas.notes_mode) do
      # A scratchpad has one note. Opening the view created it already, so
      # there is nothing to create.
      {:noreply, socket}
    else
      case Notes.create_note(socket.assigns.canvas_id, socket.assigns.user_id, %{
             title: "Untitled note"
           }) do
        {:ok, note} ->
          {:noreply,
           socket
           |> reload_notes()
           |> push_patch(
             to: ~p"/canvas/#{socket.assigns.canvas_id}?tab=notes&note=#{note.id}",
             replace: true
           )}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Could not create the note")}
      end
    end
  end

  @impl true
  def handle_event("delete_note", %{"note" => note_id}, socket) do
    # Deleting a note is the canvas author's alone, like the canvas's
    # structure. The note itself carries no access rules.
    if socket.assigns.canvas.author_id == socket.assigns.user_id do
      case Notes.get_note(note_id) do
        %{canvas_id: canvas_id} = note when canvas_id == socket.assigns.canvas_id ->
          {:ok, _note} = Notes.delete_note(note)

          {:noreply,
           socket
           |> reload_notes()
           |> push_patch(to: ~p"/canvas/#{socket.assigns.canvas_id}?tab=notes", replace: true)
           |> put_flash(:success, "Note deleted")}

        _other ->
          {:noreply, socket}
      end
    else
      {:noreply, put_flash(socket, :error, "Only the canvas owner can delete a note")}
    end
  end

  @impl true
  def handle_event("update_note_title", %{"title" => title}, socket) do
    case socket.assigns.note do
      nil ->
        {:noreply, socket}

      note ->
        {:ok, updated} = Notes.update_note(note, %{title: title})

        {:noreply,
         socket
         |> assign(:note, updated)
         |> reload_notes()}
    end
  end

  @impl true
  def handle_event("update_note_content", %{"content" => new_content}, socket) do
    case socket.assigns.note do
      nil ->
        {:noreply, socket}

      note ->
        operations = Notes.text_to_operations(socket.assigns.note_content, new_content)

        Enum.each(operations, fn operation ->
          Notes.apply_operation(note.id, socket.assigns.user_id, operation)
        end)

        socket =
          if socket.assigns.note_idle_timer_ref do
            Process.cancel_timer(socket.assigns.note_idle_timer_ref)
            assign(socket, note_idle_timer_ref: nil)
          else
            socket
          end

        note_idle_timer_ref = Process.send_after(self(), :note_idle_save, @idle_save_interval)

        {:noreply,
         socket
         |> assign(:note_content, new_content)
         |> assign(:note_idle_timer_ref, note_idle_timer_ref)
         |> assign(:note_save_state, :unsaved)}
    end
  end

  @impl true
  def handle_event("render_note", %{"content" => content}, socket) do
    {:noreply,
     push_event(socket, "note_rendered", %{
       content: content,
       html: Markdown.render(content, empty_message: "Start writing in the editor.")
     })}
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

  ## Structure editing (owner only)

  # Every structure event is guarded here, where the operation is created: a
  # shared user forging one is a no-op, the same treatment a forged note
  # delete gets. Collaborators still receive and apply the operations that
  # the owner creates, which is what keeps their grid in step.

  @impl true
  def handle_event("toggle_structure", _params, socket) do
    if socket.assigns.is_owner do
      {:noreply,
       socket
       |> assign(:edit_structure?, not socket.assigns.edit_structure?)
       |> assign(:structure_accent_picker, nil)
       |> assign(:structure_remove_confirm, nil)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("add_row", _params, socket) do
    if socket.assigns.is_owner do
      {id, index} = next_structure_id("r", Map.get(socket.assigns.cells, "rows", []))

      {:noreply,
       process_operation(socket, %{"type" => "add_row", "id" => id, "label" => "Row #{index}"})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("add_column", _params, socket) do
    if socket.assigns.is_owner do
      {id, index} = next_structure_id("c", Map.get(socket.assigns.cells, "columns", []))

      {:noreply,
       process_operation(
         socket,
         %{"type" => "add_column", "id" => id, "label" => "Column #{index}"}
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("update_row_label", %{"structure_id" => id, "label" => label}, socket) do
    if socket.assigns.is_owner do
      {:noreply,
       process_operation(socket, %{"type" => "update_row_label", "id" => id, "label" => label})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("update_column_label", %{"structure_id" => id, "label" => label}, socket) do
    if socket.assigns.is_owner do
      {:noreply,
       process_operation(socket, %{"type" => "update_column_label", "id" => id, "label" => label})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("set_row_accent", %{"id" => id, "accent" => accent}, socket) do
    if socket.assigns.is_owner do
      {:noreply,
       socket
       |> assign(:structure_accent_picker, nil)
       |> process_operation(%{
         "type" => "set_row_accent",
         "id" => id,
         "accent" => normalize_accent(accent)
       })}
    else
      {:noreply, socket}
    end
  end

  def handle_event("set_column_accent", %{"id" => id, "accent" => accent}, socket) do
    if socket.assigns.is_owner do
      {:noreply,
       socket
       |> assign(:structure_accent_picker, nil)
       |> process_operation(%{
         "type" => "set_column_accent",
         "id" => id,
         "accent" => normalize_accent(accent)
       })}
    else
      {:noreply, socket}
    end
  end

  def handle_event("toggle_structure_accent", %{"group" => group, "id" => id}, socket) do
    if socket.assigns.is_owner do
      key = if group == "row", do: {:row, id}, else: {:column, id}

      picker =
        if socket.assigns.structure_accent_picker == key, do: nil, else: key

      {:noreply, assign(socket, :structure_accent_picker, picker)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("request_remove_row", %{"id" => id}, socket) do
    if socket.assigns.is_owner do
      request_structure_remove(socket, "row", id)
    else
      {:noreply, socket}
    end
  end

  def handle_event("request_remove_column", %{"id" => id}, socket) do
    if socket.assigns.is_owner do
      request_structure_remove(socket, "column", id)
    else
      {:noreply, socket}
    end
  end

  def handle_event("confirm_remove_structure", _params, socket) do
    if socket.assigns.is_owner do
      {socket, operation} =
        case socket.assigns.structure_remove_confirm do
          %{"type" => "row", "id" => id} ->
            {socket, %{"type" => "remove_row", "id" => id}}

          %{"type" => "column", "id" => id} ->
            {socket, %{"type" => "remove_column", "id" => id}}

          _other ->
            {socket, nil}
        end

      socket = assign(socket, :structure_remove_confirm, nil)

      if operation do
        {:noreply, process_operation(socket, operation)}
      else
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("dismiss_remove_structure", _params, socket) do
    {:noreply, assign(socket, :structure_remove_confirm, nil)}
  end

  def handle_event("update_cell_label", %{"cell_key" => cell_key, "label" => label}, socket) do
    if socket.assigns.is_owner do
      {:noreply,
       process_operation(socket, %{
         "type" => "update_cell_label",
         "cell_key" => cell_key,
         "label" => label
       })}
    else
      {:noreply, socket}
    end
  end

  def handle_event("add_cell_field", %{"cell_key" => cell_key, "field" => field}, socket) do
    field = String.trim(field)

    if socket.assigns.is_owner and field != "" and
         field not in Psc.Canvas.UnstrCanvasCRDT.reserved_cell_keys() do
      {:noreply,
       process_operation(socket, %{
         "type" => "add_cell_field",
         "cell_key" => cell_key,
         "field" => field
       })}
    else
      {:noreply, socket}
    end
  end

  def handle_event("remove_cell_field", %{"cell_key" => cell_key, "field" => field}, socket) do
    if socket.assigns.is_owner do
      {:noreply,
       process_operation(socket, %{
         "type" => "remove_cell_field",
         "cell_key" => cell_key,
         "field" => field
       })}
    else
      {:noreply, socket}
    end
  end

  def handle_event(
        "update_cell_field_title",
        %{"cell_key" => cell_key, "field" => field, "title" => title},
        socket
      ) do
    if socket.assigns.is_owner do
      {:noreply,
       process_operation(socket, %{
         "type" => "update_cell_field_title",
         "cell_key" => cell_key,
         "field" => field,
         "title" => title
       })}
    else
      {:noreply, socket}
    end
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

  # The next free "rN"/"cN" index, scanning the ids that are already there.
  # `length + 1` collides after a removal (add r1, r2; remove r1; the next
  # "r2" would duplicate the survivor).
  defp next_structure_id(prefix, defs) do
    taken =
      for %{"id" => id} <- defs,
          parts = Regex.run(~r/^#{prefix}(\d+)$/, id),
          n <- tl(parts) do
        String.to_integer(n)
      end

    index = Enum.max([0 | taken]) + 1
    {"#{prefix}#{index}", index}
  end

  # Removing a row or column that holds content asks first: the operation is
  # destructive, and the event log keeps the old values only until pruning
  # folds them. An empty one goes straight away.
  defp request_structure_remove(socket, type, id) do
    ref_key = if type == "row", do: "row", else: "column"
    list_key = if type == "row", do: "rows", else: "columns"

    if structure_has_content?(socket.assigns.cells, ref_key, id) do
      label =
        socket.assigns.cells
        |> Map.get(list_key, [])
        |> Enum.find(%{}, &(&1["id"] == id))
        |> Map.get("label", "")

      {:noreply,
       assign(socket, :structure_remove_confirm, %{"type" => type, "id" => id, "label" => label})}
    else
      operation =
        if type == "row" do
          %{"type" => "remove_row", "id" => id}
        else
          %{"type" => "remove_column", "id" => id}
        end

      {:noreply, process_operation(socket, operation)}
    end
  end

  defp structure_has_content?(cells, ref_key, ref_id) do
    Enum.any?(cells, fn
      {_key, data} when is_map(data) ->
        Map.get(data, ref_key) == ref_id and cell_has_content?(data)

      _pair ->
        false
    end)
  end

  defp cell_has_content?(cell) do
    reserved = Psc.Canvas.UnstrCanvasCRDT.reserved_cell_keys()

    Enum.any?(cell, fn
      {field, value} ->
        field not in reserved and is_binary(value) and String.trim(value) != ""

      _pair ->
        false
    end)
  end

  defp fresh_scope(scope) do
    case Psc.Accounts.get_user_by_email(scope.user.email) do
      nil -> scope
      user -> Psc.Accounts.Scope.for_user(user)
    end
  end

  defp load_agent(socket) do
    user = socket.assigns.current_scope.user
    enabled? = Psc.Agent.enabled?(user)
    sessions = Psc.Agent.list_sessions_for_canvas(socket.assigns.canvas.id, user.id)

    case Psc.Agent.latest_session(socket.assigns.canvas.id, user.id) do
      nil ->
        socket
        |> assign(:agent_session, nil)
        |> assign(:agent_sessions, sessions)
        |> assign(:agent_messages, [])
        |> assign(:agent_enabled?, enabled?)

      session ->
        Psc.Agent.cancel_stale_streaming(session)

        socket
        |> subscribe_agent(session)
        |> assign(:agent_session, session)
        |> assign(:agent_sessions, sessions)
        |> assign(:agent_messages, Psc.Agent.list_messages(session))
        |> assign(:agent_enabled?, enabled?)
    end
  end

  # A turn's stream only reaches the socket if it subscribed to the session's
  # topic. Starting a chat from the tab creates the session *after* mount, so
  # this has to run there too - otherwise every delta and the completion are
  # broadcast into the void and the bubble stays empty forever.
  defp subscribe_agent(socket, %{id: id}) do
    case socket.assigns[:agent_subscribed] do
      ^id ->
        socket

      nil ->
        subscribe_to(socket, id)

      previous ->
        Phoenix.PubSub.unsubscribe(Psc.PubSub, Psc.Agent.Turn.topic(previous))
        subscribe_to(socket, id)
    end
  end

  defp subscribe_to(socket, id) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Psc.PubSub, Psc.Agent.Turn.topic(id))
    assign(socket, :agent_subscribed, id)
  end

  # Links the tools returned with their results. Built server-side from ids the
  # access check already approved, so a chip cannot point somewhere the user
  # could not open.
  defp agent_refs(message) do
    message.tool_calls
    |> Enum.flat_map(fn call ->
      case call["result"] do
        %{"refs" => refs} when is_list(refs) -> Enum.filter(refs, &is_map_key(&1, "url"))
        _other -> []
      end
    end)
    |> Enum.uniq_by(& &1["url"])
  end

  defp agent_cell_refs(message), do: Enum.filter(agent_refs(message), &(&1["kind"] == "cell"))

  defp agent_other_refs(message),
    do: Enum.reject(agent_refs(message), &(&1["kind"] == "cell"))

  defp agent_session_selected?(current, session), do: current.id == session.id

  # A turn is a user message plus the answer it produced; the counter stores both.
  defp turn_count(session), do: max(div(session.message_count + 1, 2), 0)

  defp agent_date(nil), do: "—"

  defp agent_date(%NaiveDateTime{} = at), do: Calendar.strftime(at, "%d %b")
  defp agent_date(%DateTime{} = at), do: Calendar.strftime(at, "%d %b")

  defp agent_relative_time(nil), do: "never used"

  defp agent_relative_time(%_{} = at) do
    seconds = DateTime.diff(DateTime.utc_now(), to_utc(at))

    cond do
      seconds < 60 -> "just now"
      seconds < 3_600 -> "#{div(seconds, 60)}m ago"
      seconds < 86_400 -> "#{div(seconds, 3_600)}h ago"
      seconds < 2_592_000 -> "#{div(seconds, 86_400)}d ago"
      true -> "on #{agent_date(at)}"
    end
  end

  defp to_utc(%DateTime{} = at), do: at
  defp to_utc(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")

  defp update_agent_message(socket, id, fun) do
    messages =
      Enum.map(socket.assigns.agent_messages, fn message ->
        if message.id == id, do: fun.(message), else: message
      end)

    assign(socket, :agent_messages, messages)
  end

  defp normalize_accent(""), do: nil
  defp normalize_accent(accent), do: accent

  @impl true
  def handle_params(params, _url, socket) do
    tab = find_tab(params["tab"]) |> elem(0)

    # A snippet chip links to ?tab=editor&cell=r1_c1: open the editor tab and mark
    # the cell so it is obvious which one the agent meant.
    tab = if params["cell"], do: "editor", else: tab

    socket = assign(socket, :active_tab, tab)
    socket = assign(socket, :focus_cell, params["cell"])

    socket =
      cond do
        tab == "notes" ->
          socket
          |> load_notes()
          |> load_note(params["note"])

        tab == "agent" ->
          load_agent(socket)

        true ->
          socket
      end

    {:noreply, socket}
  end

  # The notes of the canvas, most recently touched first.
  defp reload_notes(socket) do
    assign(socket, :notes, Notes.list_notes(socket.assigns.canvas_id))
  end

  # A scratchpad canvas has exactly one note, and no list. It is created the
  # first time the Notes view is opened, so a canvas that is never written in
  # costs no rows.
  defp load_notes(socket) do
    if NotesMode.single?(socket.assigns.canvas.notes_mode) do
      socket
      |> reload_notes()
      |> ensure_scratchpad()
    else
      reload_notes(socket)
    end
  end

  defp ensure_scratchpad(socket) do
    case socket.assigns.notes do
      [note | _] ->
        socket
        |> leave_note()
        |> assign(:note, note)
        |> assign(:note_content, Notes.get_note_content(note.id))
        |> assign(:note_last_saved_content, Notes.get_note_content(note.id))
        # Single-note canvases never went through load_note_by_id/2, so they
        # never subscribed: remote operations were broadcast to nobody.
        |> subscribe_to_note(note.id)
        |> push_note_resync()

      [] ->
        case Notes.create_note(
               socket.assigns.canvas_id,
               socket.assigns.user_id,
               %{title: "Scratchpad"}
             ) do
          {:ok, note} ->
            socket
            |> assign(:notes, [note])
            |> assign(:note, note)
            |> assign(:note_content, "")
            |> assign(:note_last_saved_content, "")
            |> assign(:note_save_state, :saved)
            |> assign(:note_save_stats, @initial_save_stats)
            |> subscribe_to_note(note.id)
            |> push_note_resync()

          {:error, _changeset} ->
            socket
        end
    end
  end

  # Open a note, if it belongs to this canvas. A note id from another canvas is
  # ignored: the canvas is the only thing that grants access. A scratchpad
  # canvas has one note and cannot choose another.
  defp load_note(socket, note_id) do
    if NotesMode.single?(socket.assigns.canvas.notes_mode) do
      socket
    else
      load_note_by_id(socket, note_id)
    end
  end

  defp load_note_by_id(socket, note_id) when note_id in [nil, ""] do
    socket
    |> leave_note()
    |> assign(:note, nil)
    |> assign(:note_content, "")
    |> assign(:note_last_saved_content, "")
  end

  defp load_note_by_id(socket, note_id) do
    case Notes.get_note(note_id) do
      %{canvas_id: canvas_id} = note when canvas_id == socket.assigns.canvas_id ->
        content = Notes.get_note_content(note.id)

        socket
        |> leave_note()
        |> assign(:note, note)
        |> assign(:note_content, content)
        |> assign(:note_last_saved_content, content)
        |> assign(:note_save_state, :saved)
        |> assign(:note_save_stats, @initial_save_stats)
        |> subscribe_to_note(note.id)
        |> push_note_resync()

      _other ->
        socket
        |> leave_note()
        |> assign(:note, nil)
        |> assign(:note_content, "")
    end
  end

  # Stop listening to the note that was open, so a stale topic cannot deliver
  # operations for a note that is no longer on screen.
  defp leave_note(socket) do
    if socket.assigns[:note_topic] do
      Phoenix.PubSub.unsubscribe(Psc.PubSub, socket.assigns.note_topic)
      Presence.untrack(self(), socket.assigns.note_topic, socket.assigns.user_id)
    end

    if socket.assigns[:note_idle_timer_ref] do
      Process.cancel_timer(socket.assigns.note_idle_timer_ref)
    end

    assign(socket, note_topic: nil, note_presence: %{}, note_idle_timer_ref: nil)
  end

  defp subscribe_to_note(socket, note_id) do
    if connected?(socket) do
      topic = Notes.pubsub_topic(note_id)
      :ok = Phoenix.PubSub.subscribe(Psc.PubSub, topic)

      # The canvas's presence says who is on the canvas; this one says who has
      # *this note* open, which is what the note header reports. It shares the
      # note's topic, so the diffs arrive on the subscription above.
      Presence.track(self(), topic, socket.assigns.user_id, %{
        username: socket.assigns.username
      })

      assign(socket,
        note_topic: topic,
        note_presence: Presence.list(topic)
      )
    else
      socket
    end
  end

  # The editor's textarea is owned by the client hook (`phx-update="ignore"`),
  # so it never picks up the server's content from a re-render — it only gets
  # what is pushed. A `-1` marks a resync rather than somebody's edit. Without
  # it, a note opened after an edit (or between its static render and its
  # socket connecting) showed stale text until the next keystroke elsewhere.
  defp push_note_resync(socket) do
    if connected?(socket) and socket.assigns.note do
      push_event(socket, "note_content_updated", %{
        content: socket.assigns.note_content,
        from_user_id: -1
      })
    else
      socket
    end
  end

  @impl true
  def handle_info({:status, _message_id, phase}, socket) do
    {:noreply, assign(socket, :agent_phase, phase)}
  end

  def handle_info({:delta, message_id, text}, socket) do
    {:noreply, update_agent_message(socket, message_id, &%{&1 | content: &1.content <> text})}
  end

  def handle_info({:tool_started, message_id, call}, socket) do
    {:noreply,
     update_agent_message(socket, message_id, &%{&1 | tool_calls: &1.tool_calls ++ [call]})}
  end

  def handle_info({:tool_finished, message_id, call}, socket) do
    {:noreply,
     update_agent_message(socket, message_id, fn message ->
       %{message | tool_calls: List.update_at(message.tool_calls, -1, &Map.merge(&1, call))}
     end)}
  end

  def handle_info({:completed, message_id, %{content: content}}, socket) do
    {:noreply,
     socket
     |> update_agent_message(message_id, &%{&1 | content: content, status: :complete})
     |> assign(:agent_turn_pid, nil)
     |> assign(:agent_phase, nil)}
  end

  def handle_info({:failed, message_id, reason}, socket) do
    {:noreply,
     socket
     |> update_agent_message(message_id, &%{&1 | status: :error, error: to_string(reason)})
     |> assign(:agent_turn_pid, nil)
     |> assign(:agent_phase, nil)}
  end

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
      socket = assign(socket, save_state: :saving)

      Canvas.update_unstr_canvas(socket.assigns.canvas, %{
        name: socket.assigns.c_name,
        description: socket.assigns.c_desc
      })

      {:noreply,
       socket
       |> save_cells()
       |> assign(:last_saved_cells, socket.assigns.cells)
       |> assign(:idle_timer_ref, nil)
       |> assign(:save_state, :saved)}
    else
      {:noreply, assign(socket, idle_timer_ref: nil)}
    end
  end

  @impl true
  def handle_info(:note_idle_save, socket) do
    case socket.assigns.note do
      nil ->
        {:noreply, assign(socket, note_idle_timer_ref: nil)}

      note ->
        if socket.assigns.note_content != socket.assigns.note_last_saved_content do
          socket = assign(socket, note_save_state: :saving)

          {:noreply,
           socket
           |> save_note_content(note)
           |> assign(:note_last_saved_content, socket.assigns.note_content)
           |> assign(:note_idle_timer_ref, nil)
           |> assign(:note_save_state, :saved)
           # The list shows a snippet of the note's content, so it has to be
           # re-read now that the content has been folded.
           |> reload_notes()}
        else
          {:noreply, assign(socket, note_idle_timer_ref: nil)}
        end
    end
  end

  @impl true
  def handle_info({:note_operation, user_id, operation, _seq}, socket) do
    # Only update if the operation is from another user (avoid echoing back).
    if user_id != socket.assigns.user_id and socket.assigns.note do
      new_content = Psc.Text.apply_operation(operation, socket.assigns.note_content)

      {:noreply,
       socket
       |> assign(:note_content, new_content)
       |> push_event("note_content_updated", %{
         content: new_content,
         from_user_id: user_id
       })}
    else
      {:noreply, socket}
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

        socket
        |> save_cells()
        |> assign(:last_saved_cells, socket.assigns.cells)
        |> assign(:save_state, :saved)
      else
        socket
      end

    Process.send_after(self(), :periodic_save, @periodic_save_interval)
    {:noreply, socket}
  end

  # Write the cells and record what happened, so the status pill can report
  # it. A failed write keeps the state "unsaved": the changes are still only
  # in the event log, and the next save will try again.
  defp save_cells(socket) do
    started = System.monotonic_time(:millisecond)

    result =
      Canvas.save_unstr_canvas_content_to_db(socket.assigns.canvas_id, socket.assigns.cells)

    elapsed = System.monotonic_time(:millisecond) - started
    stats = socket.assigns.save_stats

    case result do
      {:ok, _canvas} ->
        assign(socket,
          save_stats: %{
            stats
            | writes: stats.writes + 1,
              last_saved_at: DateTime.utc_now(),
              last_write_ms: elapsed
          }
        )

      {:error, _changeset} ->
        Logger.error("[UnstrCanvasLive] save failed: canvas_id=#{socket.assigns.canvas_id}")

        assign(socket,
          save_state: :unsaved,
          save_stats: %{stats | failures: stats.failures + 1}
        )
    end
  end

  # Write the note's content and record what happened, so the status pill can
  # report it. A failed write keeps the state "unsaved": the changes are
  # still only in the event log, and the next save will try again.
  defp save_note_content(socket, note) do
    started = System.monotonic_time(:millisecond)

    result = Notes.save_content_to_db(note.id, socket.assigns.note_content)

    elapsed = System.monotonic_time(:millisecond) - started
    stats = socket.assigns.note_save_stats

    case result do
      {:ok, _note} ->
        assign(socket,
          note_save_stats: %{
            stats
            | writes: stats.writes + 1,
              last_saved_at: DateTime.utc_now(),
              last_write_ms: elapsed
          }
        )

      {:error, _changeset} ->
        Logger.error("[UnstrCanvasLive] note save failed: note_id=#{note.id}")

        assign(socket,
          note_save_state: :unsaved,
          note_save_stats: %{stats | failures: stats.failures + 1}
        )
    end
  end

  defp handle_presence_change(socket, canvas_id) do
    presence_list = Presence.list("presence_unstr:#{canvas_id}")
    assign(socket, presence: presence_list)
  end

  # Every data column may shrink to this width before the table stops fitting
  # the viewport and scrolls horizontally.
  @min_column_width_rem 12

  # The row-label column is a fixed width, not one that grows with the
  # longest label.
  #
  # A content-derived width is a trap here: the label reaches the server
  # through a debounced change, so the column would resize a beat after the
  # typing - the width lags the text, and the input the user is typing in
  # moves under their cursor. Worse, the width was sized for the *label*, so
  # in Edit structure the input, the accent swatch and the remove button had
  # to share it: a 5-character label left the input 17px wide.
  #
  # A fixed column gives the input room to type in at every viewport, and it
  # does not move while typing.
  @row_label_width_rem 11

  defp table_min_width(cells) do
    columns = length(cells["columns"] || [])
    "calc(#{row_label_width()}rem + #{columns * @min_column_width_rem}rem)"
  end

  # The width of the row-label column, in rem.
  defp row_label_width, do: @row_label_width_rem

  # A canvas with no rows or no columns has nothing to render as a table: the
  # empty state takes over, and the owner builds the structure in place.
  defp structure_empty?(cells) do
    Map.get(cells, "rows", []) == [] or Map.get(cells, "columns", []) == []
  end

  defp structure_remove_confirm(confirm, :type), do: confirm["type"]
  defp structure_remove_confirm(confirm, :label), do: confirm["label"] || ""

  # The Markdown field of one cell field: the hook wrapper, the rendered
  # preview and the textarea. Shared by the view and the edit-structure
  # renderings of a cell.
  attr :cell_key, :string, required: true
  attr :field, :string, required: true
  attr :value, :any, required: true
  attr :user_id, :integer, required: true

  defp cell_field_editor(assigns) do
    ~H"""
    <div
      id={"md-" <> @cell_key <> "-" <> @field}
      phx-hook="MarkdownField"
      phx-update="ignore"
      data-cell-key={@cell_key}
      data-field={@field}
      data-field-wrapper
      data-current-user-id={@user_id}
      class="w-full"
    >
      <div
        id={"md-render-" <> @cell_key <> "-" <> @field}
        class="md-render prose prose-sm dark:prose-invert break-words mb-0.5 bg-base-300 text-base-content p-1"
        phx-update="ignore"
      >
        {@value}
      </div>
      <textarea
        name={"values[" <> @field <> "]"}
        phx-debounce="150"
        class="field-sizing-content hidden max-h-[60vh] w-full resize-none overflow-y-auto bg-base-300 px-1.5 py-0.5 text-base-content placeholder-base-content/40 focus:outline-none"
        placeholder="Enter value..."
        rows="3"
      >{@value}</textarea>
    </div>
    """
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

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :status, status_source(assigns))

    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      header_title="Canvas Editor"
      fill_height
      main_class="px-2 pt-2 sm:px-6 sm:pt-6 lg:px-8 lg:pt-8"
      container_class="mx-auto flex min-h-0 w-full max-w-none flex-1 flex-col gap-3"
    >
      <:header_nav>
        <.tab_strip tabs={@tabs} active_tab={@active_tab} />
      </:header_nav>

      <:header_actions>
        <.header_actions
          presence={@presence}
          status={@status}
          can_share?={@canvas.author_id == @user_id}
        />
      </:header_actions>

      <div
        id="canvas-workspace"
        class="flex min-h-0 w-full flex-1 flex-col gap-2 pb-[calc(var(--canvas-tab-bar-height)+var(--canvas-tab-bar-gap)+env(safe-area-inset-bottom))] lg:pb-2"
      >
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
              <.status_pill
                id="canvas-save-state-pill"
                save_state={@status.state}
                save_stats={@status.stats}
                label={@status.label}
                others={@status.others}
              />
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
        <%!-- Removing a row or column that holds content asks first: the
        operation is destructive, and the event log keeps the old values only
        until pruning folds them. --%>
        <UIDialog.dialog
          :if={@structure_remove_confirm}
          id="remove-structure-dialog"
          open
          on-close="dismiss_remove_structure"
        >
          <UIDialog.dialog_content class="sm:max-w-md">
            <UIDialog.dialog_header>
              <UIDialog.dialog_title>
                Remove this {structure_remove_confirm(@structure_remove_confirm, :type)}?
              </UIDialog.dialog_title>

              <UIDialog.dialog_description>
                "{structure_remove_confirm(@structure_remove_confirm, :label)}" and everything
                written in it will be removed. This cannot be undone.
              </UIDialog.dialog_description>
            </UIDialog.dialog_header>

            <UIDialog.dialog_footer class="flex flex-row justify-end gap-2">
              <UIButton.button type="button" variant="outline" phx-click="dismiss_remove_structure">
                Keep it
              </UIButton.button>

              <UIButton.button
                type="button"
                variant="destructive"
                id="confirm-remove-structure"
                phx-click="confirm_remove_structure"
              >
                Remove
              </UIButton.button>
            </UIDialog.dialog_footer>
          </UIDialog.dialog_content>
        </UIDialog.dialog>

        <div
          id="canvas-tabpanel"
          phx-hook="CanvasTabs"
          data-active-tab={@active_tab}
          class="flex min-h-0 w-full flex-1 flex-col"
        >
          <%!-- Every view is rendered so the client can switch instantly; the
          inactive ones are hidden. The server confirms the choice a moment
          later and owns the URL. --%>
          <div
            id="canvas-panel-editor"
            role="tabpanel"
            aria-labelledby="canvas-tab-editor"
            class={[
              "flex min-h-0 w-full flex-1 flex-col",
              @active_tab != "editor" && "hidden"
            ]}
          >
            <div
              id="canvas-grid"
              class="flex min-h-0 w-full flex-1 flex-col overflow-hidden rounded-xl border border-base-content/20 bg-base-200"
            >
              <%!-- Structure editing: the owner's toggle, and — while it is on —
              the add actions. Shared users see no toolbar at all. --%>
              <%= if @is_owner do %>
                <div class="flex shrink-0 items-center justify-between gap-2 border-b border-base-content/10 px-3 py-2">
                  <button
                    type="button"
                    id="edit-structure-toggle"
                    phx-click="toggle_structure"
                    aria-pressed={to_string(@edit_structure?)}
                    class={[
                      "inline-flex items-center gap-1.5 rounded-lg border px-2.5 py-1 text-xs font-medium transition-colors",
                      @edit_structure? &&
                        "border-primary/50 bg-primary/10 text-base-content",
                      not @edit_structure? &&
                        "border-base-content/10 text-base-content/70 hover:bg-base-content/5 hover:text-base-content"
                    ]}
                  >
                    <.icon name="hero-pencil-square" class="size-4" /> Edit structure
                  </button>

                  <%= if @edit_structure? do %>
                    <div class="flex gap-2">
                      <UIButton.button
                        type="button"
                        variant="outline"
                        size="sm"
                        phx-click="add_column"
                      >
                        Add Column
                      </UIButton.button>

                      <UIButton.button type="button" variant="outline" size="sm" phx-click="add_row">
                        Add Row
                      </UIButton.button>
                    </div>
                  <% end %>
                </div>
              <% end %>

              <div class="canvas-grid-scroll flex min-h-0 flex-1 flex-col overflow-auto">
                <%= if structure_empty?(@cells) do %>
                  <%!-- A blank canvas: nothing to render as a table yet. The
                  owner builds it here; a shared user waits. --%>
                  <div class="flex min-h-0 flex-1 flex-col items-center justify-center gap-3 p-8 text-center">
                    <.icon name="hero-squares-2x2" class="size-8 text-base-content/30" />
                    <p class="text-sm text-base-content/60">This canvas has no structure yet.</p>

                    <%= if @is_owner do %>
                      <div class="flex gap-2">
                        <UIButton.button
                          type="button"
                          id="empty-add-row"
                          variant="outline"
                          size="sm"
                          phx-click="add_row"
                        >
                          Add row
                        </UIButton.button>

                        <UIButton.button
                          type="button"
                          id="empty-add-column"
                          variant="outline"
                          size="sm"
                          phx-click="add_column"
                        >
                          Add column
                        </UIButton.button>
                      </div>
                    <% else %>
                      <p class="text-xs text-base-content/45">
                        The owner hasn't built this canvas yet.
                      </p>
                    <% end %>
                  </div>
                <% else %>
                  <table
                    class="h-full min-h-0 w-full flex-1 table-fixed border-collapse"
                    style={"min-width: #{table_min_width(@cells)}"}
                  >
                    <colgroup>
                      <col style={"width: #{row_label_width()}rem"} />
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
                                <%= if @edit_structure? do %>
                                  <%!-- Same treatment as the row header: the input
                                  takes the full width, the controls sit beside it
                                  on a pointer and below it on a phone. --%>
                                  <div class="flex flex-col gap-1 sm:flex-row sm:items-center sm:gap-1">
                                    <.form
                                      for={%{}}
                                      id={"column-" <> column["id"] <> "-label-form"}
                                      phx-change="update_column_label"
                                      class="min-w-0 flex-1"
                                    >
                                      <input type="hidden" name="structure_id" value={column["id"]} />
                                      <input
                                        type="text"
                                        id={"column-" <> column["id"] <> "-label"}
                                        name="label"
                                        value={column["label"]}
                                        phx-debounce="300"
                                        class="w-full min-w-0 rounded border border-transparent bg-transparent px-1.5 py-1.5 text-inherit hover:border-base-content/10 focus:border-primary focus:outline-none sm:py-0.5"
                                      />
                                    </.form>

                                    <div class="flex shrink-0 items-center gap-1.5 sm:gap-1">
                                      <button
                                        type="button"
                                        id={"accent-swatch-column-" <> column["id"]}
                                        phx-click="toggle_structure_accent"
                                        phx-value-group="column"
                                        phx-value-id={column["id"]}
                                        class={[
                                          "size-7 shrink-0 rounded-full ring-2 ring-base-content/25 hover:ring-primary transition sm:size-3.5",
                                          swatch_class(column["accent"])
                                        ]}
                                        title="Accent color"
                                        aria-label={"Accent color for column #{column["label"]}"}
                                      ></button>
                                      <button
                                        type="button"
                                        phx-click="request_remove_column"
                                        phx-value-id={column["id"]}
                                        class="inline-flex size-7 shrink-0 items-center justify-center rounded-md border border-error/40 text-error transition-colors hover:border-error hover:bg-error/10 sm:size-5"
                                        title="Remove column"
                                        aria-label={"Remove column #{column["label"]}"}
                                      >
                                        <.icon name="hero-x-mark" class="size-3.5 sm:size-3" />
                                      </button>
                                    </div>
                                  </div>

                                  <div
                                    :if={@structure_accent_picker == {:column, column["id"]}}
                                    class="mt-1 flex flex-wrap items-center gap-1 rounded-md bg-base-100/80 p-1"
                                  >
                                    <%= for token <- Psc.Canvas.Accent.tokens() do %>
                                      <button
                                        type="button"
                                        phx-click="set_column_accent"
                                        phx-value-id={column["id"]}
                                        phx-value-accent={token}
                                        class={[
                                          "size-6 rounded-full ring-1 ring-base-content/25 hover:scale-110 transition sm:size-3",
                                          swatch_class(token),
                                          column["accent"] == token &&
                                            "ring-2 ring-primary ring-offset-1 ring-offset-base-100"
                                        ]}
                                        title={token}
                                        aria-label={"Set column accent #{token}"}
                                      ></button>
                                    <% end %>

                                    <button
                                      type="button"
                                      phx-click="set_column_accent"
                                      phx-value-id={column["id"]}
                                      phx-value-accent=""
                                      class="px-1 text-[0.65rem] text-base-content/50 hover:text-base-content"
                                    >
                                      None
                                    </button>
                                  </div>
                                <% else %>
                                  {column["label"]}
                                <% end %>
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
                            <div class="px-2 py-1">
                              <%= if @edit_structure? do %>
                                <%!-- The input gets the full width of the column; the
                                swatch and the remove button sit beside it on a
                                pointer and below it on a phone, where a 14px
                                swatch is not a target anyone can hit. --%>
                                <div class="flex flex-col gap-1 sm:flex-row sm:items-center sm:gap-1">
                                  <.form
                                    for={%{}}
                                    id={"row-" <> row["id"] <> "-label-form"}
                                    phx-change="update_row_label"
                                    class="min-w-0 flex-1"
                                  >
                                    <input type="hidden" name="structure_id" value={row["id"]} />
                                    <input
                                      type="text"
                                      id={"row-" <> row["id"] <> "-label"}
                                      name="label"
                                      value={row["label"]}
                                      phx-debounce="300"
                                      class="w-full min-w-0 rounded border border-transparent bg-transparent px-1.5 py-1.5 text-inherit hover:border-base-content/10 focus:border-primary focus:outline-none sm:py-0.5"
                                    />
                                  </.form>

                                  <div class="flex shrink-0 items-center gap-1.5 sm:gap-1">
                                    <button
                                      type="button"
                                      id={"accent-swatch-row-" <> row["id"]}
                                      phx-click="toggle_structure_accent"
                                      phx-value-group="row"
                                      phx-value-id={row["id"]}
                                      class={[
                                        "size-7 shrink-0 rounded-full ring-2 ring-base-content/25 hover:ring-primary transition sm:size-3.5",
                                        swatch_class(row["accent"])
                                      ]}
                                      title="Accent color"
                                      aria-label={"Accent color for row #{row["label"]}"}
                                    ></button>
                                    <button
                                      type="button"
                                      phx-click="request_remove_row"
                                      phx-value-id={row["id"]}
                                      class="inline-flex size-7 shrink-0 items-center justify-center rounded-md border border-error/40 text-error transition-colors hover:border-error hover:bg-error/10 sm:size-5"
                                      title="Remove row"
                                      aria-label={"Remove row #{row["label"]}"}
                                    >
                                      <.icon name="hero-x-mark" class="size-3.5 sm:size-3" />
                                    </button>
                                  </div>
                                </div>

                                <div
                                  :if={@structure_accent_picker == {:row, row["id"]}}
                                  class="mt-1 flex flex-wrap items-center gap-1 rounded-md bg-base-100/80 p-1"
                                >
                                  <%= for token <- Psc.Canvas.Accent.tokens() do %>
                                    <button
                                      type="button"
                                      phx-click="set_row_accent"
                                      phx-value-id={row["id"]}
                                      phx-value-accent={token}
                                      class={[
                                        "size-6 rounded-full ring-1 ring-base-content/25 hover:scale-110 transition sm:size-3",
                                        swatch_class(token),
                                        row["accent"] == token &&
                                          "ring-2 ring-primary ring-offset-1 ring-offset-base-100"
                                      ]}
                                      title={token}
                                      aria-label={"Set row accent #{token}"}
                                    ></button>
                                  <% end %>

                                  <button
                                    type="button"
                                    phx-click="set_row_accent"
                                    phx-value-id={row["id"]}
                                    phx-value-accent=""
                                    class="px-1 text-[0.65rem] text-base-content/50 hover:text-base-content"
                                  >
                                    None
                                  </button>
                                </div>
                              <% else %>
                                <div
                                  class="truncate font-medium text-base-content/70 text-sm"
                                  title={row["label"]}
                                >
                                  {row["label"]}
                                </div>
                              <% end %>
                            </div>
                          </td>

                          <%= for {column, col_index} <- Enum.with_index(@cells["columns"] || []) do %>
                            <% layout = @cells["layout"] || [] %> <% cell_key =
                              Enum.at(Enum.at(layout, row_index, []), col_index) %>
                            <td class="relative border border-base-content/20 align-top">
                              <%= if cell_key do %>
                                <% cell_data =
                                  get_in(@cells, ["cells", cell_key]) || @cells[cell_key] || %{} %> <% title =
                                  Map.get(cell_data, "label") || Map.get(cell_data, "name") ||
                                    Map.get(cell_data, "title") || cell_key %>
                                <div
                                  id={"cell-card-" <> cell_key}
                                  phx-hook="CellFocus"
                                  data-cell-key={cell_key}
                                  class={[
                                    "canvas-cell cursor-text bg-base-300 transition-shadow focus-within:ring-2 focus-within:ring-primary/35 focus-within:ring-inset",
                                    @focus_cell == cell_key && "ring-2 ring-primary ring-inset"
                                  ]}
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
                                    <%= if @edit_structure? do %>
                                      <.form
                                        for={%{}}
                                        id={"cell-label-" <> cell_key}
                                        phx-change="update_cell_label"
                                        class="mb-1"
                                      >
                                        <input type="hidden" name="cell_key" value={cell_key} />
                                        <input
                                          type="text"
                                          id={"cell-" <> cell_key <> "-label"}
                                          name="label"
                                          value={Map.get(cell_data, "label", "")}
                                          placeholder={cell_key}
                                          class="w-full min-w-0 rounded border border-transparent bg-transparent px-1.5 py-1 text-sm font-medium text-base-content placeholder-base-content/40 hover:border-base-content/10 focus:border-primary focus:outline-none"
                                        />
                                      </.form>
                                    <% else %>
                                      <div class="mb-1">
                                        <div class="text-sm font-medium text-base-content break-words">
                                          {title}
                                        </div>
                                      </div>
                                    <% end %>

                                    <%= for {field, value} <- cell_data do %>
                                      <%!-- "semantics" is tolerated in older canvases but is
                                    no longer authored or shown; "titles" holds labels. --%>
                                      <%= if field not in ["row", "column", "label", "semantics", "titles"] do %>
                                        <% field_title = Psc.Canvas.field_title(cell_data, field) %>
                                        <div
                                          id={"cell-field-" <> cell_key <> "-" <> field}
                                          class="mb-1 flex min-w-0 flex-col"
                                        >
                                          <%= if @edit_structure? do %>
                                            <.form
                                              for={%{}}
                                              id={"cell-title-" <> cell_key <> "-" <> field}
                                              phx-change="update_cell_field_title"
                                              class="mb-0.5 flex items-center gap-1"
                                            >
                                              <input type="hidden" name="cell_key" value={cell_key} />
                                              <input type="hidden" name="field" value={field} />
                                              <input
                                                type="text"
                                                id={"cell-" <> cell_key <> "-field-" <> field <> "-title"}
                                                name="title"
                                                value={field_title}
                                                placeholder={field}
                                                class="min-w-0 flex-1 rounded border border-base-content/10 bg-base-200 px-1.5 py-0.5 text-xs font-medium text-base-content placeholder-base-content/35 focus:border-primary focus:outline-none"
                                              />
                                              <button
                                                type="button"
                                                phx-click="remove_cell_field"
                                                phx-value-cell_key={cell_key}
                                                phx-value-field={field}
                                                class="inline-flex size-4 shrink-0 items-center justify-center rounded border border-error/40 text-error/90 transition-colors hover:border-error hover:bg-error/10 hover:text-error"
                                                title={"Remove field #{field}"}
                                                aria-label={"Remove field #{field}"}
                                              >
                                                <.icon name="hero-x-mark" class="size-2.5" />
                                              </button>
                                            </.form>
                                          <% else %>
                                            <label
                                              :if={field_title != ""}
                                              class="text-xs font-medium text-base-content/50 uppercase tracking-wide mb-0.5 break-words"
                                            >
                                              {field_title}
                                            </label>
                                          <% end %>

                                          <.form
                                            for={%{}}
                                            id={"cell-form-" <> cell_key <> "-" <> field}
                                            phx-change="update_cell"
                                          >
                                            <input type="hidden" name="cell_key" value={cell_key} />
                                            <.cell_field_editor
                                              cell_key={cell_key}
                                              field={field}
                                              value={value}
                                              user_id={@user_id}
                                            />
                                          </.form>
                                        </div>
                                      <% end %>
                                    <% end %>

                                    <%= if @edit_structure? do %>
                                      <.form
                                        for={%{}}
                                        id={"cell-add-field-" <> cell_key}
                                        phx-submit="add_cell_field"
                                        class="mt-1 flex gap-1"
                                      >
                                        <input type="hidden" name="cell_key" value={cell_key} />
                                        <input
                                          type="text"
                                          id={"cell-" <> cell_key <> "-new-field"}
                                          name="field"
                                          placeholder="New field"
                                          class="min-w-0 flex-1 rounded border border-base-content/10 bg-base-200 px-1.5 py-0.5 text-xs text-base-content placeholder-base-content/35 focus:border-primary focus:outline-none"
                                        />
                                        <button
                                          type="submit"
                                          class="shrink-0 rounded border border-base-content/10 px-1.5 py-0.5 text-xs text-base-content/70 transition-colors hover:bg-base-content/5 hover:text-base-content"
                                        >
                                          Add
                                        </button>
                                      </.form>
                                    <% end %>
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
                <% end %>
              </div>
            </div>
          </div>

          <div
            id="canvas-panel-notes"
            role="tabpanel"
            aria-labelledby="canvas-tab-notes"
            class={[
              "flex min-h-0 w-full flex-1 flex-col",
              @active_tab != "notes" && "hidden"
            ]}
          >
            <.notes_view
              notes={@notes}
              note={@note}
              note_content={@note_content}
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
            role="tabpanel"
            aria-labelledby="canvas-tab-agent"
            class={[
              "flex min-h-0 w-full flex-1 flex-col",
              @active_tab != "agent" && "hidden"
            ]}
          >
            <div class="flex min-h-0 w-full flex-1 flex-col rounded-xl border border-base-content/10 bg-base-200/40 p-4">
              <div :if={is_nil(@agent_session)} class="m-auto max-w-md text-center">
                <h2 class="text-lg font-medium text-base-content">Agent</h2>

                <p class="mt-1 text-sm text-base-content/60">
                  Ask about this canvas. The agent reads only what you can read and cannot change anything.
                </p>

                <p :if={not @agent_enabled?} class="mt-3 text-sm text-base-content/60">
                  The agent needs a model provider key.
                  <.link navigate={~p"/users/settings"} class="link link-primary">
                    Add your API key in settings
                  </.link>
                </p>

                <button
                  type="button"
                  phx-click="agent_new"
                  disabled={not @agent_enabled?}
                  class="mt-4 rounded-lg bg-primary px-4 py-2 text-sm font-medium text-primary-content disabled:opacity-50"
                >
                  Start a chat
                </button>
              </div>

              <div :if={@agent_session} class="flex min-h-0 flex-1 flex-col">
                <div class="flex items-center justify-between gap-3 border-b border-base-content/10 pb-2">
                  <h2 id="canvas-agent-title" class="truncate text-sm font-medium text-base-content">
                    {@agent_session.title}
                  </h2>

                  <div class="flex shrink-0 items-center gap-2">
                    <div class="relative" phx-click-away="agent_close_lists">
                      <button
                        type="button"
                        id="canvas-agent-chats"
                        phx-click="agent_toggle_list"
                        class="flex max-w-[12rem] items-center gap-1 rounded-lg border border-base-content/15 px-2 py-1 text-xs text-base-content/70 hover:bg-base-100"
                      >
                        <.icon name="hero-chat-bubble-left-right" class="size-3.5 shrink-0" />
                        <span class="truncate">{length(@agent_sessions)} chats</span>
                        <.icon name="hero-chevron-down" class="size-3 shrink-0" />
                      </button>

                      <div
                        :if={@agent_list_open}
                        id="canvas-agent-chat-list"
                        class="absolute right-0 z-30 mt-1 w-72 rounded-xl border border-base-content/10 bg-base-100 p-1 shadow-lg"
                      >
                        <p class="px-2 py-1 text-[11px] uppercase tracking-wide text-base-content/40">
                          Chats on this canvas
                        </p>

                        <div :for={session <- @agent_sessions} class="group relative">
                          <button
                            type="button"
                            phx-click="agent_select"
                            phx-value-session={session.id}
                            class={[
                              "block w-full rounded-lg px-2 py-1.5 pr-8 text-left hover:bg-base-200",
                              agent_session_selected?(@agent_session, session) && "bg-base-200"
                            ]}
                          >
                            <p class="truncate text-xs font-medium text-base-content">
                              {session.title}
                            </p>

                            <p class="mt-0.5 text-[11px] text-base-content/50">
                              {turn_count(session)} turns · started {agent_date(session.inserted_at)} · {agent_relative_time(
                                session.last_message_at || session.inserted_at
                              )}
                            </p>
                          </button>

                          <button
                            type="button"
                            phx-click="agent_chat_menu"
                            phx-value-session={session.id}
                            aria-label="Chat options"
                            class={[
                              "absolute right-1 top-1.5 rounded p-1 text-base-content/50 hover:bg-base-300",
                              "opacity-0 transition-opacity group-hover:opacity-100",
                              @agent_menu_session == session.id && "opacity-100"
                            ]}
                          >
                            <.icon name="hero-ellipsis-vertical" class="size-4" />
                          </button>

                          <div
                            :if={@agent_menu_session == session.id}
                            class="absolute right-1 top-8 z-40 w-44 rounded-lg border border-base-content/10 bg-base-100 p-1 shadow-lg"
                          >
                            <.form
                              for={to_form(%{"title" => session.title}, as: :rename)}
                              id={"agent-rename-#{session.id}"}
                              phx-submit="agent_rename"
                              phx-value-session={session.id}
                              class="px-1 pb-1"
                            >
                              <input
                                type="text"
                                name="title"
                                value={session.title}
                                maxlength="120"
                                class="w-full rounded border border-base-content/15 bg-base-100 px-1.5 py-1 text-xs text-base-content"
                              />
                              <button
                                type="submit"
                                class="mt-1 w-full rounded bg-primary px-2 py-1 text-xs text-primary-content"
                              >
                                Rename
                              </button>
                            </.form>

                            <button
                              type="button"
                              phx-click="agent_duplicate"
                              phx-value-session={session.id}
                              class="w-full rounded px-2 py-1 text-left text-xs text-base-content/80 hover:bg-base-200"
                            >
                              Duplicate
                            </button>

                            <button
                              type="button"
                              phx-click="agent_delete"
                              phx-value-session={session.id}
                              data-confirm="Delete this chat and its transcript?"
                              class="w-full rounded px-2 py-1 text-left text-xs text-error hover:bg-error/10"
                            >
                              Delete
                            </button>
                          </div>
                        </div>
                      </div>
                    </div>

                    <button
                      :if={@agent_turn_pid}
                      type="button"
                      phx-click="agent_stop"
                      class="rounded-lg border border-base-content/20 px-2 py-1 text-xs hover:bg-base-100"
                    >
                      Stop
                    </button>

                    <button
                      type="button"
                      phx-click="agent_new"
                      class="rounded-lg border border-base-content/20 px-2 py-1 text-xs hover:bg-base-100"
                    >
                      New chat
                    </button>
                  </div>
                </div>

                <div
                  :if={@agent_phase}
                  id="canvas-agent-status"
                  class="mt-2 flex items-center gap-2 text-xs text-base-content/60"
                >
                  <span class="size-1.5 animate-pulse rounded-full bg-primary"></span> {@agent_phase}
                </div>

                <div id="canvas-agent-messages" class="mt-3 flex-1 space-y-3 overflow-y-auto pr-1">
                  <p :if={@agent_messages == []} class="text-sm text-base-content/60">
                    Ask about this canvas: its cells, its notes, what changed.
                  </p>

                  <div
                    :for={message <- @agent_messages}
                    id={"agent-message-#{message.id}"}
                    class={[
                      "rounded-xl border p-3 text-sm",
                      message.role == :user && "border-primary/20 bg-primary/5",
                      message.role == :assistant && "border-base-content/10 bg-base-100",
                      message.status == :error && "border-error/40"
                    ]}
                  >
                    <p class="mb-1 text-xs uppercase tracking-wide text-base-content/50">
                      {if message.role == :user, do: "You", else: "Assistant"}
                    </p>

                    <div :if={message.tool_calls != []} class="mb-2 space-y-1">
                      <p class="text-xs uppercase tracking-wide text-base-content/40">
                        Tools called
                      </p>

                      <details
                        :for={call <- message.tool_calls}
                        class="rounded-lg border border-base-content/10 px-2 py-1 text-xs"
                      >
                        <summary class="cursor-pointer list-none">
                          <span class="font-mono">{call["name"]}</span>
                          <span class="ml-2 text-base-content/50">{call["status"]}</span>
                        </summary>
                        <pre class="mt-1 overflow-x-auto whitespace-pre-wrap text-base-content/70">{Jason.encode!(
                          call["result"] || call["arguments"] || %{},
                          pretty: true
                        )}</pre>
                      </details>
                    </div>

                    <div
                      :if={agent_refs(message) != []}
                      id={"agent-refs-#{message.id}"}
                      class="mb-2 space-y-2"
                    >
                      <div
                        :for={ref <- agent_cell_refs(message)}
                        class="rounded-lg border border-base-content/10 bg-base-200/60 px-2.5 py-2"
                      >
                        <div class="flex items-start justify-between gap-2">
                          <p class="text-xs font-medium text-base-content/80">{ref["label"]}</p>

                          <.link
                            navigate={ref["url"]}
                            class="shrink-0 rounded-md border border-base-content/15 px-2 py-0.5 text-xs text-base-content/70 hover:bg-base-100"
                          >
                            Open cell
                          </.link>
                        </div>

                        <p
                          :if={ref["excerpt"]}
                          class="mt-1 line-clamp-3 whitespace-pre-wrap text-xs leading-relaxed text-base-content/60"
                        >
                          {ref["excerpt"]}
                        </p>
                      </div>

                      <div :if={agent_other_refs(message) != []} class="flex flex-wrap gap-1.5">
                        <.link
                          :for={ref <- agent_other_refs(message)}
                          navigate={ref["url"]}
                          class={[
                            "inline-flex max-w-[20rem] items-center gap-1.5 rounded-md border px-2 py-1 text-xs transition-colors hover:bg-base-200",
                            ref["kind"] == "note" && "border-primary/30 text-primary",
                            ref["kind"] != "note" && "border-base-content/15 text-base-content/70"
                          ]}
                        >
                          <.icon
                            name={
                              case ref["kind"] do
                                "note" -> "hero-document-text"
                                "template" -> "hero-rectangle-stack"
                                _other -> "hero-square-2-stack"
                              end
                            }
                            class="size-3.5 shrink-0"
                          /> <span class="truncate">{ref["label"]}</span>
                        </.link>
                      </div>
                    </div>

                    <div class="whitespace-pre-wrap break-words text-base-content">
                      {message.content}<span :if={message.status == :streaming}>▍</span>
                    </div>

                    <p :if={message.status == :cancelled} class="mt-1 text-xs text-base-content/50">
                      Stopped.
                    </p>

                    <p :if={message.error} class="mt-1 text-xs text-error">{message.error}</p>
                  </div>
                </div>

                <.form
                  for={@agent_composer}
                  id="canvas-agent-composer"
                  phx-submit="agent_send"
                  class="mt-3 rounded-xl border border-base-content/10 bg-base-100 p-2 focus-within:border-primary/50 focus-within:ring-2 focus-within:ring-primary/20"
                >
                  <.input
                    field={@agent_composer[:content]}
                    type="textarea"
                    rows="2"
                    placeholder="Ask about this canvas…"
                    disabled={not @agent_enabled? or @agent_turn_pid != nil}
                    class="border-0 bg-transparent px-1 py-1 focus:ring-0"
                  />
                  <div class="mt-2 flex items-center justify-between gap-3">
                    <p class="text-xs text-base-content/50">
                      <%= if @agent_enabled? do %>
                        Read-only. Nothing is created or changed.
                      <% else %>
                        <.link navigate={~p"/users/settings"} class="link link-primary">
                          Add your API key in settings
                        </.link>
                      <% end %>
                    </p>

                    <button
                      type="submit"
                      disabled={not @agent_enabled? or @agent_turn_pid != nil}
                      class="rounded-lg bg-primary px-3 py-1.5 text-sm font-medium text-primary-content disabled:opacity-50"
                    >
                      Send
                    </button>
                  </div>
                </.form>
              </div>
            </div>
          </div>

          <%= for {tab_id, label, icon, blurb} <- @tabs do %>
            <%= if tab_id not in ["editor", "notes", "agent"] do %>
              <div
                id={"canvas-panel-" <> tab_id}
                role="tabpanel"
                aria-labelledby={"canvas-tab-" <> tab_id}
                class={[
                  "flex min-h-0 w-full flex-1 flex-col",
                  @active_tab != tab_id && "hidden"
                ]}
              >
                <div
                  id={"canvas-placeholder-" <> tab_id}
                  class="flex min-h-0 w-full flex-1 flex-col items-center justify-center gap-3 rounded-xl border border-dashed border-base-content/20 bg-base-200/40 p-8 text-center"
                >
                  <span class="flex size-12 items-center justify-center rounded-full bg-base-content/5 text-base-content/40">
                    <.icon name={icon} class="size-6" />
                  </span>

                  <h2 class="text-lg font-medium text-base-content">
                    {label}
                  </h2>

                  <p class="max-w-sm text-sm text-base-content/60">
                    {blurb}
                  </p>

                  <p class="text-xs text-base-content/40">Coming soon.</p>
                </div>
              </div>
            <% end %>
          <% end %>
        </div>
      </div>

      <%!-- Below the header breakpoint the tabs live at the bottom of the
      screen, like a native app. --%>
      <.tab_bar tabs={@tabs} active_tab={@active_tab} />
    </Layouts.app>
    """
  end

  # One status pill reports whichever surface the user is on: the canvas's cells
  # on the Editor tab, the open note on the Notes tab. The other surface's
  # figures are listed alongside, so nothing is lost.
  defp status_source(assigns) do
    note_open? = assigns.active_tab == "notes" and assigns.note

    canvas = %{label: "Canvas", state: assigns.save_state, stats: assigns.save_stats}

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
  end

  # The Notes view: the canvas's notes, and the one that is open.
  #
  # On a wide screen the list sits beside the editor. On a phone they are one
  # pane at a time: the list, and — once a note is open — the editor with a
  # back action.
  #
  # A scratchpad canvas has one note and no list: the editor takes the whole
  # view, with no way to pick another note.
  attr :notes, :list, required: true
  attr :note, :map, default: nil
  attr :note_content, :string, default: ""
  attr :note_save_state, :atom, required: true
  attr :note_save_stats, :map, required: true
  attr :note_presence, :map, default: %{}
  attr :user_id, :integer, required: true
  attr :is_owner, :boolean, required: true
  attr :scratchpad?, :boolean, default: false

  defp notes_view(assigns) do
    ~H"""
    <div id="canvas-notes" class="flex min-h-0 w-full flex-1 flex-col lg:flex-row lg:gap-4">
      <%!-- The list. On a phone it is hidden while a note is open. A
      scratchpad has no list at all: it is not rendered. --%>
      <%= if not @scratchpad? do %>
        <div
          id="canvas-notes-list"
          class={[
            "flex min-h-0 w-full flex-col lg:w-64 lg:shrink-0",
            @note && "hidden lg:flex"
          ]}
        >
          <div class="mb-3 flex items-center justify-between gap-3">
            <h2 class="text-sm font-medium uppercase tracking-wide text-base-content/50">
              Notes
            </h2>

            <UIButton.button type="button" id="new-note-button" phx-click="create_note" size="sm">
              <.icon name="hero-plus" class="size-4" /> New note
            </UIButton.button>
          </div>

          <%= if @notes == [] do %>
            <div
              id="canvas-notes-empty"
              class="rounded-xl border border-dashed border-base-content/20 bg-base-200/40 p-6 text-center"
            >
              <p class="text-sm text-base-content/60">No notes yet.</p>

              <p class="mt-1 text-xs text-base-content/45">
                Notes are shared Markdown attached to this canvas.
              </p>
            </div>
          <% else %>
            <ul id="canvas-notes-items" class="min-h-0 flex-1 space-y-2 overflow-y-auto">
              <li :for={note <- @notes} id={"canvas-note-" <> note.id}>
                <button
                  type="button"
                  phx-click="select_note"
                  phx-value-note={note.id}
                  aria-current={to_string(@note && @note.id == note.id)}
                  class={[
                    "w-full rounded-lg border p-3 text-left transition-colors",
                    @note && @note.id == note.id && "border-primary/40 bg-primary/10",
                    !(@note && @note.id == note.id) &&
                      "border-base-content/10 bg-base-200 hover:border-base-content/25"
                  ]}
                >
                  <span class="block truncate text-sm font-medium text-base-content">
                    {note.title || "Untitled note"}
                  </span>

                  <span class="mt-1 block truncate text-xs text-base-content/50">
                    {note_snippet(note.content)}
                  </span>
                </button>
              </li>
            </ul>
          <% end %>
        </div>
      <% end %>
      <%!-- The editor. On a phone it takes over the pane. --%>
      <div
        id="canvas-note-editor"
        class={[
          "flex min-h-0 w-full flex-1 flex-col",
          !@note && "hidden lg:flex"
        ]}
      >
        <%= if @note do %>
          <div class="mb-3 flex flex-wrap items-center gap-3">
            <%!-- There is no list to go back to in a scratchpad. --%>
            <button
              :if={!@scratchpad?}
              type="button"
              id="canvas-notes-back"
              phx-click="select_note"
              phx-value-note=""
              class="inline-flex size-8 shrink-0 items-center justify-center rounded-lg text-base-content/60 transition-colors hover:bg-base-content/5 hover:text-base-content lg:hidden"
              aria-label="Back to the notes"
            >
              <.icon name="hero-arrow-left" class="size-5" />
            </button>

            <.form
              for={%{}}
              id="canvas-note-title-form"
              phx-change="update_note_title"
              class="min-w-0 flex-1"
            >
              <input
                name="title"
                type="text"
                value={@note.title}
                phx-debounce="500"
                placeholder="Untitled note"
                class="w-full min-w-0 border-b-2 border-transparent bg-transparent text-lg font-semibold text-base-content transition-colors placeholder-base-content/40 hover:border-base-content/20 focus:border-primary focus:outline-none"
              />
            </.form>

            <%!-- Who else has this note open. The canvas's Active Users says
            who is on the canvas; this says who is in the same note. --%>
            <span
              :if={note_editors(@note_presence, @user_id) != []}
              id="canvas-note-presence"
              title={note_editors_label(note_editors(@note_presence, @user_id))}
              class="inline-flex max-w-48 items-center gap-1.5 rounded-full border border-base-content/10 bg-base-content/5 px-2.5 py-1 text-xs text-base-content/70"
            >
              <span class="relative flex size-2 shrink-0">
                <span class="absolute inline-flex size-full rounded-full bg-success/50"></span>
                <span class="relative inline-flex size-2 rounded-full bg-success"></span>
              </span>
              <span class="truncate">
                {note_editors_label(note_editors(@note_presence, @user_id))}
              </span>
            </span>

            <%= if @is_owner and not @scratchpad? do %>
              <UIButton.button
                type="button"
                id="canvas-note-delete"
                phx-click="delete_note"
                phx-value-note={@note.id}
                variant="outline"
                size="sm"
                class="text-error hover:text-error"
              >
                Delete
              </UIButton.button>
            <% end %>
          </div>

          <.markdown_editor
            id="canvas-note-markdown"
            input_id="canvas-note-input"
            form_id="canvas-note-form"
            preview_id="canvas-note-preview"
            content={@note_content}
            html={Markdown.render(@note_content, empty_message: "Start writing in the editor.")}
            current_user_id={@user_id}
            change_event="update_note_content"
            preview_event="render_note"
            render_event="note_rendered"
            update_event="note_content_updated"
            empty_message="Start writing in the editor."
            preview_label="Edit note content"
          />
        <% else %>
          <div class="flex min-h-0 flex-1 items-center justify-center rounded-xl border border-dashed border-base-content/20 bg-base-200/40 p-8 text-center">
            <p class="max-w-sm text-sm text-base-content/50">
              <%= if @scratchpad? do %>
                The scratchpad is on its way. Reload the view to write in it.
              <% else %>
                Select a note, or create one, to start writing.
              <% end %>
            </p>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # A one-line preview of a note's content for the list.
  defp note_snippet(nil), do: "Empty"

  defp note_snippet(content) when content in ["", nil], do: "Empty"

  defp note_snippet(content) do
    content
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, 90)
  end

  # The other people who have this note open. Presence keys come back from the
  # CRDT as strings, so the id is compared as one.
  defp note_editors(presence, user_id) do
    for {id, %{metas: [meta | _]}} <- presence, to_string(id) != to_string(user_id) do
      meta[:username]
    end
  end

  defp note_editors_label([username]), do: "#{username} is editing"
  defp note_editors_label(usernames), do: "#{length(usernames)} others are editing"

  # On phones the canvas header gives its vertical space back to the grid: the
  # presence, the save state and Share move into the app header as icons.
  attr :presence, :map, required: true
  attr :status, :map, required: true
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

      <.status_pill
        id="canvas-save-state-compact"
        save_state={@status.state}
        save_stats={@status.stats}
        label={@status.label}
        others={@status.others}
        compact
      />
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
        data-tab={tab_id}
        aria-selected={to_string(@active_tab == tab_id)}
        aria-controls={"canvas-panel-#{tab_id}"}
        aria-label={label}
        title={label}
        phx-click="select_tab"
        phx-value-tab={tab_id}
        class="flex shrink-0 items-center gap-1.5 rounded-md px-2.5 py-1.5 text-sm font-medium transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-primary"
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
      class="fixed inset-x-0 bottom-0 z-40 flex h-[calc(var(--canvas-tab-bar-height)+env(safe-area-inset-bottom))] items-stretch justify-around gap-1 border-t border-base-content/10 bg-base-200/95 px-1 py-1 pb-[env(safe-area-inset-bottom)] backdrop-blur lg:hidden"
    >
      <button
        :for={{tab_id, label, icon, _blurb} <- @tabs}
        type="button"
        role="tab"
        id={"canvas-tab-bar-#{tab_id}"}
        data-tab={tab_id}
        aria-selected={to_string(@active_tab == tab_id)}
        aria-controls={"canvas-panel-#{tab_id}"}
        aria-label={label}
        title={label}
        phx-click="select_tab"
        phx-value-tab={tab_id}
        class="flex flex-1 shrink-0 flex-col items-center justify-center gap-0.5 rounded-lg px-2 py-1.5 text-[0.7rem] font-medium transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-primary"
      >
        <.icon name={icon} class="size-5" /> <span>{label}</span>
      </button>
    </nav>
    """
  end
end
