defmodule PscWeb.UnstrCanvasLive.Index do
  use PscWeb, :live_view

  import PscWeb.CoreComponents, except: [button: 1]
  import PscWeb.Components.UI.Button
  import PscWeb.Components.TemplatePreview

  alias Psc.Canvas
  alias Psc.Canvas.Structure
  alias PscWeb.Components.UI.Dialog, as: UIDialog

  @impl true
  def mount(_params, _session, socket) do
    user_id = socket.assigns.current_scope.user.id
    user_email = socket.assigns.current_scope.user.email

    my_canvases = Canvas.list_user_unstr_canvases(user_id)
    shared_canvases = Canvas.list_shared_unstr_canvases(user_email)
    # Only templates this user may use: their own plus ones shared with them.
    templates = Canvas.list_templates(socket.assigns.current_scope.user)

    {:ok,
     socket
     |> assign(:my_canvases, my_canvases)
     |> assign(:shared_canvases, shared_canvases)
     |> assign(:new_canvas_form, to_form(%{}))
     |> assign(:templates, templates)
     |> assign(:selected_template_id, "")
     |> assign(:delete_canvas, nil)}
  end

  # Picking a starting point is a click on its card. The id lands in the form's
  # hidden input, so the submit carries it like a select's value would. Only
  # ids the picker offered are accepted - blank, or one of the templates the
  # user can access - so a forged one cannot sit in the draft waiting for a
  # submit. A built-in template's id is its stable slug.
  @impl true
  def handle_event("select_template", %{"id" => id}, socket) do
    if id == "" or Enum.any?(socket.assigns.templates, &(template_id(&1) == id)) do
      {:noreply, assign(socket, :selected_template_id, id)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("create_canvas", params, socket) do
    name = params["name"]
    description = params["description"]
    template_id = params["template_id"]

    user = socket.assigns.current_scope.user

    case create_canvas(user, name, description, template_id) do
      {:ok, canvas} ->
        # Creating is the start of work, not a list update: land the user in
        # the canvas they just asked for, the way the catalog's Use does.
        {:noreply,
         socket
         |> put_flash(:success, "Canvas created successfully")
         |> redirect(to: ~p"/canvas/#{canvas.id}")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You do not have access to that template")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create canvas")}
    end
  end

  # Deleting asks first, in a dialog. The card's button only opens it: the id
  # waits in an assign, so nothing is removed until the dialog's own button
  # sends `delete_canvas` — a native `confirm()` cannot guard a `phx-click`,
  # because returning false from `onclick` does not stop LiveView's handler.
  @impl true
  def handle_event("confirm_delete_canvas", %{"id" => id}, socket) do
    user_id = socket.assigns.current_scope.user.id

    case Canvas.get_unstr_canvas(id) do
      %{author_id: ^user_id} = canvas ->
        {:noreply, assign(socket, :delete_canvas, canvas)}

      _other ->
        {:noreply, put_flash(socket, :error, "Unauthorized")}
    end
  end

  @impl true
  def handle_event("dismiss_delete_canvas", _params, socket) do
    {:noreply, assign(socket, :delete_canvas, nil)}
  end

  @impl true
  def handle_event("delete_canvas", %{"id" => id}, socket) do
    user_id = socket.assigns.current_scope.user.id

    case socket.assigns.delete_canvas do
      %{id: ^id, author_id: ^user_id} ->
        # Re-read: another tab may have removed the canvas while the dialog
        # was open, and deleting the stale struct would raise.
        case Canvas.get_unstr_canvas(id) do
          %{author_id: ^user_id} = canvas ->
            Canvas.delete_unstr_canvas(canvas)

            {:noreply,
             socket
             |> assign(:my_canvases, Canvas.list_user_unstr_canvases(user_id))
             |> assign(:delete_canvas, nil)
             |> put_flash(:success, "Canvas deleted")}

          _other ->
            {:noreply,
             socket
             |> assign(:delete_canvas, nil)
             |> put_flash(:error, "That canvas is no longer there")}
        end

      _other ->
        {:noreply,
         socket
         |> assign(:delete_canvas, nil)
         |> put_flash(:error, "Unauthorized")}
    end
  end

  # The creation paths, routed by the picker's id: blank (the empty
  # structure) or a template instantiated through the context — which
  # transforms the template's nested cell metadata into the flat cell shape a
  # canvas expects; copying the template's layout_map verbatim is rejected by
  # the canvas changeset. The name/description typed in the form win over the
  # template's.
  defp create_canvas(user, name, description, template_id) do
    attrs = %{"name" => name, "description" => description || ""}

    case template_id do
      "" ->
        Canvas.create_unstr_canvas(user.id, Map.put(attrs, "cells", Canvas.blank_cells()))

      other ->
        case template_for(user, other) do
          {:ok, template} ->
            Canvas.instantiate_template(template, user.id, attrs)

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  # A picker id is a template's slug (built-ins) or its id (user templates).
  defp template_for(_user, template_id) when template_id in [nil, ""], do: :blank

  defp template_for(user, template_id) do
    template =
      Canvas.get_template_by_slug(template_id) || Canvas.get_template_with_author(template_id)

    cond do
      is_nil(template) ->
        {:error, :not_found}

      Canvas.can_access_template?(template, user.email) ->
        {:ok, template}

      true ->
        {:error, :unauthorized}
    end
  end

  defp template_id(template), do: template.slug || template.id

  # A library card states what the canvas is: the layout mode, and for a table
  # its matrix. A blank structure has no dimensions worth printing.
  defp layout_caption(cells) do
    label =
      case Structure.mode(cells) do
        :bento -> "Bento"
        :image -> "Image"
        _ -> "Table"
      end

    if Structure.empty?(cells), do: label, else: "#{label} · #{dimensions(cells)}"
  end

  defp created_label(%NaiveDateTime{} = at), do: Calendar.strftime(at, "%d %b %Y")
  defp created_label(%DateTime{} = at), do: Calendar.strftime(at, "%d %b %Y")
  defp created_label(_at), do: "—"

  # "Edited 3h ago" reads better than a date, and it is the field the list is
  # ordered by. Negative diff (clock skew) falls into "just now".
  defp edited_label(%NaiveDateTime{} = at),
    do: relative_time(NaiveDateTime.diff(NaiveDateTime.utc_now(), at), at)

  defp edited_label(%DateTime{} = at),
    do: relative_time(DateTime.diff(DateTime.utc_now(), at), at)

  defp edited_label(_at), do: "—"

  defp relative_time(seconds, _at) when seconds < 60, do: "just now"
  defp relative_time(seconds, _at) when seconds < 3_600, do: "#{div(seconds, 60)}m ago"
  defp relative_time(seconds, _at) when seconds < 86_400, do: "#{div(seconds, 3_600)}h ago"
  defp relative_time(seconds, _at) when seconds < 2_592_000, do: "#{div(seconds, 86_400)}d ago"
  defp relative_time(_seconds, at), do: Calendar.strftime(at, "%d %b %Y")

  defp iso8601(%NaiveDateTime{} = at), do: NaiveDateTime.to_iso8601(at)
  defp iso8601(%DateTime{} = at), do: DateTime.to_iso8601(at)
  defp iso8601(_at), do: nil

  defp delete_description(canvas) do
    audience =
      if canvas.shared_with in [nil, []], do: "", else: " for everyone it is shared with"

    ~s("#{canvas.name}" and its notes will be removed#{audience}. This cannot be undone.)
  end

  # The picker card's states: the selected card carries the primary border and
  # tint, the rest stay quiet until hovered.
  defp picker_card_class(selected?) do
    [
      "flex w-40 shrink-0 flex-col gap-2 rounded-xl border p-3 text-left transition-colors",
      selected? && "border-primary/60 bg-primary/10",
      not selected? && "border-base-content/10 bg-base-200 hover:border-base-content/25"
    ]
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      header_title="Canvases"
      container_class="w-full mx-auto max-w-screen-xl"
    >
      <div class="mx-auto w-full max-w-6xl">
        <%!-- Start a canvas: templates first, so the structure is chosen before naming --%>
        <div class="mb-6 rounded-xl border border-base-content/10 bg-base-200 p-4 sm:p-6">
          <h2 class="mb-4 text-lg font-medium text-base-content">Start a canvas</h2>
          <.form
            for={@new_canvas_form}
            id="new-canvas-form"
            phx-submit="create_canvas"
            class="space-y-4"
          >
            <div>
              <span class="label mb-1">Start from</span>

              <%!-- The picker: the catalog first, then blank, then a card per
              template (the built-in defaults included). The choice is made with
              the eyes — a layout is the one thing a dropdown cannot show. The
              selected id rides to the submit in the hidden input below, the way
              a select's value would. --%>
              <%!-- On a phone the strip is wider than the screen and the
              scrollbar is hidden, so the arrows make the panning explicit. The
              buttons live outside `#template-picker`: that element's children
              are the cards, in order (the catalog spec relies on it). --%>
              <div id="template-carousel" class="relative" phx-hook=".TemplateCarousel">
                <div
                  id="template-picker"
                  class="canvas-grid-scroll flex gap-3 overflow-x-auto pb-1"
                >
                  <%!-- The catalog is a link, not a choice: a dashed card, like
                every other action card in the app. It navigates in this tab
                like the catalog entry in the app header. --%>
                  <.link
                    id="template-picker-catalog"
                    navigate={~p"/catalog"}
                    class="flex w-40 shrink-0 flex-col gap-2 rounded-xl border border-dashed border-base-content/25 bg-base-200 p-3 text-left transition-colors hover:border-base-content/45 hover:bg-base-content/5"
                  >
                    <span class="flex h-16 items-center justify-center">
                      <span class="flex size-10 items-center justify-center rounded-full bg-primary/10 text-primary">
                        <.icon name="hero-book-open" class="size-5" />
                      </span>
                    </span>

                    <span class="break-words text-sm font-medium text-base-content">
                      Browse the catalog
                    </span>
                    <span class="text-xs text-base-content/50">Public templates</span>
                  </.link>

                  <button
                    type="button"
                    id="template-picker-blank"
                    phx-click="select_template"
                    phx-value-id=""
                    aria-pressed={to_string(@selected_template_id == "")}
                    aria-label="Start from a blank canvas"
                    class={picker_card_class(@selected_template_id == "")}
                  >
                    <.mini_preview layout_map={%{"rows" => [], "columns" => []}} />

                    <span class="break-words text-sm font-medium text-base-content">
                      Blank canvas
                    </span>
                    <span class="text-xs text-base-content/50">Build it in place</span>
                  </button>

                  <button
                    :for={template <- @templates}
                    type="button"
                    id={"template-picker-#{template_id(template)}"}
                    phx-click="select_template"
                    phx-value-id={template_id(template)}
                    aria-pressed={to_string(@selected_template_id == template_id(template))}
                    aria-label={"Start from #{template.name}"}
                    class={picker_card_class(@selected_template_id == template_id(template))}
                  >
                    <.mini_preview layout_map={template.layout_map} />

                    <span class="break-words text-sm font-medium text-base-content">
                      {template.name}
                    </span>
                    <span class="text-xs text-base-content/50">
                      {PscWeb.Components.TemplatePreview.dimensions(template.layout_map)}
                    </span>
                  </button>
                </div>

                <button
                  type="button"
                  data-carousel-prev
                  aria-label="Scroll templates left"
                  class="absolute left-1 top-1/2 z-10 flex size-9 -translate-y-1/2 items-center justify-center rounded-full border border-base-content/15 bg-base-100/95 text-base-content/70 shadow-lg backdrop-blur transition hover:text-base-content focus:outline-none focus-visible:ring-2 focus-visible:ring-primary invisible opacity-0 lg:hidden"
                >
                  <.icon name="hero-chevron-left" class="size-5" />
                </button>

                <button
                  type="button"
                  data-carousel-next
                  aria-label="Scroll templates right"
                  class="absolute right-1 top-1/2 z-10 flex size-9 -translate-y-1/2 items-center justify-center rounded-full border border-base-content/15 bg-base-100/95 text-base-content/70 shadow-lg backdrop-blur transition hover:text-base-content focus:outline-none focus-visible:ring-2 focus-visible:ring-primary invisible opacity-0 lg:hidden"
                >
                  <.icon name="hero-chevron-right" class="size-5" />
                </button>
              </div>
            </div>

            <input type="hidden" name="template_id" value={@selected_template_id} />

            <.input
              field={@new_canvas_form[:name]}
              type="text"
              label="Canvas Name"
              placeholder="Enter canvas name..."
              required
            />
            <.input
              field={@new_canvas_form[:description]}
              type="textarea"
              label="Description"
              placeholder="Enter canvas description..."
            />
            <.button type="submit" phx-disable-with="Creating…">
              Create Canvas
            </.button>
          </.form>
        </div>

        <%!-- My Canvases --%>
        <div class="mb-12">
          <h2 class="text-lg font-medium text-base-content mb-4">My Canvases</h2>
          <%= if Enum.empty?(@my_canvases) do %>
            <div class="rounded-xl border border-base-content/10 bg-base-200 p-8 text-center">
              <p class="text-base-content/60">No canvases yet. Create one to get started!</p>
            </div>
          <% else %>
            <div id="my-canvases-grid" class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
              <%= for canvas <- @my_canvases do %>
                <div class="h-full flex flex-col rounded-xl border border-base-content/10 bg-base-200 p-4 transition-colors hover:border-base-content/25">
                  <div class="flex items-start justify-between gap-2">
                    <h3 class="min-w-0 font-medium text-base-content break-words">
                      {canvas.name}
                    </h3>

                    <span class="shrink-0 rounded-full border border-base-content/15 bg-base-content/5 px-2 py-0.5 text-[11px] text-base-content/60">
                      {layout_caption(canvas.cells)}
                    </span>
                  </div>

                  <p
                    :if={canvas.description not in [nil, ""]}
                    class="mt-2 text-sm text-base-content/60 break-words line-clamp-2"
                  >
                    {canvas.description}
                  </p>

                  <div class="mt-3 flex flex-wrap items-center gap-x-3 gap-y-1 text-[11px] text-base-content/45">
                    <span class="flex items-center gap-1.5">
                      <.icon name="hero-calendar-days" class="size-3.5 shrink-0" /> Created
                      <time datetime={iso8601(canvas.inserted_at)}>
                        {created_label(canvas.inserted_at)}
                      </time>
                    </span>

                    <span class="flex items-center gap-1.5">
                      <.icon name="hero-pencil-square" class="size-3.5 shrink-0" /> Edited
                      <time datetime={iso8601(canvas.updated_at)}>
                        {edited_label(canvas.updated_at)}
                      </time>
                    </span>
                  </div>

                  <div class="mt-auto flex items-center gap-2 pt-4">
                    <.link
                      navigate={~p"/canvas/#{canvas.id}"}
                      class="flex-1 rounded-lg bg-primary px-3 py-2 text-center text-sm font-medium text-primary-content transition-opacity hover:opacity-90"
                    >
                      Edit
                    </.link>

                    <.button
                      variant="ghost"
                      size="icon"
                      class="shrink-0 text-base-content/50 hover:bg-error/10 hover:text-error"
                      phx-click="confirm_delete_canvas"
                      phx-value-id={canvas.id}
                      aria-label={"Delete #{canvas.name}"}
                      aria-haspopup="dialog"
                      title="Delete"
                    >
                      <.icon name="hero-trash" class="size-4" />
                    </.button>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>

        <%!-- Shared with Me --%>
        <%= if Enum.any?(@shared_canvases) do %>
          <div>
            <h2 class="text-lg font-medium text-base-content mb-4">Shared with Me</h2>
            <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
              <%= for canvas <- @shared_canvases do %>
                <div class="h-full flex flex-col rounded-xl border border-base-content/10 bg-base-200 p-4 transition-colors hover:border-base-content/25">
                  <div class="flex items-start justify-between gap-2">
                    <h3 class="min-w-0 font-medium text-base-content break-words">
                      {canvas.name}
                    </h3>

                    <span class="shrink-0 rounded-full border border-base-content/15 bg-base-content/5 px-2 py-0.5 text-[11px] text-base-content/60">
                      {layout_caption(canvas.cells)}
                    </span>
                  </div>

                  <p class="mt-1 flex min-w-0 items-center gap-1.5 text-xs text-base-content/50">
                    <span class="shrink-0 rounded-full border border-primary/25 bg-primary/10 px-1.5 py-0.5 text-[10px] text-primary">
                      shared
                    </span>
                    <span class="truncate">by {canvas.author.email}</span>
                  </p>

                  <p
                    :if={canvas.description not in [nil, ""]}
                    class="mt-2 text-sm text-base-content/60 break-words line-clamp-2"
                  >
                    {canvas.description}
                  </p>

                  <div class="mt-3 flex flex-wrap items-center gap-x-3 gap-y-1 text-[11px] text-base-content/45">
                    <span class="flex items-center gap-1.5">
                      <.icon name="hero-calendar-days" class="size-3.5 shrink-0" /> Created
                      <time datetime={iso8601(canvas.inserted_at)}>
                        {created_label(canvas.inserted_at)}
                      </time>
                    </span>

                    <span class="flex items-center gap-1.5">
                      <.icon name="hero-pencil-square" class="size-3.5 shrink-0" /> Edited
                      <time datetime={iso8601(canvas.updated_at)}>
                        {edited_label(canvas.updated_at)}
                      </time>
                    </span>
                  </div>

                  <div class="mt-auto flex items-center gap-2 pt-4">
                    <.link
                      navigate={~p"/canvas/#{canvas.id}"}
                      class="flex-1 rounded-lg bg-primary px-3 py-2 text-center text-sm font-medium text-primary-content transition-opacity hover:opacity-90"
                    >
                      Open
                    </.link>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>

      <%!-- Deleting a canvas is permanent: its cells, its event log and its notes
      go with it. The dialog names the canvas so the wrong card is obvious
      before the button is pressed. --%>
      <UIDialog.dialog
        :if={@delete_canvas}
        id="delete-canvas-dialog"
        open
        on-close="dismiss_delete_canvas"
      >
        <%!-- The close button is the dialog's way out, so it gets a 36 px tap
        target: the shared default is a bare 16 px glyph. --%>
        <UIDialog.dialog_content
          open
          class="sm:max-w-md"
          close_class="right-3 top-3 rounded-lg p-2"
          close_icon_class="size-5"
        >
          <UIDialog.dialog_header>
            <UIDialog.dialog_title>Delete this canvas?</UIDialog.dialog_title>

            <UIDialog.dialog_description>
              {delete_description(@delete_canvas)}
            </UIDialog.dialog_description>
          </UIDialog.dialog_header>

          <UIDialog.dialog_footer class="flex flex-row justify-end gap-2">
            <.button
              type="button"
              variant="outline"
              id="cancel-delete-canvas"
              phx-click="dismiss_delete_canvas"
            >
              Keep it
            </.button>

            <.button
              type="button"
              variant="destructive"
              id="confirm-delete-canvas"
              phx-click="delete_canvas"
              phx-value-id={@delete_canvas.id}
              phx-disable-with="Deleting…"
            >
              Delete
            </.button>
          </UIDialog.dialog_footer>
        </UIDialog.dialog_content>
      </UIDialog.dialog>
    </Layouts.app>

    <%!-- The picker's arrows are a scroll affordance, not state: each one is
    hidden until the strip can move in its direction, and both disappear where
    the strip is wide enough to show the cards outright. --%>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".TemplateCarousel">
      export default {
        mounted() {
          this.track = this.el.querySelector("#template-picker")
          this.prev = this.el.querySelector("[data-carousel-prev]")
          this.next = this.el.querySelector("[data-carousel-next]")
          if (!this.track || !this.prev || !this.next) return

          this.onPrev = () => this.nudge(-1)
          this.onNext = () => this.nudge(1)
          this.prev.addEventListener("click", this.onPrev)
          this.next.addEventListener("click", this.onNext)

          this.onScroll = () => this.update()
          this.track.addEventListener("scroll", this.onScroll, { passive: true })

          // Momentum and wheel pans arrive as scroll events, but a drag or a
          // wheel tick can land before the first one; refresh on the input too
          // so the arrows never lag a gesture by a frame.
          this.onInteract = () => requestAnimationFrame(() => this.update())
          this.track.addEventListener("wheel", this.onInteract, { passive: true })
          this.track.addEventListener("pointerup", this.onInteract)

          this.resize = new ResizeObserver(() => this.update())
          this.resize.observe(this.track)
          this.update()
        },

        destroyed() {
          if (!this.track) return
          this.prev.removeEventListener("click", this.onPrev)
          this.next.removeEventListener("click", this.onNext)
          this.track.removeEventListener("scroll", this.onScroll)
          this.track.removeEventListener("wheel", this.onInteract)
          this.track.removeEventListener("pointerup", this.onInteract)
          this.resize.disconnect()
        },

        nudge(direction) {
          const amount = Math.max(this.track.clientWidth * 0.8, 160)
          const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches
          this.track.scrollBy({ left: direction * amount, behavior: reduceMotion ? "auto" : "smooth" })
        },

        update() {
          const max = this.track.scrollWidth - this.track.clientWidth
          this.toggle(this.prev, this.track.scrollLeft > 4)
          this.toggle(this.next, this.track.scrollLeft < max - 4)
        },

        toggle(button, visible) {
          button.classList.toggle("invisible", !visible)
          button.classList.toggle("opacity-0", !visible)
        }
      }
    </script>
    """
  end
end
