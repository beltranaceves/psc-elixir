defmodule PscWeb.UnstrCanvasLive.PivotPanel do
  @moduledoc """
  The History view of a canvas: its versions drawn as a tree, the one the
  canvas holds marked, the selected version's details, and its canvas,
  read-only (ADR-043). Unnamed drafts are dashed.

  The panel is presentational. It emits `select_pivot`, `name_pivot`,
  `request_load`, `fork_pivot` and `open_pivot` to the editor, which also
  renders `pivot_dialog/1`, `load_dialog/1` and `fork_dialog/1`. The editor fills the `preview`
  slot with the canvas renderer, so a snapshot looks exactly like the canvas.
  """

  use Phoenix.Component

  import PscWeb.CoreComponents, only: [icon: 1]

  alias PscWeb.Components.UI.Button, as: UIButton
  alias PscWeb.Components.UI.Checkbox, as: UICheckbox
  alias PscWeb.Components.UI.Dialog, as: UIDialog
  alias PscWeb.Components.UI.Form, as: UIForm
  alias PscWeb.Components.UI.Input, as: UIInput
  alias PscWeb.Components.UI.Textarea, as: UITextarea

  # The tree's geometry, in pixels: one slot per leaf, one row per depth.
  @node_w 176
  @node_h 56
  @slot_w 196
  @row_h 96

  attr :pivots, :list, required: true
  attr :selected_id, :string, default: nil
  attr :head_id, :string, default: nil

  slot :preview, required: true

  def panel(assigns) do
    selected = Enum.find(assigns.pivots, &(&1.id == assigns.selected_id))
    head = Enum.find(assigns.pivots, &(&1.id == assigns.head_id))

    assigns =
      assigns
      |> assign(:tree, layout(assigns.pivots))
      |> assign(:selected, selected)
      |> assign(:head_draft?, head != nil and draft?(head))

    ~H"""
    <div id="canvas-history" class="min-h-0 w-full flex-1 overflow-y-auto">
      <div class="mx-auto w-full max-w-6xl space-y-3 pb-6">
        <div class="flex flex-wrap items-start justify-between gap-2">
          <div class="min-w-0">
            <h2 class="text-sm font-medium uppercase tracking-wide text-base-content/50">History</h2>
            <p class="mt-0.5 text-xs text-base-content/50">
              {version_count(@pivots)} · editing a version starts a new one under it.
            </p>
          </div>

          <UIButton.button
            :if={@head_draft?}
            type="button"
            id="history-pivot-button"
            size="sm"
            phx-click="open_pivot"
            class="gap-1.5"
          >
            <.icon name="hero-flag" class="size-4" /> Name current changes
          </UIButton.button>
        </div>

        <div
          :if={@pivots == []}
          id="pivot-empty"
          class="rounded-xl border border-dashed border-base-content/15 px-6 py-12 text-center"
        >
          <.icon name="hero-clock" class="mx-auto size-8 text-base-content/30" />
          <p class="mt-3 text-sm font-medium text-base-content/80">No versions yet</p>
          <p class="mx-auto mt-1 max-w-sm text-xs text-base-content/50">
            Edit the canvas to start its first version.
          </p>
        </div>

        <div
          :if={@pivots != []}
          id="pivot-tree"
          class="overflow-x-auto rounded-xl border border-base-content/10 bg-base-200/60 p-4"
        >
          <div class="relative mx-auto" style={"width: #{@tree.width}px; height: #{@tree.height}px;"}>
            <svg
              class="pointer-events-none absolute inset-0 overflow-visible"
              width={@tree.width}
              height={@tree.height}
              aria-hidden="true"
            >
              <path
                :for={edge <- @tree.edges}
                d={edge.d}
                fill="none"
                stroke-width="1.5"
                class={["stroke-base-content/25", edge.draft? && "[stroke-dasharray:4_4]"]}
              />
            </svg>

            <button
              :for={node <- @tree.nodes}
              type="button"
              id={"pivot-node-#{node.pivot.id}"}
              phx-click="select_pivot"
              phx-value-id={node.pivot.id}
              aria-pressed={to_string(node.pivot.id == @selected_id)}
              title={node.pivot.rationale}
              style={"left: #{node.left}px; top: #{node.top}px; width: #{node_w()}px; height: #{node_h()}px;"}
              class={[
                "absolute flex flex-col justify-center rounded-lg border px-3 text-left transition",
                "focus:outline-none focus-visible:ring-2 focus-visible:ring-primary",
                draft?(node.pivot) && "border-dashed",
                node.pivot.id == @selected_id &&
                  "border-primary bg-primary/10 ring-2 ring-primary/30",
                node.pivot.id != @selected_id &&
                  "border-base-content/15 bg-base-100 hover:border-base-content/30"
              ]}
            >
              <span class="flex items-center gap-1.5">
                <span class={[
                  "truncate text-sm font-medium",
                  draft?(node.pivot) && "italic text-base-content/60",
                  !draft?(node.pivot) && "text-base-content"
                ]}>
                  {label(node.pivot)}
                </span>
                <span
                  :if={node.pivot.id == @head_id}
                  class="ml-auto size-2 shrink-0 rounded-full bg-primary"
                  title="The version the canvas holds"
                ></span>
              </span>
              <span class="truncate text-xs text-base-content/50">
                {Calendar.strftime(node.pivot.inserted_at, "%d %b %Y")}
              </span>
            </button>
          </div>
        </div>

        <div
          :if={@selected}
          id="pivot-details"
          class="flex flex-wrap items-start gap-3 rounded-xl border border-base-content/10 bg-base-100 p-4"
        >
          <div class="min-w-[14rem] flex-1">
            <p class="flex items-center gap-2 text-sm font-semibold text-base-content">
              {label(@selected)}
              <span
                :if={@selected.id == @head_id}
                class="rounded-md bg-primary/10 px-1.5 py-0.5 text-[0.7rem] font-medium text-primary"
              >
                Current
              </span>
            </p>
            <p class="mt-0.5 text-xs text-base-content/50">
              {author(@selected)} · {date(@selected)}
            </p>
            <p :if={@selected.rationale} class="mt-2 whitespace-pre-line text-sm text-base-content/80">
              {@selected.rationale}
            </p>
            <p :if={draft?(@selected)} class="mt-2 text-sm text-base-content/60">
              These changes have no name yet. Name them when you know what the pivot is.
            </p>
          </div>

          <div class="flex flex-wrap items-center gap-2">
            <UIButton.button
              :if={draft?(@selected)}
              type="button"
              id="pivot-name"
              size="sm"
              phx-click="name_pivot"
              phx-value-id={@selected.id}
              class="gap-1.5"
            >
              <.icon name="hero-flag" class="size-4" /> Name this version
            </UIButton.button>
            <UIButton.button
              type="button"
              id="pivot-fork"
              variant="outline"
              size="sm"
              phx-click="fork_pivot"
              class="gap-1.5"
            >
              <.icon name="hero-document-duplicate" class="size-4" /> Fork
            </UIButton.button>
            <UIButton.button
              :if={@selected.id != @head_id}
              type="button"
              id="pivot-load"
              variant="outline"
              size="sm"
              phx-click="request_load"
              class="gap-1.5"
            >
              <.icon name="hero-arrow-down-tray" class="size-4" /> Load this version
            </UIButton.button>
          </div>
        </div>

        <div :if={@selected} id="pivot-preview" class="space-y-2">
          <h2 class="flex items-center gap-1.5 text-sm font-medium uppercase tracking-wide text-base-content/50">
            <.icon name="hero-eye" class="size-4" /> Version Preview
          </h2>
          <div class="flex min-h-[28rem] flex-col">
            {render_slot(@preview, @selected)}
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc "The dialog that names a version: opened after an edit, or from History."
  attr :form, :any, required: true

  def pivot_dialog(assigns) do
    ~H"""
    <UIDialog.dialog :if={@form} id="pivot-dialog" open on-close="close_pivot">
      <UIDialog.dialog_content open class="sm:max-w-md">
        <UIDialog.dialog_header>
          <UIDialog.dialog_title>Name this version</UIDialog.dialog_title>
          <UIDialog.dialog_description>
            You changed the canvas, so it is now a new version. Say what the pivot is, or do it
            later from the History tab.
          </UIDialog.dialog_description>
        </UIDialog.dialog_header>

        <%!-- The SaladUI fields, like every other form in the app, so focus and
        errors look the same here. --%>
        <.form for={@form} id="pivot-form" phx-submit="save_pivot" class="space-y-4">
          <UIForm.form_item>
            <UIForm.form_label field={@form[:name]}>Name</UIForm.form_label>
            <UIForm.form_control>
              <UIInput.input
                field={@form[:name]}
                type="text"
                placeholder="Switch to B2B"
                maxlength="120"
              />
            </UIForm.form_control>
            <UIForm.form_message field={@form[:name]} />
          </UIForm.form_item>

          <UIForm.form_item>
            <UIForm.form_label field={@form[:rationale]}>Why are you pivoting?</UIForm.form_label>
            <UIForm.form_control>
              <UITextarea.textarea
                field={@form[:rationale]}
                rows="4"
                placeholder="Interviews show small teams won't pay; mid-market teams will."
                maxlength="2000"
              />
            </UIForm.form_control>
            <UIForm.form_message field={@form[:rationale]} />
          </UIForm.form_item>

          <UIDialog.dialog_footer class="flex flex-row justify-end gap-2 pt-2">
            <UIButton.button type="button" id="pivot-later" variant="outline" phx-click="close_pivot">
              Later
            </UIButton.button>
            <UIButton.button type="submit" id="pivot-save">Save version</UIButton.button>
          </UIDialog.dialog_footer>
        </.form>
      </UIDialog.dialog_content>
    </UIDialog.dialog>
    """
  end

  @doc """
  Loading swaps the canvas for everyone, so it asks first. Nothing is lost:
  unnamed changes stay in the tree.
  """
  attr :pivot, :any, required: true

  def load_dialog(assigns) do
    ~H"""
    <UIDialog.dialog :if={@pivot} id="pivot-load-dialog" open on-close="dismiss_load">
      <UIDialog.dialog_content open class="sm:max-w-md">
        <UIDialog.dialog_header>
          <UIDialog.dialog_title>Load "{label(@pivot)}"?</UIDialog.dialog_title>
          <UIDialog.dialog_description>
            The canvas switches to this version for everyone who has it open. The current
            version stays in the tree, unnamed changes included, so you can load it again.
          </UIDialog.dialog_description>
        </UIDialog.dialog_header>

        <UIDialog.dialog_footer class="flex flex-row justify-end gap-2">
          <UIButton.button type="button" variant="outline" phx-click="dismiss_load">
            Cancel
          </UIButton.button>
          <UIButton.button type="button" id="pivot-confirm-load" phx-click="confirm_load">
            Load version
          </UIButton.button>
        </UIDialog.dialog_footer>
      </UIDialog.dialog_content>
    </UIDialog.dialog>
    """
  end

  @doc """
  Fork asks where the copy goes: a new canvas (with or without the history
  that led to the version), or a new version right under it in this canvas.
  """
  attr :pivot, :any, required: true
  attr :form, :any, required: true

  def fork_dialog(assigns) do
    ~H"""
    <UIDialog.dialog :if={@pivot && @form} id="pivot-fork-dialog" open on-close="dismiss_fork">
      <UIDialog.dialog_content open class="sm:max-w-md">
        <UIDialog.dialog_header>
          <UIDialog.dialog_title>Fork "{label(@pivot)}"</UIDialog.dialog_title>
          <UIDialog.dialog_description>
            Start something new from this version.
          </UIDialog.dialog_description>
        </UIDialog.dialog_header>

        <.form
          for={@form}
          id="pivot-fork-form"
          phx-change="fork_change"
          phx-submit="confirm_fork"
          class="space-y-2"
        >
          <%!-- The checkbox has its own label: inside the radio's label, a
          click on its text would pick the radio instead. --%>
          <div class={[
            "rounded-xl border bg-base-100 p-3 transition-colors",
            fork_mode(@form) == "canvas" && "border-primary/40",
            fork_mode(@form) != "canvas" && "border-base-content/10 hover:border-base-content/20"
          ]}>
            <label for="fork-mode-canvas" class="flex cursor-pointer items-start gap-3">
              <input
                type="radio"
                id="fork-mode-canvas"
                name={@form[:mode].name}
                value="canvas"
                checked={fork_mode(@form) == "canvas"}
                class="mt-1 size-4 shrink-0 accent-primary"
              />
              <span class="min-w-0 flex-1">
                <span class="block text-sm font-medium text-base-content">Into a new canvas</span>
                <span class="mt-0.5 block text-xs text-base-content/55">
                  A separate canvas that you own, starting from this version.
                </span>
              </span>
            </label>
            <label
              :if={fork_mode(@form) == "canvas"}
              for="fork-keep-history"
              class="ml-7 mt-2.5 flex cursor-pointer items-center gap-2 text-sm text-base-content"
            >
              <UICheckbox.checkbox
                id="fork-keep-history"
                name={@form[:keep_history].name}
                value={@form[:keep_history].value == "true"}
              />
              <span>Keep the history that led here</span>
            </label>
          </div>

          <label
            for="fork-mode-here"
            class={[
              "flex cursor-pointer items-start gap-3 rounded-xl border bg-base-100 p-3 transition-colors",
              fork_mode(@form) == "here" && "border-primary/40",
              fork_mode(@form) != "here" && "border-base-content/10 hover:border-base-content/20"
            ]}
          >
            <input
              type="radio"
              id="fork-mode-here"
              name={@form[:mode].name}
              value="here"
              checked={fork_mode(@form) == "here"}
              class="mt-1 size-4 shrink-0 accent-primary"
            />
            <span class="min-w-0 flex-1">
              <span class="block text-sm font-medium text-base-content">In this canvas</span>
              <span class="mt-0.5 block text-xs text-base-content/55">
                A new version right under this one, loaded for everyone, so you can take it
                in another direction.
              </span>
            </span>
          </label>

          <UIDialog.dialog_footer class="flex flex-row justify-end gap-2 pt-2">
            <UIButton.button type="button" variant="outline" phx-click="dismiss_fork">
              Cancel
            </UIButton.button>
            <UIButton.button type="submit" id="pivot-confirm-fork">Fork</UIButton.button>
          </UIDialog.dialog_footer>
        </.form>
      </UIDialog.dialog_content>
    </UIDialog.dialog>
    """
  end

  defp fork_mode(form), do: form[:mode].value || "canvas"

  @doc """
  Places the pivots as a top-down tree: leaves take one slot each, left to
  right in creation order, and a parent sits centred over its children.
  """
  def layout(pivots) do
    children = Enum.group_by(pivots, & &1.parent_id)
    ids = MapSet.new(pivots, & &1.id)
    roots = Enum.reject(pivots, &MapSet.member?(ids, &1.parent_id))

    {placed, leaves} = Enum.reduce(roots, {[], 0}, &place(&1, 0, children, &2))
    by_id = Map.new(placed, &{&1.pivot.id, &1})

    nodes =
      Enum.map(placed, fn node ->
        Map.merge(node, %{left: round(node.slot * @slot_w), top: node.depth * @row_h})
      end)

    edges =
      for node <- nodes, parent <- List.wrap(by_id[node.pivot.parent_id]) do
        x1 = round(parent.slot * @slot_w) + div(@node_w, 2)
        y1 = parent.depth * @row_h + @node_h
        x2 = node.left + div(@node_w, 2)
        y2 = node.top
        mid = div(y1 + y2, 2)

        %{
          d: "M#{x1} #{y1} C#{x1} #{mid} #{x2} #{mid} #{x2} #{y2}",
          draft?: draft?(node.pivot)
        }
      end

    depth = nodes |> Enum.map(& &1.depth) |> Enum.max(fn -> 0 end)

    %{
      nodes: nodes,
      edges: edges,
      width: max(leaves - 1, 0) * @slot_w + @node_w,
      height: depth * @row_h + @node_h
    }
  end

  defp place(pivot, depth, children, {placed, next_slot}) do
    case Map.get(children, pivot.id, []) do
      [] ->
        {[%{pivot: pivot, depth: depth, slot: next_slot} | placed], next_slot + 1}

      kids ->
        {placed, next_slot} =
          Enum.reduce(kids, {placed, next_slot}, &place(&1, depth + 1, children, &2))

        slots = for node <- placed, node.pivot.parent_id == pivot.id, do: node.slot
        slot = (Enum.min(slots) + Enum.max(slots)) / 2
        {[%{pivot: pivot, depth: depth, slot: slot} | placed], next_slot}
    end
  end

  defp author(%{author: %{email: email}}), do: email
  defp author(_pivot), do: "Unknown"

  defp date(pivot), do: Calendar.strftime(pivot.inserted_at, "%d %b %Y, %H:%M UTC")

  defp version_count([_one]), do: "1 version"
  defp version_count(pivots), do: "#{length(pivots)} versions"

  defp draft?(pivot), do: pivot.kind == "draft"

  defp label(%{name: nil}), do: "Unnamed changes"
  defp label(%{name: name}), do: name

  defp node_w, do: @node_w
  defp node_h, do: @node_h
end
