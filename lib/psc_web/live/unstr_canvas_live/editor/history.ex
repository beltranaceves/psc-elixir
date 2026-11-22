defmodule PscWeb.UnstrCanvasLive.Editor.History do
  @moduledoc """
  The History tab and the version tree (ADR-043): naming a draft, loading a
  version and forking one. Also starts a draft when an edit lands on a named
  version, and asks for its name after the next save.
  """
  use PscWeb, :html
  import Phoenix.LiveView

  import PscWeb.UnstrCanvasLive.Editor.Operations,
    only: [process_operation: 2, push_cells_resync: 1]

  alias Psc.Canvas

  @doc "Adds the History tab's assigns, reads the current version and registers its hooks."
  def attach(socket) do
    socket
    |> assign(:pivots, [])
    |> assign(:selected_pivot_id, nil)
    |> assign(:pivot_form, nil)
    |> assign(:pivot_target, nil)
    |> assign(:pivot_prompt, nil)
    |> assign(:pending_load, nil)
    |> assign(:pending_fork, nil)
    |> assign(:fork_form, nil)
    |> load_head()
    |> attach_hook(__MODULE__, :handle_event, &handle_event/3)
    |> attach_hook(__MODULE__, :handle_info, &handle_info/2)
  end

  # ─── History tab (versions) ───
  #
  # The canvas holds one version at a time (ADR-043). Editing a named version
  # starts a draft (`maybe_start_draft/2`); the person whose edit started it is
  # asked to name it after the first save. Naming can wait: the draft stays in
  # the tree.

  # The Pivot button names the draft the canvas holds.
  def handle_event("open_pivot", _params, socket) do
    if socket.assigns.head_draft? do
      {:halt, open_pivot_dialog(socket, socket.assigns.head_id)}
    else
      {:halt,
       put_flash(
         socket,
         :info,
         "No changes since the current version. Edit the canvas to start one."
       )}
    end
  end

  # A draft that was left behind can be named from History.
  def handle_event("name_pivot", %{"id" => id}, socket) do
    {:halt, open_pivot_dialog(socket, id)}
  end

  def handle_event("close_pivot", _params, socket) do
    {:halt, assign(socket, pivot_form: nil, pivot_target: nil)}
  end

  def handle_event("save_pivot", %{"pivot" => params}, socket) do
    case Canvas.name_pivot(socket.assigns.canvas_id, socket.assigns.pivot_target, params) do
      {:ok, pivot} ->
        {:halt,
         socket
         |> assign(pivot_form: nil, pivot_target: nil, selected_pivot_id: pivot.id)
         |> load_head()
         |> load_pivots()
         |> put_flash(:info, "Version \"#{pivot.name}\" saved")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:halt, assign(socket, :pivot_form, to_form(changeset, as: :pivot))}

      {:error, _reason} ->
        {:halt,
         socket
         |> assign(pivot_form: nil, pivot_target: nil)
         |> put_flash(:error, "That version already has a name")}
    end
  end

  def handle_event("select_pivot", %{"id" => id}, socket) do
    {:halt, assign(socket, :selected_pivot_id, id)}
  end

  def handle_event("request_load", _params, socket) do
    {:halt, assign(socket, :pending_load, selected_pivot(socket))}
  end

  def handle_event("dismiss_load", _params, socket) do
    {:halt, assign(socket, :pending_load, nil)}
  end

  # Loading travels as a `replace_cells` operation, so every open editor
  # converges and the save path folds it like any other edit. It is not an
  # edit: it never starts a draft.
  def handle_event("confirm_load", _params, socket) do
    pivot = socket.assigns.pending_load
    socket = assign(socket, :pending_load, nil)

    case pivot && Canvas.load_pivot(socket.assigns.canvas_id, pivot) do
      {:ok, operation} ->
        {:halt,
         socket
         |> process_operation(operation)
         |> push_cells_resync()
         |> load_head()
         |> load_pivots()
         |> put_flash(:info, "Loaded \"#{pivot_label(pivot)}\"")}

      _error ->
        {:halt, put_flash(socket, :error, "Could not load this version")}
    end
  end

  # Fork asks where: a new canvas (with or without the history), or a new
  # version right under this one, in this canvas.
  def handle_event("fork_pivot", _params, socket) do
    {:halt,
     assign(socket,
       pending_fork: selected_pivot(socket),
       fork_form: to_form(%{"mode" => "canvas", "keep_history" => "false"}, as: :fork)
     )}
  end

  def handle_event("fork_change", %{"fork" => params}, socket) do
    {:halt, assign(socket, :fork_form, to_form(params, as: :fork))}
  end

  def handle_event("dismiss_fork", _params, socket) do
    {:halt, assign(socket, pending_fork: nil, fork_form: nil)}
  end

  def handle_event("confirm_fork", %{"fork" => %{"mode" => "here"}}, socket) do
    pivot = socket.assigns.pending_fork
    socket = assign(socket, pending_fork: nil, fork_form: nil)

    case pivot && Canvas.fork_in_place(socket.assigns.canvas_id, pivot, socket.assigns.user_id) do
      {:ok, {draft, operation}} ->
        {:halt,
         socket
         |> process_operation(operation)
         |> push_cells_resync()
         |> load_head()
         |> assign(:selected_pivot_id, draft.id)
         |> load_pivots()
         |> open_pivot_dialog(draft.id)}

      _error ->
        {:halt, put_flash(socket, :error, "Could not fork this version")}
    end
  end

  def handle_event("confirm_fork", %{"fork" => params}, socket) do
    pivot = socket.assigns.pending_fork
    socket = assign(socket, pending_fork: nil, fork_form: nil)
    keep_history = params["keep_history"] == "true"

    case pivot &&
           Canvas.fork_pivot(socket.assigns.canvas, pivot, socket.assigns.user_id,
             keep_history: keep_history
           ) do
      {:ok, fork} ->
        {:halt,
         socket
         |> put_flash(:info, "Forked into \"#{fork.name}\"")
         |> push_navigate(to: ~p"/canvas/#{fork.id}?tab=history")}

      _error ->
        {:halt, put_flash(socket, :error, "Could not fork this version")}
    end
  end

  def handle_event(_event, _params, socket), do: {:cont, socket}

  # The versions are read when the History view opens and whenever one changes,
  # here or in another tab. The current version is selected by default.
  def load_pivots(socket) do
    pivots = Canvas.list_pivots(socket.assigns.canvas_id)
    selected = socket.assigns.selected_pivot_id

    selected =
      if Enum.any?(pivots, &(&1.id == selected)),
        do: selected,
        else: socket.assigns.head_id

    assign(socket, pivots: pivots, selected_pivot_id: selected)
  end

  defp selected_pivot(socket) do
    Enum.find(socket.assigns.pivots, &(&1.id == socket.assigns.selected_pivot_id))
  end

  # Which version the canvas holds, and whether it is a draft: an edit on a
  # named version starts a draft, an edit on a draft does not.
  def load_head(socket) do
    head = Canvas.head_pivot(socket.assigns.canvas_id)
    assign(socket, head_id: head && head.id, head_draft?: head != nil and head.kind == "draft")
  end

  # Called for every edit this editor makes. The context locks the canvas, so
  # when two people start editing a named version at once, one draft starts;
  # the person whose edit started it is asked to name it after the next save.
  def maybe_start_draft(socket, operation) do
    if socket.assigns.head_draft? or not Canvas.versioned_operation?(operation) do
      socket
    else
      case Canvas.start_draft(socket.assigns.canvas_id, socket.assigns.user_id) do
        {:ok, {:created, draft}} ->
          assign(socket, head_id: draft.id, head_draft?: true, pivot_prompt: draft.id)

        _exists_or_error ->
          load_head(socket)
      end
    end
  end

  # The prompt waits for the first save, so the edit that started the draft
  # can be finished before the dialog appears.
  def maybe_prompt_pivot(%{assigns: %{pivot_prompt: nil}} = socket), do: socket

  def maybe_prompt_pivot(%{assigns: %{save_state: :saved, pivot_form: nil}} = socket) do
    socket
    |> open_pivot_dialog(socket.assigns.pivot_prompt)
    |> assign(:pivot_prompt, nil)
  end

  def maybe_prompt_pivot(socket), do: socket

  defp open_pivot_dialog(socket, pivot_id) do
    assign(socket,
      pivot_form: to_form(Canvas.change_pivot(), as: :pivot),
      pivot_target: pivot_id
    )
  end

  defp pivot_label(%{name: nil}), do: "Unnamed changes"
  defp pivot_label(%{name: name}), do: name

  def handle_info({:pivots_changed}, socket) do
    {:halt, socket |> load_head() |> load_pivots()}
  end

  def handle_info(_message, socket), do: {:cont, socket}
end
