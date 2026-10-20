defmodule PscWeb.CatalogLive.Index do
  @moduledoc """
  The catalog: the public face of the template library.

  A template its owner marked public is listed here, ranked by how many times it
  has been used. A card opens a modal with the template's details and a picture
  of its grid; the actions on it live with the modal too.
  """

  use PscWeb, :live_view

  alias Psc.Canvas
  alias PscWeb.Components.UI.Dialog, as: UIDialog

  @impl true
  def mount(_params, _session, socket) do
    templates = Canvas.list_public_templates()

    socket =
      socket
      |> assign(:query, "")
      |> assign(:search_form, to_form(%{}))
      |> assign(:open_template, nil)
      |> assign(:forked_from_name, nil)
      |> assign(:truncated?, truncated?(templates))
      |> stream(:templates, templates)

    {:ok, socket}
  end

  @impl true
  def handle_event("search", %{"q" => query} = params, socket) do
    query = String.trim(query || "")
    templates = Canvas.list_public_templates(query)

    {:noreply,
     socket
     |> assign(:query, query)
     |> assign(:search_form, to_form(params))
     |> assign(:truncated?, truncated?(templates))
     |> stream(:templates, templates, reset: true)}
  end

  def handle_event("open_template", %{"id" => id}, socket) do
    template = Canvas.get_public_template(id)

    {:noreply,
     socket
     |> assign(:open_template, template)
     |> assign(:forked_from_name, forked_from_name(template))}
  end

  def handle_event("close_template", _params, socket) do
    {:noreply, assign(socket, :open_template, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      header_title="Catalog"
      container_class="w-full"
    >
      <div class="mx-auto flex w-full max-w-6xl min-w-0 flex-col gap-4">
        <.form for={@search_form} id="catalog-search" phx-change="search" phx-debounce="300">
          <.input
            field={@search_form[:q]}
            type="search"
            placeholder="Search templates…"
            aria-label="Search templates"
          />
        </.form>

        <div
          id="catalog-grid"
          phx-update="stream"
          class="grid grid-cols-1 gap-4 md:grid-cols-2 lg:grid-cols-3"
        >
          <div
            id="catalog-empty-state"
            class="hidden only:block rounded-xl border border-dashed border-base-content/20 bg-base-200 p-8 text-center md:col-span-2 lg:col-span-3"
          >
            <p class="text-base-content/60">No public templates yet.</p>

            <p class="mt-1 text-sm text-base-content/45">
              Publish one from the template designer to put it here.
            </p>
          </div>

          <div
            :for={{id, template} <- @streams.templates}
            id={id}
            class="flex flex-col rounded-xl border border-base-content/10 bg-base-200 p-4 text-left transition-colors hover:border-base-content/25 hover:bg-base-content/5"
          >
            <button
              type="button"
              phx-click="open_template"
              phx-value-id={template.id}
              class="flex min-w-0 flex-1 flex-col items-start gap-2 text-left"
              aria-label={"Details for #{template.name}"}
            >
              <span class="break-words font-medium text-base-content">{template.name}</span>
              <span
                :if={template.description not in [nil, ""]}
                class="line-clamp-2 break-words text-sm text-base-content/60"
              >
                {template.description}
              </span>

              <span class="flex items-center gap-2 text-xs text-base-content/50">
                <span>{length(template.layout_map["rows"] || [])} rows</span> <span>&times;</span>
                <span>{length(template.layout_map["columns"] || [])} columns</span>
              </span>
            </button>

            <div class="mt-3 flex items-center justify-between gap-2 border-t border-base-content/10 pt-3 text-xs text-base-content/50">
              <span class="truncate">{author_handle(template)}</span>
              <span class="shrink-0">
                Used {template.use_count} · Forked {template.fork_count}
              </span>
            </div>
          </div>
        </div>

        <p :if={@truncated?} class="text-xs text-base-content/45">
          Showing the top {Canvas.catalog_limit()} by use — the catalog is a ranking, not an
          index. Narrow it with the search.
        </p>
      </div>

      <UIDialog.dialog
        :if={@open_template}
        id="catalog-template-dialog"
        open
        on-close="close_template"
      >
        <UIDialog.dialog_content class="sm:max-w-lg">
          <UIDialog.dialog_header class="min-w-0">
            <UIDialog.dialog_title class="break-words">{@open_template.name}</UIDialog.dialog_title>
            
            <UIDialog.dialog_description
              :if={@open_template.description not in [nil, ""]}
              class="break-words"
            >
              {@open_template.description}
            </UIDialog.dialog_description>
          </UIDialog.dialog_header>
          
          <dl class="grid min-w-0 grid-cols-2 gap-x-4 gap-y-2 text-sm">
            <div>
              <dt class="text-xs uppercase tracking-wide text-base-content/45">By</dt>

              <dd class="text-base-content">{author_handle(@open_template)}</dd>
            </div>

            <div>
              <dt class="text-xs uppercase tracking-wide text-base-content/45">Updated</dt>

              <dd class="text-base-content">{date(@open_template.updated_at)}</dd>
            </div>

            <div>
              <dt class="text-xs uppercase tracking-wide text-base-content/45">Grid</dt>

              <dd class="text-base-content">
                {length(@open_template.layout_map["rows"] || [])} rows × {length(
                  @open_template.layout_map["columns"] || []
                )} columns
              </dd>
            </div>

            <div>
              <dt class="text-xs uppercase tracking-wide text-base-content/45">Cells</dt>

              <dd class="text-base-content">{cell_count(@open_template)}</dd>
            </div>

            <div>
              <dt class="text-xs uppercase tracking-wide text-base-content/45">Used</dt>

              <dd class="text-base-content">{@open_template.use_count}</dd>
            </div>

            <div>
              <dt class="text-xs uppercase tracking-wide text-base-content/45">Forked</dt>

              <dd class="text-base-content">{@open_template.fork_count}</dd>
            </div>
          </dl>

          <p :if={@forked_from_name} class="min-w-0 break-words text-xs text-base-content/50">
            Forked from {@forked_from_name}
          </p>
          <.grid_preview template={@open_template} />
        </UIDialog.dialog_content>
      </UIDialog.dialog>
    </Layouts.app>
    """
  end

  # A template's author is shown by the handle in front of their email: the
  # catalog is public to every signed-in user, and an email address is more of
  # them than a catalog needs to give away.
  defp author_handle(%{author: %{email: email}}) when is_binary(email) do
    email |> String.split("@") |> List.first()
  end

  defp author_handle(_template), do: "Unknown"

  defp date(datetime) when is_struct(datetime, NaiveDateTime) or is_struct(datetime, DateTime) do
    Calendar.strftime(datetime, "%d %b %Y")
  end

  defp date(_datetime), do: "—"

  defp cell_count(template) do
    template.layout_map |> Map.get("cells", %{}) |> map_size()
  end

  defp forked_from_name(%{forked_from_id: forked_from_id})
       when is_binary(forked_from_id) and forked_from_id != "" do
    case Canvas.get_canvas_layout(forked_from_id) do
      %{name: name} -> name
      _ -> nil
    end
  end

  defp forked_from_name(_template), do: nil

  defp truncated?(templates), do: length(templates) >= Canvas.catalog_limit()

  # A picture of what a canvas from this template will look like: the grid with
  # its cell labels. The designer's table is an editor; this is the detail a
  # user needs before choosing between two templates.
  attr :template, :map, required: true

  defp grid_preview(assigns) do
    ~H"""
    <div class="min-w-0 overflow-auto rounded-lg border border-base-content/10 bg-base-200/60">
      <table class="w-full table-fixed border-collapse text-xs">
        <thead>
          <tr>
            <th class="w-16 border border-base-content/10 p-1"></th>

            <th
              :for={column <- @template.layout_map["columns"] || []}
              class="border border-base-content/10 bg-base-content/5 p-1 font-medium text-base-content/70"
            >
              {column["label"]}
            </th>
          </tr>
        </thead>

        <tbody>
          <tr :for={{row, ri} <- Enum.with_index(@template.layout_map["rows"] || [])}>
            <th class="border border-base-content/10 bg-base-content/5 p-1 text-left font-medium text-base-content/70">
              {row["label"]}
            </th>

            <td
              :for={cell_key <- cell_keys(@template, ri)}
              class="border border-base-content/10 p-1 text-base-content/80"
            >
              {cell_label(@template, cell_key)}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp cell_keys(template, row_index) do
    template.layout_map |> Map.get("layout", []) |> Enum.at(row_index, [])
  end

  defp cell_label(template, cell_key) do
    label =
      template.layout_map
      |> Map.get("cells", %{})
      |> Map.get(cell_key, %{})
      |> Map.get("label", "")

    if label in [nil, ""], do: cell_key, else: label
  end
end
