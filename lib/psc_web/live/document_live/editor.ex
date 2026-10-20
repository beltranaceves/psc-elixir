defmodule PscWeb.DocumentLive.Editor do
  use PscWeb, :live_view

  # SaladUI badge/button/input are called qualified (UIBadge/UIButtton/UIInput)
  # because CoreComponents is imported globally via html_helpers and defines
  # the same names — unqualified imports would conflict.
  alias PscWeb.Components.UI.Badge, as: UIBadge

  alias Psc.Documents
  alias Psc.Documents.CRDT
  alias Psc.Documents.ConsistencyManager
  alias PscWeb.Markdown
  alias PscWeb.Presence

  import PscWeb.Components.MarkdownEditor
  import PscWeb.Components.ShareDialog

  # Check every 5 seconds
  @consistency_check_interval 5000
  # Fold pending operations into `content` immediately above this many, rather
  # than waiting for the idle timer — bounds how many un-pruned event rows a
  # single document can accumulate during a continuous typing burst.
  @max_pending_events 500
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
        |> assign(:share_open, false)
        |> assign(:content, content)
        |> assign(:last_saved_content, content)
        # :saved, :unsaved, :saving
        |> assign(:save_state, :saved)
        |> assign(:idle_timer_ref, nil)
        |> assign(:pending_events, 0)
        |> subscribe_to_document(document_id)

      # Schedule periodic consistency and save checks
      if connected?(socket) do
        Process.send_after(self(), :check_consistency, @consistency_check_interval)
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

    pending_events = socket.assigns.pending_events + length(operations)

    # Cancel any pending idle save timer
    socket =
      if socket.assigns.idle_timer_ref do
        Process.cancel_timer(socket.assigns.idle_timer_ref)
        assign(socket, idle_timer_ref: nil)
      else
        socket
      end

    socket =
      if pending_events >= @max_pending_events do
        # Fold now: bounds the un-pruned event rows instead of waiting for idle
        fold_pending(socket, new_content)
      else
        # Schedule new idle save timer
        idle_timer_ref = Process.send_after(self(), :idle_save, @idle_save_interval)

        socket
        |> assign(:save_state, :unsaved)
        |> assign(:idle_timer_ref, idle_timer_ref)
        |> assign(:pending_events, pending_events)
      end

    socket =
      socket
      |> assign(:content, new_content)
      |> push_document_render(new_content)

    {:noreply, socket}
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
  def handle_event("render_document", %{"content" => content}, socket) do
    {:noreply, push_document_render(socket, content)}
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
  def handle_event("share_document", %{"email" => email}, socket) do
    # Only owner can share
    if socket.assigns.document.user_id == socket.assigns.user_id do
      case Documents.share_document_with(socket.assigns.document, email) do
        {:ok, updated_document} ->
          {:noreply,
           socket
           |> assign(:document, updated_document)
           |> put_flash(:success, "Document shared with #{email}")}

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
           |> put_flash(:success, "Access removed for #{email}")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to remove access")}
      end
    else
      {:noreply, put_flash(socket, :error, "Only document owner can remove access")}
    end
  end

  # Fold the in-socket content into the document and prune the events it covers.
  defp fold_pending(socket, content) do
    case Documents.save_content_to_db(socket.assigns.document_id, content) do
      {:ok, _document} ->
        assign(socket,
          pending_events: 0,
          last_saved_content: content,
          save_state: :saved
        )

      {:error, _changeset} ->
        # Leave the counter alone so the next edit retries the fold
        assign(socket, :save_state, :unsaved)
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
           |> assign(:pending_events, 0)
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
            |> assign(:pending_events, 0)

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
        |> push_document_render(new_content)

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
          |> push_document_render(server_text)

        # Log the divergence for debugging
        :telemetry.execute(
          [:psc, :document, :consistency_divergence],
          %{document_id: socket.assigns.document_id, user_id: socket.assigns.user_id}
        )

        Process.send_after(self(), :check_consistency, @consistency_check_interval)
        {:noreply, assign(socket, content: server_text)}
    end
  end

  defp handle_presence_change(socket, document_id) do
    presence_list = Presence.list("presence:#{document_id}")
    assign(socket, presence: presence_list)
  end

  defp push_document_render(socket, content) do
    push_event(socket, "document_rendered", %{
      content: content,
      html: Markdown.render(content, empty_message: "Start writing in the editor.")
    })
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} header_title="Documents">
      <div class="flex h-dvh flex-col bg-base-100">
        <%!-- Header --%>
        <div class="border-b border-base-content/10 bg-base-200/60 px-6 py-4">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-4">
              <input
                type="text"
                value={@document.title}
                class="text-2xl font-semibold text-base-content bg-transparent border-b-2 border-transparent hover:border-base-content/20 focus:outline-none focus:border-primary px-2"
                placeholder="Untitled Document"
              />
              <%!-- Save Status Indicator --%>
              <%= cond do %>
                <% @save_state == :saving -> %>
                  <UIBadge.badge variant="secondary">
                    <div class="w-3 h-3 rounded-full border-2 border-current border-t-transparent animate-spin">
                    </div>
                    <span>Saving...</span>
                  </UIBadge.badge>
                <% @save_state == :saved -> %>
                  <UIBadge.badge variant="default">
                    <.icon name="hero-check-circle" class="w-4 h-4" />
                    <span>Saved</span>
                  </UIBadge.badge>
                <% true -> %>
                  <UIBadge.badge variant="outline">
                    <.icon name="hero-exclamation-circle" class="w-4 h-4" />
                    <span>Unsaved changes</span>
                  </UIBadge.badge>
              <% end %>
            </div>
            <%= if @document.user_id == @user_id do %>
              <.share_button id="share-document-button" label="Share" class="mr-2" />
            <% end %>
            <.link
              navigate={~p"/documents"}
              class="inline-flex items-center gap-2 text-sm font-medium text-base-content/60 hover:text-base-content transition-colors"
            >
              <.icon name="hero-arrow-left" class="w-4 h-4" /> Back
            </.link>
          </div>
        </div>

        <div class="flex min-h-0 flex-1 overflow-hidden bg-base-100">
          <div class="flex min-h-0 min-w-0 flex-1 flex-col overflow-hidden">
            <.markdown_editor
              id="document-editor"
              input_id="editor"
              form_id="editor-form"
              preview_id="document-markdown-preview"
              content={@content}
              html={Markdown.render(@content, empty_message: "Start writing in the editor.")}
              current_user_id={@user_id}
              change_event="update_content"
              preview_event="render_document"
              render_event="document_rendered"
              update_event="content_updated"
              empty_message="Start writing in the editor."
              preview_label="Edit document content"
            />
          </div>

          <%!-- Presence Sidebar --%>
          <div class="w-64 border-l border-base-content/10 bg-base-200 p-4 overflow-y-auto">
            <h3 class="text-sm font-medium text-base-content mb-4">Active Users</h3>
            <div class="space-y-2">
              <%= for {user_id, %{metas: metas}} <- @presence do %>
                <% meta = List.first(metas) %>
                <div class="text-sm p-3 rounded-lg bg-primary/10 border border-primary/20 hover:bg-primary/15 transition">
                  <div class="font-medium text-base-content">{meta[:username]}</div>
                  <div class="text-xs text-base-content/60 mt-1">
                    Cursor: <span class="font-mono">{meta[:cursor_pos]}</span>
                  </div>
                </div>
              <% end %>
            </div>

            <div class="mt-8 pt-4 border-t border-base-content/10">
              <p class="text-xs text-base-content/50">
                Use the Share button in the header to invite collaborators.
              </p>
            </div>
          </div>
        </div>

        <.share_dialog
          id="share-document-dialog"
          open={@share_open}
          title="Share document"
          description="People with access can edit this document with you in real time."
          manage?={@document.user_id == @user_id}
          shared_with={@document.shared_with || []}
          share_event="share_document"
          remove_event="remove_access"
          on_close="share_closed"
          link={document_url(assigns)}
        />
      </div>
    </Layouts.app>
    """
  end

  defp document_url(assigns) do
    # Build a shareable URL - in production, use the actual host
    "/documents/#{assigns.document_id}"
  end
end
