defmodule PscWeb.DocumentLive.Editor do
  use PscWeb, :live_view
  alias Psc.Documents
  alias Psc.Documents.CRDT
  alias Psc.Documents.ConsistencyManager
  alias PscWeb.Presence

  # Check every 5 seconds
  @consistency_check_interval 5000
  # Check if snapshot needed every 10 seconds
  @snapshot_check_interval 10000
  # Save after 1.5 seconds of inactivity
  @idle_save_interval 1500
  # Save every 10 seconds as fallback
  @periodic_save_interval 10000

  @impl true
  def mount(%{"id" => document_id}, _session, socket) do
    document = Documents.get_document(document_id) |> Psc.Repo.preload(:user)

    # Check authorization - user must be owner or in shared_with list
    user_email = socket.assigns.current_scope.user.email

    if Documents.can_access_document?(document, user_email) do
      # Load initial content from database
      content = Documents.get_document_content(document_id)

      socket =
        socket
        |> assign(:document, document)
        |> assign(:document_id, document_id)
        |> assign(:user_id, socket.assigns.current_scope.user.id)
        |> assign(:username, socket.assigns.current_scope.user.email)
        |> assign(:cursor_pos, 0)
        |> assign(:presence, %{})
        |> assign(:content, content)
        |> assign(:last_saved_content, content)
        # :saved, :unsaved, :saving
        |> assign(:save_state, :saved)
        |> assign(:idle_timer_ref, nil)
        |> subscribe_to_document(document_id)

      # Schedule periodic consistency checks and snapshot checks
      if connected?(socket) do
        Process.send_after(self(), :check_consistency, @consistency_check_interval)
        Process.send_after(self(), :check_snapshot, @snapshot_check_interval)
        Process.send_after(self(), :periodic_save, @periodic_save_interval)
      end

      {:ok, socket}
    else
      {:ok, redirect(socket, to: ~p"/documents")}
    end
  end

  defp subscribe_to_document(socket, document_id) do
    if connected?(socket) do
      # Subscribe to document changes
      Phoenix.PubSub.subscribe(Psc.PubSub, Documents.pubsub_topic(document_id))

      # Subscribe to presence updates via PubSub (Phoenix.Presence broadcasts to this topic)
      Phoenix.PubSub.subscribe(Psc.PubSub, "presence:#{document_id}")

      # Track this user's presence
      Presence.track(self(), "presence:#{document_id}", socket.assigns.user_id, %{
        username: socket.assigns.username,
        cursor_pos: 0
      })

      # Initialize content from events
      content = Documents.get_document_content(document_id)

      socket
      |> assign(:content, content)
      |> handle_presence_change(document_id)
    else
      socket
    end
  end

  @impl true
  def handle_event("update_content", %{"content" => new_content}, socket) do
    old_content = socket.assigns.content

    # Detect changes using CRDT delta diff
    operations = Documents.text_to_operations(old_content, new_content)

    # Apply each operation and broadcast
    Enum.each(operations, fn operation ->
      Documents.apply_operation(socket.assigns.document_id, socket.assigns.user_id, operation)
    end)

    # Update presence with cursor position
    Presence.update(self(), "presence:#{socket.assigns.document_id}", socket.assigns.user_id, %{
      username: socket.assigns.username,
      cursor_pos: String.length(new_content)
    })

    # Cancel any pending idle save timer
    socket =
      if socket.assigns.idle_timer_ref do
        Process.cancel_timer(socket.assigns.idle_timer_ref)
        assign(socket, idle_timer_ref: nil)
      else
        socket
      end

    # Schedule new idle save timer
    idle_timer_ref = Process.send_after(self(), :idle_save, @idle_save_interval)

    {:noreply,
     socket
     |> assign(:content, new_content)
     |> assign(:save_state, :unsaved)
     |> assign(:idle_timer_ref, idle_timer_ref)}
  end

  @impl true
  def handle_event("update_cursor", %{"pos" => pos}, socket) do
    Presence.update(self(), "presence:#{socket.assigns.document_id}", socket.assigns.user_id, %{
      username: socket.assigns.username,
      cursor_pos: pos
    })

    {:noreply, assign(socket, cursor_pos: pos)}
  end

  @impl true
  def handle_event("share_document", %{"email" => email}, socket) do
    # Only owner can share
    if socket.assigns.document.user_id == socket.assigns.user_id do
      case Documents.share_document_with(socket.assigns.document, email) do
        {:ok, updated_document} ->
          {:noreply,
           socket
           |> assign(:document, updated_document)
           |> put_flash(:info, "Document shared with #{email}")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to share document")}
      end
    else
      {:noreply, put_flash(socket, :error, "Only document owner can share")}
    end
  end

  @impl true
  def handle_event("remove_access", %{"email" => email}, socket) do
    # Only owner can remove access
    if socket.assigns.document.user_id == socket.assigns.user_id do
      case Documents.unshare_document(socket.assigns.document, email) do
        {:ok, updated_document} ->
          {:noreply,
           socket
           |> assign(:document, updated_document)
           |> put_flash(:info, "Access removed for #{email}")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to remove access")}
      end
    else
      {:noreply, put_flash(socket, :error, "Only document owner can remove access")}
    end
  end

  @impl true
  def handle_info(:idle_save, socket) do
    # Save content after idle period
    if socket.assigns.content != socket.assigns.last_saved_content do
      socket = assign(socket, save_state: :saving)

      case Documents.save_content_to_db(socket.assigns.document_id, socket.assigns.content) do
        {:ok, _} ->
          :telemetry.execute(
            [:psc, :document, :content_saved],
            %{document_id: socket.assigns.document_id, source: :idle}
          )

          {:noreply,
           socket
           |> assign(:last_saved_content, socket.assigns.content)
           |> assign(:save_state, :saved)
           |> assign(:idle_timer_ref, nil)}

        {:error, _} ->
          {:noreply,
           socket
           |> assign(:save_state, :unsaved)
           |> assign(:idle_timer_ref, nil)}
      end
    else
      {:noreply, assign(socket, idle_timer_ref: nil)}
    end
  end

  @impl true
  def handle_info(:periodic_save, socket) do
    # Save content periodically as a safety net
    socket =
      if socket.assigns.content != socket.assigns.last_saved_content do
        case Documents.save_content_to_db(socket.assigns.document_id, socket.assigns.content) do
          {:ok, _} ->
            :telemetry.execute(
              [:psc, :document, :content_saved],
              %{document_id: socket.assigns.document_id, source: :periodic}
            )

            socket
            |> assign(:last_saved_content, socket.assigns.content)
            |> assign(:save_state, :saved)

          {:error, _} ->
            socket
        end
      else
        socket
      end

    # Reschedule periodic save
    Process.send_after(self(), :periodic_save, @periodic_save_interval)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:operation, user_id, operation, _seq}, socket) do
    # Only update if not from current user (avoid echoing back)
    if user_id != socket.assigns.user_id do
      # Apply the operation directly instead of rebuilding
      # This is more efficient and avoids race conditions
      new_content = CRDT.apply_operation(operation, socket.assigns.content)

      # Push event to the hook to update the textarea
      # Include the user_id so the hook knows this is from another user
      socket =
        push_event(socket, "content_updated", %{
          "newContent" => new_content,
          "fromUserId" => user_id
        })

      {:noreply, assign(socket, content: new_content)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:noreply, handle_presence_change(socket, socket.assigns.document_id)}
  end

  @impl true
  def handle_info(:check_consistency, socket) do
    # Verify that client state matches server state
    case ConsistencyManager.verify_consistency(socket.assigns.document_id, socket.assigns.content) do
      :ok ->
        # Client is consistent with server, schedule next check
        Process.send_after(self(), :check_consistency, @consistency_check_interval)
        {:noreply, socket}

      {:diverged, server_text} ->
        # Client has diverged from server - resync to authoritative state
        socket =
          push_event(socket, "content_updated", %{
            "newContent" => server_text,
            # Special ID indicating server resync
            "fromUserId" => -1
          })

        # Log the divergence for debugging
        :telemetry.execute(
          [:psc, :document, :consistency_divergence],
          %{document_id: socket.assigns.document_id, user_id: socket.assigns.user_id}
        )

        Process.send_after(self(), :check_consistency, @consistency_check_interval)
        {:noreply, assign(socket, content: server_text)}
    end
  end

  @impl true
  def handle_info(:check_snapshot, socket) do
    # Check if a snapshot should be created (after many operations)
    if Documents.should_snapshot?(socket.assigns.document_id) do
      case Documents.create_snapshot(socket.assigns.document_id) do
        {:ok, _document} ->
          # Snapshot created successfully
          :telemetry.execute(
            [:psc, :document, :snapshot_created],
            %{document_id: socket.assigns.document_id}
          )

        {:error, _changeset} ->
          # Snapshot creation failed - not critical, will retry next interval
          :ok
      end
    end

    # Schedule next snapshot check
    Process.send_after(self(), :check_snapshot, @snapshot_check_interval)
    {:noreply, socket}
  end

  defp handle_presence_change(socket, document_id) do
    presence_list = Presence.list("presence:#{document_id}")
    assign(socket, presence: presence_list)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="flex h-screen flex-col bg-gray-50">
        <%!-- Header --%>
        <div class="border-b border-gray-300 bg-white px-6 py-4 shadow-sm">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-4">
              <input
                type="text"
                value={@document.title}
                class="text-2xl font-bold text-gray-900 bg-white border-b-2 border-transparent hover:border-blue-300 focus:outline-none focus:border-blue-500 px-2"
                placeholder="Untitled Document"
              />
              <%!-- Save Status Indicator --%>
              <%= cond do %>
                <% @save_state == :saving -> %>
                  <div class="flex items-center gap-2 text-sm font-medium px-3 py-1 rounded-full text-amber-700 bg-amber-100">
                    <div class="w-3 h-3 rounded-full border-2 border-amber-600 border-t-transparent animate-spin">
                    </div>
                    <span>Saving...</span>
                  </div>
                <% @save_state == :saved -> %>
                  <div class="flex items-center gap-2 text-sm font-medium px-3 py-1 rounded-full text-green-700 bg-green-100">
                    <.icon name="hero-check-circle" class="w-4 h-4" />
                    <span>Saved</span>
                  </div>
                <% true -> %>
                  <div class="flex items-center gap-2 text-sm font-medium px-3 py-1 rounded-full text-gray-700 bg-gray-100">
                    <.icon name="hero-exclamation-circle" class="w-4 h-4" />
                    <span>Unsaved changes</span>
                  </div>
              <% end %>
            </div>
            <.link
              navigate={~p"/documents"}
              class="inline-flex items-center gap-2 text-sm font-medium text-blue-600 hover:text-blue-700"
            >
              <.icon name="hero-arrow-left" class="w-4 h-4" /> Back
            </.link>
          </div>
        </div>

        <div class="flex flex-1 overflow-hidden bg-gray-50">
          <%!-- Editor --%>
          <div class="flex-1 flex flex-col">
            <.form for={%{}} id="editor-form" phx-change="update_content" class="flex-1 flex flex-col">
              <textarea
                name="content"
                id="editor"
                phx-hook="EditorHook"
                phx-update="ignore"
                data-current-user-id={@user_id}
                class="flex-1 resize-none border-0 p-6 font-mono text-sm bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 placeholder-gray-400 dark:placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-inset"
                placeholder="Start typing..."
                value={@content}
              ></textarea>
            </.form>
          </div>

          <%!-- Presence Sidebar --%>
          <div class="w-64 border-l border-gray-300 bg-white p-4 shadow-sm overflow-y-auto">
            <h3 class="font-semibold text-gray-900 mb-4">Active Users</h3>
            <div class="space-y-2">
              <%= for {user_id, %{metas: metas}} <- @presence do %>
                <% meta = List.first(metas) %>
                <div class="text-sm text-gray-900 p-3 rounded-lg bg-blue-50 border border-blue-200 hover:bg-blue-100 transition">
                  <div class="font-medium text-gray-900">{meta[:username]}</div>
                  <div class="text-xs text-gray-600 mt-1">
                    Cursor: <span class="font-mono">{meta[:cursor_pos]}</span>
                  </div>
                </div>
              <% end %>
            </div>

            <div class="mt-8 pt-4 border-t border-gray-200">
              <h4 class="font-semibold text-gray-900 mb-3">Share Document</h4>

              <%!-- Share with email form (only for owner) --%>
              <%= if @document.user_id == @user_id do %>
                <.form for={%{}} id="share-form" phx-submit="share_document" class="flex gap-2 mb-4">
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

              <%!-- List of shared users --%>
              <%= if @document.shared_with && Enum.any?(@document.shared_with) do %>
                <div class="mb-4">
                  <p class="text-xs font-medium text-gray-600 mb-2">Shared with:</p>
                  <div class="space-y-1">
                    <%= for email <- @document.shared_with do %>
                      <div class="text-xs text-gray-700 px-3 py-2 bg-green-50 rounded border border-green-200 flex items-center justify-between">
                        <span>{email}</span>
                        <%= if @document.user_id == @user_id do %>
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

              <p class="text-xs text-gray-500 mb-3">Copy link to share with anyone:</p>
              <div class="flex gap-2">
                <input
                  type="text"
                  readonly
                  value={document_url(assigns)}
                  class="flex-1 text-xs px-3 py-2 bg-gray-100 border border-gray-300 rounded-lg text-gray-700 font-mono"
                />
                <button
                  onclick={"navigator.clipboard.writeText('#{document_url(assigns)}')"}
                  class="px-3 py-2 bg-blue-600 text-white text-xs font-medium rounded-lg hover:bg-blue-700 transition"
                >
                  Copy
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp document_url(assigns) do
    # Build a shareable URL - in production, use the actual host
    "/documents/#{assigns.document_id}"
  end
end
