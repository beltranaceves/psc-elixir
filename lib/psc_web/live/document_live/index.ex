defmodule PscWeb.DocumentLive.Index do
  use PscWeb, :live_view
  alias Psc.Documents

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Psc.PubSub, "user:#{socket.assigns.current_scope.user.id}:documents")
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
  def handle_info({:document_created, document}, socket) do
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
          <h1 class="text-3xl font-bold text-gray-900">My Documents</h1>
          <button
            phx-click="show_new_form"
            class="inline-flex items-center gap-2 rounded-lg bg-blue-600 px-4 py-2 font-semibold text-white hover:bg-blue-700 transition-colors"
          >
            <.icon name="hero-plus" class="w-5 h-5" />
            New Document
          </button>
        </div>

        <%= if @show_new_form do %>
          <div class="mb-8 rounded-lg border border-gray-200 bg-white p-6">
            <.form
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
              <button
                type="submit"
                disabled={String.trim(@new_title) == ""}
                class="rounded-lg bg-blue-600 px-4 py-2 font-semibold text-white hover:bg-blue-700 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
              >
                Create
              </button>
              <button
                type="button"
                phx-click="cancel_new"
                class="rounded-lg bg-gray-200 px-4 py-2 font-semibold text-gray-700 hover:bg-gray-300 transition-colors"
              >
                Cancel
              </button>
            </.form>
          </div>
        <% end %>

        <%= if Enum.empty?(@documents) do %>
          <div class="rounded-lg border border-dashed border-gray-300 bg-gray-50 p-12 text-center">
            <.icon name="hero-document-text" class="mx-auto w-12 h-12 text-gray-400 mb-4" />
            <p class="text-gray-600">No documents yet. Create one to get started!</p>
          </div>
        <% else %>
          <div class="grid gap-4">
            <%= for doc <- @documents do %>
              <.link
                navigate={~p"/documents/#{doc.id}"}
                class="block rounded-lg border border-gray-200 bg-white p-4 hover:shadow-md transition-shadow"
              >
                <div class="flex items-center justify-between">
                  <div>
                    <h3 class="font-semibold text-gray-900"><%= doc.title %></h3>
                    <p class="text-sm text-gray-500">
                      Updated <%= Calendar.strftime(doc.updated_at, "%b %d, %Y") %>
                    </p>
                  </div>
                  <.icon name="hero-arrow-right" class="w-5 h-5 text-gray-400" />
                </div>
              </.link>
            <% end %>
          </div>
        <% end %>

        <%!-- Shared with me section --%>
        <%= if !Enum.empty?(@shared_documents) do %>
          <div class="mt-12">
            <h2 class="text-2xl font-bold text-gray-900 mb-6">Shared with me</h2>
            <div class="grid gap-4">
              <%= for doc <- @shared_documents do %>
                <.link
                  navigate={~p"/documents/#{doc.id}"}
                  class="block rounded-lg border border-gray-200 bg-blue-50 p-4 hover:shadow-md transition-shadow"
                >
                  <div class="flex items-center justify-between">
                    <div>
                      <h3 class="font-semibold text-gray-900"><%= doc.title %></h3>
                      <p class="text-sm text-gray-600">
                        By <%= doc.user.email %> • Updated <%= Calendar.strftime(doc.updated_at, "%b %d, %Y") %>
                      </p>
                    </div>
                    <.icon name="hero-arrow-right" class="w-5 h-5 text-gray-400" />
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
