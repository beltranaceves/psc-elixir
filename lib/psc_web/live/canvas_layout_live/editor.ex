defmodule PscWeb.CanvasLayoutLive.Editor do
  use PscWeb, :live_view

  # Qualified SaladUI aliases (house pattern) — CoreComponents' button/1 etc.
  # would collide with unqualified imports.
  alias PscWeb.Components.UI.Button, as: UIButton
  alias PscWeb.Components.UI.Checkbox, as: UICheckbox
  alias PscWeb.Components.UI.Input, as: UIInput
  alias PscWeb.Components.UI.Textarea, as: UITextarea
  alias PscWeb.Components.UI.Label, as: UILabel
  alias PscWeb.Components.UI.Dialog, as: UIDialog

  import PscWeb.Components.Accent
  import PscWeb.Components.EmptySection
  import PscWeb.Components.MarkdownEditor
  import PscWeb.Components.Section
  import PscWeb.Components.ShareDialog

  alias Psc.Canvas
  alias Psc.Canvas.Accent
  alias Psc.Canvas.NotesMode
  alias Psc.Canvas.Structure
  alias PscWeb.CanvasLayoutLive.BentoEditor
  alias PscWeb.Markdown

  @impl true
  def mount(params, _session, socket) do
    user = socket.assigns.current_scope.user

    case Map.get(params, "id") do
      nil ->
        mode = if Map.get(params, "mode") == "bento", do: :bento, else: :table

        {:ok,
         socket
         |> assign(:layout_map, empty_layout_map(mode))
         |> assign(:mode, mode)
         |> assign(:template_form, to_form(%{}))
         |> assign(:editing_layout, nil)
         |> assign(:owner?, true)
         |> assign(:can_edit?, true)
         |> assign(:share_open, false)
         |> assign(:accent_picker, nil)
         |> assign(:confirm_leave?, false)
         |> assign(:dirty?, false)
         |> assign(:public_draft, false)}

      id ->
        case Canvas.get_template_with_author(id) do
          %{} = template ->
            if Canvas.can_access_template?(template, user.email) do
              owner? = template.author_id == user.id
              can_edit? = not template.built_in

              {:ok,
               socket
               |> assign(:layout_map, normalize_layout_map(template.layout_map || %{}))
               |> assign(:mode, Structure.mode(template.layout_map || %{}))
               |> assign(
                 :template_form,
                 to_form(%{"name" => template.name, "description" => template.description})
               )
               |> assign(:editing_layout, template)
               |> assign(:owner?, owner?)
               |> assign(:can_edit?, can_edit?)
               |> assign(:share_open, false)
               |> assign(:accent_picker, nil)
               |> assign(:confirm_leave?, false)
               |> assign(:dirty?, false)
               |> assign(:public_draft, template.public)}
            else
              {:ok,
               socket
               |> put_flash(:error, "Template not found")
               |> redirect(to: ~p"/templates")}
            end

          _ ->
            {:ok,
             socket
             |> put_flash(:error, "Template not found")
             |> redirect(to: ~p"/templates")}
        end
    end
  end

  # ─── Grid structure events ───

  @impl true
  def handle_event("add_column", _params, socket) do
    {:noreply, update_layout(socket, &add_column/1)}
  end

  # The note mode is a property of the template, and it decides how the
  # canvases made from it behave.
  def handle_event("set_notes_mode", %{"mode" => mode}, socket) do
    if socket.assigns.can_edit? and mode in NotesMode.modes() do
      {:noreply,
       update_layout(socket, fn lm ->
         lm
         |> Map.put("notes_mode", mode)
         |> apply_notes_mode()
       end)}
    else
      {:noreply, socket}
    end
  end

  # A note the template carries. A canvas made from it starts with a copy.
  def handle_event("add_note", _params, socket) do
    if socket.assigns.can_edit? do
      {:noreply,
       update_layout(socket, fn lm ->
         notes = Map.get(lm, "notes", []) ++ [empty_template_note()]
         Map.put(lm, "notes", notes)
       end)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("remove_note", %{"index" => index}, socket) do
    if socket.assigns.can_edit? do
      {:noreply,
       update_layout(socket, fn lm ->
         Map.put(lm, "notes", List.delete_at(Map.get(lm, "notes", []), String.to_integer(index)))
       end)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("update_note_title", %{"index" => index, "value" => title}, socket) do
    {:noreply,
     update_layout(socket, &update_template_note(&1, String.to_integer(index), "title", title))}
  end

  def handle_event("update_note_content", %{"index" => index, "content" => content}, socket) do
    {:noreply,
     update_layout(
       socket,
       &update_template_note(&1, String.to_integer(index), "content", content)
     )}
  end

  # The note editor asks for a re-render when its textarea loses focus. The
  # reply is pushed to the one editor that asked, by index, so several note
  # editors on the page do not cross their previews.
  def handle_event("render_template_note", %{"index" => index, "content" => content}, socket) do
    {:noreply,
     push_event(socket, "template_note_#{index}_rendered", %{
       content: content,
       html: Markdown.render(content, empty_message: "The note is empty.")
     })}
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

  # ─── Accent colors ───

  @impl true
  def handle_event("toggle_accent_picker", %{"group" => group, "index" => index}, socket)
      when group in ["column", "row"] do
    key = {String.to_atom(group), String.to_integer(index)}
    picker = if socket.assigns.accent_picker == key, do: nil, else: key
    {:noreply, assign(socket, :accent_picker, picker)}
  end

  def handle_event("set_column_accent", %{"index" => index, "accent" => accent}, socket) do
    idx = String.to_integer(index)

    {:noreply,
     socket
     |> update_layout(&put_column_accent(&1, idx, normalize_accent(accent)))
     |> assign(:accent_picker, nil)}
  end

  def handle_event("set_row_accent", %{"index" => index, "accent" => accent}, socket) do
    idx = String.to_integer(index)

    {:noreply,
     socket
     |> update_layout(&put_row_accent(&1, idx, normalize_accent(accent)))
     |> assign(:accent_picker, nil)}
  end

  # ─── Cell metadata events ───

  @impl true
  def handle_event(
        "update_cell_meta",
        %{"cell_key" => cell_key, "field" => field, "value" => value},
        socket
      ) do
    {:noreply,
     update_layout(socket, fn lm ->
       cell = cell_meta(lm, cell_key)
       put_cell_meta(lm, cell_key, Map.put(cell, field, value))
     end)}
  end

  def handle_event("add_cell_field", %{"cell_key" => cell_key, "field" => field}, socket) do
    field = String.trim(field)

    if field == "" do
      {:noreply, put_flash(socket, :error, "Field name required")}
    else
      {:noreply,
       update_layout(socket, fn lm ->
         cell = cell_meta(lm, cell_key)
         fields = cell["fields"] || []

         if field in fields do
           lm
         else
           new_cell =
             cell
             |> Map.put("fields", fields ++ [field])
             |> Map.update("defaults", %{}, &Map.put_new(&1, field, ""))

           put_cell_meta(lm, cell_key, new_cell)
         end
       end)}
    end
  end

  def handle_event("remove_cell_field", %{"cell_key" => cell_key, "field" => field}, socket) do
    {:noreply,
     update_layout(socket, fn lm ->
       cell = cell_meta(lm, cell_key)

       new_cell =
         cell
         |> Map.update("fields", [], &List.delete(&1, field))
         |> Map.update("defaults", %{}, &Map.delete(&1, field))
         |> Map.update("titles", %{}, &Map.delete(&1, field))

       put_cell_meta(lm, cell_key, new_cell)
     end)}
  end

  def handle_event(
        "update_cell_field_title",
        %{"cell_key" => cell_key, "field" => field, "value" => value},
        socket
      ) do
    {:noreply,
     update_layout(socket, fn lm ->
       cell = cell_meta(lm, cell_key)
       titles = Map.put(cell["titles"] || %{}, field, String.trim(value))
       put_cell_meta(lm, cell_key, Map.put(cell, "titles", titles))
     end)}
  end

  def handle_event(
        "update_cell_field_default",
        %{"cell_key" => cell_key, "field" => field, "value" => value},
        socket
      ) do
    {:noreply,
     update_layout(socket, fn lm ->
       cell = cell_meta(lm, cell_key)
       defaults = Map.put(cell["defaults"] || %{}, field, value)
       put_cell_meta(lm, cell_key, Map.put(cell, "defaults", defaults))
     end)}
  end

  # ─── Bento board events ───

  def handle_event("add_card", _params, socket) do
    {:noreply, update_layout(socket, &add_bento_card/1)}
  end

  # The board's own grid. Out-of-range values are ignored rather than clamped,
  # so typing "1" on the way to "12" does not resize the board.
  def handle_event("set_bento_columns", %{"value" => value}, socket) do
    case parse_size(value) do
      count when is_integer(count) ->
        if count in Structure.column_range() do
          {:noreply, update_layout(socket, &Structure.set_columns(&1, count))}
        else
          {:noreply, socket}
        end

      _other ->
        {:noreply, socket}
    end
  end

  def handle_event("set_bento_rows", %{"value" => value}, socket) do
    case parse_size(value) do
      count when is_integer(count) ->
        if count in Structure.row_range() do
          {:noreply, update_layout(socket, &Structure.set_rows(&1, count))}
        else
          {:noreply, socket}
        end

      _other ->
        {:noreply, socket}
    end
  end

  def handle_event("remove_card", %{"cell_key" => key}, socket) do
    {:noreply,
     update_layout(socket, fn lm ->
       if length(Structure.cards(lm)) <= 1 do
         lm
       else
         Structure.remove_card(lm, key)
       end
     end)}
  end

  def handle_event("toggle_card_accent", %{"cell_key" => key}, socket) do
    picker = if socket.assigns.accent_picker == {:card, key}, do: nil, else: {:card, key}
    {:noreply, assign(socket, :accent_picker, picker)}
  end

  def handle_event("set_card_accent", %{"cell_key" => key, "accent" => accent}, socket) do
    {:noreply,
     socket
     |> assign(:accent_picker, nil)
     |> update_layout(&Structure.set_accent(&1, key, normalize_accent(accent)))}
  end

  def handle_event("move_card", %{"cell_key" => key} = params, socket) do
    with x when is_number(x) <- to_number(params["x"]),
         y when is_number(y) <- to_number(params["y"]) do
      {:noreply, update_layout(socket, &Structure.move(&1, key, x, y))}
    else
      _other -> {:noreply, socket}
    end
  end

  def handle_event("resize_card", %{"cell_key" => key} = params, socket) do
    with w when is_number(w) <- to_number(params["w"]),
         h when is_number(h) <- to_number(params["h"]) do
      {:noreply, update_layout(socket, &Structure.resize(&1, key, w, h))}
    else
      _other -> {:noreply, socket}
    end
  end

  def handle_event("nudge_card", %{"key" => key, "cell_key" => cell_key} = params, socket) do
    resize? = params["shiftKey"] == true

    case nudge_delta(key) do
      nil ->
        {:noreply, socket}

      {dx, dy} ->
        {:noreply, update_layout(socket, &nudge_bento_card(&1, cell_key, dx, dy, resize?))}
    end
  end

  # ─── Save / share events ───

  @impl true
  def handle_event(
        "save_template",
        %{"name" => name, "description" => description} = params,
        %{assigns: %{can_edit?: true}} = socket
      ) do
    user = socket.assigns.current_scope.user

    attrs = %{
      "name" => name,
      "description" => description,
      "layout_map" => socket.assigns.layout_map,
      "public" => public?(params)
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
         |> put_flash(:success, "Template saved")
         |> redirect(to: ~p"/templates")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to save template")}
    end
  end

  def handle_event("save_template", _params, socket) do
    {:noreply, put_flash(socket, :error, "This template cannot be edited")}
  end

  @impl true
  def handle_event("open_share", _params, socket) do
    {:noreply, assign(socket, :share_open, true)}
  end

  @impl true
  def handle_event("share_closed", _params, socket) do
    {:noreply, assign(socket, :share_open, false)}
  end

  # The template name/description live in the save form and are not persisted
  # until submit, so any keystroke marks the draft as dirty. The publish toggle
  # is tracked too: LiveView re-derives a checkbox's `checked` from the server's
  # render on every patch, so a toggle the server does not know about would be
  # undone the moment it fired a change event.
  @impl true
  def handle_event("mark_dirty", params, socket) do
    {:noreply,
     socket
     |> assign(:dirty?, true)
     |> assign(:public_draft, public?(params))}
  end

  # Templates are saved explicitly (no autosave), so Cancel discards the
  # in-memory draft. A dirty draft is confirmed through a modal first.
  @impl true
  def handle_event("request_cancel", _params, socket) do
    if socket.assigns.dirty? do
      {:noreply, assign(socket, :confirm_leave?, true)}
    else
      {:noreply, push_navigate(socket, to: ~p"/templates")}
    end
  end

  @impl true
  def handle_event("dismiss_leave_dialog", _params, socket) do
    {:noreply, assign(socket, :confirm_leave?, false)}
  end

  # The dialog pushes "close" on Escape, outside click, the × button or after a
  # transition, so the server state has to follow it back to closed.
  @impl true
  def handle_event("leave_dialog_closed", _params, socket) do
    {:noreply, assign(socket, :confirm_leave?, false)}
  end

  @impl true
  def handle_event("confirm_leave", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/templates")}
  end

  @impl true
  def handle_event("share_template", %{"email" => email}, socket) do
    case Canvas.share_template_with(socket.assigns.editing_layout, String.downcase(email)) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:editing_layout, Canvas.get_template_with_author(updated.id))
         |> put_flash(:success, "Template shared with #{email}")}

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
         |> put_flash(:success, "Access removed for #{email}")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to remove access")}
    end
  end

  # ─── Layout map helpers ───

  # Update one field of one of the template's notes. The notes list may be
  # missing entirely on a template saved before notes existed, so the list is
  # rebuilt rather than indexed into.
  defp update_template_note(lm, index, key, value) do
    notes =
      lm
      |> Map.get("notes", [])
      |> Enum.with_index()
      |> Enum.map(fn
        {note, ^index} -> Map.put(note, key, value)
        {note, _other} -> note
      end)

    Map.put(lm, "notes", notes)
  end

  defp update_layout(socket, fun) do
    socket
    |> assign(:layout_map, fun.(socket.assigns.layout_map))
    |> assign(:dirty?, true)
  end

  # A table template keeps its cells under "cells"; a bento template is flat,
  # exactly like a bento canvas. These two accessors are the only place the
  # difference shows.
  defp cell_meta(lm, key) do
    if Structure.bento?(lm) do
      Map.get(lm, key) || BentoEditor.empty_cell_meta()
    else
      get_in(lm, ["cells", key]) || empty_cell_meta()
    end
  end

  defp put_cell_meta(lm, key, cell) do
    if Structure.bento?(lm) do
      Map.put(lm, key, cell)
    else
      put_in(lm, ["cells", key], cell)
    end
  end

  defp empty_layout_map(:table) do
    %{
      "rows" => [],
      "columns" => [],
      "layout" => [],
      "cells" => %{},
      "notes" => [],
      "notes_mode" => NotesMode.default()
    }
  end

  # A bento starts with one card so the template is valid the moment it is
  # saved; the rest of the board is built in place.
  defp empty_layout_map(:bento) do
    %{
      "layout_mode" => "bento",
      "bento_columns" => 12,
      "notes" => [],
      "notes_mode" => NotesMode.default()
    }
    |> Structure.add_card("card1", %{"x" => 0, "y" => 0, "w" => 6, "h" => 2}, "Card 1")
  end

  # The template's notes, each with a title and a body. A template saved
  # before notes existed has none.
  defp normalize_template_notes(notes) when is_list(notes) do
    Enum.map(notes, fn note ->
      %{
        "title" => note["title"] || "",
        "content" => note["content"] || ""
      }
    end)
  end

  defp normalize_template_notes(_notes), do: []

  defp empty_template_note, do: %{"title" => "", "content" => ""}

  # The publish toggle is a checkbox pair, so an unticked box still submits
  # "false". A form without the toggle at all stays private.
  defp public?(%{"public" => "true"}), do: true
  defp public?(_params), do: false

  # A scratchpad holds one note. Switching a template that carries several
  # notes to the scratchpad mode keeps the first one and drops the rest; a
  # template that has none gets one, so there is always something to write the
  # scratchpad's starting content into.
  defp apply_notes_mode(lm) do
    if NotesMode.single?(lm["notes_mode"]) do
      case Map.get(lm, "notes", []) do
        [] -> Map.put(lm, "notes", [empty_template_note()])
        notes -> Map.put(lm, "notes", Enum.take(notes, 1))
      end
    else
      lm
    end
  end

  defp empty_cell_meta do
    %{
      "label" => "",
      "fields" => ["content"],
      "defaults" => %{"content" => ""}
    }
  end

  # The section summaries. A collapsed section still has to say what is inside
  # it, or collapsing it would hide information the user needs in order to
  # decide whether to open it.
  defp notes_hint(%{"notes_mode" => mode, "notes" => notes}) do
    if NotesMode.single?(mode), do: "Scratchpad", else: notes_count_hint(length(notes))
  end

  defp notes_hint(_layout_map), do: "No notes yet"

  defp notes_count_hint(0), do: "No notes yet"
  defp notes_count_hint(1), do: "1 note"
  defp notes_count_hint(count), do: "#{count} notes"

  defp grid_hint(%{"layout_mode" => "bento"} = lm) do
    case length(Structure.cards(lm)) do
      0 -> "No cards yet"
      1 -> "1 card on #{Structure.columns(lm)} columns"
      count -> "#{count} cards on #{Structure.columns(lm)} columns"
    end
  end

  defp grid_hint(%{"rows" => rows, "columns" => columns}) do
    case {length(columns), length(rows)} do
      {0, 0} -> "No rows or columns yet"
      {columns, rows} -> "#{columns} columns × #{rows} rows"
    end
  end

  defp grid_hint(_layout_map), do: "No rows or columns yet"

  # Normalizes a stored layout_map into the current shape and guarantees
  # consistency: the matrix is rebuilt strictly from rows × columns,
  # preserving existing cell keys where present and generating
  # "#{row_id}_#{column_id}" keys elsewhere.
  defp normalize_layout_map(lm) do
    if Structure.bento?(lm),
      do: normalize_bento_layout_map(lm),
      else: normalize_table_layout_map(lm)
  end

  # A bento layout map is already flat; normalizing only fills the shared
  # keys and clamps every placement into the board.
  defp normalize_bento_layout_map(lm) do
    lm = Map.put_new(lm, "bento_columns", Structure.columns(lm))

    lm
    |> Map.put("notes", normalize_template_notes(lm["notes"]))
    |> Map.put("notes_mode", NotesMode.normalize(lm["notes_mode"]))
    |> apply_notes_mode()
    |> Structure.set_columns(Structure.columns(lm))
  end

  defp normalize_table_layout_map(lm) do
    lm =
      lm
      |> Map.put_new("rows", [])
      |> Map.put_new("columns", [])
      |> Map.put_new("layout", [])
      |> Map.put_new("cells", %{})
      |> Map.put("notes", normalize_template_notes(lm["notes"]))
      |> Map.put("notes_mode", NotesMode.normalize(lm["notes_mode"]))
      |> apply_notes_mode()

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

  defp add_bento_card(lm) do
    taken =
      for key <- Structure.cell_keys(lm),
          parts = Regex.run(~r/^card(\d+)$/, key),
          n <- tl(parts) do
        String.to_integer(n)
      end

    index = Enum.max([0 | taken]) + 1
    key = "card#{index}"

    Structure.add_card(lm, key, nil, "Card #{length(Structure.cards(lm)) + 1}")
  end

  defp nudge_bento_card(lm, key, dx, dy, resize?) do
    case Structure.card(lm, key) do
      nil ->
        lm

      card ->
        if resize? do
          step = Structure.min_size()
          Structure.resize(lm, key, card.w + dx * step, card.h + dy * step)
        else
          step = Structure.min_size()
          Structure.move(lm, key, card.x + dx * step, card.y + dy * step)
        end
    end
  end

  defp nudge_delta("ArrowLeft"), do: {-1, 0}
  defp nudge_delta("ArrowRight"), do: {1, 0}
  defp nudge_delta("ArrowUp"), do: {0, -1}
  defp nudge_delta("ArrowDown"), do: {0, 1}
  defp nudge_delta(_key), do: nil

  defp parse_size(value) do
    case Integer.parse(to_string(value)) do
      {int, ""} -> int
      _other -> nil
    end
  end

  # A coordinate keeps its half: 6.5 columns must not become 6.
  defp to_number(value) when is_integer(value) or is_float(value), do: value

  defp to_number(value) when is_binary(value) do
    case Float.parse(value) do
      {number, _rest} -> number
      :error -> nil
    end
  end

  defp to_number(_other), do: nil

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

  defp put_column_accent(lm, idx, accent) do
    columns = List.update_at(lm["columns"], idx, &Map.put(&1, "accent", accent))
    Map.put(lm, "columns", columns)
  end

  defp put_row_accent(lm, idx, accent) do
    rows = List.update_at(lm["rows"], idx, &Map.put(&1, "accent", accent))
    Map.put(lm, "rows", rows)
  end

  # The UI sends "" for "no accent"; anything unrecognised is treated as none,
  # which the layout changeset also rejects if it ever reaches the database.
  defp normalize_accent(""), do: nil

  defp normalize_accent(accent) do
    if Accent.valid?(accent), do: accent, else: nil
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      header_title="Designer"
      header_section="Templates"
      main_class="px-2 py-2 sm:px-6 lg:px-8"
      container_class="w-full mx-auto max-w-screen-xl"
    >
      <div>
        <%= if @editing_layout && !@can_edit? do %>
          <div class="mb-6 p-3 rounded-lg border border-base-content/10 bg-base-200 text-sm text-base-content/60">
            Built-in templates are read-only. Create your own template to change the structure.
          </div>
        <% end %>

        <.share_dialog
          :if={@editing_layout}
          id="share-template-dialog"
          open={@share_open}
          title="Share template"
          description="People with access can open this template and create canvases from it."
          manage?={@owner?}
          shared_with={@editing_layout.shared_with || []}
          share_event="share_template"
          remove_event="unshare_template"
          on_close="share_closed"
        />
        <div class="space-y-4">
          <%!-- Page-level actions sit outside the collapsible sections: the back
          link and Share belong to the page, not to any one section. --%>
          <div class="flex flex-wrap items-center justify-between gap-2">
            <.link
              navigate={~p"/templates"}
              class="inline-flex h-9 items-center gap-1.5 rounded-lg border border-base-content/10 px-3 text-sm text-base-content transition-colors hover:bg-base-content/5"
            >
              <.icon name="hero-arrow-left" class="size-4" /> Templates
            </.link>

            <%= if @owner? and @editing_layout do %>
              <.share_button id="share-template-button" label="Share" size="default" />
            <% end %>
          </div>

          <.form
            for={@template_form}
            id="template-form"
            phx-change="mark_dirty"
            phx-submit="save_template"
            class="rounded-xl border border-base-content/10 bg-base-200 p-4 space-y-4 sm:p-6"
          >
            <div>
              <UILabel.label for={@template_form[:name].id}>Name</UILabel.label>

              <UIInput.input
                field={@template_form[:name]}
                type="text"
                required
                disabled={!@can_edit?}
              />
            </div>

            <div>
              <UILabel.label for="template-description">Description</UILabel.label>

              <UITextarea.textarea
                field={@template_form[:description]}
                rows="2"
                disabled={!@can_edit?}
              />
            </div>

            <%= if @can_edit? do %>
              <%!-- Publishing is saved with the template like any other field:
              no separate publish action. --%>
              <label class="flex items-start gap-2.5 rounded-lg border border-base-content/10 bg-base-200/60 p-3 text-sm text-base-content transition-colors hover:border-base-content/20">
                <UICheckbox.checkbox
                  id="template-public"
                  name="public"
                  value={@public_draft}
                  class="mt-0.5"
                />
                <span class="min-w-0">
                  <span class="font-medium">Public</span>
                  <span class="block text-xs text-base-content/55">
                    List this template in the catalog, where anyone can use or fork it.
                  </span>
                </span>
              </label>
            <% end %>

            <%= if @can_edit? do %>
              <div class="flex items-center justify-end gap-3 border-t border-base-content/10 pt-4">
                <span
                  :if={@dirty?}
                  id="unsaved-changes-hint"
                  class="mr-auto text-xs font-medium text-amber-600 dark:text-amber-300"
                >
                  Unsaved changes
                </span>

                <UIButton.button
                  type="button"
                  variant="outline"
                  id="cancel-template-editing"
                  phx-click="request_cancel"
                >
                  Cancel
                </UIButton.button>
                <UIButton.button type="submit">Save Template</UIButton.button>
              </div>
            <% end %>
          </.form>

          <.section id="template-notes" title="Notes" hint={notes_hint(@layout_map)} open>
            <%!-- The note mode decides how the canvases made from this template
            behave: a list of notes, or one scratchpad. --%>
            <p class="max-w-lg text-sm text-base-content/60">
              {NotesMode.blurb(@layout_map["notes_mode"])}
            </p>

            <div class="mt-3 flex flex-wrap gap-2">
              <%= for mode <- NotesMode.modes() do %>
                <button
                  type="button"
                  id={"notes-mode-" <> mode}
                  phx-click="set_notes_mode"
                  phx-value-mode={mode}
                  disabled={not @can_edit?}
                  aria-pressed={to_string(@layout_map["notes_mode"] == mode)}
                  class={[
                    "rounded-lg border px-3 py-1.5 text-sm font-medium transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-primary disabled:opacity-50",
                    @layout_map["notes_mode"] == mode &&
                      "border-primary/50 bg-primary/10 text-base-content",
                    @layout_map["notes_mode"] != mode &&
                      "border-base-content/15 bg-base-200 text-base-content/60 hover:border-base-content/30 hover:text-base-content"
                  ]}
                >
                  {NotesMode.label(mode)}
                </button>
              <% end %>
            </div>

            <%!-- The template's notes. A canvas made from this template
            starts with a copy of them. --%>
            <div class="mt-4 border-t border-base-content/10 pt-4">
              <div class="flex items-center justify-between gap-2">
                <h3 class="text-xs font-medium uppercase tracking-wide text-base-content/50">
                  <%= if @layout_map["notes_mode"] == "single" do %>
                    Scratchpad content
                  <% else %>
                    Notes
                  <% end %>
                </h3>

                <%= if @can_edit? and @layout_map["notes_mode"] != "single" do %>
                  <UIButton.button variant="outline" size="sm" phx-click="add_note">
                    <.icon name="hero-plus" class="size-4" /> Add note
                  </UIButton.button>
                <% end %>
              </div>

              <p class="mt-1 text-xs text-base-content/45">
                <%= if @layout_map["notes_mode"] == "single" do %>
                  The scratchpad every canvas from this template starts with.
                <% else %>
                  Canvases made from this template start with these notes.
                <% end %>
              </p>

              <div id="template-notes-list" class="mt-3 space-y-3">
                <%= for {note, index} <- Enum.with_index(@layout_map["notes"] || []) do %>
                  <div
                    id={"template-note-#{index}"}
                    class="rounded-lg border border-base-content/10 bg-base-200/60 p-3"
                  >
                    <div class="flex items-start gap-2">
                      <form
                        id={"template-note-#{index}-title-form"}
                        phx-change="update_note_title"
                        class="min-w-0 flex-1"
                      >
                        <input type="hidden" name="index" value={index} />
                        <input
                          type="text"
                          name="value"
                          value={note["title"]}
                          phx-debounce="300"
                          placeholder="Note title"
                          class="w-full border-b border-transparent bg-transparent text-sm font-medium text-base-content transition-colors placeholder-base-content/40 hover:border-base-content/20 focus:border-primary focus:outline-none"
                        />
                      </form>

                      <%= if @can_edit? and @layout_map["notes_mode"] != "single" do %>
                        <button
                          type="button"
                          phx-click="remove_note"
                          phx-value-index={index}
                          class="shrink-0 rounded-md p-1 text-base-content/40 transition-colors hover:bg-base-content/5 hover:text-error"
                          aria-label="Remove note"
                        >
                          <.icon name="hero-x-mark" class="size-4" />
                        </button>
                      <% end %>
                    </div>

                    <.markdown_editor
                      id={"template-note-#{index}-editor"}
                      input_id={"template-note-#{index}-input"}
                      form_id={"template-note-#{index}-content-form"}
                      preview_id={"template-note-#{index}-preview"}
                      content={note["content"]}
                      html={Markdown.render(note["content"], empty_message: "The note is empty.")}
                      hidden_fields={[{"index", index}]}
                      change_event="update_note_content"
                      preview_event="render_template_note"
                      render_event={"template_note_#{index}_rendered"}
                      update_event="template_note_content_updated"
                      preview_label="Edit note content"
                      placeholder="The note's Markdown…"
                      auto_grow
                      body_class="min-h-36 p-3 font-mono text-xs leading-5"
                      class="mt-2"
                    />
                  </div>
                <% end %>
              </div>
            </div>
          </.section>

          <.section
            id="template-grid"
            title={if @mode == :bento, do: "Board", else: "Grid"}
            hint={grid_hint(@layout_map)}
            open
          >
            <%= if @mode == :bento do %>
              <BentoEditor.editor
                layout_map={@layout_map}
                can_edit?={@can_edit?}
                accent_picker={@accent_picker}
              />
            <% else %>
              <%= if @can_edit? do %>
                <div class="mb-3 flex flex-wrap justify-end gap-2">
                  <UIButton.button variant="outline" size="sm" phx-click="add_column">
                    Add Column
                  </UIButton.button>

                  <UIButton.button variant="outline" size="sm" phx-click="add_row">
                    Add Row
                  </UIButton.button>
                </div>
              <% end %>

              <%= if Enum.empty?(@layout_map["rows"]) or Enum.empty?(@layout_map["columns"]) do %>
                <p class="px-2 pb-2 text-sm text-base-content/50 sm:px-0 sm:pb-0">
                  Add at least one row and one column to start building your template.
                </p>
              <% else %>
                <div class="overflow-auto">
                  <table
                    class="w-full border-collapse table-fixed text-sm"
                    style={"min-width: #{length(@layout_map["columns"] || []) * 14 + 10}rem"}
                  >
                    <thead>
                      <tr>
                        <th class="w-40 p-2 border border-base-content/10"></th>

                        <%= for {col, ci} <- Enum.with_index(@layout_map["columns"]) do %>
                          <th class="border border-base-content/10 bg-base-content/5 p-0 text-base-content/70 align-bottom">
                            <div class="flex flex-col">
                              <.accent_bar
                                id={"accent-bar-column-#{col["id"]}"}
                                token={col["accent"]}
                              />
                              <div class="p-2">
                                <div class="flex items-center gap-1">
                                  <form
                                    id={"column-#{col["id"]}-label-form"}
                                    phx-change="update_column_label"
                                    class="min-w-0 flex-1"
                                  >
                                    <input type="hidden" name="index" value={ci} />
                                    <input
                                      type="text"
                                      id={"column-#{col["id"]}-label"}
                                      name="label"
                                      value={col["label"]}
                                      phx-debounce="300"
                                      disabled={!@can_edit?}
                                      class="w-full rounded border border-transparent bg-transparent px-2 py-1 text-inherit hover:border-base-content/10 focus:border-primary focus:outline-none"
                                    />
                                  </form>

                                  <%= if @can_edit? do %>
                                    <button
                                      type="button"
                                      id={"accent-swatch-column-#{col["id"]}"}
                                      phx-click="toggle_accent_picker"
                                      phx-value-group="column"
                                      phx-value-index={ci}
                                      class={[
                                        "size-3.5 shrink-0 rounded-full ring-2 ring-base-content/25 hover:ring-primary transition",
                                        swatch_class(col["accent"])
                                      ]}
                                      title="Accent color"
                                      aria-label={"Accent color for column #{col["label"]}"}
                                    ></button>
                                    <button
                                      type="button"
                                      id={"remove-column-#{col["id"]}"}
                                      phx-click="remove_column"
                                      phx-value-index={ci}
                                      class="inline-flex size-5 shrink-0 items-center justify-center rounded-md border border-error/40 text-error transition-colors hover:border-error hover:bg-error/10"
                                      title="Remove column"
                                      aria-label={"Remove column #{col["label"]}"}
                                    >
                                      <.icon name="hero-x-mark" class="size-3" />
                                    </button>
                                  <% end %>
                                </div>

                                <div
                                  :if={@can_edit? and @accent_picker == {:column, ci}}
                                  id={"accent-picker-column-#{col["id"]}"}
                                  class="mt-1 flex flex-wrap items-center gap-1 rounded-md bg-base-100/80 p-1"
                                >
                                  <button
                                    :for={token <- Accent.tokens()}
                                    type="button"
                                    id={"accent-option-column-#{col["id"]}-#{token}"}
                                    phx-click="set_column_accent"
                                    phx-value-index={ci}
                                    phx-value-accent={token}
                                    class={[
                                      "size-3 rounded-full ring-1 ring-base-content/25 hover:scale-110 transition",
                                      swatch_class(token),
                                      col["accent"] == token &&
                                        "ring-2 ring-primary ring-offset-1 ring-offset-base-100"
                                    ]}
                                    title={token}
                                    aria-label={"Set column accent #{token}"}
                                  ></button>
                                  <button
                                    type="button"
                                    phx-click="set_column_accent"
                                    phx-value-index={ci}
                                    phx-value-accent=""
                                    class="px-1 text-[0.65rem] text-base-content/50 hover:text-base-content"
                                  >
                                    None
                                  </button>
                                </div>
                              </div>
                            </div>
                          </th>
                        <% end %>
                      </tr>
                    </thead>

                    <tbody>
                      <%= for {row_meta, ri} <- Enum.with_index(@layout_map["rows"]) do %>
                        <tr>
                          <td class="relative border border-base-content/10 bg-base-content/5 p-0 align-top">
                            <.accent_bar
                              id={"accent-bar-row-#{row_meta["id"]}"}
                              token={row_meta["accent"]}
                              orientation={:left}
                            />
                            <div class="p-2">
                              <div class="flex items-center gap-1">
                                <form
                                  id={"row-#{row_meta["id"]}-label-form"}
                                  phx-change="update_row_label"
                                  class="min-w-0 flex-1"
                                >
                                  <input type="hidden" name="index" value={ri} />
                                  <input
                                    type="text"
                                    id={"row-#{row_meta["id"]}-label"}
                                    name="label"
                                    value={row_meta["label"]}
                                    phx-debounce="300"
                                    disabled={!@can_edit?}
                                    class="w-full rounded border border-transparent bg-transparent px-2 py-1 text-inherit hover:border-base-content/10 focus:border-primary focus:outline-none"
                                  />
                                </form>

                                <%= if @can_edit? do %>
                                  <button
                                    type="button"
                                    id={"accent-swatch-row-#{row_meta["id"]}"}
                                    phx-click="toggle_accent_picker"
                                    phx-value-group="row"
                                    phx-value-index={ri}
                                    class={[
                                      "size-3.5 shrink-0 rounded-full ring-2 ring-base-content/25 hover:ring-primary transition",
                                      swatch_class(row_meta["accent"])
                                    ]}
                                    title="Accent color"
                                    aria-label={"Accent color for row #{row_meta["label"]}"}
                                  ></button>
                                  <button
                                    type="button"
                                    id={"remove-row-#{row_meta["id"]}"}
                                    phx-click="remove_row"
                                    phx-value-index={ri}
                                    class="inline-flex size-5 shrink-0 items-center justify-center rounded-md border border-error/40 text-error transition-colors hover:border-error hover:bg-error/10"
                                    title="Remove row"
                                    aria-label={"Remove row #{row_meta["label"]}"}
                                  >
                                    <.icon name="hero-x-mark" class="size-3" />
                                  </button>
                                <% end %>
                              </div>

                              <div
                                :if={@can_edit? and @accent_picker == {:row, ri}}
                                id={"accent-picker-row-#{row_meta["id"]}"}
                                class="mt-1 flex flex-wrap items-center gap-1 rounded-md bg-base-100/80 p-1"
                              >
                                <button
                                  :for={token <- Accent.tokens()}
                                  type="button"
                                  id={"accent-option-row-#{row_meta["id"]}-#{token}"}
                                  phx-click="set_row_accent"
                                  phx-value-index={ri}
                                  phx-value-accent={token}
                                  class={[
                                    "size-3 rounded-full ring-1 ring-base-content/25 hover:scale-110 transition",
                                    swatch_class(token),
                                    row_meta["accent"] == token &&
                                      "ring-2 ring-primary ring-offset-1 ring-offset-base-100"
                                  ]}
                                  title={token}
                                  aria-label={"Set row accent #{token}"}
                                ></button>
                                <button
                                  type="button"
                                  phx-click="set_row_accent"
                                  phx-value-index={ri}
                                  phx-value-accent=""
                                  class="px-1 text-[0.65rem] text-base-content/50 hover:text-base-content"
                                >
                                  None
                                </button>
                              </div>
                            </div>
                          </td>

                          <%= for cell_key <- Enum.at(@layout_map["layout"], ri, []) do %>
                            <td class="p-2 border border-base-content/10 align-top">
                              <div id={"cell-#{cell_key}"} class="rounded-lg bg-base-300/50 p-2">
                                <form
                                  id={"cell-#{cell_key}-label-form"}
                                  phx-change="update_cell_meta"
                                >
                                  <input type="hidden" name="cell_key" value={cell_key} />
                                  <input type="hidden" name="field" value="label" />
                                  <input
                                    type="text"
                                    id={"cell-#{cell_key}-label"}
                                    value={get_in(@layout_map, ["cells", cell_key, "label"])}
                                    phx-debounce="300"
                                    name="value"
                                    placeholder={cell_key}
                                    disabled={!@can_edit?}
                                    class="w-full min-w-0 rounded border border-transparent bg-transparent px-1 py-0.5 text-sm font-medium text-base-content placeholder-base-content/40 hover:border-base-content/10 focus:border-primary focus:outline-none"
                                  />
                                </form>

                                <ul class="mt-2 space-y-1">
                                  <%= for field <- get_in(@layout_map, ["cells", cell_key, "fields"]) || [] do %>
                                    <li class="flex items-center gap-1">
                                      <form
                                        id={"cell-#{cell_key}-field-#{field}-title-form"}
                                        phx-change="update_cell_field_title"
                                        class="w-28 shrink-0"
                                      >
                                        <input type="hidden" name="cell_key" value={cell_key} />
                                        <input type="hidden" name="field" value={field} />
                                        <input
                                          type="text"
                                          id={"cell-#{cell_key}-field-#{field}-title"}
                                          value={
                                            Psc.Canvas.field_title(
                                              get_in(@layout_map, ["cells", cell_key]) || %{},
                                              field
                                            )
                                          }
                                          phx-debounce="300"
                                          name="value"
                                          placeholder={field}
                                          title={"Section title for #{field} (empty hides it)"}
                                          disabled={!@can_edit?}
                                          class="w-full min-w-0 rounded border border-base-content/10 bg-base-200 px-1.5 py-0.5 text-xs font-medium text-base-content placeholder-base-content/35 focus:border-primary focus:outline-none"
                                        />
                                      </form>

                                      <form
                                        id={"cell-#{cell_key}-field-#{field}-form"}
                                        phx-change="update_cell_field_default"
                                        class="min-w-0 flex-1"
                                      >
                                        <input type="hidden" name="cell_key" value={cell_key} />
                                        <input type="hidden" name="field" value={field} />
                                        <input
                                          type="text"
                                          id={"cell-#{cell_key}-field-#{field}"}
                                          value={
                                            get_in(@layout_map, [
                                              "cells",
                                              cell_key,
                                              "defaults",
                                              field
                                            ])
                                          }
                                          phx-debounce="300"
                                          name="value"
                                          placeholder="Default"
                                          disabled={!@can_edit?}
                                          class="w-full min-w-0 rounded border border-base-content/10 bg-base-200 px-1.5 py-0.5 text-xs text-base-content placeholder-base-content/35 focus:border-primary focus:outline-none"
                                        />
                                      </form>

                                      <button
                                        :if={@can_edit?}
                                        type="button"
                                        phx-click="remove_cell_field"
                                        phx-value-cell_key={cell_key}
                                        phx-value-field={field}
                                        class="inline-flex size-4 shrink-0 items-center justify-center rounded border border-error/40 text-error/90 transition-colors hover:border-error hover:bg-error/10 hover:text-error"
                                        title={"Remove field #{field}"}
                                        aria-label={"Remove field #{field}"}
                                      >
                                        <.icon name="hero-x-mark" class="size-2.5" />
                                      </button>
                                    </li>
                                  <% end %>
                                </ul>

                                <form
                                  :if={@can_edit?}
                                  id={"cell-#{cell_key}-add-field-form"}
                                  phx-submit="add_cell_field"
                                  class="mt-2 flex gap-1"
                                >
                                  <input type="hidden" name="cell_key" value={cell_key} />
                                  <input
                                    type="text"
                                    id={"cell-#{cell_key}-new-field"}
                                    name="field"
                                    placeholder="New field"
                                    class="min-w-0 flex-1 rounded border border-base-content/10 bg-base-200 px-1.5 py-0.5 text-xs text-base-content placeholder-base-content/35 focus:border-primary focus:outline-none"
                                  />
                                  <button
                                    type="submit"
                                    class="shrink-0 rounded border border-base-content/10 px-1.5 py-0.5 text-xs text-base-content/70 hover:bg-base-content/5 hover:text-base-content transition-colors"
                                  >
                                    Add
                                  </button>
                                </form>
                              </div>
                            </td>
                          <% end %>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </div>
              <% end %>
            <% end %>
          </.section>

          <%!-- Analysis and Agent are planned parts of a template. They are
          rendered now so the designer's shape does not change when they land,
          and so a user can see that they exist and are not configured. --%>
          <.section id="template-analysis" title="Analysis" hint="Not configured" open>
            <.empty_section
              id="template-analysis-placeholder"
              icon="hero-chart-bar"
              title="Nothing here yet"
              description="Analysis settings for templates are coming soon."
            />
          </.section>

          <.section id="template-agent" title="Agent" hint="Not configured" open>
            <.empty_section
              id="template-agent-placeholder"
              icon="hero-cpu-chip"
              title="Nothing here yet"
              description="Agent settings for templates are coming soon."
            />
          </.section>
        </div>

        <UIDialog.dialog
          :if={@can_edit?}
          id="discard-template-dialog"
          open={@confirm_leave?}
          on-close="leave_dialog_closed"
        >
          <UIDialog.dialog_content class="sm:max-w-md">
            <UIDialog.dialog_header>
              <UIDialog.dialog_title>Discard unsaved changes?</UIDialog.dialog_title>

              <UIDialog.dialog_description>
                This template has edits that have not been saved. Leaving now discards the
                grid, cell and accent changes made in this session.
              </UIDialog.dialog_description>
            </UIDialog.dialog_header>

            <UIDialog.dialog_footer>
              <UIButton.button
                type="button"
                variant="outline"
                id="keep-editing-template"
                phx-click="dismiss_leave_dialog"
              >
                Keep editing
              </UIButton.button>

              <UIButton.button
                type="button"
                variant="destructive"
                id="discard-template-changes"
                phx-click="confirm_leave"
              >
                Discard and leave
              </UIButton.button>
            </UIDialog.dialog_footer>
          </UIDialog.dialog_content>
        </UIDialog.dialog>
      </div>
    </Layouts.app>
    """
  end
end
