defmodule PscWeb.UnstrCanvasLive.Editor.Notes do
  @moduledoc """
  The Notes tab: the note list (or a scratchpad's single note), the open
  note's collaborative text with its own idle save, presence and remote
  operations.
  """
  use PscWeb, :html
  import Phoenix.LiveView

  alias Psc.Canvas.NotesMode
  alias Psc.Notes
  alias PscWeb.Presence
  alias PscWeb.UnstrCanvasLive.Editor.Operations
  alias PscWeb.UnstrCanvasLive.NotesPanel
  alias PscWeb.UnstrCanvasLive.Save
  require Logger

  @doc "Adds the Notes tab's assigns and registers its hooks."
  def attach(socket) do
    socket
    |> assign(:notes, [])
    |> assign(:note, nil)
    |> assign(:note_content, "")
    |> assign(:note_html, "")
    |> assign(:note_last_saved_content, "")
    |> assign(:note_idle_timer_ref, nil)
    |> assign(:note_save_state, :saved)
    |> assign(:note_save_stats, Operations.initial_save_stats())
    |> assign(:note_topic, nil)
    |> assign(:note_presence, %{})
    |> attach_hook(__MODULE__, :handle_event, &handle_event/3)
    |> attach_hook(__MODULE__, :handle_info, &handle_info/2)
  end

  def handle_event("select_note", %{"note" => note_id}, socket) do
    {:halt,
     push_patch(
       socket,
       to: ~p"/canvas/#{socket.assigns.canvas_id}?tab=notes&note=#{note_id}",
       replace: true
     )}
  end

  def handle_event("create_note", _params, socket) do
    if NotesMode.single?(socket.assigns.canvas.notes_mode) do
      # A scratchpad has one note. Opening the view created it already, so
      # there is nothing to create.
      {:halt, socket}
    else
      case Notes.create_note(socket.assigns.canvas_id, socket.assigns.user_id, %{
             title: "Untitled note"
           }) do
        {:ok, note} ->
          {:halt,
           socket
           |> reload_notes()
           |> push_patch(
             to: ~p"/canvas/#{socket.assigns.canvas_id}?tab=notes&note=#{note.id}",
             replace: true
           )}

        {:error, _changeset} ->
          {:halt, put_flash(socket, :error, "Could not create the note")}
      end
    end
  end

  def handle_event("delete_note", %{"note" => note_id}, socket) do
    # Deleting a note is the canvas author's alone, like the canvas's
    # structure. The note itself carries no access rules.
    if socket.assigns.canvas.author_id == socket.assigns.user_id do
      case Notes.get_note(note_id) do
        %{canvas_id: canvas_id} = note when canvas_id == socket.assigns.canvas_id ->
          case Notes.delete_note(note) do
            {:ok, _note} ->
              {:halt,
               socket
               |> assign(:note, nil)
               |> assign(:note_content, "")
               |> assign(:note_html, "")
               |> assign(:note_last_saved_content, "")
               |> reload_notes()
               |> push_patch(to: ~p"/canvas/#{socket.assigns.canvas_id}?tab=notes", replace: true)
               |> put_flash(:success, "Note deleted")}

            {:error, _changeset} ->
              {:halt, put_flash(socket, :error, "Could not delete the note")}
          end

        _other ->
          {:halt, socket}
      end
    else
      {:halt, put_flash(socket, :error, "Only the canvas owner can delete a note")}
    end
  end

  def handle_event("update_note_title", %{"title" => title}, socket) do
    case socket.assigns.note do
      nil ->
        {:halt, socket}

      note ->
        case Notes.update_note(note, %{title: title}) do
          {:ok, updated} ->
            {:halt,
             socket
             |> assign(:note, updated)
             |> reload_notes()}

          {:error, _changeset} ->
            {:halt, put_flash(socket, :error, "Could not rename the note.")}
        end
    end
  end

  def handle_event("update_note_content", %{"content" => new_content}, socket) do
    case socket.assigns.note do
      nil ->
        {:halt, socket}

      note ->
        operations = Notes.text_to_operations(socket.assigns.note_content, new_content)

        Enum.each(operations, fn operation ->
          Notes.apply_operation(
            note.id,
            socket.assigns.user_id,
            operation,
            socket.assigns.client_id
          )
        end)

        socket =
          if socket.assigns.note_idle_timer_ref do
            Process.cancel_timer(socket.assigns.note_idle_timer_ref)
            assign(socket, note_idle_timer_ref: nil)
          else
            socket
          end

        note_idle_timer_ref =
          Process.send_after(self(), :note_idle_save, Operations.idle_save_interval())

        {:halt,
         socket
         |> assign(:note_content, new_content)
         |> assign(:note_html, NotesPanel.render_html(new_content))
         |> assign(:note_idle_timer_ref, note_idle_timer_ref)
         |> assign(:note_save_state, :unsaved)}
    end
  end

  def handle_event("render_note", %{"content" => content}, socket) do
    {:halt,
     push_event(socket, "note_rendered", %{
       content: content,
       html: NotesPanel.render_html(content)
     })}
  end

  def handle_event(_event, _params, socket), do: {:cont, socket}

  # The notes of the canvas, most recently touched first. The snippet is
  # derived once here instead of on every render.
  defp reload_notes(socket) do
    assign(socket, :notes, NotesPanel.with_snippets(Notes.list_notes(socket.assigns.canvas_id)))
  end

  # A scratchpad canvas has exactly one note, and no list. It is created the
  # first time the Notes view is opened, so a canvas that is never written in
  # costs no rows.
  def load_notes(socket) do
    if NotesMode.single?(socket.assigns.canvas.notes_mode) do
      socket
      |> reload_notes()
      |> ensure_scratchpad()
    else
      reload_notes(socket)
    end
  end

  defp ensure_scratchpad(socket) do
    case socket.assigns.notes do
      [note | _] ->
        content = Notes.get_note_content(note.id)

        socket
        |> leave_note()
        |> assign(:note, note)
        |> assign(:note_content, content)
        |> assign(:note_html, NotesPanel.render_html(content))
        |> assign(:note_last_saved_content, content)
        # Single-note canvases never went through load_note_by_id/2, so they
        # never subscribed: remote operations were broadcast to nobody.
        |> subscribe_to_note(note.id)
        |> push_note_resync()

      [] ->
        case Notes.create_note(
               socket.assigns.canvas_id,
               socket.assigns.user_id,
               %{title: "Scratchpad"}
             ) do
          {:ok, note} ->
            socket
            |> assign(:notes, NotesPanel.with_snippets([note]))
            |> assign(:note, note)
            |> assign(:note_content, "")
            |> assign(:note_html, "")
            |> assign(:note_last_saved_content, "")
            |> assign(:note_save_state, :saved)
            |> assign(:note_save_stats, Operations.initial_save_stats())
            |> subscribe_to_note(note.id)
            |> push_note_resync()

          {:error, _changeset} ->
            socket
        end
    end
  end

  # Open a note, if it belongs to this canvas. A note id from another canvas is
  # ignored: the canvas is the only thing that grants access. A scratchpad
  # canvas has one note and cannot choose another.
  def load_note(socket, note_id) do
    if NotesMode.single?(socket.assigns.canvas.notes_mode) do
      socket
    else
      load_note_by_id(socket, note_id)
    end
  end

  defp load_note_by_id(socket, note_id) when note_id in [nil, ""] do
    socket
    |> leave_note()
    |> assign(:note, nil)
    |> assign(:note_content, "")
    |> assign(:note_html, "")
    |> assign(:note_last_saved_content, "")
    |> assign(:note_save_state, :saved)
    |> assign(:note_save_stats, Operations.initial_save_stats())
  end

  defp load_note_by_id(socket, note_id) do
    case Notes.get_note(note_id) do
      %{canvas_id: canvas_id} = note when canvas_id == socket.assigns.canvas_id ->
        content = Notes.get_note_content(note.id)

        socket
        |> leave_note()
        |> assign(:note, note)
        |> assign(:note_content, content)
        |> assign(:note_html, NotesPanel.render_html(content))
        |> assign(:note_last_saved_content, content)
        |> assign(:note_save_state, :saved)
        |> assign(:note_save_stats, Operations.initial_save_stats())
        |> subscribe_to_note(note.id)
        |> push_note_resync()

      _other ->
        socket
        |> leave_note()
        |> assign(:note, nil)
        |> assign(:note_content, "")
        |> assign(:note_html, "")
        |> assign(:note_last_saved_content, "")
        |> assign(:note_save_state, :saved)
        |> assign(:note_save_stats, Operations.initial_save_stats())
    end
  end

  # Stop listening to the note that was open, so a stale topic cannot deliver
  # operations for a note that is no longer on screen. Flush first: the idle
  # timer is about to be cancelled, and the note's events would otherwise stay
  # unfolded until it was edited and saved again.
  defp leave_note(socket) do
    socket = flush_note(socket)

    if socket.assigns[:note_topic] do
      Phoenix.PubSub.unsubscribe(Psc.PubSub, socket.assigns.note_topic)
      Presence.untrack(self(), socket.assigns.note_topic, socket.assigns.user_id)
    end

    if socket.assigns[:note_idle_timer_ref] do
      Process.cancel_timer(socket.assigns.note_idle_timer_ref)
    end

    assign(socket, note_topic: nil, note_presence: %{}, note_idle_timer_ref: nil)
  end

  defp flush_note(socket) do
    case socket.assigns[:note] do
      nil ->
        socket

      note ->
        if socket.assigns.note_content != socket.assigns.note_last_saved_content do
          save_note_content(socket, note)
        else
          socket
        end
    end
  end

  defp subscribe_to_note(socket, note_id) do
    if connected?(socket) do
      topic = Notes.pubsub_topic(note_id)
      :ok = Phoenix.PubSub.subscribe(Psc.PubSub, topic)

      # The canvas's presence says who is on the canvas; this one says who has
      # *this note* open, which is what the note header reports. It shares the
      # note's topic, so the diffs arrive on the subscription above.
      Presence.track(self(), topic, socket.assigns.user_id, %{
        username: socket.assigns.username
      })

      assign(socket,
        note_topic: topic,
        note_presence: Presence.list(topic)
      )
    else
      socket
    end
  end

  # The editor's textarea is owned by the client hook (`phx-update="ignore"`),
  # so it never picks up the server's content from a re-render — it only gets
  # what is pushed. A `-1` marks a resync rather than somebody's edit. Without
  # it, a note opened after an edit (or between its static render and its
  # socket connecting) showed stale text until the next keystroke elsewhere.
  defp push_note_resync(socket) do
    if connected?(socket) and socket.assigns.note do
      push_event(socket, "note_content_updated", %{
        content: socket.assigns.note_content,
        html: NotesPanel.render_html(socket.assigns.note_content),
        from_user_id: -1
      })
    else
      socket
    end
  end

  # A remote operation on the open note: fold it in and hand the result to the
  # editor, whose textarea is not re-rendered (`phx-update="ignore"`).
  #
  # The rendered Markdown travels with it. The editor usually sits in its
  # preview, and the preview is only re-asked for on blur, so a reader would
  # otherwise see nothing change until they clicked into the note.
  defp apply_remote_note_operation(socket, user_id, operation) do
    if socket.assigns.note do
      new_content = Psc.Text.apply_operation(operation, socket.assigns.note_content)
      html = NotesPanel.render_html(new_content)

      {:halt,
       socket
       |> assign(:note_content, new_content)
       |> assign(:note_html, html)
       |> push_event("note_content_updated", %{
         content: new_content,
         html: html,
         from_user_id: user_id
       })}
    else
      {:halt, socket}
    end
  end

  def handle_info(:note_idle_save, socket) do
    case socket.assigns.note do
      nil ->
        {:halt, assign(socket, note_idle_timer_ref: nil)}

      note ->
        if socket.assigns.note_content != socket.assigns.note_last_saved_content do
          socket =
            socket
            |> assign(:note_save_state, :saving)
            |> save_note_content(note)
            |> assign(:note_idle_timer_ref, nil)

          socket =
            cond do
              socket.assigns.note_save_state != :unsaved ->
                # The list shows a snippet of the note's content, so it has to
                # be re-read now that the content has been folded.
                reload_notes(socket)

              Notes.get_note(note.id) ->
                # The note still exists: retry shortly instead of waiting for
                # the user to type again.
                ref = Process.send_after(self(), :note_idle_save, Operations.idle_save_interval())
                assign(socket, :note_idle_timer_ref, ref)

              true ->
                socket
            end

          {:halt, socket}
        else
          {:halt, assign(socket, note_idle_timer_ref: nil)}
        end
    end
  end

  def handle_info({:note_operation, user_id, client_id, operation, _seq}, socket) do
    # The broadcast names the client that wrote it, not just the user, so this
    # view ignores its own echo and nothing else: another tab of the same user
    # is a different client and must still see the edit.
    if client_id != socket.assigns.client_id do
      apply_remote_note_operation(socket, user_id, operation)
    else
      {:halt, socket}
    end
  end

  # An operation applied straight through the context (no client id): there is
  # no client to compare, so the user is the only thing to go on.
  def handle_info({:note_operation, user_id, operation, _seq}, socket) do
    if user_id != socket.assigns.user_id do
      apply_remote_note_operation(socket, user_id, operation)
    else
      {:halt, socket}
    end
  end

  def handle_info(_message, socket), do: {:cont, socket}

  defp save_note_content(socket, note) do
    socket =
      Save.commit(socket, :note, fn ->
        Notes.save_content_to_db(note.id, socket.assigns.note_content)
      end)

    if socket.assigns.note_save_state == :unsaved do
      Logger.error("[UnstrCanvasLive] note save failed: note_id=#{note.id}")
    end

    socket
  end
end
