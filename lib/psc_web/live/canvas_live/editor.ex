defmodule PscWeb.CanvasLive.Editor do
  use PscWeb, :live_view
  alias Psc.Canvas
  alias Psc.Canvas.Canvas, as: CanvasSchema
  alias PscWeb.Presence

  @idle_save_interval 1500
  @periodic_save_interval 10000

  @impl true
  def mount(%{"id" => canvas_id}, _session, socket) do
    canvas = Canvas.get_canvas_with_author(canvas_id)
    user_email = socket.assigns.current_scope.user.email
    user_id = socket.assigns.current_scope.user.id

    if canvas && Canvas.can_access_canvas?(canvas, user_email) do
      socket =
        socket
        |> assign(:canvas, canvas)
        |> assign(:canvas_id, canvas_id)
        |> assign(:user_id, user_id)
        |> assign(:username, user_email)
        |> assign(:save_state, :saved)
        |> assign(:idle_timer_ref, nil)
        |> assign(:original_canvas, canvas)
        |> assign(:presence, %{})
        |> subscribe_to_canvas(canvas_id)

      if connected?(socket) do
        Process.send_after(self(), :periodic_save, @periodic_save_interval)
      end

      {:ok, socket}
    else
      {:ok, redirect(socket, to: ~p"/canvases")}
    end
  end

  defp subscribe_to_canvas(socket, canvas_id) do
    if connected?(socket) do
      # Subscribe to presence updates
      Phoenix.PubSub.subscribe(Psc.PubSub, "presence:canvas:#{canvas_id}")

      # Track this user's presence
      Presence.track(self(), "presence:canvas:#{canvas_id}", socket.assigns.user_id, %{
        username: socket.assigns.username
      })

      socket
      |> handle_presence_change(canvas_id)
    else
      socket
    end
  end

  defp handle_presence_change(socket, canvas_id) do
    presence_list = Presence.list("presence:canvas:#{canvas_id}")
    assign(socket, presence: presence_list)
  end

  @impl true
  def handle_event("update_title", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("update_description", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("update_cell", %{"cell" => cell_name, "field" => field, "value" => value}, socket) do
    canvas = socket.assigns.canvas

    # Update the nested cell data
    cell_atom = String.to_atom(cell_name)
    cell_data = Map.get(canvas, cell_atom) || %{}

    field_atom = String.to_atom(field)
    updated_cell = Map.put(cell_data, field_atom, value)

    updated_canvas =
      canvas
      |> Map.put(cell_atom, updated_cell)

    # Cancel pending idle save and schedule new one
    socket =
      if socket.assigns.idle_timer_ref do
        Process.cancel_timer(socket.assigns.idle_timer_ref)
        assign(socket, idle_timer_ref: nil)
      else
        socket
      end

    idle_timer_ref = Process.send_after(self(), :idle_save, @idle_save_interval)

    {:noreply,
     socket
     |> assign(:canvas, updated_canvas)
     |> assign(:save_state, :unsaved)
     |> assign(:idle_timer_ref, idle_timer_ref)}
  end

  @impl true
  def handle_event("update_title", _params, socket) do
    # phx-change on an input sends the entire form value
    # We get it from the parameter 'html_escaped_value' when using regular input
    # Actually, let's simplify and just get it from the input value directly
    {:noreply, socket}
  end

  @impl true
  def handle_event("update_description", _params, socket) do
    # Similarly for description
    {:noreply, socket}
  end

  @impl true
  def handle_event("share_canvas", %{"email" => email}, socket) do
    # Only owner can share
    if socket.assigns.canvas.author_id == socket.assigns.user_id do
      case Canvas.share_canvas_with(socket.assigns.canvas, email) do
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
    # Only owner can remove access
    if socket.assigns.canvas.author_id == socket.assigns.user_id do
      case Canvas.unshare_canvas(socket.assigns.canvas, email) do
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
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:noreply, handle_presence_change(socket, socket.assigns.canvas_id)}
  end

  @impl true
  def handle_info(:idle_save, socket) do
    if has_changes?(socket.assigns.canvas, socket.assigns.original_canvas) do
      socket = assign(socket, save_state: :saving)

      case Canvas.update_canvas(socket.assigns.canvas, %{
             name: socket.assigns.canvas.name,
             description: socket.assigns.canvas.description,
             problem: socket.assigns.canvas.problem,
             leverage: socket.assigns.canvas.leverage,
             solution_cluster: socket.assigns.canvas.solution_cluster,
             horizon: socket.assigns.canvas.horizon,
             outer_environment: socket.assigns.canvas.outer_environment,
             inner_environment: socket.assigns.canvas.inner_environment,
             evolvability_cluster: socket.assigns.canvas.evolvability_cluster,
             potential: socket.assigns.canvas.potential,
             manifestations: socket.assigns.canvas.manifestations,
             capabilities: socket.assigns.canvas.capabilities,
             merit_cluster: socket.assigns.canvas.merit_cluster,
             mission: socket.assigns.canvas.mission
           }) do
        {:ok, updated_canvas} ->
          {:noreply,
           socket
           |> assign(:original_canvas, updated_canvas)
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
    if has_changes?(socket.assigns.canvas, socket.assigns.original_canvas) do
      Canvas.update_canvas(socket.assigns.canvas, %{
        name: socket.assigns.canvas.name,
        description: socket.assigns.canvas.description,
        problem: socket.assigns.canvas.problem,
        leverage: socket.assigns.canvas.leverage,
        solution_cluster: socket.assigns.canvas.solution_cluster,
        horizon: socket.assigns.canvas.horizon,
        outer_environment: socket.assigns.canvas.outer_environment,
        inner_environment: socket.assigns.canvas.inner_environment,
        evolvability_cluster: socket.assigns.canvas.evolvability_cluster,
        potential: socket.assigns.canvas.potential,
        manifestations: socket.assigns.canvas.manifestations,
        capabilities: socket.assigns.canvas.capabilities,
        merit_cluster: socket.assigns.canvas.merit_cluster,
        mission: socket.assigns.canvas.mission
      })
    end

    Process.send_after(self(), :periodic_save, @periodic_save_interval)
    {:noreply, socket}
  end

  defp has_changes?(canvas1, canvas2) do
    canvas1 != canvas2
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="min-h-screen bg-gray-50 py-8">
        <div class="mx-auto max-w-5xl px-4">
          <%!-- Header --%>
          <div class="mb-6">
            <div class="flex items-center justify-between">
              <div>
                <h1 class="text-3xl font-bold text-gray-900"><%= @canvas.name %></h1>
                <p class="text-sm text-gray-600 mt-1"><%= @canvas.description %></p>
              </div>
              <%= cond do %>
                <% @save_state == :saving -> %>
                  <div class="flex items-center gap-2 text-sm font-medium px-3 py-1 rounded-full text-amber-700 bg-amber-100">
                    <div class="w-3 h-3 rounded-full border-2 border-amber-600 border-t-transparent animate-spin"></div>
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
                    <span>Unsaved</span>
                  </div>
              <% end %>
            </div>
            <.link
              navigate={~p"/canvases"}
              class="inline-flex items-center gap-2 text-sm font-medium text-blue-600 hover:text-blue-700 mt-4"
            >
              <.icon name="hero-arrow-left" class="w-4 h-4" />
              Back
            </.link>
          </div>

          <%!-- Content: Grid + Sidebar --%>
          <div class="flex gap-6 min-h-0">
            <%!-- Canvas Grid --%>
            <div class="flex-1 min-w-0 overflow-x-auto">
              <table class="w-full border-collapse table-fixed">
                <tbody>
                  <%!-- Row 1: Rationale --%>
                  <tr>
                    <th class="border border-gray-300 bg-blue-50 p-3 text-left text-sm font-semibold text-gray-900">
                      Rationale
                    </th>
                    <%!-- Perceive: Problem --%>
                    <td class="border border-gray-300 bg-white p-3">
                      <h3 class="text-sm font-bold text-gray-900 mb-2">Problem</h3>
                      <textarea
                        phx-change="update_cell"
                        phx-value-cell="problem"
                        phx-value-field="content"
                        class="w-full h-32 border border-gray-300 rounded px-2 py-1 text-sm resize-none text-black"
                        placeholder="Describe the problem..."
                      ><%= @canvas.problem && @canvas.problem.content %></textarea>
                    </td>
                    <%!-- Form: Leverage --%>
                    <td class="border border-gray-300 bg-white p-3">
                      <h3 class="text-sm font-bold text-gray-900 mb-2">Leverage</h3>
                      <div class="space-y-2 text-sm">
                        <input
                          type="text"
                          placeholder="Technology..."
                          value={@canvas.leverage && @canvas.leverage.technology}
                          phx-change="update_cell"
                          phx-value-cell="leverage"
                          phx-value-field="technology"
                          class="w-full border border-gray-300 rounded px-2 py-1 text-black"
                        />
                        <input
                          type="text"
                          placeholder="Components..."
                          value={@canvas.leverage && @canvas.leverage.components}
                          phx-change="update_cell"
                          phx-value-cell="leverage"
                          phx-value-field="components"
                          class="w-full border border-gray-300 rounded px-2 py-1 text-black"
                        />
                        <input
                          type="text"
                          placeholder="Information..."
                          value={@canvas.leverage && @canvas.leverage.information}
                          phx-change="update_cell"
                          phx-value-cell="leverage"
                          phx-value-field="information"
                          class="w-full border border-gray-300 rounded px-2 py-1 text-black"
                        />
                        <input
                          type="text"
                          placeholder="Human Resources..."
                          value={@canvas.leverage && @canvas.leverage.human_resources}
                          phx-change="update_cell"
                          phx-value-cell="leverage"
                          phx-value-field="human_resources"
                          class="w-full border border-gray-300 rounded px-2 py-1 text-black"
                        />
                      </div>
                    </td>
                    <%!-- Consolidate: Solution Cluster --%>
                    <td class="border border-gray-300 bg-white p-3">
                      <h3 class="text-sm font-bold text-gray-900 mb-2">Solution</h3>
                      <textarea
                        phx-change="update_cell"
                        phx-value-cell="solution_cluster"
                        phx-value-field="content"
                        class="w-full h-32 border border-gray-300 rounded px-2 py-1 text-sm resize-none text-black"
                        placeholder="Describe the solution..."
                      ><%= @canvas.solution_cluster && @canvas.solution_cluster.content %></textarea>
                    </td>
                    <%!-- Learn: Horizon --%>
                    <td class="border border-gray-300 bg-white p-3">
                      <h3 class="text-sm font-bold text-gray-900 mb-2">Horizon</h3>
                      <textarea
                        phx-change="update_cell"
                        phx-value-cell="horizon"
                        phx-value-field="content"
                        class="w-full h-32 border border-gray-300 rounded px-2 py-1 text-sm resize-none text-black"
                        placeholder="Describe the horizon..."
                      ><%= @canvas.horizon && @canvas.horizon.content %></textarea>
                    </td>
                  </tr>

                  <%!-- Row 2: Strategy --%>
                  <tr>
                    <th class="border border-gray-300 bg-purple-50 p-3 text-left text-sm font-semibold text-gray-900">
                      Strategy
                    </th>
                    <%!-- Perceive: Outer Environment --%>
                    <td class="border border-gray-300 bg-white p-3">
                      <h3 class="text-sm font-bold text-gray-900 mb-2">Outer Environment</h3>
                      <div class="space-y-2 text-sm">
                        <input
                          type="text"
                          placeholder="External Services..."
                          value={@canvas.outer_environment && @canvas.outer_environment.external_services}
                          phx-change="update_cell"
                          phx-value-cell="outer_environment"
                          phx-value-field="external_services"
                          class="w-full border border-gray-300 rounded px-2 py-1 text-black"
                        />
                        <input
                          type="text"
                          placeholder="External Implements..."
                          value={@canvas.outer_environment && @canvas.outer_environment.external_implements}
                          phx-change="update_cell"
                          phx-value-cell="outer_environment"
                          phx-value-field="external_implements"
                          class="w-full border border-gray-300 rounded px-2 py-1 text-black"
                        />
                        <input
                          type="text"
                          placeholder="External Repositories..."
                          value={@canvas.outer_environment && @canvas.outer_environment.external_repositories}
                          phx-change="update_cell"
                          phx-value-cell="outer_environment"
                          phx-value-field="external_repositories"
                          class="w-full border border-gray-300 rounded px-2 py-1 text-black"
                        />
                        <input
                          type="text"
                          placeholder="External People..."
                          value={@canvas.outer_environment && @canvas.outer_environment.external_people}
                          phx-change="update_cell"
                          phx-value-cell="outer_environment"
                          phx-value-field="external_people"
                          class="w-full border border-gray-300 rounded px-2 py-1 text-black"
                        />
                      </div>
                    </td>
                    <%!-- Form: Inner Environment --%>
                    <td class="border border-gray-300 bg-white p-3">
                      <h3 class="text-sm font-bold text-gray-900 mb-2">Inner Environment</h3>
                      <textarea
                        phx-change="update_cell"
                        phx-value-cell="inner_environment"
                        phx-value-field="content"
                        class="w-full h-32 border border-gray-300 rounded px-2 py-1 text-sm resize-none text-black"
                        placeholder="Describe the inner environment..."
                      ><%= @canvas.inner_environment && @canvas.inner_environment.content %></textarea>
                    </td>
                    <%!-- Consolidate: Evolvability Cluster --%>
                    <td class="border border-gray-300 bg-white p-3">
                      <h3 class="text-sm font-bold text-gray-900 mb-2">Evolvability</h3>
                      <div class="space-y-2 text-sm">
                        <input
                          type="text"
                          placeholder="Evolvability..."
                          value={@canvas.evolvability_cluster && @canvas.evolvability_cluster.evolvability}
                          phx-change="update_cell"
                          phx-value-cell="evolvability_cluster"
                          phx-value-field="evolvability"
                          class="w-full border border-gray-300 rounded px-2 py-1 text-black"
                        />
                        <input
                          type="text"
                          placeholder="Diffusibility..."
                          value={@canvas.evolvability_cluster && @canvas.evolvability_cluster.diffusibility}
                          phx-change="update_cell"
                          phx-value-cell="evolvability_cluster"
                          phx-value-field="diffusibility"
                          class="w-full border border-gray-300 rounded px-2 py-1 text-black"
                        />
                        <input
                          type="text"
                          placeholder="Adoptability..."
                          value={@canvas.evolvability_cluster && @canvas.evolvability_cluster.adoptability}
                          phx-change="update_cell"
                          phx-value-cell="evolvability_cluster"
                          phx-value-field="adoptability"
                          class="w-full border border-gray-300 rounded px-2 py-1 text-black"
                        />
                      </div>
                    </td>
                    <%!-- Learn: Potential --%>
                    <td class="border border-gray-300 bg-white p-3">
                      <h3 class="text-sm font-bold text-gray-900 mb-2">Potential</h3>
                      <textarea
                        phx-change="update_cell"
                        phx-value-cell="potential"
                        phx-value-field="content"
                        class="w-full h-32 border border-gray-300 rounded px-2 py-1 text-sm resize-none text-black"
                        placeholder="Describe the potential..."
                      ><%= @canvas.potential && @canvas.potential.content %></textarea>
                    </td>
                  </tr>

                  <%!-- Row 3: Tactics --%>
                  <tr>
                    <th class="border border-gray-300 bg-green-50 p-3 text-left text-sm font-semibold text-gray-900">
                      Tactics
                    </th>
                    <%!-- Perceive: Manifestations --%>
                    <td class="border border-gray-300 bg-white p-3">
                      <h3 class="text-sm font-bold text-gray-900 mb-2">Manifestations</h3>
                      <textarea
                        phx-change="update_cell"
                        phx-value-cell="manifestations"
                        phx-value-field="content"
                        class="w-full h-32 border border-gray-300 rounded px-2 py-1 text-sm resize-none text-black"
                        placeholder="Describe the manifestations..."
                      ><%= @canvas.manifestations && @canvas.manifestations.content %></textarea>
                    </td>
                    <%!-- Form: Capabilities --%>
                    <td class="border border-gray-300 bg-white p-3">
                      <h3 class="text-sm font-bold text-gray-900 mb-2">Capabilities</h3>
                      <textarea
                        phx-change="update_cell"
                        phx-value-cell="capabilities"
                        phx-value-field="content"
                        class="w-full h-32 border border-gray-300 rounded px-2 py-1 text-sm resize-none text-black"
                        placeholder="Describe the capabilities..."
                      ><%= @canvas.capabilities && @canvas.capabilities.content %></textarea>
                    </td>
                    <%!-- Consolidate: Merit Cluster --%>
                    <td class="border border-gray-300 bg-white p-3">
                      <h3 class="text-sm font-bold text-gray-900 mb-2">Merit</h3>
                      <div class="space-y-2 text-sm">
                        <input
                          type="text"
                          placeholder="Merit..."
                          value={@canvas.merit_cluster && @canvas.merit_cluster.merit}
                          phx-change="update_cell"
                          phx-value-cell="merit_cluster"
                          phx-value-field="merit"
                          class="w-full border border-gray-300 rounded px-2 py-1 text-black"
                        />
                        <input
                          type="text"
                          placeholder="Value..."
                          value={@canvas.merit_cluster && @canvas.merit_cluster.value}
                          phx-change="update_cell"
                          phx-value-cell="merit_cluster"
                          phx-value-field="value"
                          class="w-full border border-gray-300 rounded px-2 py-1 text-black"
                        />
                        <input
                          type="text"
                          placeholder="Reservation..."
                          value={@canvas.merit_cluster && @canvas.merit_cluster.reservation}
                          phx-change="update_cell"
                          phx-value-cell="merit_cluster"
                          phx-value-field="reservation"
                          class="w-full border border-gray-300 rounded px-2 py-1 text-black"
                        />
                        <input
                          type="text"
                          placeholder="Rebuttal..."
                          value={@canvas.merit_cluster && @canvas.merit_cluster.rebuttal}
                          phx-change="update_cell"
                          phx-value-cell="merit_cluster"
                          phx-value-field="rebuttal"
                          class="w-full border border-gray-300 rounded px-2 py-1 text-black"
                        />
                      </div>
                    </td>
                    <%!-- Learn: Mission --%>
                    <td class="border border-gray-300 bg-white p-3">
                      <h3 class="text-sm font-bold text-gray-900 mb-2">Mission</h3>
                      <textarea
                        phx-change="update_cell"
                        phx-value-cell="mission"
                        phx-value-field="content"
                        class="w-full h-32 border border-gray-300 rounded px-2 py-1 text-sm resize-none text-black"
                        placeholder="Describe the mission..."
                      ><%= @canvas.mission && @canvas.mission.content %></textarea>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>

            <%!-- Sidebar --%>
            <div class="w-64 flex-shrink-0">
              <div class="bg-white border border-gray-300 rounded-lg p-4">
                <h3 class="font-semibold text-gray-900 mb-3">Active Users</h3>
                <div class="space-y-2 mb-6">
                  <%= for {_user_id, %{metas: metas}} <- @presence do %>
                    <% meta = List.first(metas) %>
                    <div class="text-xs text-gray-700 p-2 rounded bg-blue-50 border border-blue-200">
                      <%= meta[:username] %>
                    </div>
                  <% end %>
                </div>

                <h4 class="font-semibold text-gray-900 mb-3">Share Canvas</h4>
                <%= if @canvas.author_id == @user_id do %>
                  <.form for={%{}} id="share-form" phx-submit="share_canvas" class="flex gap-2 mb-4">
                    <input
                      type="email"
                      name="email"
                      placeholder="Email..."
                      class="flex-1 text-xs px-2 py-1 border border-gray-300 rounded text-gray-900 placeholder-gray-400"
                    />
                    <button type="submit" class="px-2 py-1 bg-green-600 text-white text-xs font-medium rounded">
                      +
                    </button>
                  </.form>
                <% end %>

                <%= if @canvas.shared_with && Enum.any?(@canvas.shared_with) do %>
                  <div class="space-y-1">
                    <%= for email <- @canvas.shared_with do %>
                      <div class="text-xs text-gray-700 px-2 py-1 bg-green-50 rounded border border-green-200 flex items-center justify-between">
                        <span><%= email %></span>
                        <%= if @canvas.author_id == @user_id do %>
                          <button
                            phx-click="remove_access"
                            phx-value-email={email}
                            class="text-red-600 hover:text-red-700 font-bold"
                          >
                            ×
                          </button>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
