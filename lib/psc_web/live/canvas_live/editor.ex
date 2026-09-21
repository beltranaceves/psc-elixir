defmodule PscWeb.CanvasLive.Editor do
  use PscWeb, :live_view
  require Logger
  alias Psc.Canvas
  alias PscWeb.Presence

  @idle_save_interval 1500
  @periodic_save_interval 10000

  @impl true
  def mount(%{"id" => canvas_id}, _session, socket) do
    Logger.debug("---------- [MOUNT] Loading canvas_id: #{canvas_id} ----------")

    canvas = Canvas.get_canvas_with_author(canvas_id)
    user_email = socket.assigns.current_scope.user.email
    user_id = socket.assigns.current_scope.user.id

    if canvas do
      Logger.debug("[MOUNT] Canvas loaded successfully, will be displayed in template")
    else
      Logger.warning("[MOUNT] Canvas is nil - will redirect")
    end

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
  def handle_event("update_cell", params, socket) do
    canvas = socket.assigns.canvas

    # Extract the field that was changed from params
    field_key =
      params
      |> Map.drop(["_target"])
      |> Map.keys()
      |> List.first()

    if field_key do
      value = Map.get(params, field_key, "")

      cell_field_map = %{
        "problem_content" => {"problem", "content"},
        "leverage_technology" => {"leverage", "technology"},
        "leverage_components" => {"leverage", "components"},
        "leverage_information" => {"leverage", "information"},
        "leverage_human_resources" => {"leverage", "human_resources"},
        "solution_cluster_content" => {"solution_cluster", "content"},
        "horizon_content" => {"horizon", "content"},
        "outer_environment_external_services" => {"outer_environment", "external_services"},
        "outer_environment_external_implements" => {"outer_environment", "external_implements"},
        "outer_environment_external_repositories" => {"outer_environment", "external_repositories"},
        "outer_environment_external_people" => {"outer_environment", "external_people"},
        "inner_environment_content" => {"inner_environment", "content"},
        "evolvability_cluster_evolvability" => {"evolvability_cluster", "evolvability"},
        "evolvability_cluster_diffusibility" => {"evolvability_cluster", "diffusibility"},
        "evolvability_cluster_adoptability" => {"evolvability_cluster", "adoptability"},
        "potential_content" => {"potential", "content"},
        "manifestations_content" => {"manifestations", "content"},
        "capabilities_content" => {"capabilities", "content"},
        "merit_cluster_merit" => {"merit_cluster", "merit"},
        "merit_cluster_value" => {"merit_cluster", "value"},
        "merit_cluster_reservation" => {"merit_cluster", "reservation"},
        "merit_cluster_rebuttal" => {"merit_cluster", "rebuttal"},
        "mission_content" => {"mission", "content"}
      }

      case Map.get(cell_field_map, field_key) do
        {cell_name, field_name} ->
          cell_atom = String.to_atom(cell_name)
          # Get existing cell or create a new struct of the correct type
          cell_data =
            case Map.get(canvas, cell_atom) do
              nil -> struct(cell_struct_module(cell_name))
              existing -> existing
            end

          field_atom = String.to_atom(field_name)
          updated_cell = Map.put(cell_data, field_atom, value)
          updated_canvas = Map.put(canvas, cell_atom, updated_cell)

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

        nil ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
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

  # Map cell names to their struct modules for instantiation
  defp cell_struct_module(cell_name) do
    case cell_name do
      "problem" -> Psc.Canvas.Problem
      "leverage" -> Psc.Canvas.Leverage
      "solution_cluster" -> Psc.Canvas.SolutionCluster
      "horizon" -> Psc.Canvas.Horizon
      "outer_environment" -> Psc.Canvas.OuterEnvironment
      "inner_environment" -> Psc.Canvas.InnerEnvironment
      "evolvability_cluster" -> Psc.Canvas.EvolvabilityCluster
      "potential" -> Psc.Canvas.Potential
      "manifestations" -> Psc.Canvas.Manifestations
      "capabilities" -> Psc.Canvas.Capabilities
      "merit_cluster" -> Psc.Canvas.MeritCluster
      "mission" -> Psc.Canvas.Mission
      _ -> nil
    end
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:noreply, handle_presence_change(socket, socket.assigns.canvas_id)}
  end

  @impl true
  def handle_info(:idle_save, socket) do
    if has_changes?(socket.assigns.canvas, socket.assigns.original_canvas) do
      Logger.debug("[IDLE SAVE] Saving changes for canvas_id: #{socket.assigns.canvas_id}")
      socket = assign(socket, save_state: :saving)
      canvas = socket.assigns.canvas
      attrs = build_canvas_update_attrs(canvas)

      case Canvas.update_canvas(canvas, attrs) do
        {:ok, updated_canvas} ->
          Logger.debug(fn -> "[IDLE SAVE SUCCESS] #{inspect(updated_canvas, limit: :infinity)}" end)
          {:noreply,
           socket
           |> assign(:original_canvas, updated_canvas)
           |> assign(:save_state, :saved)
           |> assign(:idle_timer_ref, nil)}

        {:error, error} ->
          Logger.error("[IDLE SAVE FAILED] Error: #{inspect(error)}")
          {:noreply,
           socket
           |> assign(:save_state, :unsaved)
           |> assign(:idle_timer_ref, nil)}
      end
    else
      Logger.debug("[IDLE SAVE] No changes detected, skipping save")
      {:noreply, assign(socket, :idle_timer_ref, nil)}
    end
  end

  @impl true
  def handle_info(:periodic_save, socket) do
    if has_changes?(socket.assigns.canvas, socket.assigns.original_canvas) do
      Logger.debug("[PERIODIC SAVE] Saving changes for canvas_id: #{socket.assigns.canvas_id}")
      attrs = build_canvas_update_attrs(socket.assigns.canvas)

      case Canvas.update_canvas(socket.assigns.canvas, attrs) do
        {:ok, updated_canvas} ->
          Logger.debug(fn -> "[PERIODIC SAVE SUCCESS] #{inspect(updated_canvas, limit: :infinity)}" end)
          :ok
        {:error, error} ->
          Logger.error("[PERIODIC SAVE FAILED] Error: #{inspect(error)}")
          :ok
      end
    else
      Logger.debug("[PERIODIC SAVE] No changes detected, skipping save")
    end

    Process.send_after(self(), :periodic_save, @periodic_save_interval)
    {:noreply, socket}
  end

  defp build_canvas_update_attrs(canvas) do
    attrs = %{name: canvas.name, description: canvas.description}
    |> Map.merge(
      [
        :problem, :leverage, :solution_cluster, :horizon,
        :outer_environment, :inner_environment, :evolvability_cluster,
        :potential, :manifestations, :capabilities, :merit_cluster, :mission
      ]
      |> Enum.reduce(%{}, fn cell_field, acc ->
        case Map.get(canvas, cell_field) do
          nil ->
            acc
          value ->
            # Convert struct to map for cast_embed (which expects maps, not structs)
            map_value = if is_struct(value), do: Map.from_struct(value), else: value
            Map.put(acc, cell_field, map_value)
        end
      end)
    )

    Logger.debug(fn -> "[BUILD ATTRS] Canvas ID: #{canvas.id}: #{inspect(attrs, limit: :infinity)}" end)
    attrs
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
              <.form for={%{}} id="canvas-form">
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
                        name="problem_content"
                        phx-change="update_cell"
                        class="w-full h-32 border border-gray-300 dark:border-gray-700 rounded px-2 py-1 text-sm resize-none text-gray-900 dark:text-gray-100 bg-white dark:bg-gray-800 placeholder-gray-400 dark:placeholder-gray-400"
                        placeholder="Describe the problem..."
                      ><%= Map.get(@canvas.problem || %{}, :content, "") %></textarea>
                    </td>
                    <%!-- Form: Leverage --%>
                    <td class="border border-gray-300 bg-white p-3">
                      <h3 class="text-sm font-bold text-gray-900 mb-2">Leverage</h3>
                      <div class="space-y-2 text-sm">
                        <input
                          type="text"
                          name="leverage_technology"
                          placeholder="Technology..."
                          value={Map.get(@canvas.leverage || %{}, :technology, "")}
                          phx-change="update_cell"
                          class="w-full border border-gray-300 dark:border-gray-700 rounded px-2 py-1 text-gray-900 dark:text-gray-100 bg-white dark:bg-gray-800 placeholder-gray-400 dark:placeholder-gray-400"
                        />
                        <input
                          type="text"
                          name="leverage_components"
                          placeholder="Components..."
                          value={Map.get(@canvas.leverage || %{}, :components, "")}
                          phx-change="update_cell"
                          class="w-full border border-gray-300 dark:border-gray-700 rounded px-2 py-1 text-gray-900 dark:text-gray-100 bg-white dark:bg-gray-800 placeholder-gray-400 dark:placeholder-gray-400"
                        />
                        <input
                          type="text"
                          name="leverage_information"
                          placeholder="Information..."
                          value={Map.get(@canvas.leverage || %{}, :information, "")}
                          phx-change="update_cell"
                          class="w-full border border-gray-300 dark:border-gray-700 rounded px-2 py-1 text-gray-900 dark:text-gray-100 bg-white dark:bg-gray-800 placeholder-gray-400 dark:placeholder-gray-400"
                        />
                        <input
                          type="text"
                          name="leverage_human_resources"
                          placeholder="Human Resources..."
                          value={Map.get(@canvas.leverage || %{}, :human_resources, "")}
                          phx-change="update_cell"
                          class="w-full border border-gray-300 rounded px-2 py-1 text-black"
                        />
                      </div>
                    </td>
                    <%!-- Consolidate: Solution Cluster --%>
                    <td class="border border-gray-300 bg-white p-3">
                      <h3 class="text-sm font-bold text-gray-900 mb-2">Solution</h3>
                      <textarea
                        name="solution_cluster_content"
                        phx-change="update_cell"
                        class="w-full h-32 border border-gray-300 dark:border-gray-700 rounded px-2 py-1 text-sm resize-none text-gray-900 dark:text-gray-100 bg-white dark:bg-gray-800 placeholder-gray-400 dark:placeholder-gray-400"
                        placeholder="Describe the solution..."
                      ><%= Map.get(@canvas.solution_cluster || %{}, :content, "") %></textarea>
                    </td>
                    <%!-- Learn: Horizon --%>
                    <td class="border border-gray-300 bg-white p-3">
                      <h3 class="text-sm font-bold text-gray-900 mb-2">Horizon</h3>
                      <textarea
                        name="horizon_content"
                        phx-change="update_cell"
                        class="w-full h-32 border border-gray-300 dark:border-gray-700 rounded px-2 py-1 text-sm resize-none text-gray-900 dark:text-gray-100 bg-white dark:bg-gray-800 placeholder-gray-400 dark:placeholder-gray-400"
                        placeholder="Describe the horizon..."
                      ><%= Map.get(@canvas.horizon || %{}, :content, "") %></textarea>
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
                          name="outer_environment_external_services"
                          placeholder="External Services..."
                          value={Map.get(@canvas.outer_environment || %{}, :external_services, "")}
                          phx-change="update_cell"
                          class="w-full border border-gray-300 rounded px-2 py-1 text-black"
                        />
                        <input
                          type="text"
                          name="outer_environment_external_implements"
                          placeholder="External Implements..."
                          value={Map.get(@canvas.outer_environment || %{}, :external_implements, "")}
                          phx-change="update_cell"
                          class="w-full border border-gray-300 rounded px-2 py-1 text-black"
                        />
                        <input
                          type="text"
                          name="outer_environment_external_repositories"
                          placeholder="External Repositories..."
                          value={Map.get(@canvas.outer_environment || %{}, :external_repositories, "")}
                          phx-change="update_cell"
                          class="w-full border border-gray-300 rounded px-2 py-1 text-black"
                        />
                        <input
                          type="text"
                          name="outer_environment_external_people"
                          placeholder="External People..."
                          value={Map.get(@canvas.outer_environment || %{}, :external_people, "")}
                          phx-change="update_cell"
                          class="w-full border border-gray-300 rounded px-2 py-1 text-black"
                        />
                      </div>
                    </td>
                    <%!-- Form: Inner Environment --%>
                    <td class="border border-gray-300 bg-white p-3">
                      <h3 class="text-sm font-bold text-gray-900 mb-2">Inner Environment</h3>
                      <textarea
                        name="inner_environment_content"
                        phx-change="update_cell"
                        class="w-full h-32 border border-gray-300 dark:border-gray-700 rounded px-2 py-1 text-sm resize-none text-gray-900 dark:text-gray-100 bg-white dark:bg-gray-800 placeholder-gray-400 dark:placeholder-gray-400"
                        placeholder="Describe the inner environment..."
                      ><%= Map.get(@canvas.inner_environment || %{}, :content, "") %></textarea>
                    </td>
                    <%!-- Consolidate: Evolvability Cluster --%>
                    <td class="border border-gray-300 bg-white p-3">
                      <h3 class="text-sm font-bold text-gray-900 mb-2">Evolvability</h3>
                      <div class="space-y-2 text-sm">
                        <input
                          type="text"
                          name="evolvability_cluster_evolvability"
                          placeholder="Evolvability..."
                          value={Map.get(@canvas.evolvability_cluster || %{}, :evolvability, "")}
                          phx-change="update_cell"
                          class="w-full border border-gray-300 dark:border-gray-700 rounded px-2 py-1 text-gray-900 dark:text-gray-100 bg-white dark:bg-gray-800 placeholder-gray-400 dark:placeholder-gray-400"
                        />
                        <input
                          type="text"
                          name="evolvability_cluster_diffusibility"
                          placeholder="Diffusibility..."
                          value={Map.get(@canvas.evolvability_cluster || %{}, :diffusibility, "")}
                          phx-change="update_cell"
                          class="w-full border border-gray-300 dark:border-gray-700 rounded px-2 py-1 text-gray-900 dark:text-gray-100 bg-white dark:bg-gray-800 placeholder-gray-400 dark:placeholder-gray-400"
                        />
                        <input
                          type="text"
                          name="evolvability_cluster_adoptability"
                          placeholder="Adoptability..."
                          value={Map.get(@canvas.evolvability_cluster || %{}, :adoptability, "")}
                          phx-change="update_cell"
                          class="w-full border border-gray-300 rounded px-2 py-1 text-black"
                        />
                      </div>
                    </td>
                    <%!-- Learn: Potential --%>
                    <td class="border border-gray-300 bg-white p-3">
                      <h3 class="text-sm font-bold text-gray-900 mb-2">Potential</h3>
                      <textarea
                        name="potential_content"
                        phx-change="update_cell"
                        class="w-full h-32 border border-gray-300 dark:border-gray-700 rounded px-2 py-1 text-sm resize-none text-gray-900 dark:text-gray-100 bg-white dark:bg-gray-800 placeholder-gray-400 dark:placeholder-gray-400"
                        placeholder="Describe the potential..."
                      ><%= Map.get(@canvas.potential || %{}, :content, "") %></textarea>
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
                        name="manifestations_content"
                        phx-change="update_cell"
                        class="w-full h-32 border border-gray-300 dark:border-gray-700 rounded px-2 py-1 text-sm resize-none text-gray-900 dark:text-gray-100 bg-white dark:bg-gray-800 placeholder-gray-400 dark:placeholder-gray-400"
                        placeholder="Describe the manifestations..."
                      ><%= Map.get(@canvas.manifestations || %{}, :content, "") %></textarea>
                    </td>
                    <%!-- Form: Capabilities --%>
                    <td class="border border-gray-300 bg-white p-3">
                      <h3 class="text-sm font-bold text-gray-900 mb-2">Capabilities</h3>
                      <textarea
                        name="capabilities_content"
                        phx-change="update_cell"
                        class="w-full h-32 border border-gray-300 dark:border-gray-700 rounded px-2 py-1 text-sm resize-none text-gray-900 dark:text-gray-100 bg-white dark:bg-gray-800 placeholder-gray-400 dark:placeholder-gray-400"
                        placeholder="Describe the capabilities..."
                      ><%= Map.get(@canvas.capabilities || %{}, :content, "") %></textarea>
                    </td>
                    <%!-- Consolidate: Merit Cluster --%>
                    <td class="border border-gray-300 bg-white p-3">
                      <h3 class="text-sm font-bold text-gray-900 mb-2">Merit</h3>
                      <div class="space-y-2 text-sm">
                        <input
                          type="text"
                          name="merit_cluster_merit"
                          placeholder="Merit..."
                          value={Map.get(@canvas.merit_cluster || %{}, :merit, "")}
                          phx-change="update_cell"
                          class="w-full border border-gray-300 dark:border-gray-700 rounded px-2 py-1 text-gray-900 dark:text-gray-100 bg-white dark:bg-gray-800 placeholder-gray-400 dark:placeholder-gray-400"
                        />
                        <input
                          type="text"
                          name="merit_cluster_value"
                          placeholder="Value..."
                          value={Map.get(@canvas.merit_cluster || %{}, :value, "")}
                          phx-change="update_cell"
                          class="w-full border border-gray-300 rounded px-2 py-1 text-black"
                        />
                        <input
                          type="text"
                          name="merit_cluster_reservation"
                          placeholder="Reservation..."
                          value={Map.get(@canvas.merit_cluster || %{}, :reservation, "")}
                          phx-change="update_cell"
                          class="w-full border border-gray-300 rounded px-2 py-1 text-black"
                        />
                        <input
                          type="text"
                          name="merit_cluster_rebuttal"
                          placeholder="Rebuttal..."
                          value={Map.get(@canvas.merit_cluster || %{}, :rebuttal, "")}
                          phx-change="update_cell"
                          class="w-full border border-gray-300 rounded px-2 py-1 text-black"
                        />
                      </div>
                    </td>
                    <%!-- Learn: Mission --%>
                    <td class="border border-gray-300 bg-white p-3">
                      <h3 class="text-sm font-bold text-gray-900 mb-2">Mission</h3>
                      <textarea
                        name="mission_content"
                        phx-change="update_cell"
                        class="w-full h-32 border border-gray-300 dark:border-gray-700 rounded px-2 py-1 text-sm resize-none text-gray-900 dark:text-gray-100 bg-white dark:bg-gray-800 placeholder-gray-400 dark:placeholder-gray-400"
                        placeholder="Describe the mission..."
                      ><%= Map.get(@canvas.mission || %{}, :content, "") %></textarea>
                    </td>
                  </tr>
                </tbody>
              </table>
              </.form>
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
