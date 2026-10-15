defmodule PscWeb.CanvasLayoutLive.Editor do
  use PscWeb, :live_view

  # Qualified SaladUI aliases (house pattern) — CoreComponents' button/1 etc.
  # would collide with unqualified imports.
  alias PscWeb.Components.UI.Button, as: UIButton
  alias PscWeb.Components.UI.Input, as: UIInput
  alias PscWeb.Components.UI.Badge, as: UIBadge
  alias PscWeb.Components.UI.Textarea, as: UITextarea
  alias PscWeb.Components.UI.Label, as: UILabel

  alias Psc.Canvas

  @semantics_options ["free", "problem", "solution", "evidence", "note"]

  @impl true
  def mount(params, _session, socket) do
    user = socket.assigns.current_scope.user

    case Map.get(params, "id") do
      nil ->
        {:ok,
         socket
         |> assign(:layout_map, empty_layout_map())
         |> assign(:template_form, to_form(%{}))
         |> assign(:editing_layout, nil)
         |> assign(:owner?, true)
         |> assign(:share_form_open, false)
         |> assign(:semantics_options, @semantics_options)
         |> assign(:selected_cell, nil)}

      id ->
        case Canvas.get_template_with_author(id) do
          %{} = template ->
            if Canvas.can_access_template?(template, user.email) do
              owner? = template.author_id == user.id

              {:ok,
               socket
               |> assign(:layout_map, normalize_layout_map(template.layout_map || %{}))
               |> assign(
                 :template_form,
                 to_form(%{"name" => template.name, "description" => template.description})
               )
               |> assign(:editing_layout, template)
               |> assign(:owner?, owner?)
               |> assign(:share_form_open, false)
               |> assign(:semantics_options, @semantics_options)
               |> assign(:selected_cell, nil)}
            else
              {:ok,
               socket
               |> put_flash(:error, "Template not found")
               |> redirect(to: ~p"/canvas-layouts")}
            end

          _ ->
            {:ok,
             socket
             |> put_flash(:error, "Template not found")
             |> redirect(to: ~p"/canvas-layouts")}
        end
    end
  end

  # ─── Grid structure events (owner only) ───

  @impl true
  def handle_event("add_column", _params, socket) do
    {:noreply, update_layout(socket, &add_column/1)}
  end

  def handle_event("remove_column", %{"index" => index}, socket) do
    {:noreply, update_layout(socket, &remove_column(&1, String.to_integer(index)))}
  end

  def handle_event("update_column_label", %{"index" => index, "label" => label}, socket) do
    {:noreply, update_layout(socket, &update_column_label(&1, String.to_integer(index), label))}
  end

  def handle_event("add_row", _params, socket) do
    {:noreply, update_layout(socket, &add_row/1)}
  end

  def handle_event("remove_row", %{"index" => index}, socket) do
    {:noreply, update_layout(socket, &remove_row(&1, String.to_integer(index)))}
  end

  def handle_event("update_row_label", %{"index" => index, "label" => label}, socket) do
    {:noreply, update_layout(socket, &update_row_label(&1, String.to_integer(index), label))}
  end

  # ─── Cell metadata events (owner only) ───

  @impl true
  def handle_event("select_cell", %{"cell_key" => cell_key}, socket) do
    selected = if socket.assigns.selected_cell == cell_key, do: nil, else: cell_key
    {:noreply, assign(socket, :selected_cell, selected)}
  end

  def handle_event(
        "update_cell_meta",
        %{"cell_key" => cell_key, "field" => field, "value" => value},
        socket
      ) do
    {:noreply,
     update_layout(socket, fn lm ->
       cells = lm["cells"] || %{}
       cell = Map.get(cells, cell_key, empty_cell_meta())
       Map.put(lm, "cells", Map.put(cells, cell_key, Map.put(cell, field, value)))
     end)}
  end

  def handle_event("add_cell_field", %{"cell_key" => cell_key, "field" => field}, socket) do
    field = String.trim(field)

    if field == "" do
      {:noreply, put_flash(socket, :error, "Field name required")}
    else
      {:noreply,
       update_layout(socket, fn lm ->
         cells = lm["cells"] || %{}
         cell = Map.get(cells, cell_key, empty_cell_meta())
         fields = cell["fields"] || []

         if field in fields do
           lm
         else
           new_cell =
             cell
             |> Map.put("fields", fields ++ [field])
             |> Map.update("defaults", %{}, &Map.put_new(&1, field, ""))

           Map.put(lm, "cells", Map.put(cells, cell_key, new_cell))
         end
       end)}
    end
  end

  def handle_event("remove_cell_field", %{"cell_key" => cell_key, "field" => field}, socket) do
    {:noreply,
     update_layout(socket, fn lm ->
       cells = lm["cells"] || %{}
       cell = Map.get(cells, cell_key, empty_cell_meta())

       new_cell =
         cell
         |> Map.update("fields", [], &List.delete(&1, field))
         |> Map.update("defaults", %{}, &Map.delete(&1, field))

       Map.put(lm, "cells", Map.put(cells, cell_key, new_cell))
     end)}
  end

  def handle_event(
        "update_cell_field_default",
        %{"cell_key" => cell_key, "field" => field, "value" => value},
        socket
      ) do
    {:noreply,
     update_layout(socket, fn lm ->
       cells = lm["cells"] || %{}
       cell = Map.get(cells, cell_key, empty_cell_meta())
       defaults = Map.put(cell["defaults"] || %{}, field, value)
       Map.put(lm, "cells", Map.put(cells, cell_key, Map.put(cell, "defaults", defaults)))
     end)}
  end

  # ─── Relations events (owner only) ───

  @impl true
  def handle_event(
        "add_relation",
        %{"from" => from, "to" => to, "label" => label},
        socket
      ) do
    if from == "" or to == "" or from == to do
      {:noreply, put_flash(socket, :error, "Select a source and a different target cell")}
    else
      {:noreply,
       update_layout(socket, fn lm ->
         relations = lm["relations"] || []
         rel = %{"from" => from, "to" => to, "label" => String.trim(label)}
         Map.put(lm, "relations", relations ++ [rel])
       end)}
    end
  end

  @impl true
  def handle_event("remove_relation", %{"index" => index}, socket) do
    idx = String.to_integer(index)

    {:noreply,
     update_layout(socket, fn lm ->
       Map.put(lm, "relations", List.delete_at(lm["relations"] || [], idx))
     end)}
  end

  # ─── Save / share events ───

  @impl true
  def handle_event("save_template", %{"name" => name, "description" => description}, socket) do
    user = socket.assigns.current_scope.user

    attrs = %{
      "name" => name,
      "description" => description,
      "layout_map" => socket.assigns.layout_map
    }

    result =
      case socket.assigns.editing_layout do
        nil -> Canvas.create_template(user.id, attrs)
        template -> Canvas.update_template(template, attrs)
      end

    case result do
      {:ok, _template} ->
        {:noreply,
         socket
         |> put_flash(:info, "Template saved")
         |> redirect(to: ~p"/canvas-layouts")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to save template")}
    end
  end

  @impl true
  def handle_event("toggle_share_form", _params, socket) do
    {:noreply, update(socket, :share_form_open, &(!&1))}
  end

  @impl true
  def handle_event("share_template", %{"email" => email}, socket) do
    case Canvas.share_template_with(socket.assigns.editing_layout, String.downcase(email)) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:editing_layout, Canvas.get_template_with_author(updated.id))
         |> put_flash(:info, "Template shared with #{email}")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to share template")}
    end
  end

  @impl true
  def handle_event("unshare_template", %{"email" => email}, socket) do
    case Canvas.unshare_template(socket.assigns.editing_layout, email) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:editing_layout, Canvas.get_template_with_author(updated.id))
         |> put_flash(:info, "Access removed for #{email}")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to remove access")}
    end
  end

  # ─── Layout map helpers ───

  defp update_layout(socket, fun) do
    assign(socket, :layout_map, fun.(socket.assigns.layout_map))
  end

  defp empty_layout_map do
    %{"rows" => [], "columns" => [], "layout" => [], "cells" => %{}, "relations" => []}
  end

  defp empty_cell_meta do
    %{
      "label" => "",
      "semantics" => "free",
      "fields" => ["content"],
      "defaults" => %{"content" => ""}
    }
  end

  # Normalizes a stored layout_map into the current shape and guarantees
  # consistency: the matrix is rebuilt strictly from rows × columns,
  # preserving existing cell keys where present and generating
  # "#{row_id}_#{column_id}" keys elsewhere.
  defp normalize_layout_map(lm) do
    lm =
      lm
      |> Map.put_new("rows", [])
      |> Map.put_new("columns", [])
      |> Map.put_new("layout", [])
      |> Map.put_new("cells", %{})
      |> Map.put_new("relations", [])

    rows = lm["rows"]
    columns = lm["columns"]
    stored = lm["layout"] || []

    matrix =
      for {row_meta, ri} <- Enum.with_index(rows) do
        for {col_meta, ci} <- Enum.with_index(columns) do
          existing = Enum.at(Enum.at(stored, ri, []), ci)

          if is_binary(existing) and existing != "" do
            existing
          else
            "#{row_meta["id"]}_#{col_meta["id"]}"
          end
        end
      end

    cells =
      matrix
      |> List.flatten()
      |> Enum.reduce(lm["cells"], fn key, acc ->
        Map.put_new(acc, key, empty_cell_meta())
      end)

    lm |> Map.put("layout", matrix) |> Map.put("cells", cells)
  end

  defp add_column(lm) do
    idx = length(lm["columns"]) + 1
    columns = lm["columns"] ++ [%{"id" => "c#{idx}", "label" => "Column #{idx}"}]
    Map.put(lm, "columns", columns) |> normalize_layout_map()
  end

  defp remove_column(lm, idx) do
    columns = List.delete_at(lm["columns"], idx)
    matrix = Enum.map(lm["layout"] || [], fn row -> List.delete_at(row, idx) end)
    lm |> Map.put("columns", columns) |> Map.put("layout", matrix) |> normalize_layout_map()
  end

  defp update_column_label(lm, idx, label) do
    columns = List.update_at(lm["columns"], idx, &Map.put(&1, "label", label))
    Map.put(lm, "columns", columns)
  end

  defp add_row(lm) do
    idx = length(lm["rows"]) + 1
    rows = lm["rows"] ++ [%{"id" => "r#{idx}", "label" => "Row #{idx}"}]
    Map.put(lm, "rows", rows) |> normalize_layout_map()
  end

  defp remove_row(lm, idx) do
    rows = List.delete_at(lm["rows"], idx)
    matrix = List.delete_at(lm["layout"] || [], idx)
    lm |> Map.put("rows", rows) |> Map.put("layout", matrix) |> normalize_layout_map()
  end

  defp update_row_label(lm, idx, label) do
    rows = List.update_at(lm["rows"], idx, &Map.put(&1, "label", label))
    Map.put(lm, "rows", rows)
  end

  defp all_cell_keys(lm) do
    (lm["layout"] || []) |> List.flatten() |> Enum.reject(&is_nil/1)
  end

  defp cell_label(lm, key) do
    get_in(lm, ["cells", key, "label"])
    |> case do
      nil -> key
      "" -> key
      label -> label
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      container_class="w-full mx-auto max-w-screen-xl"
    >
      <div class="px-4 py-8">
        <div class="flex items-center justify-between mb-6">
          <h1 class="text-2xl font-semibold text-base-content">
            {if @editing_layout, do: "Edit Template", else: "New Template"}
          </h1>
          <div class="flex items-center gap-2">
            <%= if @owner? do %>
              <UIButton.button phx-click="toggle_share_form" variant="ghost" size="sm">
                Share
              </UIButton.button>
            <% end %>
            <.link
              navigate={~p"/canvas-layouts"}
              class="inline-flex items-center px-3 py-1.5 text-sm rounded-lg border border-white/10 text-base-content hover:bg-white/5 transition-colors"
            >
              Back to Templates
            </.link>
          </div>
        </div>

        <%= if @editing_layout && !@owner? do %>
          <div class="mb-6 p-3 rounded-lg border border-white/10 bg-base-200 text-sm text-base-content/60">
            You have read-only access to this template. Ask the owner to make changes.
          </div>
        <% end %>

        <%= if @share_form_open && @owner? do %>
          <div class="mb-6 p-4 rounded-xl border border-white/10 bg-base-200">
            <h2 class="text-sm font-medium text-base-content mb-3">Share Template</h2>
            <form phx-submit="share_template" class="flex gap-2 max-w-md">
              <UIInput.input
                type="email"
                name="email"
                placeholder="user@example.com"
                required
                class="flex-1"
              />
              <UIButton.button type="submit" size="sm">Share</UIButton.button>
            </form>
            <%= if length(@editing_layout.shared_with || []) > 0 do %>
              <ul class="mt-3 space-y-1">
                <%= for email <- @editing_layout.shared_with do %>
                  <li class="flex items-center justify-between text-xs text-base-content/60 max-w-md">
                    <span>{email}</span>
                    <button
                      type="button"
                      phx-click="unshare_template"
                      phx-value-email={email}
                      class="text-error hover:underline"
                    >
                      Remove
                    </button>
                  </li>
                <% end %>
              </ul>
            <% end %>
          </div>
        <% end %>

        <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <div class="lg:col-span-2 space-y-6">
            <.form
              for={@template_form}
              id="template-form"
              phx-submit="save_template"
              class="p-6 rounded-xl border border-white/10 bg-base-200 space-y-4"
            >
              <div>
                <UILabel.label for="template-name">Template Name</UILabel.label>
                <UIInput.input
                  field={@template_form[:name]}
                  type="text"
                  required
                  disabled={!@owner?}
                />
              </div>
              <div>
                <UILabel.label for="template-description">Description</UILabel.label>
                <UITextarea.textarea
                  field={@template_form[:description]}
                  rows="2"
                  disabled={!@owner?}
                />
              </div>
              <%= if @owner? do %>
                <div class="flex justify-end">
                  <UIButton.button type="submit">Save Template</UIButton.button>
                </div>
              <% end %>
            </.form>

            <div class="p-6 rounded-xl border border-white/10 bg-base-200">
              <div class="flex items-center justify-between mb-4">
                <h2 class="text-sm font-medium text-base-content">Grid</h2>
                <%= if @owner? do %>
                  <div class="flex gap-2">
                    <UIButton.button variant="outline" size="sm" phx-click="add_column">
                      Add Column
                    </UIButton.button>
                    <UIButton.button variant="outline" size="sm" phx-click="add_row">
                      Add Row
                    </UIButton.button>
                  </div>
                <% end %>
              </div>

              <%= if Enum.empty?(@layout_map["rows"]) or Enum.empty?(@layout_map["columns"]) do %>
                <p class="text-sm text-base-content/50">
                  Add at least one row and one column to start building your template.
                </p>
              <% else %>
                <div class="overflow-auto">
                  <table class="w-full border-collapse table-fixed text-sm">
                    <thead>
                      <tr>
                        <th class="w-40 p-2 border border-white/10"></th>
                        <%= for {col, ci} <- Enum.with_index(@layout_map["columns"]) do %>
                          <th class="p-2 border border-white/10 bg-white/5 text-base-content/70">
                            <div class="flex items-center gap-1">
                              <input
                                type="text"
                                value={col["label"]}
                                phx-change="update_column_label"
                                phx-debounce="300"
                                phx-value-index={ci}
                                name="label"
                                disabled={!@owner?}
                                class="w-full px-2 py-1 rounded bg-transparent border border-transparent hover:border-white/10 focus:border-primary text-inherit"
                              />
                              <%= if @owner? do %>
                                <button
                                  type="button"
                                  phx-click="remove_column"
                                  phx-value-index={ci}
                                  class="text-error shrink-0"
                                  title="Remove column"
                                >
                                  &times;
                                </button>
                              <% end %>
                            </div>
                          </th>
                        <% end %>
                      </tr>
                    </thead>
                    <tbody>
                      <%= for {row_meta, ri} <- Enum.with_index(@layout_map["rows"]) do %>
                        <tr>
                          <td class="p-2 border border-white/10 bg-white/5 align-top">
                            <input
                              type="text"
                              value={row_meta["label"]}
                              phx-change="update_row_label"
                              phx-debounce="300"
                              phx-value-index={ri}
                              name="label"
                              disabled={!@owner?}
                              class="w-full px-2 py-1 rounded bg-transparent border border-transparent hover:border-white/10 focus:border-primary text-inherit"
                            />
                            <%= if @owner? do %>
                              <button
                                type="button"
                                phx-click="remove_row"
                                phx-value-index={ri}
                                class="mt-2 text-xs text-error"
                              >
                                Remove Row
                              </button>
                            <% end %>
                          </td>
                          <%= for cell_key <- Enum.at(@layout_map["layout"], ri, []) do %>
                            <td class="p-2 border border-white/10 align-top">
                              <button
                                type="button"
                                phx-click="select_cell"
                                phx-value-cell_key={cell_key}
                                class={[
                                  "w-full text-left rounded-lg p-2 transition-colors",
                                  @selected_cell == cell_key && "bg-primary/10 ring-1 ring-primary",
                                  @selected_cell != cell_key && "hover:bg-white/5"
                                ]}
                              >
                                <div class="font-medium text-base-content">
                                  {cell_label(@layout_map, cell_key)}
                                </div>
                                <div class="flex flex-wrap gap-1 mt-1">
                                  <%= for field <- get_in(@layout_map, ["cells", cell_key, "fields"]) || [] do %>
                                    <UIBadge.badge variant="secondary" class="text-xs">
                                      {field}
                                    </UIBadge.badge>
                                  <% end %>
                                </div>
                              </button>
                            </td>
                          <% end %>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </div>
              <% end %>
            </div>

            <div class="p-6 rounded-xl border border-white/10 bg-base-200">
              <h2 class="text-sm font-medium text-base-content mb-4">Relations</h2>
              <%= if Enum.empty?(@layout_map["relations"]) do %>
                <p class="text-sm text-base-content/50 mb-4">No relations defined yet.</p>
              <% else %>
                <ul class="space-y-2 mb-4">
                  <%= for {rel, idx} <- Enum.with_index(@layout_map["relations"]) do %>
                    <li class="flex items-center justify-between text-sm text-base-content">
                      <span>
                        {cell_label(@layout_map, rel["from"])}
                        <span class="text-base-content/40">&rarr;</span>
                        {cell_label(@layout_map, rel["to"])}
                        <%= if rel["label"] not in [nil, ""] do %>
                          <UIBadge.badge variant="outline" class="ml-2 text-xs">
                            {rel["label"]}
                          </UIBadge.badge>
                        <% end %>
                      </span>
                      <%= if @owner? do %>
                        <button
                          type="button"
                          phx-click="remove_relation"
                          phx-value-index={idx}
                          class="text-error text-xs"
                        >
                          Remove
                        </button>
                      <% end %>
                    </li>
                  <% end %>
                </ul>
              <% end %>
              <%= if @owner? do %>
                <form phx-submit="add_relation" class="flex flex-wrap items-center gap-2">
                  <select
                    name="from"
                    class="px-2 py-1.5 rounded-lg bg-base-300 border border-white/10 text-sm text-base-content"
                  >
                    <option value="">From cell...</option>
                    <%= for key <- all_cell_keys(@layout_map) do %>
                      <option value={key}>{cell_label(@layout_map, key)}</option>
                    <% end %>
                  </select>
                  <span class="text-base-content/40">&rarr;</span>
                  <select
                    name="to"
                    class="px-2 py-1.5 rounded-lg bg-base-300 border border-white/10 text-sm text-base-content"
                  >
                    <option value="">To cell...</option>
                    <%= for key <- all_cell_keys(@layout_map) do %>
                      <option value={key}>{cell_label(@layout_map, key)}</option>
                    <% end %>
                  </select>
                  <input
                    type="text"
                    name="label"
                    placeholder="Label (optional)"
                    class="px-2 py-1.5 rounded-lg bg-base-300 border border-white/10 text-sm text-base-content"
                  />
                  <UIButton.button type="submit" variant="outline" size="sm">
                    Add Relation
                  </UIButton.button>
                </form>
              <% end %>
            </div>
          </div>

          <div>
            <%= if @selected_cell do %>
              <div class="p-6 rounded-xl border border-white/10 bg-base-200 sticky top-6">
                <h2 class="text-sm font-medium text-base-content mb-4">
                  Cell: {cell_label(@layout_map, @selected_cell)}
                </h2>
                <div class="space-y-4">
                  <div>
                    <UILabel.label>Label</UILabel.label>
                    <UIInput.input
                      type="text"
                      value={get_in(@layout_map, ["cells", @selected_cell, "label"])}
                      phx-change="update_cell_meta"
                      phx-debounce="300"
                      phx-value-cell_key={@selected_cell}
                      phx-value-field="label"
                      name="value"
                      disabled={!@owner?}
                    />
                  </div>
                  <div>
                    <UILabel.label>Semantics</UILabel.label>
                    <select
                      phx-change="update_cell_meta"
                      phx-value-cell_key={@selected_cell}
                      phx-value-field="semantics"
                      name="value"
                      disabled={!@owner?}
                      class="w-full px-3 py-2 rounded-lg bg-base-300 border border-white/10 text-sm text-base-content"
                    >
                      <%= for opt <- @semantics_options do %>
                        <option
                          value={opt}
                          selected={
                            get_in(@layout_map, ["cells", @selected_cell, "semantics"]) == opt
                          }
                        >
                          {String.capitalize(opt)}
                        </option>
                      <% end %>
                    </select>
                  </div>

                  <div>
                    <UILabel.label>Fields</UILabel.label>
                    <ul class="mt-2 space-y-2">
                      <%= for field <- get_in(@layout_map, ["cells", @selected_cell, "fields"]) || [] do %>
                        <li class="flex items-center gap-2">
                          <span class="text-sm text-base-content w-1/3">{field}</span>
                          <UIInput.input
                            type="text"
                            value={get_in(@layout_map, ["cells", @selected_cell, "defaults", field])}
                            phx-change="update_cell_field_default"
                            phx-debounce="300"
                            phx-value-cell_key={@selected_cell}
                            phx-value-field={field}
                            name="value"
                            placeholder="Default value"
                            disabled={!@owner?}
                            class="flex-1"
                          />
                          <%= if @owner? do %>
                            <button
                              type="button"
                              phx-click="remove_cell_field"
                              phx-value-cell_key={@selected_cell}
                              phx-value-field={field}
                              class="text-error shrink-0"
                            >
                              &times;
                            </button>
                          <% end %>
                        </li>
                      <% end %>
                    </ul>
                    <%= if @owner? do %>
                      <form phx-submit="add_cell_field" class="mt-3 flex gap-2">
                        <input type="hidden" name="cell_key" value={@selected_cell} />
                        <input
                          type="text"
                          name="field"
                          placeholder="New field name"
                          class="flex-1 px-2 py-1.5 rounded-lg bg-base-300 border border-white/10 text-sm text-base-content"
                        />
                        <UIButton.button type="submit" variant="outline" size="sm">
                          Add
                        </UIButton.button>
                      </form>
                    <% end %>
                  </div>
                </div>
              </div>
            <% else %>
              <div class="p-6 rounded-xl border border-white/10 bg-base-200 text-sm text-base-content/50">
                Select a cell in the grid to edit its label, semantics, and fields.
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
