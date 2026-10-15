defmodule PscWeb.DocumentLive.Index do
  use PscWeb, :live_view

  import PscWeb.CoreComponents, except: [button: 1]
  import PscWeb.Components.UI.Button

  alias Psc.Documents

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(
        Psc.PubSub,
        "user:#{socket.assigns.current_scope.user.id}:documents"
      )
    end

    user_email = socket.assigns.current_scope.user.email
    documents = Documents.list_user_documents(socket.assigns.current_scope.user.id)
    shared_documents = Documents.list_shared_documents(user_email)

    {:ok,
     socket
     |> assign(:documents, documents)
     |> assign(:shared_documents, shared_documents)
     |> assign(:show_new_form, false)
     |> assign(:new_title, "")}
  end

  @impl true
  def handle_event("show_new_form", _params, socket) do
    {:noreply, assign(socket, show_new_form: true, new_title: "")}
  end

  @impl true
  def handle_event("cancel_new", _params, socket) do
    {:noreply, assign(socket, show_new_form: false, new_title: "")}
  end

  @impl true
  def handle_event("create_document", %{"title" => title}, socket) do
    title_trimmed = String.trim(title)

    if title_trimmed == "" do
      {:noreply, put_flash(socket, :error, "Document title cannot be empty")}
    else
      case Documents.create_document(socket.assigns.current_scope.user.id, %{title: title_trimmed}) do
        {:ok, document} ->
          Phoenix.PubSub.broadcast(
            Psc.PubSub,
            "user:#{socket.assigns.current_scope.user.id}:documents",
            {:document_created, document}
          )

          {:noreply,
           socket
           |> assign(show_new_form: false, new_title: "")
           |> put_flash(:info, "Document created successfully")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to create document")}
      end
    end
  end

  @impl true
  def handle_event("update_title", %{"title" => title}, socket) do
    {:noreply, assign(socket, new_title: title)}
  end

  @impl true
  def handle_info({:document_created, _document}, socket) do
    user_email = socket.assigns.current_scope.user.email
    documents = Documents.list_user_documents(socket.assigns.current_scope.user.id)
    shared_documents = Documents.list_shared_documents(user_email)
    {:noreply, assign(socket, documents: documents, shared_documents: shared_documents)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-2xl px-6 py-12">
        <div class="mb-8 flex items-center justify-between">
          <h1 class="text-2xl font-semibold text-base-content">My Documents</h1>
          <.button phx-click="show_new_form">
            <.icon name="hero-plus" class="w-5 h-5" /> New Document
          </.button>
        </div>

        <%= if @show_new_form do %>
          <div class="mb-8 rounded-xl border border-white/10 bg-base-200 p-6">
            <.form
              for={nil}
              id="new-document-form"
              phx-submit="create_document"
              phx-change="update_title"
              class="flex gap-4"
            >
              <.input
                name="title"
                type="text"
                placeholder="Document title..."
                value={@new_title}
                required
                class="flex-1"
              />
              <.button type="submit" disabled={String.trim(@new_title) == ""}>
                Create
              </.button>
              <.button type="button" variant="secondary" phx-click="cancel_new">
                Cancel
              </.button>
            </.form>
          </div>
        <% end %>

        <%= if Enum.empty?(@documents) do %>
          <div class="rounded-xl border border-dashed border-white/10 bg-base-200 p-12 text-center">
            <.icon name="hero-document-text" class="mx-auto w-12 h-12 text-base-content/30 mb-4" />
            <p class="text-base-content/60">No documents yet. Create one to get started!</p>
          </div>
        <% else %>
          <div class="grid gap-3">
            <%= for doc <- @documents do %>
              <.link
                navigate={~p"/documents/#{doc.id}"}
                class="block rounded-xl border border-white/10 bg-base-200 p-4 hover:border-white/25 transition-colors"
              >
                <div class="flex items-center justify-between">
                  <div>
                    <h3 class="font-medium text-base-content">{doc.title}</h3>
                    <p class="text-sm text-base-content/50">
                      Updated {Calendar.strftime(doc.updated_at, "%b %d, %Y")}
                    </p>
                  </div>
                  <.icon name="hero-arrow-right" class="w-5 h-5 text-base-content/30" />
                </div>
              </.link>
            <% end %>
          </div>
        <% end %>

        <%!-- Shared with me section --%>
        <%= if !Enum.empty?(@shared_documents) do %>
          <div class="mt-12">
            <h2 class="text-lg font-medium text-base-content mb-4">Shared with me</h2>
            <div class="grid gap-3">
              <%= for doc <- @shared_documents do %>
                <.link
                  navigate={~p"/documents/#{doc.id}"}
                  class="block rounded-xl border border-primary/20 bg-primary/5 p-4 hover:border-primary/40 transition-colors"
                >
                  <div class="flex items-center justify-between">
                    <div>
                      <h3 class="font-medium text-base-content">{doc.title}</h3>
                      <p class="text-sm text-base-content/50">
                        By {doc.user.email} • Updated {Calendar.strftime(doc.updated_at, "%b %d, %Y")}
                      </p>
                    </div>
                    <.icon name="hero-arrow-right" class="w-5 h-5 text-base-content/30" />
                  </div>
                </.link>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
