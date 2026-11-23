defmodule PscWeb.UnstrCanvasLive.Editor.Export do
  @moduledoc """
  Exporting a canvas: the PNG/SVG picture (an off-screen render that the
  `CanvasExport` hook snapshots) and the Markdown dialog, whose form downloads
  from `CanvasExportController`.
  """
  use PscWeb, :html
  import Phoenix.LiveView
  import PscWeb.UnstrCanvasLive.Board, only: [canvas_board: 1]

  alias Psc.Canvas.BackdropFetch
  alias Psc.Canvas.Structure
  alias PscWeb.Components.UI.Button, as: UIButton
  alias PscWeb.Components.UI.Dialog, as: UIDialog

  @doc "Adds the export assigns and registers the hook."
  def attach(socket) do
    socket
    |> assign(:export_format, nil)
    |> assign(:markdown_export_form, nil)
    |> attach_hook(__MODULE__, :handle_event, &handle_event/3)
  end

  # Export: the LiveView renders the board off screen (`export_board/1`) and the
  # `CanvasExport` hook turns that render into a PNG or SVG download, then
  # reports back so the render is removed. One export runs at a time.
  def handle_event("export_canvas", %{"format" => format}, socket)
      when format in ["png", "svg"] do
    if socket.assigns.export_format do
      {:halt, socket}
    else
      {:halt, assign(socket, :export_format, format)}
    end
  end

  # Markdown export: a dialog picks the sections, then submits them as a plain
  # GET to `CanvasExportController`, which sends the file. The LiveView only
  # keeps the dialog's choices.
  def handle_event("open_markdown_export", _params, socket) do
    {:halt, assign(socket, :markdown_export_form, markdown_export_form(%{"canvas" => "true"}))}
  end

  def handle_event("change_markdown_export", %{"sections" => sections}, socket) do
    {:halt, assign(socket, :markdown_export_form, markdown_export_form(sections))}
  end

  def handle_event("close_markdown_export", _params, socket) do
    {:halt, assign(socket, :markdown_export_form, nil)}
  end

  def handle_event("export_finished", params, socket) do
    socket = assign(socket, :export_format, nil)

    case params do
      %{"ok" => true} ->
        {:halt, socket}

      _failed ->
        {:halt, put_flash(socket, :error, "The export failed. Please try again.")}
    end
  end

  def handle_event(_event, _params, socket), do: {:cont, socket}

  # The Markdown export's choices. The form is a plain GET to the download
  # route, so the browser saves the file and the editor stays where it is;
  # Download also closes the dialog.
  attr :form, :any, required: true
  attr :canvas_id, :string, required: true

  def markdown_export_dialog(assigns) do
    assigns =
      assign(assigns,
        none?:
          assigns.form &&
            Enum.all?(Psc.Export.Markdown.sections(), &(assigns.form[&1].value != "true"))
      )

    ~H"""
    <UIDialog.dialog
      :if={@form}
      id="markdown-export-dialog"
      open
      on-close="close_markdown_export"
    >
      <UIDialog.dialog_content open class="max-h-[85vh] overflow-y-auto sm:max-w-md">
        <UIDialog.dialog_header>
          <UIDialog.dialog_title>Export as Markdown</UIDialog.dialog_title>
          <UIDialog.dialog_description>
            Choose what to include. Agent chats are only your own.
          </UIDialog.dialog_description>
        </UIDialog.dialog_header>

        <.form
          for={@form}
          id="markdown-export-form"
          action={~p"/canvas/#{@canvas_id}/export.md"}
          method="get"
          phx-change="change_markdown_export"
        >
          <div class="flex flex-col gap-1 py-2">
            <.input
              :for={section <- Psc.Export.Markdown.sections()}
              type="checkbox"
              field={@form[section]}
              id={"markdown-export-" <> section}
              label={Psc.Export.Markdown.section_label(section)}
            />
          </div>

          <UIDialog.dialog_footer class="flex flex-row items-center justify-end gap-2 pt-2">
            <p :if={@none?} class="mr-auto text-xs text-base-content/55">
              Pick at least one section.
            </p>
            <UIButton.button type="button" variant="outline" phx-click="close_markdown_export">
              Cancel
            </UIButton.button>
            <UIButton.button
              type="submit"
              id="markdown-export-download"
              disabled={@none?}
              phx-click="close_markdown_export"
            >
              <.icon name="hero-arrow-down-tray" class="size-4" /> Download
            </UIButton.button>
          </UIDialog.dialog_footer>
        </.form>
      </UIDialog.dialog_content>
    </UIDialog.dialog>
    """
  end

  defp markdown_export_form(sections) do
    Psc.Export.Markdown.sections()
    |> Map.new(&{&1, if(sections[&1] == "true", do: "true", else: "false")})
    |> to_form(as: :sections)
  end

  attr :format, :string, required: true
  attr :canvas_id, :string, required: true
  attr :cells, :map, required: true
  attr :c_name, :string, required: true
  attr :c_desc, :string, default: nil
  attr :user_id, :integer, required: true

  # The board as it is exported: off screen, read-only, at a fixed width, with
  # the title on top. The `canvas-export` class lets table and bento cells grow
  # to their content instead of clipping it (see app.css).
  def export_board(assigns) do
    cells = export_cells(assigns.cells, assigns.canvas_id)

    assigns =
      assign(assigns,
        export_cells: cells,
        mode: cells |> Structure.mode() |> Atom.to_string(),
        width: export_width(cells),
        filename: export_filename(assigns.c_name, assigns.format)
      )

    ~H"""
    <div
      id="canvas-export"
      phx-hook="CanvasExport"
      data-format={@format}
      data-filename={@filename}
      aria-hidden="true"
      class="pointer-events-none fixed top-0"
      style={"left: -100000px; width: #{@width}px"}
    >
      <div
        data-export-sheet
        data-mode={@mode}
        class="canvas-export flex flex-col gap-3 bg-base-100 p-6"
      >
        <div>
          <h1 class="text-xl font-semibold text-base-content">{@c_name}</h1>
          <p :if={@c_desc not in [nil, ""]} class="mt-1 text-sm text-base-content/70">{@c_desc}</p>
        </div>
        <.canvas_board
          cells={@export_cells}
          c_name={@c_name}
          edit_structure?={false}
          presence={%{}}
          can_share?={false}
          user_id={@user_id}
          read_only?
        />
      </div>
    </div>
    """
  end

  # A picture has no use for the ⓘ tooltips, and an external backdrop is
  # fetched through our own origin so the browser may draw it.
  defp export_cells(cells, canvas_id) do
    cells
    |> Map.new(fn
      {key, list} when key in ["rows", "columns"] and is_list(list) ->
        {key, Enum.map(list, &drop_hint/1)}

      {key, value} ->
        {key, drop_hint(value)}
    end)
    |> proxy_backdrop(canvas_id)
  end

  defp drop_hint(%{} = item), do: Map.delete(item, "hint")
  defp drop_hint(item), do: item

  defp proxy_backdrop(cells, canvas_id) do
    if Structure.image?(cells) and BackdropFetch.external?(Structure.backdrop(cells).url) do
      Map.update!(cells, "backdrop", &Map.put(&1, "url", ~p"/canvas/#{canvas_id}/backdrop"))
    else
      cells
    end
  end

  defp export_width(cells) do
    case Structure.mode(cells) do
      :table -> max(1100, 180 + length(cells["columns"] || []) * 300)
      :bento -> 1280
      :image -> 1600
    end
  end

  @doc false
  def export_filename(name, format) do
    slug =
      name
      |> to_string()
      |> String.downcase()
      |> String.replace(~r/[^\p{L}\p{N}]+/u, "-")
      |> String.trim("-")
      |> String.slice(0, 80)

    if(slug == "", do: "canvas", else: slug) <> "." <> format
  end
end
