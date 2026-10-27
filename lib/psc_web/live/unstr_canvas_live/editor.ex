defmodule PscWeb.UnstrCanvasLive.Editor do
  use PscWeb, :live_view

  # SaladUI button/input are called qualified (UIButton/UIInput) because
  # CoreComponents is imported globally via html_helpers and defines the same
  # names — unqualified imports would conflict.
  alias PscWeb.Components.UI.Button, as: UIButton
  alias PscWeb.Components.UI.Dialog, as: UIDialog
  alias PscWeb.Components.ImageBoard, as: ImageFrame

  alias Psc.Agent.Config, as: AgentConfig
  alias Psc.Agent.Files, as: AgentFiles
  alias Psc.Canvas
  alias Psc.Canvas.NotesMode
  alias Psc.Canvas.Structure
  alias Psc.Notes
  alias PscWeb.AgentUploads
  alias PscWeb.Markdown
  alias PscWeb.Presence
  alias PscWeb.UnstrCanvasLive.AgentPanel
  alias PscWeb.UnstrCanvasLive.Bento
  alias PscWeb.UnstrCanvasLive.Grid
  alias PscWeb.UnstrCanvasLive.Header
  alias PscWeb.UnstrCanvasLive.ImageCanvas
  alias PscWeb.UnstrCanvasLive.InfoPanel
  alias PscWeb.UnstrCanvasLive.NotesPanel
  alias PscWeb.UnstrCanvasLive.Save
  alias PscWeb.UnstrCanvasLive.Tabs
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

      agent_config = AgentConfig.normalize(canvas.agent_config)
      agent_source = Canvas.agent_source_template(canvas)

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
        |> assign(:tabs, Tabs.tabs())
        |> assign(:agent_session, nil)
        |> assign(:agent_messages, [])
        |> assign(:agent_turn_pid, nil)
        |> assign(:agent_subscribed, nil)
        |> assign(:agent_sessions, [])
        |> assign(:agent_list_open, false)
        |> assign(:agent_menu_session, nil)
        |> assign(:agent_phase, nil)
        |> assign(:agent_composer, to_form(%{"content" => ""}, as: :message))
        |> assign(:agent_enabled?, Psc.Agent.enabled?(socket.assigns.current_scope.user))
        |> assign(
          :agent_missing,
          Psc.Agent.missing_configuration(socket.assigns.current_scope.user)
        )
        |> assign(:agent_connections, [])
        |> assign(:agent_connection, nil)
        |> assign(:agent_connection_list_open, false)
        |> assign(:agent_config, agent_config)
        |> assign(
          :agent_files,
          AgentFiles.drafts(:canvas, canvas.id) |> AgentUploads.with_html()
        )
        |> assign(:agent_config_dirty?, false)
        |> assign(:agent_source_template, agent_source)
        |> assign(:agent_config_drift?, Canvas.agent_config_drift?(canvas, agent_source))
        |> assign(:agent_roles, agent_config["roles"] || [])
        |> assign(:agent_role, agent_config["default_role"])
        |> AgentUploads.allow()
        |> assign(:notes, [])
        |> assign(:note, nil)
        |> assign(:note_content, "")
        |> assign(:note_html, "")
        |> assign(:note_last_saved_content, "")
        |> assign(:note_idle_timer_ref, nil)
        |> assign(:note_save_state, :saved)
        |> assign(:note_save_stats, @initial_save_stats)
        |> assign(:note_topic, nil)
        |> assign(:note_presence, %{})
        |> assign(:edit_structure?, false)
        |> assign(:structure_accent_picker, nil)
        |> assign(:structure_colors_picker, nil)
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
    cells = Psc.Canvas.UnstrCanvasCRDT.apply_operation(operation, socket.assigns.cells)

    # A blur can send the value that was already there (the cell hook does this
    # for every field), and structure edits are idempotent. Recording those
    # would create an event row and flip the pill to Unsaved for no change.
    if cells == socket.assigns.cells do
      socket
    else
      socket = record_operation(socket, operation)

      Logger.debug(fn ->
        "[UnstrCanvasLive] applied operation: canvas_id=#{socket.assigns.canvas_id} user_id=#{socket.assigns.user_id} op=#{inspect(operation)} resulting_cells_sample=#{inspect(Map.take(cells, ["cells", "layout", "columns", "rows"]))}"
      end)

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
  end

  defp record_operation(socket, operation) do
    case Canvas.apply_unstr_canvas_operation(
           socket.assigns.canvas_id,
           socket.assigns.user_id,
           socket.assigns.client_id,
           operation
         ) do
      {:ok, _seq} ->
        socket

      {:error, _changeset} ->
        Logger.error(
          "[UnstrCanvasLive] operation was not recorded: canvas_id=#{socket.assigns.canvas_id} op=#{inspect(operation["type"])}"
        )

        put_flash(
          socket,
          :error,
          "Could not record the change. It will be saved with the next snapshot."
        )
    end
  end

  # ─── Canvas agent settings (Info tab) ───

  @impl true
  def handle_event("agent_cfg_change", %{"_target" => target} = params, socket) do
    {:noreply,
     socket
     |> update_agent_config(&AgentConfig.apply_form_change(&1, target, params))
     |> assign(
       :agent_files,
       AgentFiles.apply_form_change(socket.assigns.agent_files, target, params)
     )}
  end

  def handle_event("agent_cfg_change", _params, socket), do: {:noreply, socket}

  def handle_event("agent_cfg_cancel_upload", %{"upload" => upload, "ref" => ref}, socket) do
    {:noreply, AgentUploads.cancel(socket, upload, ref)}
  end

  def handle_event("agent_cfg_cancel_directory", %{"path" => path}, socket) do
    {:noreply, AgentUploads.cancel_directory(socket, path)}
  end

  def handle_event("agent_cfg_upload", _params, socket) do
    cond do
      AgentUploads.pending?(socket.assigns.uploads) ->
        {:noreply, put_flash(socket, :info, "Files are still uploading. Try again in a moment.")}

      not AgentUploads.ready?(socket.assigns.uploads) ->
        {:noreply, socket}

      true ->
        {files, stats} = AgentUploads.apply(socket, socket.assigns.agent_files)
        socket = update_agent_files(socket, fn _files -> files end)

        {:noreply, put_flash(socket, :info, AgentFiles.upload_summary(stats))}
    end
  end

  def handle_event("agent_file_render", %{"index" => index, "content" => content}, socket)
      when is_binary(content) do
    with {index, ""} <- Integer.parse(to_string(index)),
         true <- index >= 0 and index < length(socket.assigns.agent_files) do
      html = Markdown.render(content, empty_message: "")
      files = List.update_at(socket.assigns.agent_files, index, &Map.put(&1, "html", html))

      {:noreply,
       socket
       |> assign(:agent_files, files)
       |> push_event("agent_file_rendered", %{content: content, html: html})}
    else
      _other -> {:noreply, socket}
    end
  end

  def handle_event("agent_file_render", _params, socket), do: {:noreply, socket}

  def handle_event("agent_cfg_add_role", _params, socket) do
    {:noreply, update_agent_config(socket, &AgentConfig.add_role/1)}
  end

  def handle_event("agent_cfg_remove_role", %{"key" => key}, socket) do
    {:noreply, update_agent_config(socket, &AgentConfig.remove_role(&1, key))}
  end

  def handle_event("agent_cfg_set_default_role", %{"key" => key}, socket) do
    {:noreply, update_agent_config(socket, &AgentConfig.set_default_role(&1, key))}
  end

  def handle_event("agent_cfg_toggle_tool", %{"name" => name}, socket) do
    {:noreply, update_agent_config(socket, &AgentConfig.toggle_tool(&1, name))}
  end

  def handle_event("agent_cfg_add_file", _params, socket) do
    if length(socket.assigns.agent_files) < AgentFiles.max_files() do
      {:noreply, update_agent_files(socket, &(&1 ++ [AgentFiles.blank_draft()]))}
    else
      {:noreply, put_flash(socket, :error, "At most #{AgentFiles.max_files()} reference files.")}
    end
  end

  def handle_event("agent_cfg_remove_file", %{"index" => index}, socket) do
    case parse_index(index) do
      nil ->
        {:noreply, socket}

      index ->
        {:noreply, update_agent_files(socket, &List.delete_at(&1, index))}
    end
  end

  def handle_event("agent_cfg_save", _params, socket) do
    {:noreply, save_agent_config(socket)}
  end

  # Enter in one of the section's text fields submits its form; saving is the
  # least surprising outcome on the canvas.
  def handle_event("agent_cfg_form_submit", _params, socket) do
    {:noreply, save_agent_config(socket)}
  end

  def handle_event("agent_cfg_reset", _params, socket) do
    case Canvas.reset_agent_config(socket.assigns.canvas) do
      {:ok, canvas} ->
        {:noreply,
         socket
         |> assign(:canvas, canvas)
         |> reload_agent_config()
         |> put_flash(:success, "Agent settings reset to the template")}

      {:error, :no_template} ->
        {:noreply, put_flash(socket, :error, "The source template is no longer available")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not reset the agent settings")}
    end
  end

  def handle_event("agent_select_role", %{"role" => role}, socket) do
    session = socket.assigns.agent_session

    cond do
      is_nil(session) ->
        {:noreply, assign(socket, :agent_role, role)}

      session.message_count in [nil, 0] ->
        case Psc.Agent.set_session_role(session, role) do
          {:ok, session} ->
            {:noreply, assign(socket, agent_session: session, agent_role: role)}

          {:error, _reason} ->
            {:noreply, socket}
        end

      true ->
        {:noreply, put_flash(socket, :error, "Start a new chat to change the role.")}
    end
  end

  @impl true
  def handle_event("agent_new", _params, socket) do
    socket = stop_running_turn(socket)
    user = socket.assigns.current_scope.user
    # The saved config, not the Info tab's unsaved draft, decides what a new
    # chat starts with.
    default_role = AgentConfig.normalize(socket.assigns.canvas.agent_config)["default_role"]

    case Psc.Agent.create_session(user.id, %{canvas_id: socket.assigns.canvas_id}) do
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
         |> assign(:agent_role, default_role)
         |> assign(:agent_composer, to_form(%{"content" => ""}, as: :message))
         |> assign(:agent_list_open, false)
         |> assign(:agent_connection_list_open, false)
         |> assign_agent_connections()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not start a chat.")}
    end
  end

  def handle_event("agent_send", %{"message" => %{"content" => content}}, socket) do
    content = String.trim(content)
    session = socket.assigns.agent_session

    # Settings live in another tab - or on another device - and this socket's
    # user was loaded at mount. Re-read it *before* gating: a key or model saved
    # since then must take effect without reloading the canvas, and a user who
    # already saved a key must never be told to add it again.
    socket = refresh_agent_scope(socket)
    scope = socket.assigns.current_scope

    cond do
      content == "" ->
        {:noreply, socket}

      is_nil(session) ->
        {:noreply, put_flash(socket, :error, "Start a chat first.")}

      socket.assigns.agent_missing == :connection ->
        {:noreply, put_flash(socket, :error, "Add a connection in settings first.")}

      socket.assigns.agent_turn_pid ->
        {:noreply, put_flash(socket, :error, "Wait for the current answer to finish.")}

      true ->
        # Subscribe before the turn starts: the first deltas can arrive within
        # milliseconds, and a late subscription loses them.
        socket = subscribe_agent(socket, session)
        connection = Psc.Agent.Connections.for_session(session, scope.user)
        config = Psc.Agent.Connections.turn_config(session, scope.user)

        profile =
          Psc.Agent.Profile.for_canvas(
            socket.assigns.canvas,
            session.role || socket.assigns.agent_role
          )

        with {:ok, user_message} <-
               Psc.Agent.append_user_message(session, content, profile: profile),
             %{} = session <-
               Psc.Agent.get_session(session.id, session.user_id) || {:error, :not_found},
             {:ok, session} <- pin_connection(session, connection),
             {:ok, assistant} <-
               Psc.Agent.start_assistant_message(session, model: config.model) do
          case Psc.Agent.Turn.start(session, assistant, scope, config) do
            {:ok, pid} ->
              {:noreply,
               socket
               |> assign(:agent_session, Psc.Agent.get_session(session.id, session.user_id))
               |> assign(
                 :agent_messages,
                 socket.assigns.agent_messages ++ [user_message, assistant]
               )
               |> assign(:agent_turn_pid, pid)
               |> assign(:agent_composer, to_form(%{"content" => ""}, as: :message))
               |> assign_agent_connections()}

            {:error, reason} ->
              Psc.Agent.fail_message(assistant, reason)

              {:noreply,
               put_flash(socket, :error, "Could not start the answer. Please try again.")}
          end
        else
          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, "Could not start the answer. Please try again.")}
        end
    end
  end

  # A suggested prompt fills the composer rather than sending itself, so the
  # user can edit it before spending a model call.
  def handle_event("agent_suggest", %{"prompt" => prompt}, socket) when is_binary(prompt) do
    {:noreply, assign(socket, :agent_composer, to_form(%{"content" => prompt}, as: :message))}
  end

  def handle_event("agent_refresh", _params, socket) do
    # Settings can be saved in another tab or on another device. While the
    # panel is still waiting on a key or a model, re-read the account so saving
    # settings enables the composer without a page reload.
    if socket.assigns.agent_enabled? do
      {:noreply, socket}
    else
      {:noreply, refresh_agent_scope(socket)}
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
        # Stop before copying: an in-flight message would otherwise be copied
        # as `:streaming` into a chat that has no turn behind it.
        socket = stop_running_turn(socket)

        case Psc.Agent.duplicate_session(session) do
          {:ok, copy} ->
            {:noreply,
             socket
             |> subscribe_agent(copy)
             |> assign(:agent_session, copy)
             |> assign(:agent_messages, Psc.Agent.list_messages(copy))
             |> assign(
               :agent_sessions,
               Psc.Agent.list_sessions_for_canvas(copy.canvas_id, user.id)
             )
             |> assign(:agent_menu_session, nil)}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Could not duplicate the chat.")}
        end
    end
  end

  def handle_event("agent_delete", %{"session" => session_id}, socket) do
    user = socket.assigns.current_scope.user

    case Psc.Agent.get_session(session_id, user.id) do
      nil ->
        {:noreply, socket}

      session ->
        case Psc.Agent.delete_session(session) do
          {:ok, _} ->
            sessions = Psc.Agent.list_sessions_for_canvas(session.canvas_id, user.id)

            deleted_current? =
              socket.assigns.agent_session && socket.assigns.agent_session.id == session.id

            socket =
              if deleted_current? do
                socket = stop_running_turn(socket)

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
             |> assign(:agent_menu_session, nil)}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Could not delete the chat.")}
        end
    end
  end

  def handle_event("agent_close_lists", _params, socket) do
    {:noreply,
     assign(socket,
       agent_list_open: false,
       agent_menu_session: nil,
       agent_connection_list_open: false
     )}
  end

  def handle_event("agent_toggle_list", _params, socket) do
    {:noreply,
     assign(socket,
       agent_list_open: not socket.assigns.agent_list_open,
       agent_connection_list_open: false
     )}
  end

  def handle_event("agent_toggle_connections", _params, socket) do
    {:noreply,
     assign(socket,
       agent_connection_list_open: not socket.assigns.agent_connection_list_open,
       agent_list_open: false,
       agent_menu_session: nil
     )}
  end

  def handle_event("agent_select_connection", %{"connection" => id}, socket) do
    user = socket.assigns.current_scope.user

    cond do
      socket.assigns.agent_turn_pid ->
        {:noreply, put_flash(socket, :error, "Wait for the current answer to finish.")}

      is_nil(socket.assigns.agent_session) ->
        {:noreply, assign(socket, :agent_connection_list_open, false)}

      true ->
        case Psc.Agent.Connections.get(id, user.id) do
          nil ->
            {:noreply, put_flash(socket, :error, "That connection is no longer available.")}

          connection ->
            {:ok, session} =
              Psc.Agent.set_session_connection(socket.assigns.agent_session, connection)

            {:noreply,
             socket
             |> assign(:agent_session, session)
             |> assign(:agent_connection_list_open, false)
             |> assign_agent_connections()}
        end
    end
  end

  def handle_event("agent_select", %{"session" => session_id}, socket) do
    user = socket.assigns.current_scope.user

    case Psc.Agent.get_session(session_id, user.id) do
      nil ->
        {:noreply, put_flash(socket, :error, "That chat is no longer available.")}

      session ->
        Psc.Agent.cancel_stale_streaming(session)

        same_session? =
          socket.assigns.agent_session && socket.assigns.agent_session.id == session.id

        socket = if same_session?, do: socket, else: stop_running_turn(socket)

        messages =
          if same_session?,
            do: socket.assigns.agent_messages,
            else: Psc.Agent.list_messages(session)

        {:noreply,
         socket
         |> subscribe_agent(session)
         |> assign(:agent_session, session)
         |> assign(:agent_messages, messages)
         |> assign(:agent_list_open, false)
         |> assign(:agent_connection_list_open, false)
         |> assign_agent_connections()}
    end
  end

  def handle_event("agent_stop", _params, socket) do
    {:noreply, stop_running_turn(socket)}
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
          case Notes.delete_note(note) do
            {:ok, _note} ->
              {:noreply,
               socket
               |> assign(:note, nil)
               |> assign(:note_content, "")
               |> assign(:note_html, "")
               |> assign(:note_last_saved_content, "")
               |> reload_notes()
               |> push_patch(to: ~p"/canvas/#{socket.assigns.canvas_id}?tab=notes", replace: true)
               |> put_flash(:success, "Note deleted")}

            {:error, _changeset} ->
              {:noreply, put_flash(socket, :error, "Could not delete the note")}
          end

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
        case Notes.update_note(note, %{title: title}) do
          {:ok, updated} ->
            {:noreply,
             socket
             |> assign(:note, updated)
             |> reload_notes()}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Could not rename the note.")}
        end
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
          Notes.apply_operation(
            note.id,
            socket.assigns.user_id,
            operation,
            socket.assigns.client_id
          )
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
         |> assign(:note_html, NotesPanel.render_html(new_content))
         |> assign(:note_idle_timer_ref, note_idle_timer_ref)
         |> assign(:note_save_state, :unsaved)}
    end
  end

  @impl true
  def handle_event("render_note", %{"content" => content}, socket) do
    {:noreply,
     push_event(socket, "note_rendered", %{
       content: content,
       html: NotesPanel.render_html(content)
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

  ## Structure editing

  # Every structure event is available to anyone the canvas is shared with: a
  # canvas's access rule is the only gate. The operation is broadcast like any
  # other edit, so every open client applies it and the grid stays in step.

  @impl true
  def handle_event("toggle_structure", _params, socket) do
    {:noreply,
     socket
     |> assign(:edit_structure?, not socket.assigns.edit_structure?)
     |> assign(:structure_accent_picker, nil)
     |> assign(:structure_colors_picker, nil)
     |> assign(:structure_remove_confirm, nil)}
  end

  def handle_event("add_row", _params, socket) do
    {id, index} = next_structure_id("r", Map.get(socket.assigns.cells, "rows", []))

    {:noreply,
     process_operation(socket, %{"type" => "add_row", "id" => id, "label" => "Row #{index}"})}
  end

  def handle_event("add_column", _params, socket) do
    {id, index} = next_structure_id("c", Map.get(socket.assigns.cells, "columns", []))

    {:noreply,
     process_operation(
       socket,
       %{"type" => "add_column", "id" => id, "label" => "Column #{index}"}
     )}
  end

  def handle_event("update_row_label", %{"structure_id" => id, "label" => label}, socket) do
    {:noreply,
     process_operation(socket, %{"type" => "update_row_label", "id" => id, "label" => label})}
  end

  def handle_event("update_column_label", %{"structure_id" => id, "label" => label}, socket) do
    {:noreply,
     process_operation(socket, %{"type" => "update_column_label", "id" => id, "label" => label})}
  end

  def handle_event("set_row_accent", %{"id" => id, "accent" => accent}, socket) do
    {:noreply,
     socket
     |> assign(:structure_accent_picker, nil)
     |> process_operation(%{
       "type" => "set_row_accent",
       "id" => id,
       "accent" => normalize_token(accent)
     })}
  end

  def handle_event("set_column_accent", %{"id" => id, "accent" => accent}, socket) do
    {:noreply,
     socket
     |> assign(:structure_accent_picker, nil)
     |> process_operation(%{
       "type" => "set_column_accent",
       "id" => id,
       "accent" => normalize_token(accent)
     })}
  end

  def handle_event("toggle_structure_accent", %{"group" => group, "id" => id}, socket) do
    key =
      case group do
        "row" -> {:row, id}
        "card" -> {:card, id}
        _other -> {:column, id}
      end

    picker = if socket.assigns.structure_accent_picker == key, do: nil, else: key

    {:noreply,
     assign(socket,
       structure_accent_picker: picker,
       structure_colors_picker: nil
     )}
  end

  def handle_event("toggle_cell_colors", %{"cell_key" => key}, socket) do
    picker = if socket.assigns.structure_colors_picker == key, do: nil, else: key

    {:noreply,
     assign(socket,
       structure_colors_picker: picker,
       structure_accent_picker: nil
     )}
  end

  # A click outside the pickers closes them (the client hook reports it), so
  # the panel can be dismissed without finding its trigger again.
  def handle_event("dismiss_color_pickers", _params, socket) do
    {:noreply,
     assign(socket,
       structure_colors_picker: nil,
       structure_accent_picker: nil
     )}
  end

  # Choosing either colour keeps the panel open: the outline and the
  # background are usually set together.
  def handle_event("set_cell_background", %{"cell_key" => key} = params, socket) do
    {:noreply,
     process_operation(socket, %{
       "type" => "set_cell_background",
       "cell_key" => key,
       "background" => normalize_token(params["background"])
     })}
  end

  def handle_event("request_remove_row", %{"id" => id}, socket) do
    request_structure_remove(socket, "row", id)
  end

  def handle_event("request_remove_column", %{"id" => id}, socket) do
    request_structure_remove(socket, "column", id)
  end

  def handle_event("confirm_remove_structure", _params, socket) do
    {socket, operation} =
      case socket.assigns.structure_remove_confirm do
        %{"type" => "row", "id" => id} ->
          {socket, %{"type" => "remove_row", "id" => id}}

        %{"type" => "column", "id" => id} ->
          {socket, %{"type" => "remove_column", "id" => id}}

        %{"type" => "card", "cell_key" => key} ->
          {socket, %{"type" => "remove_card", "cell_key" => key}}

        _other ->
          {socket, nil}
      end

    socket = assign(socket, :structure_remove_confirm, nil)

    if operation do
      {:noreply, process_operation(socket, operation)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("dismiss_remove_structure", _params, socket) do
    {:noreply, assign(socket, :structure_remove_confirm, nil)}
  end

  ## Free-form cells (bento cards and image-board cells)

  def handle_event("add_card", _params, socket) do
    cells = socket.assigns.cells

    cond do
      Structure.image?(cells) ->
        key = next_cell_key(cells, "cell")
        count = length(Structure.cards(cells)) + 1

        {:noreply,
         process_operation(socket, %{
           "type" => "add_card",
           "cell_key" => key,
           "label" => "Card #{count}"
         })}

      Structure.bento?(cells) ->
        key = next_cell_key(cells, "card")
        count = length(Structure.cards(cells)) + 1

        {:noreply,
         process_operation(socket, %{
           "type" => "add_card",
           "cell_key" => key,
           "label" => "Card #{count}"
         })}

      true ->
        {:noreply, socket}
    end
  end

  # A bare text label on an image board. It is an ordinary cell from the start:
  # one `add_card` carries the kind, so adding it is a single event.
  def handle_event("add_text", _params, socket) do
    if Structure.image?(socket.assigns.cells) do
      key = next_cell_key(socket.assigns.cells, "text")
      count = length(Structure.cards(socket.assigns.cells)) + 1

      {:noreply,
       process_operation(socket, %{
         "type" => "add_card",
         "cell_key" => key,
         "label" => "Text #{count}",
         "kind" => "text"
       })}
    else
      {:noreply, socket}
    end
  end

  # The backdrop is part of the canvas, so changing it is an operation like any
  # other and every open client sees the new picture.
  def handle_event("set_backdrop", params, socket) when is_map(params) do
    if Structure.image?(socket.assigns.cells) do
      {:noreply,
       process_operation(socket, %{
         "type" => "set_backdrop",
         "backdrop" => ImageFrame.backdrop_attrs(params)
       })}
    else
      {:noreply, socket}
    end
  end

  def handle_event("set_cell_kind", %{"cell_key" => key, "kind" => kind}, socket) do
    {:noreply,
     process_operation(socket, %{"type" => "set_cell_kind", "cell_key" => key, "kind" => kind})}
  end

  def handle_event("request_remove_card", %{"cell_key" => key}, socket) do
    case Map.get(Structure.cells(socket.assigns.cells), key) do
      nil ->
        {:noreply, socket}

      cell ->
        if cell_has_content?(cell) do
          {:noreply,
           assign(socket, :structure_remove_confirm, %{
             "type" => if(Structure.image?(socket.assigns.cells), do: "cell", else: "card"),
             "cell_key" => key,
             "label" => cell["label"] || key
           })}
        else
          {:noreply, process_operation(socket, %{"type" => "remove_card", "cell_key" => key})}
        end
    end
  end

  # The board's own grid. A value outside the allowed range is ignored rather
  # than clamped, so typing "1" on the way to "12" does not resize the board.
  def handle_event("set_bento_columns", %{"value" => value}, socket) do
    case parse_size(value) do
      count when is_integer(count) ->
        if count in Structure.column_range() do
          {:noreply,
           process_operation(socket, %{"type" => "set_bento_columns", "columns" => count})}
        else
          {:noreply, socket}
        end

      _other ->
        {:noreply, socket}
    end
  end

  def handle_event("set_bento_rows", %{"value" => value}, socket) do
    case parse_size(value) do
      count when is_integer(count) ->
        if count in Structure.row_range() do
          {:noreply, process_operation(socket, %{"type" => "set_bento_rows", "rows" => count})}
        else
          {:noreply, socket}
        end

      _other ->
        {:noreply, socket}
    end
  end

  def handle_event("set_card_accent", %{"cell_key" => key, "accent" => accent}, socket) do
    {:noreply,
     process_operation(socket, %{
       "type" => "set_card_accent",
       "cell_key" => key,
       "accent" => normalize_token(accent)
     })}
  end

  # One operation per completed gesture: the drag hook pushes the final cell,
  # and the arrow keys push one step at a time.
  def handle_event("move_card", %{"cell_key" => key} = params, socket) do
    with x when is_number(x) <- to_number(params["x"]),
         y when is_number(y) <- to_number(params["y"]) do
      {:noreply,
       process_operation(socket, %{"type" => "move_card", "cell_key" => key, "x" => x, "y" => y})}
    else
      _other -> {:noreply, socket}
    end
  end

  def handle_event("resize_card", %{"cell_key" => key} = params, socket) do
    with w when is_number(w) <- to_number(params["w"]),
         h when is_number(h) <- to_number(params["h"]) do
      {:noreply,
       process_operation(socket, %{
         "type" => "resize_card",
         "cell_key" => key,
         "w" => w,
         "h" => h
       })}
    else
      _other -> {:noreply, socket}
    end
  end

  # Arrow keys on the card's drag grip move it by one unit; holding shift
  # resizes it. The grip is a button, so the handler never competes with an
  # arrow key pressed inside a Markdown editor.
  def handle_event("nudge_card", %{"key" => key, "cell_key" => cell_key} = params, socket) do
    resize? = params["shiftKey"] == true

    case nudge_delta(key) do
      nil -> {:noreply, socket}
      {dx, dy} -> {:noreply, nudge_card(socket, cell_key, dx, dy, resize?)}
    end
  end

  def handle_event("update_cell_label", %{"cell_key" => cell_key, "label" => label}, socket) do
    {:noreply,
     process_operation(socket, %{
       "type" => "update_cell_label",
       "cell_key" => cell_key,
       "label" => label
     })}
  end

  def handle_event("add_cell_field", %{"cell_key" => cell_key, "field" => field}, socket) do
    field = String.trim(field)

    if field != "" and field not in Psc.Canvas.UnstrCanvasCRDT.reserved_cell_keys() do
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
    {:noreply,
     process_operation(socket, %{
       "type" => "remove_cell_field",
       "cell_key" => cell_key,
       "field" => field
     })}
  end

  def handle_event(
        "update_cell_field_title",
        %{"cell_key" => cell_key, "field" => field, "title" => title},
        socket
      ) do
    {:noreply,
     process_operation(socket, %{
       "type" => "update_cell_field_title",
       "cell_key" => cell_key,
       "field" => field,
       "title" => title
     })}
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

  # The next free "<prefix>N" key, scanning the keys that are already there so
  # a removal never makes the next cell collide with a survivor.
  defp next_cell_key(cells, prefix) do
    taken =
      for key <- Structure.cell_keys(cells),
          parts = Regex.run(~r/^#{prefix}(\d+)$/, key),
          n <- tl(parts) do
        String.to_integer(n)
      end

    "#{prefix}#{Enum.max([0 | taken]) + 1}"
  end

  defp nudge_delta("ArrowLeft"), do: {-1, 0}
  defp nudge_delta("ArrowRight"), do: {1, 0}
  defp nudge_delta("ArrowUp"), do: {0, -1}
  defp nudge_delta("ArrowDown"), do: {0, 1}
  defp nudge_delta(_key), do: nil

  defp nudge_card(socket, key, dx, dy, resize?) do
    case Structure.card(socket.assigns.cells, key) do
      nil ->
        socket

      card ->
        # Position and size share one step: half a grid unit on a bento, half a
        # percent of the picture on an image board.
        step =
          if Structure.image?(socket.assigns.cells),
            do: Structure.image_step(),
            else: Structure.min_size()

        operation =
          if resize? do
            %{
              "type" => "resize_card",
              "cell_key" => key,
              "w" => card.w + dx * step,
              "h" => card.h + dy * step
            }
          else
            %{
              "type" => "move_card",
              "cell_key" => key,
              "x" => card.x + dx * step,
              "y" => card.y + dy * step
            }
          end

        process_operation(socket, operation)
    end
  end

  defp parse_size(value) do
    case Integer.parse(to_string(value)) do
      {int, ""} -> int
      _other -> nil
    end
  end

  # A coordinate keeps its half: 6.5 columns must not become 6.
  defp to_number(value) when is_integer(value) or is_float(value), do: value

  defp to_number(value) when is_binary(value) do
    case Float.parse(value) do
      {number, _rest} -> number
      :error -> nil
    end
  end

  defp to_number(_other), do: nil

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

  # Re-read the signed-in account and everything the agent tab derives from it.
  # The scope is a snapshot from mount time, so a connection saved in settings
  # since then is invisible until this runs.
  defp refresh_agent_scope(socket) do
    scope = fresh_scope(socket.assigns.current_scope)

    socket
    |> assign(:current_scope, scope)
    |> assign(:agent_enabled?, Psc.Agent.enabled?(scope.user))
    |> assign(:agent_missing, Psc.Agent.missing_configuration(scope.user))
    |> assign_agent_connections()
  end

  # The picker's data: every connection of the user, and the one this chat uses
  # next (its own, else the user's default).
  defp assign_agent_connections(socket) do
    user = socket.assigns.current_scope.user
    connections = Psc.Agent.Connections.summaries(user.id)

    active =
      case Psc.Agent.Connections.for_session(socket.assigns.agent_session, user) do
        nil ->
          nil

        connection ->
          Enum.find(connections, &(&1.id == connection.id)) ||
            Psc.Agent.Connection.summary(connection)
      end

    socket
    |> assign(:agent_connections, connections)
    |> assign(:agent_connection, active)
  end

  # A chat keeps the connection its first turn ran on; opening an old chat with
  # the same model must not rewrite the row on every send.
  defp pin_connection(session, nil), do: {:ok, session}

  defp pin_connection(session, connection) do
    Psc.Agent.Connections.mark_used(connection)
    Psc.Agent.set_session_connection(session, connection)
  end

  defp load_agent(socket) do
    user = socket.assigns.current_scope.user
    enabled? = Psc.Agent.enabled?(user)
    missing = Psc.Agent.missing_configuration(user)
    sessions = Psc.Agent.list_sessions_for_canvas(socket.assigns.canvas_id, user.id)

    socket =
      case Psc.Agent.latest_session(socket.assigns.canvas_id, user.id) do
        nil ->
          socket
          |> assign(:agent_session, nil)
          |> assign(:agent_sessions, sessions)
          |> assign(:agent_messages, [])

        session ->
          Psc.Agent.cancel_stale_streaming(session)

          # Deltas are broadcast, not persisted, until the turn completes. Keep
          # the transcript already on screen when the same session is reopened by
          # a tab switch; reloading from the database would drop them.
          messages =
            if socket.assigns.agent_session && socket.assigns.agent_session.id == session.id do
              socket.assigns.agent_messages
            else
              Psc.Agent.list_messages(session)
            end

          socket
          |> subscribe_agent(session)
          |> assign(:agent_session, session)
          |> assign(:agent_sessions, sessions)
          |> assign(:agent_messages, messages)
      end

    config = AgentConfig.normalize(socket.assigns.canvas.agent_config)
    roles = config["roles"] || []

    role =
      case socket.assigns[:agent_session] do
        %{role: role} when is_binary(role) ->
          if Enum.any?(roles, &(&1["key"] == role)), do: role, else: config["default_role"]

        _other ->
          config["default_role"]
      end

    socket
    |> assign(:agent_enabled?, enabled?)
    |> assign(:agent_missing, missing)
    |> assign(:agent_roles, roles)
    |> assign(:agent_role, role)
    |> assign_agent_connections()
  end

  # Re-reads the saved agent setup after a save or a collaborator's broadcast.
  # The draft is replaced on purpose: the database is the source of truth.
  defp reload_agent_config(socket) do
    canvas =
      Psc.Canvas.get_unstr_canvas_with_author(socket.assigns.canvas.id) || socket.assigns.canvas

    config = AgentConfig.normalize(canvas.agent_config)
    source = Canvas.agent_source_template(canvas)

    role =
      case socket.assigns[:agent_session] do
        %{role: role} when is_binary(role) -> role
        _other -> config["default_role"]
      end

    socket
    |> assign(:canvas, canvas)
    |> assign(:agent_config, config)
    |> assign(:agent_files, AgentFiles.drafts(:canvas, canvas.id) |> AgentUploads.with_html())
    |> assign(:agent_config_dirty?, false)
    |> assign(:agent_source_template, source)
    |> assign(:agent_config_drift?, Canvas.agent_config_drift?(canvas, source))
    |> assign(:agent_roles, config["roles"] || [])
    |> assign(:agent_role, role)
  end

  defp save_agent_config(socket) do
    case Canvas.update_agent_config(
           socket.assigns.canvas,
           socket.assigns.agent_config,
           socket.assigns.agent_files
         ) do
      {:ok, canvas} ->
        socket
        |> assign(:canvas, canvas)
        |> reload_agent_config()
        |> put_flash(:success, "Agent settings saved")

      {:error, _reason} ->
        put_flash(socket, :error, "Could not save the agent settings")
    end
  end

  defp update_agent_config(socket, fun) do
    socket
    |> assign(:agent_config, fun.(socket.assigns.agent_config))
    |> assign(:agent_config_dirty?, true)
  end

  defp update_agent_files(socket, fun) do
    socket
    |> assign(:agent_files, fun.(socket.assigns.agent_files))
    |> assign(:agent_config_dirty?, true)
  end

  defp parse_index(value) when is_integer(value), do: value

  defp parse_index(value) when is_binary(value) do
    case Integer.parse(value) do
      {index, ""} when index >= 0 -> index
      _other -> nil
    end
  end

  defp parse_index(_value), do: nil

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
  defp update_agent_message(socket, id, fun) do
    messages =
      Enum.map(socket.assigns.agent_messages, fn message ->
        if message.id == id, do: fun.(message), else: message
      end)

    assign(socket, :agent_messages, messages)
  end

  # A turn belongs to the chat that started it. Switching chats (or stopping)
  # must terminate the task, cancel the streaming message and clear the phase;
  # otherwise the pid stays set, the composer stays disabled and the task keeps
  # consuming tokens into a topic nobody reads.
  defp stop_running_turn(socket) do
    if pid = socket.assigns.agent_turn_pid do
      Task.Supervisor.terminate_child(Psc.Agent.TurnSupervisor, pid)
    end

    socket =
      case Enum.find(socket.assigns.agent_messages, &(&1.status == :streaming)) do
        nil -> socket
        message -> update_agent_message(socket, message.id, &cancel_message/1)
      end

    assign(socket, agent_turn_pid: nil, agent_phase: nil)
  end

  # `Psc.Agent.cancel_message/1` returns a result tuple; the transcript holds
  # message structs.
  defp cancel_message(message) do
    case Psc.Agent.cancel_message(message) do
      {:ok, updated} -> updated
      {:error, _changeset} -> %{message | status: :cancelled}
    end
  end

  defp normalize_token(""), do: nil
  defp normalize_token(token), do: token

  @impl true
  def handle_params(params, _url, socket) do
    tab = Tabs.find(params["tab"]) |> elem(0)

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

  # The notes of the canvas, most recently touched first. The snippet is
  # derived once here instead of on every render.
  defp reload_notes(socket) do
    assign(socket, :notes, NotesPanel.with_snippets(Notes.list_notes(socket.assigns.canvas_id)))
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
        content = Notes.get_note_content(note.id)

        socket
        |> leave_note()
        |> assign(:note, note)
        |> assign(:note_content, content)
        |> assign(:note_html, NotesPanel.render_html(content))
        |> assign(:note_last_saved_content, content)
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
            |> assign(:notes, NotesPanel.with_snippets([note]))
            |> assign(:note, note)
            |> assign(:note_content, "")
            |> assign(:note_html, "")
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
    |> assign(:note_html, "")
    |> assign(:note_last_saved_content, "")
    |> assign(:note_save_state, :saved)
    |> assign(:note_save_stats, @initial_save_stats)
  end

  defp load_note_by_id(socket, note_id) do
    case Notes.get_note(note_id) do
      %{canvas_id: canvas_id} = note when canvas_id == socket.assigns.canvas_id ->
        content = Notes.get_note_content(note.id)

        socket
        |> leave_note()
        |> assign(:note, note)
        |> assign(:note_content, content)
        |> assign(:note_html, NotesPanel.render_html(content))
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
        |> assign(:note_html, "")
        |> assign(:note_last_saved_content, "")
        |> assign(:note_save_state, :saved)
        |> assign(:note_save_stats, @initial_save_stats)
    end
  end

  # Stop listening to the note that was open, so a stale topic cannot deliver
  # operations for a note that is no longer on screen. Flush first: the idle
  # timer is about to be cancelled, and the note's events would otherwise stay
  # unfolded until it was edited and saved again.
  defp leave_note(socket) do
    socket = flush_note(socket)

    if socket.assigns[:note_topic] do
      Phoenix.PubSub.unsubscribe(Psc.PubSub, socket.assigns.note_topic)
      Presence.untrack(self(), socket.assigns.note_topic, socket.assigns.user_id)
    end

    if socket.assigns[:note_idle_timer_ref] do
      Process.cancel_timer(socket.assigns.note_idle_timer_ref)
    end

    assign(socket, note_topic: nil, note_presence: %{}, note_idle_timer_ref: nil)
  end

  defp flush_note(socket) do
    case socket.assigns[:note] do
      nil ->
        socket

      note ->
        if socket.assigns.note_content != socket.assigns.note_last_saved_content do
          save_note_content(socket, note)
        else
          socket
        end
    end
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
        html: NotesPanel.render_html(socket.assigns.note_content),
        from_user_id: -1
      })
    else
      socket
    end
  end

  # A remote operation on the open note: fold it in and hand the result to the
  # editor, whose textarea is not re-rendered (`phx-update="ignore"`).
  #
  # The rendered Markdown travels with it. The editor usually sits in its
  # preview, and the preview is only re-asked for on blur, so a reader would
  # otherwise see nothing change until they clicked into the note.
  defp apply_remote_note_operation(socket, user_id, operation) do
    if socket.assigns.note do
      new_content = Psc.Text.apply_operation(operation, socket.assigns.note_content)
      html = NotesPanel.render_html(new_content)

      {:noreply,
       socket
       |> assign(:note_content, new_content)
       |> assign(:note_html, html)
       |> push_event("note_content_updated", %{
         content: new_content,
         html: html,
         from_user_id: user_id
       })}
    else
      {:noreply, socket}
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

  def handle_info({:agent_config_updated, canvas_id}, socket) do
    cond do
      socket.assigns.canvas_id != canvas_id ->
        {:noreply, socket}

      socket.assigns.agent_config_dirty? ->
        {:noreply,
         put_flash(
           socket,
           :info,
           "Agent settings were updated in another tab. Save yours to overwrite them."
         )}

      true ->
        {:noreply, reload_agent_config(socket)}
    end
  end

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
  def handle_info(:note_idle_save, socket) do
    case socket.assigns.note do
      nil ->
        {:noreply, assign(socket, note_idle_timer_ref: nil)}

      note ->
        if socket.assigns.note_content != socket.assigns.note_last_saved_content do
          socket =
            socket
            |> assign(:note_save_state, :saving)
            |> save_note_content(note)
            |> assign(:note_idle_timer_ref, nil)

          socket =
            cond do
              socket.assigns.note_save_state != :unsaved ->
                # The list shows a snippet of the note's content, so it has to
                # be re-read now that the content has been folded.
                reload_notes(socket)

              Notes.get_note(note.id) ->
                # The note still exists: retry shortly instead of waiting for
                # the user to type again.
                ref = Process.send_after(self(), :note_idle_save, @idle_save_interval)
                assign(socket, :note_idle_timer_ref, ref)

              true ->
                socket
            end

          {:noreply, socket}
        else
          {:noreply, assign(socket, note_idle_timer_ref: nil)}
        end
    end
  end

  @impl true
  def handle_info({:note_operation, user_id, client_id, operation, _seq}, socket) do
    # The broadcast names the client that wrote it, not just the user, so this
    # view ignores its own echo and nothing else: another tab of the same user
    # is a different client and must still see the edit.
    if client_id != socket.assigns.client_id do
      apply_remote_note_operation(socket, user_id, operation)
    else
      {:noreply, socket}
    end
  end

  # An operation applied straight through the context (no client id): there is
  # no client to compare, so the user is the only thing to go on.
  def handle_info({:note_operation, user_id, operation, _seq}, socket) do
    if user_id != socket.assigns.user_id do
      apply_remote_note_operation(socket, user_id, operation)
    else
      {:noreply, socket}
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

      {:noreply,
       socket
       |> assign(:cells, cells)
       |> assign(:c_name, c_name)
       |> assign(:c_desc, c_desc)}
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

    socket
  end

  defp save_note_content(socket, note) do
    socket =
      Save.commit(socket, :note, fn ->
        Notes.save_content_to_db(note.id, socket.assigns.note_content)
      end)

    if socket.assigns.note_save_state == :unsaved do
      Logger.error("[UnstrCanvasLive] note save failed: note_id=#{note.id}")
    end

    socket
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

  defp structure_remove_confirm(confirm, :type), do: confirm["type"]
  defp structure_remove_confirm(confirm, :label), do: confirm["label"] || ""

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :status, status_source(assigns))

    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      header_title="Canvas Editor"
      fill_height
      main_class="px-2 pt-2 sm:px-6 sm:pt-3 lg:px-8 lg:pt-3"
      container_class="mx-auto flex min-h-0 w-full max-w-none flex-1 flex-col gap-3"
    >
      <:header_nav>
        <Tabs.strip tabs={@tabs} active_tab={@active_tab} />
      </:header_nav>

      <:header_actions>
        <Header.actions
          presence={@presence}
          status={@status}
          can_share?={@canvas.author_id == @user_id}
        />
      </:header_actions>

      <div
        id="canvas-workspace"
        phx-hook="DismissPicker"
        data-picker-open={
          to_string(not is_nil(@structure_colors_picker) or not is_nil(@structure_accent_picker))
        }
        class="flex min-h-0 w-full flex-1 flex-col gap-2 pb-[calc(var(--canvas-tab-bar-height)+var(--canvas-tab-bar-gap)+env(safe-area-inset-bottom))] lg:pb-2"
      >
        <Header.header
          presence={@presence}
          status={@status}
          can_share?={@canvas.author_id == @user_id}
          controls?={@active_tab != "editor" and (@active_tab != "agent" or is_nil(@agent_session))}
        />
        <Header.share_dialog
          canvas={@canvas}
          share_open={@share_open}
          can_share?={@canvas.author_id == @user_id}
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
          <UIDialog.dialog_content open class="sm:max-w-md">
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
            class={
              [
                "flex min-h-0 w-full flex-1 flex-col",
                # A bento or image board grows with its content on a desktop
                # (the page scrolls); the table keeps filling the viewport. A
                # phone keeps the inner scroll for all three.
                Structure.freeform?(@cells) && "lg:flex-none",
                @active_tab != "editor" && "hidden"
              ]
            }
          >
            <%= cond do %>
              <% Structure.image?(@cells) -> %>
                <ImageCanvas.board
                  cells={@cells}
                  c_name={@c_name}
                  edit_structure?={@edit_structure?}
                  structure_accent_picker={@structure_accent_picker}
                  colors_picker={@structure_colors_picker}
                  presence={@presence}
                  status={@status}
                  can_share?={@canvas.author_id == @user_id}
                  status_row?={@active_tab == "editor"}
                  focus_cell={@focus_cell}
                  user_id={@user_id}
                />
              <% Structure.bento?(@cells) -> %>
                <Bento.board
                  cells={@cells}
                  c_name={@c_name}
                  edit_structure?={@edit_structure?}
                  structure_accent_picker={@structure_accent_picker}
                  colors_picker={@structure_colors_picker}
                  presence={@presence}
                  status={@status}
                  can_share?={@canvas.author_id == @user_id}
                  status_row?={@active_tab == "editor"}
                  focus_cell={@focus_cell}
                  user_id={@user_id}
                />
              <% true -> %>
                <Grid.grid
                  cells={@cells}
                  c_name={@c_name}
                  edit_structure?={@edit_structure?}
                  structure_accent_picker={@structure_accent_picker}
                  colors_picker={@structure_colors_picker}
                  presence={@presence}
                  status={@status}
                  can_share?={@canvas.author_id == @user_id}
                  status_row?={@active_tab == "editor"}
                  focus_cell={@focus_cell}
                  user_id={@user_id}
                />
            <% end %>
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
            role="tabpanel"
            aria-labelledby="canvas-tab-agent"
            phx-window-focus="agent_refresh"
            class={[
              "flex min-h-0 w-full flex-1 flex-col",
              @active_tab != "agent" && "hidden"
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
              presence={@presence}
              status={if @active_tab == "agent", do: @status, else: nil}
              can_share?={@canvas.author_id == @user_id}
            />
          </div>

          <%!-- The Info view scrolls inside its panel, like Notes and Agent. Its
          sections are taller than the phone viewport, and a panel that merely
          overflowed the workspace painted its last rows under the bottom bar:
          the workspace's reservation sits inside the box the content spills
          out of. --%>
          <div
            id="canvas-panel-info"
            role="tabpanel"
            aria-labelledby="canvas-tab-info"
            class={[
              "flex min-h-0 w-full flex-1 flex-col overflow-y-auto",
              @active_tab != "info" && "hidden"
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

          <%= for {tab_id, label, icon, blurb} <- @tabs do %>
            <%= if tab_id not in ["editor", "notes", "agent", "info"] do %>
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
      <Tabs.bar tabs={@tabs} active_tab={@active_tab} />
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
end
