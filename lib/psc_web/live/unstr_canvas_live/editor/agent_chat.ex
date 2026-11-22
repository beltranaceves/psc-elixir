defmodule PscWeb.UnstrCanvasLive.Editor.AgentChat do
  @moduledoc """
  The Agent tab: the person's chats on this canvas, the connection and role
  pickers, and the streamed turns. A turn runs in its own process and reports
  over PubSub; the messages it sends are handled here.
  """
  use PscWeb, :html
  import Phoenix.LiveView

  alias Psc.Agent.Config, as: AgentConfig

  @doc "Adds the Agent tab's assigns and registers its hooks."
  def attach(socket) do
    user = socket.assigns.current_scope.user
    config = AgentConfig.normalize(socket.assigns.canvas.agent_config)

    socket
    |> assign(:agent_session, nil)
    |> assign(:agent_messages, [])
    |> assign(:agent_turn_pid, nil)
    |> assign(:agent_subscribed, nil)
    |> assign(:agent_sessions, [])
    |> assign(:agent_list_open, false)
    |> assign(:agent_menu_session, nil)
    |> assign(:agent_phase, nil)
    |> assign(:agent_composer, to_form(%{"content" => ""}, as: :message))
    |> assign(:agent_enabled?, Psc.Agent.enabled?(user))
    |> assign(:agent_missing, Psc.Agent.missing_configuration(user))
    |> assign(:agent_connections, [])
    |> assign(:agent_connection, nil)
    |> assign(:agent_connection_list_open, false)
    |> assign(:agent_roles, config["roles"] || [])
    |> assign(:agent_role, config["default_role"])
    |> attach_hook(__MODULE__, :handle_event, &handle_event/3)
    |> attach_hook(__MODULE__, :handle_info, &handle_info/2)
  end

  def handle_event("agent_select_role", %{"role" => role}, socket) do
    session = socket.assigns.agent_session

    cond do
      is_nil(session) ->
        {:halt, assign(socket, :agent_role, role)}

      session.message_count in [nil, 0] ->
        case Psc.Agent.set_session_role(session, role) do
          {:ok, session} ->
            {:halt, assign(socket, agent_session: session, agent_role: role)}

          {:error, _reason} ->
            {:halt, socket}
        end

      true ->
        {:halt, put_flash(socket, :error, "Start a new chat to change the role.")}
    end
  end

  def handle_event("agent_new", _params, socket) do
    socket = stop_running_turn(socket)
    user = socket.assigns.current_scope.user
    # The saved config, not the Info tab's unsaved draft, decides what a new
    # chat starts with.
    default_role = AgentConfig.normalize(socket.assigns.canvas.agent_config)["default_role"]

    case Psc.Agent.create_session(user.id, %{canvas_id: socket.assigns.canvas_id}) do
      {:ok, session} ->
        {:halt,
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
        {:halt, put_flash(socket, :error, "Could not start a chat.")}
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
        {:halt, socket}

      is_nil(session) ->
        {:halt, put_flash(socket, :error, "Start a chat first.")}

      socket.assigns.agent_missing == :connection ->
        {:halt, put_flash(socket, :error, "Add a connection in settings first.")}

      socket.assigns.agent_turn_pid ->
        {:halt, put_flash(socket, :error, "Wait for the current answer to finish.")}

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
              {:halt,
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

              {:halt, put_flash(socket, :error, "Could not start the answer. Please try again.")}
          end
        else
          {:error, _reason} ->
            {:halt, put_flash(socket, :error, "Could not start the answer. Please try again.")}
        end
    end
  end

  # A suggested prompt fills the composer rather than sending itself, so the
  # user can edit it before spending a model call.
  def handle_event("agent_suggest", %{"prompt" => prompt}, socket) when is_binary(prompt) do
    {:halt, assign(socket, :agent_composer, to_form(%{"content" => prompt}, as: :message))}
  end

  def handle_event("agent_refresh", _params, socket) do
    # Settings can be saved in another tab or on another device. While the
    # panel is still waiting on a key or a model, re-read the account so saving
    # settings enables the composer without a page reload.
    if socket.assigns.agent_enabled? do
      {:halt, socket}
    else
      {:halt, refresh_agent_scope(socket)}
    end
  end

  def handle_event("agent_chat_menu", %{"session" => session_id}, socket) do
    open = if socket.assigns.agent_menu_session == session_id, do: nil, else: session_id
    {:halt, assign(socket, :agent_menu_session, open)}
  end

  def handle_event("agent_rename", %{"session" => session_id, "title" => title}, socket) do
    user = socket.assigns.current_scope.user

    case Psc.Agent.get_session(session_id, user.id) do
      nil ->
        {:halt, put_flash(socket, :error, "That chat is no longer available.")}

      session ->
        case Psc.Agent.rename_session(session, title) do
          {:ok, renamed} ->
            current =
              if socket.assigns.agent_session && socket.assigns.agent_session.id == renamed.id,
                do: renamed,
                else: socket.assigns.agent_session

            {:halt,
             socket
             |> assign(:agent_session, current)
             |> assign(
               :agent_sessions,
               Psc.Agent.list_sessions_for_canvas(renamed.canvas_id, user.id)
             )
             |> assign(:agent_menu_session, nil)}

          {:error, _changeset} ->
            {:halt, put_flash(socket, :error, "A title is required.")}
        end
    end
  end

  def handle_event("agent_duplicate", %{"session" => session_id}, socket) do
    user = socket.assigns.current_scope.user

    case Psc.Agent.get_session(session_id, user.id) do
      nil ->
        {:halt, put_flash(socket, :error, "That chat is no longer available.")}

      session ->
        # Stop before copying: an in-flight message would otherwise be copied
        # as `:streaming` into a chat that has no turn behind it.
        socket = stop_running_turn(socket)

        case Psc.Agent.duplicate_session(session) do
          {:ok, copy} ->
            {:halt,
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
            {:halt, put_flash(socket, :error, "Could not duplicate the chat.")}
        end
    end
  end

  def handle_event("agent_delete", %{"session" => session_id}, socket) do
    user = socket.assigns.current_scope.user

    case Psc.Agent.get_session(session_id, user.id) do
      nil ->
        {:halt, socket}

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

            {:halt,
             socket
             |> assign(:agent_sessions, sessions)
             |> assign(:agent_menu_session, nil)}

          {:error, _changeset} ->
            {:halt, put_flash(socket, :error, "Could not delete the chat.")}
        end
    end
  end

  def handle_event("agent_close_lists", _params, socket) do
    {:halt,
     assign(socket,
       agent_list_open: false,
       agent_menu_session: nil,
       agent_connection_list_open: false
     )}
  end

  def handle_event("agent_toggle_list", _params, socket) do
    {:halt,
     assign(socket,
       agent_list_open: not socket.assigns.agent_list_open,
       agent_connection_list_open: false
     )}
  end

  def handle_event("agent_toggle_connections", _params, socket) do
    {:halt,
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
        {:halt, put_flash(socket, :error, "Wait for the current answer to finish.")}

      is_nil(socket.assigns.agent_session) ->
        {:halt, assign(socket, :agent_connection_list_open, false)}

      true ->
        case Psc.Agent.Connections.get(id, user.id) do
          nil ->
            {:halt, put_flash(socket, :error, "That connection is no longer available.")}

          connection ->
            {:ok, session} =
              Psc.Agent.set_session_connection(socket.assigns.agent_session, connection)

            {:halt,
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
        {:halt, put_flash(socket, :error, "That chat is no longer available.")}

      session ->
        Psc.Agent.cancel_stale_streaming(session)

        same_session? =
          socket.assigns.agent_session && socket.assigns.agent_session.id == session.id

        socket = if same_session?, do: socket, else: stop_running_turn(socket)

        messages =
          if same_session?,
            do: socket.assigns.agent_messages,
            else: Psc.Agent.list_messages(session)

        {:halt,
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
    {:halt, stop_running_turn(socket)}
  end

  def handle_event(_event, _params, socket), do: {:cont, socket}

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

  def load_agent(socket) do
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

  def handle_info({:status, _message_id, phase}, socket) do
    {:halt, assign(socket, :agent_phase, phase)}
  end

  def handle_info({:delta, message_id, text}, socket) do
    {:halt, update_agent_message(socket, message_id, &%{&1 | content: &1.content <> text})}
  end

  def handle_info({:tool_started, message_id, call}, socket) do
    {:halt,
     update_agent_message(socket, message_id, &%{&1 | tool_calls: &1.tool_calls ++ [call]})}
  end

  def handle_info({:tool_finished, message_id, call}, socket) do
    {:halt,
     update_agent_message(socket, message_id, fn message ->
       %{message | tool_calls: List.update_at(message.tool_calls, -1, &Map.merge(&1, call))}
     end)}
  end

  def handle_info({:completed, message_id, %{content: content}}, socket) do
    {:halt,
     socket
     |> update_agent_message(message_id, &%{&1 | content: content, status: :complete})
     |> assign(:agent_turn_pid, nil)
     |> assign(:agent_phase, nil)}
  end

  def handle_info({:failed, message_id, reason}, socket) do
    {:halt,
     socket
     |> update_agent_message(message_id, &%{&1 | status: :error, error: to_string(reason)})
     |> assign(:agent_turn_pid, nil)
     |> assign(:agent_phase, nil)}
  end

  def handle_info(_message, socket), do: {:cont, socket}
end
