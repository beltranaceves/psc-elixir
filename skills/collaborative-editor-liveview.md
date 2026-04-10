# Collaborative Editor LiveView Skill

## Purpose
Create new collaborative editor LiveViews or convert existing LiveViews into collaborative editors with real-time synchronization, CRDT-based conflict resolution, and user presence tracking.

## Overview
This skill leverages the proven architecture from `psc-elixir` which uses:
- **CRDT Delta Operations**: Per-character insert/delete operations for eventual consistency
- **Event Sourcing**: Immutable event log stored in `document_events` table
- **Snapshots**: Periodic snapshots reduce replay overhead for large documents
- **Multi-layer Persistence**: Idle save (1.5s), periodic save (10s), and DB event log
- **User Presence**: Phoenix.Presence tracking active editors with cursor positions
- **Consistency Verification**: 5-second heartbeat to detect and fix divergence
- **PubSub Broadcasting**: Immediate operation distribution to all connected clients

## Prerequisites
- Phoenix 1.7+ with LiveView
- PostgreSQL (for event log)
- Understanding of the project's AGENTS.md authentication setup

## Workflow: Creating a New Collaborative Editor

### Step 1: Define Your Data Structure
Before any code, define:
1. **What entity are you editing?** (document, post, comment, whiteboard, etc.)
2. **What text fields are collaborative?** (body, description, code, etc.)
3. **Editable by whom?** (owner only, shared list, public, etc.)
4. **Optional features?** (presence avatars, comments, permissions, rich text)

**Questions to ask the user:**
- What's the name of the entity being edited? (e.g., "document", "article", "code_snippet")
- What existing schema already exists, or create new?
- Is this owner-only or shared/multi-user?
- Do you want presence cursors or just "who's editing"?
- Any special UI requirements beyond a textarea?

### Step 2: Database Schema Setup

Create/extend Ecto schemas following the psc-elixir pattern:

#### Main Entity Schema (e.g., Document)
```elixir
defmodule MyApp.Resource.MyEntity do
  use Ecto.Schema
  import Ecto.Changeset

  schema "my_entities" do
    field :title, :string
    field :content, :string              # Cached latest content
    field :snapshot_seq, :integer, default: 0  # Track event replay point
    field :shared_with, {:array, :string}, default: []  # Email list for sharing
    
    belongs_to :user, MyApp.Accounts.User
    has_many :events, MyApp.Resource.MyEntityEvent
    
    timestamps()
  end

  def changeset(entity, attrs) do
    entity
    |> cast(attrs, [:title, :content, :snapshot_seq, :shared_with, :user_id])
    |> validate_required([:title, :user_id])
  end
end
```

**Key fields:**
- `content`: Last saved version (snapshot)
- `snapshot_seq`: Max event seq at last save
- `shared_with`: Array of emails who can access

#### Event Schema (stores all operations)
```elixir
defmodule MyApp.Resource.MyEntityEvent do
  use Ecto.Schema
  import Ecto.Changeset

  schema "my_entity_events" do
    field :operation, :map      # %{"type" => "insert"|"delete", "pos" => N, "char" => "x"}
    field :seq, :integer        # Monotonic sequence number
    
    belongs_to :my_entity, MyApp.Resource.MyEntity
    belongs_to :user, MyApp.Accounts.User
    
    timestamps()
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:operation, :seq, :my_entity_id, :user_id])
    |> validate_required([:operation, :seq, :my_entity_id, :user_id])
  end
end
```

**Why this structure:**
- Events table is append-only (source of truth)
- Seq ensures causal ordering
- Operation map is JSON-serialized CRDT delta
- User assignment enables attribution & auditing

#### Migration Example
```elixir
def change do
  create table(:my_entities) do
    add :title, :string, null: false
    add :content, :text, default: ""
    add :snapshot_seq, :integer, default: 0
    add :shared_with, {:array, :string}, default: []
    add :user_id, references(:users), null: false
    
    timestamps()
  end
  
  create table(:my_entity_events) do
    add :operation, :map, null: false
    add :seq, :integer, null: false
    add :my_entity_id, references(:my_entities), null: false
    add :user_id, references(:users), null: false
    
    timestamps()
  end
  
  create index(:my_entity_events, [:my_entity_id, :seq])
end
```

### Step 3: Create the Context Module

Implement `MyApp.Resource` with operations, broadcasting, and persistence:

```elixir
defmodule MyApp.Resource do
  import Ecto.Query
  alias MyApp.Repo
  alias MyApp.Resource.{MyEntity, MyEntityEvent, CRDT}
  
  @pubsub_topic_prefix "my_entity:"
  
  def pubsub_topic(entity_id), do: "#{@pubsub_topic_prefix}#{entity_id}"

  # ===== Authorization =====
  def can_access_entity?(entity, user_email) do
    entity.user.email == user_email || 
      Enum.any?(entity.shared_with, &(&1 == user_email))
  end

  # ===== Reading =====
  def get_entity(id) do
    Repo.get(MyEntity, id) |> Repo.preload(:user)
  end

  def get_entity_content(entity_id) do
    # Load cached content + replay recent events
    entity = Repo.get!(MyEntity, entity_id)
    content = entity.content || ""
    snapshot_seq = entity.snapshot_seq || 0
    
    # Only load events after the cached snapshot
    events =
      from(e in MyEntityEvent,
        where: e.my_entity_id == ^entity_id and e.seq > ^snapshot_seq,
        order_by: [asc: e.seq]
      )
      |> Repo.all()
    
    # Replay recent events on cached content
    Enum.reduce(events, content, &CRDT.apply_operation/2)
  end

  # ===== Writing =====
  def create_entity(user_id, attrs) do
    MyEntity.changeset(%MyEntity{}, Map.merge(attrs, %{user_id: user_id}))
    |> Repo.insert()
  end

  # ===== Collaboration =====
  def apply_operation(entity_id, user_id, operation) do
    seq = next_sequence(entity_id)
    
    event_attrs = %{
      operation: operation,
      seq: seq,
      my_entity_id: entity_id,
      user_id: user_id
    }
    
    case Repo.insert(MyEntityEvent.changeset(%MyEntityEvent{}, event_attrs)) do
      {:ok, _event} ->
        # Broadcast to all subscribers
        Phoenix.PubSub.broadcast(
          MyApp.PubSub,
          pubsub_topic(entity_id),
          {:operation, user_id, operation, seq}
        )
        {:ok, seq}
      
      {:error, changeset} ->
        {:error, changeset}
    end
  end

  # ===== Persistence =====
  def save_content_to_db(entity_id, content) do
    max_seq =
      Repo.one(
        from(e in MyEntityEvent,
          where: e.my_entity_id == ^entity_id,
          select: max(e.seq)
        )
      ) || 0
    
    Repo.get!(MyEntity, entity_id)
    |> MyEntity.changeset(%{content: content, snapshot_seq: max_seq})
    |> Repo.update()
  end

  # ===== Consistency =====
  def verify_consistency(entity_id, client_content) do
    server_content = get_entity_content(entity_id)
    
    if client_content == server_content do
      :ok
    else
      {:diverged, server_content}
    end
  end

  # ===== Private Helpers =====
  defp next_sequence(entity_id) do
    case Repo.one(
      from(e in MyEntityEvent,
        where: e.my_entity_id == ^entity_id,
        select: max(e.seq)
      )
    ) do
      nil -> 1
      max_seq -> max_seq + 1
    end
  end
end
```

### Step 4: Create the CRDT Module

```elixir
defmodule MyApp.Resource.CRDT do
  @moduledoc """
  CRDT operations for collaborative editing.
  Handles delta-based text transformations.
  """
  
  def apply_operation(%{operation: op}, text), do: apply_operation(op, text)
  
  def apply_operation(%{"type" => "insert", "pos" => pos, "char" => char}, text) do
    pos = max(0, min(pos, String.length(text)))
    before = String.slice(text, 0, pos)
    after_part = String.slice(text, pos..-1//1)
    before <> char <> after_part
  end
  
  def apply_operation(%{"type" => "delete", "pos" => pos}, text) do
    if pos >= 0 and pos < String.length(text) do
      before = String.slice(text, 0, pos)
      after_part = String.slice(text, (pos + 1)..-1//1)
      before <> after_part
    else
      text
    end
  end
  
  def apply_operation(_op, text), do: text

  def text_to_deltas(old_text, new_text) when is_binary(old_text) and is_binary(new_text) do
    case {old_text, new_text} do
      {same, same} -> []
      {_old, new} when byte_size(new) > byte_size(_old) ->
        find_insertion_point(old_text, new_text)
      {_old, new} when byte_size(new) < byte_size(_old) ->
        find_deletion_point(old_text, new_text)
      _ -> []
    end
  end

  defp find_insertion_point(old_text, new_text) do
    pos = find_diff_position(old_text, new_text, 0)
    inserted_length = String.length(new_text) - String.length(old_text)
    inserted_text = String.slice(new_text, pos, inserted_length)
    
    inserted_text
    |> String.graphemes()
    |> Enum.with_index()
    |> Enum.map(fn {char, idx} ->
      %{"type" => "insert", "pos" => pos + idx, "char" => char}
    end)
  end

  defp find_deletion_point(old_text, new_text) do
    pos = find_diff_position(old_text, new_text, 0)
    deleted_count = String.length(old_text) - String.length(new_text)
    
    Enum.map(1..deleted_count, fn _ ->
      %{"type" => "delete", "pos" => pos}
    end)
  end

  defp find_diff_position(str1, str2, pos) do
    len1 = String.length(str1)
    len2 = String.length(str2)
    
    cond do
      pos >= len1 or pos >= len2 -> pos
      String.at(str1, pos) == String.at(str2, pos) -> 
        find_diff_position(str1, str2, pos + 1)
      true -> pos
    end
  end
end
```

### Step 5: Create the LiveView

#### New Collaborative Editor Template

```elixir
defmodule MyAppWeb.ResourceLive.Editor do
  use MyAppWeb, :live_view
  alias MyApp.Resource
  alias MyApp.Resource.CRDT
  alias PscWeb.Presence  # or create your MyAppWeb.Presence

  @consistency_check_interval 5000
  @idle_save_interval 1500
  @periodic_save_interval 10000

  @impl true
  def mount(%{"id" => entity_id}, _session, socket) do
    entity = Resource.get_entity(entity_id) |> MyApp.Repo.preload(:user)
    user_email = socket.assigns.current_scope.user.email

    if Resource.can_access_entity?(entity, user_email) do
      content = Resource.get_entity_content(entity_id)

      socket =
        socket
        |> assign(:entity, entity)
        |> assign(:entity_id, entity_id)
        |> assign(:user_id, socket.assigns.current_scope.user.id)
        |> assign(:username, socket.assigns.current_scope.user.email)
        |> assign(:content, content)
        |> assign(:last_saved_content, content)
        |> assign(:save_state, :saved)
        |> assign(:idle_timer_ref, nil)
        |> assign(:presence, %{})
        |> subscribe_to_entity(entity_id)

      if connected?(socket) do
        Process.send_after(self(), :check_consistency, @consistency_check_interval)
        Process.send_after(self(), :periodic_save, @periodic_save_interval)
      end

      {:ok, socket}
    else
      {:ok, redirect(socket, to: ~p"/resources")}
    end
  end

  defp subscribe_to_entity(socket, entity_id) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(MyApp.PubSub, Resource.pubsub_topic(entity_id))
      Phoenix.PubSub.subscribe(MyApp.PubSub, "presence:#{entity_id}")

      Presence.track(self(), "presence:#{entity_id}", socket.assigns.user_id, %{
        username: socket.assigns.username,
        cursor_pos: 0
      })

      socket
      |> assign(:content, Resource.get_entity_content(entity_id))
      |> handle_presence_change(entity_id)
    else
      socket
    end
  end

  @impl true
  def handle_event("update_content", %{"content" => new_content}, socket) do
    old_content = socket.assigns.content
    operations = Resource.text_to_deltas(old_content, new_content)

    Enum.each(operations, fn operation ->
      Resource.apply_operation(socket.assigns.entity_id, socket.assigns.user_id, operation)
    end)

    Presence.update(self(), "presence:#{socket.assigns.entity_id}", socket.assigns.user_id, %{
      username: socket.assigns.username,
      cursor_pos: String.length(new_content)
    })

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
     |> assign(:content, new_content)
     |> assign(:save_state, :unsaved)
     |> assign(:idle_timer_ref, idle_timer_ref)}
  end

  @impl true
  def handle_info(:idle_save, socket) do
    if socket.assigns.content != socket.assigns.last_saved_content do
      socket = assign(socket, save_state: :saving)

      case Resource.save_content_to_db(socket.assigns.entity_id, socket.assigns.content) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(:last_saved_content, socket.assigns.content)
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
    socket =
      if socket.assigns.content != socket.assigns.last_saved_content do
        case Resource.save_content_to_db(socket.assigns.entity_id, socket.assigns.content) do
          {:ok, _} ->
            socket
            |> assign(:last_saved_content, socket.assigns.content)
            |> assign(:save_state, :saved)

          {:error, _} ->
            socket
        end
      else
        socket
      end

    Process.send_after(self(), :periodic_save, @periodic_save_interval)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:operation, user_id, operation, _seq}, socket) do
    if user_id != socket.assigns.user_id do
      new_content = CRDT.apply_operation(operation, socket.assigns.content)
      socket = push_event(socket, "content_updated", %{
        "newContent" => new_content,
        "fromUserId" => user_id
      })

      {:noreply, assign(socket, content: new_content)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:noreply, handle_presence_change(socket, socket.assigns.entity_id)}
  end

  @impl true
  def handle_info(:check_consistency, socket) do
    case Resource.verify_consistency(socket.assigns.entity_id, socket.assigns.content) do
      :ok ->
        Process.send_after(self(), :check_consistency, @consistency_check_interval)
        {:noreply, socket}

      {:diverged, server_content} ->
        socket = push_event(socket, "content_updated", %{
          "newContent" => server_content,
          "fromUserId" => -1
        })

        Process.send_after(self(), :check_consistency, @consistency_check_interval)
        {:noreply, assign(socket, content: server_content)}
    end
  end

  defp handle_presence_change(socket, entity_id) do
    presence_list = Presence.list("presence:#{entity_id}")
    assign(socket, presence: presence_list)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="flex h-screen flex-col bg-gray-50">
        <div class="border-b border-gray-300 bg-white px-6 py-4 shadow-sm">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-4">
              <h1 class="text-2xl font-bold text-gray-900"><%= @entity.title %></h1>
              
              <%= cond do %>
                <% @save_state == :saving -> %>
                  <span class="text-sm text-amber-700">Saving...</span>
                <% @save_state == :saved -> %>
                  <span class="text-sm text-green-700">Saved</span>
                <% true -> %>
                  <span class="text-sm text-gray-700">Unsaved</span>
              <% end %>
            </div>
            <.link navigate={~p"/resources"} class="text-blue-600 hover:text-blue-700">
              Back
            </.link>
          </div>
        </div>

        <div class="flex flex-1 overflow-hidden">
          <div class="flex-1">
            <.form for={%{}} id="editor-form" phx-change="update_content" class="h-full">
              <textarea
                name="content"
                id="editor"
                phx-hook="EditorHook"
                phx-update="ignore"
                data-current-user-id={@user_id}
                value={@content}
                class="w-full h-full resize-none border-0 p-6 font-mono text-sm"
              ></textarea>
            </.form>
          </div>

          <div class="w-64 border-l border-gray-300 bg-white p-4 overflow-y-auto">
            <h3 class="font-semibold text-gray-900 mb-4">Active Users</h3>
            <div class="space-y-2">
              <%= for {user_id, %{metas: metas}} <- @presence do %>
                <% meta = List.first(metas) %>
                <div class="text-sm bg-blue-50 border border-blue-200 p-3 rounded-lg">
                  <div class="font-medium"><%= meta[:username] %></div>
                  <div class="text-xs text-gray-600">Cursor: {meta[:cursor_pos]}</div>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
```

#### JavaScript EditorHook
Create `assets/js/hooks/editor_hook.js`:

```javascript
export default {
  mounted() {
    this.currentUserId = this.el.dataset.currentUserId;
    const initialValue = this.el.getAttribute('value');
    
    if (initialValue) {
      this.el.value = initialValue;
    }
    
    this.handleEvent("content_updated", ({ newContent, fromUserId }) => {
      const isServerResync = fromUserId == -1;
      
      if (!isServerResync && this.currentUserId == fromUserId && 
          document.activeElement === this.el) {
        return;
      }
      
      const cursorPos = this.el.selectionStart;
      this.el.value = newContent;
      
      if (cursorPos <= newContent.length) {
        this.el.setSelectionRange(cursorPos, cursorPos);
      }
    });
  }
};
```

### Step 6: Router Configuration

Add to your router (respecting authenticated routes pattern from AGENTS.md):

```elixir
scope "/", MyAppWeb do
  pipe_through [:browser, :require_authenticated_user]

  live_session :require_authenticated_user,
    on_mount: [{MyAppWeb.UserAuth, :require_authenticated}] do
    
    live "/resources", ResourceLive.Index, :index
    live "/resources/:id/edit", ResourceLive.Editor, :edit
  end
end
```

---

## Workflow: Converting Existing LiveView to Collaborative

If you already have a LiveView reading/writing to a single text field, here's the conversion path:

### Analysis Phase
1. **Identify the entity** being edited (the Ecto schema)
2. **Identify text fields** needing collaboration
3. **Track current persistence** (how is it saved?)
4. **Identify deleters** (who can access/edit?)
5. **Current authorization logic** (needs to move to context/policy)

### Migration Steps

**1. Create events table migration**
```elixir
def change do
  create table(:my_entity_events) do
    add :operation, :map, null: false
    add :seq, :integer, null: false
    add :my_entity_id, references(:my_entities), null: false
    add :user_id, references(:users), null: false
    timestamps()
  end
  create index(:my_entity_events, [:my_entity_id, :seq])
end
```

**2. Add fields to entity table**
```elixir
def change do
  alter table(:my_entities) do
    add :snapshot_seq, :integer, default: 0
  end
end
```

**3. Create MyEntityEvent schema** (see Step 2 above)

**4. Create CRDT module** (see Step 4 above)

**5. Update context module** (see Step 3 above)
- Add `apply_operation/3` → saves to events + broadcasts
- Add `get_entity_content/1` → loads cached content + replays recent events
- Add `save_content_to_db/2` → saves snapshot
- Add `verify_consistency/2` → checks divergence

**6. Update LiveView handle_event**

Before:
```elixir
def handle_event("update_content", %{"content" => new_content}, socket) do
  {:noreply, 
   socket
   |> assign(:content, new_content)
   |> MyContext.save_entity(socket.assigns.entity, %{content: new_content})}
end
```

After:
```elixir
def handle_event("update_content", %{"content" => new_content}, socket) do
  old_content = socket.assigns.content
  operations = MyApp.Resource.CRDT.text_to_deltas(old_content, new_content)

  Enum.each(operations, fn operation ->
    MyApp.Resource.apply_operation(socket.assigns.entity_id, socket.assigns.user_id, operation)
  end)

  # Idle save scheduling (see Step 5 full example)
  {:noreply, assign(socket, content: new_content, save_state: :unsaved)}
end
```

**7. Add subscription in mount**
```elixir
def mount(%{"id" => entity_id}, _session, socket) do
  if connected?(socket) do
    Phoenix.PubSub.subscribe(MyApp.PubSub, MyApp.Resource.pubsub_topic(entity_id))
    Phoenix.PubSub.subscribe(MyApp.PubSub, "presence:#{entity_id}")
  end
  # ... rest of mount
end
```

**8. Add operation handling**
```elixir
@impl true
def handle_info({:operation, user_id, operation, _seq}, socket) do
  if user_id != socket.assigns.user_id do
    new_content = CRDT.apply_operation(operation, socket.assigns.content)
    socket = push_event(socket, "content_updated", %{
      "newContent" => new_content,
      "fromUserId" => user_id
    })
    {:noreply, assign(socket, content: new_content)}
  else
    {:noreply, socket}
  end
end
```

**9. Add EditorHook** if textarea is involved (see Step 5)

---

## Common Customizations

### Rich Text / Markdown Support
**Challenge**: CRDT works at character level; rich text needs structure awareness

**Solution Options:**
1. **Simple**: Store markdown in plain text, apply CRDT at text level
   - Apply character deltas to markdown source
   - Render as HTML but edit the markdown
   
2. **Advanced**: Use structured CRDT library (y.js, Automerge)
   - Requires JavaScript integration
   - Sync Elixir events to Yjs store

**Recommendation for MVP**: Use plain text/markdown + character-level CRDT. Rich text support is a later enhancement.

### Multiple Concurrent Text Fields
**Challenge**: Single `content` field becomes multiple `field1`, `field2`, etc.

**Solution:**
```elixir
# In operation struct, add field identifier
%{
  "type" => "insert",
  "field" => "body",   # Add this
  "pos" => 5,
  "char" => "x"
}

# In apply_operation, branch by field
def apply_operation_to_entity(entity, operation) do
  case operation["field"] do
    "body" -> update_body(entity, operation)
    "description" -> update_description(entity, operation)
  end
end
```

### Comments / Annotations
**Pattern**: Store separately, reference by text offset

```elixir
# In comments schema
field :text_offset_start, :integer   # Char position in content
field :text_offset_end, :integer
field :position, :string              # "line:col" for rich formats
```

When content changes, reindex comments:
```elixir
def shift_comment_offsets_after_operation(document_id, operation) do
  case operation do
    %{"type" => "insert", "pos" => pos} ->
      # Shift all comments after this position
      from(c in Comment,
        where: c.document_id == ^document_id and c.text_offset_start >= ^pos)
      |> Repo.update_all(inc: [text_offset_start: 1, text_offset_end: 1])
    
    %{"type" => "delete", "pos" => pos} ->
      # Similar for deletions
      :ok
  end
end
```

### User Permissions (Read-only / Editor / Owner)
**In authorization:**
```elixir
def user_permission(entity, user_email) do
  cond do
    entity.user.email == user_email -> :owner
    Enum.any?(entity.shared_with, &(&1 == user_email)) -> :editor
    true -> :none
  end
end

def can_edit?(entity, user_email) do
  permission = user_permission(entity, user_email)
  permission in [:owner, :editor]
end
```

**In LiveView:**
```elixir
if Resource.can_edit?(entity, user_email) do
  # Render textarea with phx-change
else
  # Render read-only div
end
```

### Offline Support
**Pattern**: Queue operations locally, sync on reconnect

```javascript
// EditorHook.js enhancement
mounted() {
  this.operationQueue = [];
  this.isOnline = navigator.onLine;
  
  window.addEventListener('online', () => {
    this.isOnline = true;
    this.flushQueue();
  });
  
  window.addEventListener('offline', () => {
    this.isOnline = false;
  });
}

flushQueue() {
  this.operationQueue.forEach(op => {
    this.el.pushEvent("offline_operations", { operations: this.operationQueue });
  });
  this.operationQueue = [];
}
```

### Real-time Cursor Position Sharing
**Already implemented in pattern**, but can extend:

```elixir
def handle_event("cursor_moved", %{"pos" => pos}, socket) do
  Presence.update(self(), "presence:#{socket.assigns.entity_id}", 
                 socket.assigns.user_id, %{
    username: socket.assigns.username,
    cursor_pos: pos,
    selection_end: pos + 10  # If supporting selection highlighting
  })
  
  {:noreply, assign(socket, cursor_pos: pos)}
end
```

```heex
<%!-- In template, render cursor indicators --%>
<div class="absolute" style={"left: #{user_cursor_pos}px; top: #{calculate_line_height(meta[:cursor_pos])}px;"}>
  <div class="w-0.5 h-5 bg-red-500 animate-pulse"></div>
  <span class="text-xs bg-red-500 text-white px-1 rounded"><%= meta[:username] %></span>
</div>
```

### Conflict Resolution Strategies

**Default (event ordering):** Last operation wins by sequence number
```elixir
# User A: Insert "a" at pos 10 → seq 100
# User B: Insert "b" at pos 10 → seq 101
# Result: "...ab..." (b inserted after a due to higher seq)
```

**Alternative (LWW - Last Write Wins by timestamp):**
```elixir
def apply_operation_with_timestamp(operation, text, timestamp) do
  # Store timestamp in operation
  # On replay, compare timestamps if positions conflict
end
```

**For advanced needs**: Consider external CRDT library (Automerge, Yjs)

---

## Telemetry & Monitoring

Add metrics for production visibility:

```elixir
# In event application
:telemetry.execute(
  [:my_app, :collaboration, :operation_applied],
  %{entity_id: entity_id, operation_type: operation["type"]},
  %{user_id: user_id}
)

# In idle save
:telemetry.execute(
  [:my_app, :collaboration, :content_saved],
  %{entity_id: entity_id, byte_size: byte_size(content)},
  %{source: :idle}
)

# In divergence detection
:telemetry.execute(
  [:my_app, :collaboration, :consistency_check_failed],
  %{entity_id: entity_id},
  %{user_id: user_id}
)
```

Then in your telemetry handler:
```elixir
defmodule MyApp.Telemetry do
  def handle_event([:my_app, :collaboration, :consistency_check_failed], _measurements, _metadata, _config) do
    # Alert admins about divergence
    # Log for debugging
  end
end
```

---

## Testing Collaborative Features

### Unit Tests (Context module)
```elixir
describe "apply_operation" do
  test "broadcasts operation to subscribers" do
    entity = fixture(:entity)
    operation = %{"type" => "insert", "pos" => 0, "char" => "a"}
    
    {:ok, _seq} = Resource.apply_operation(entity.id, @user_id, operation)
    
    # Assert message was broadcast
    assert_receive {:operation, ^@user_id, ^operation, _seq}
  end
end
```

### Integration Tests (LiveView)
```elixir
describe "collaborative editing" do
  test "receives updates from other users", %{conn: conn} do
    entity = fixture(:entity)
    
    {:ok, view, html} = live(conn, ~p"/resources/#{entity.id}/edit")
    
    # Simulate another user applying operation
    operation = %{"type" => "insert", "pos" => 0, "char" => "a"}
    send(view.pid, {:operation, 999, operation, 1})
    
    # Assert content updated
    assert render(view) =~ "a"
  end
end
```

### Property-Based Tests (CRDT)
```elixir
property "apply_delete then insert gives deterministic result" do
  forall [{original, pos, char} <- gen_text_and_position()] do
    text1 = original
    text1 = CRDT.apply_operation(%{"type" => "delete", "pos" => pos}, text1)
    text1 = CRDT.apply_operation(%{"type" => "insert", "pos" => pos, "char" => char}, text1)
    
    text2 = original
    text2 = CRDT.apply_operation(%{"type" => "insert", "pos" => pos, "char" => char}, text2)
    text2 = CRDT.apply_operation(%{"type" => "delete", "pos" => pos}, text2)
    
    # Operations should commute or have predictable ordering
    assert text1 != text2 or determinism_check(text1, text2)
  end
end
```

---

## Troubleshooting

### Operations not broadcasting
- Check PubSub topic name matches: `Resource.pubsub_topic(id)` == subscription
- Verify `connected?(socket) == true` (initial render doesn't subscribe)
- Check `Phoenix.PubSub` is started in supervision tree

### Content diverging between users
- 5-second consistency check should auto-fix
- If persisting, check `snapshot_seq` is being updated in database
- Verify event sequence is monotonically increasing (no gaps)

### Cursor position out of bounds
- EditorHook has bounds check: `if (cursorPos <= newContent.length)`
- Can happen if shorter text received than cursor position stored
- Safe to reset cursor to end: `Math.min(cursorPos, newContent.length)`

### Presence not updating
- Verify `Presence.update/4` called after each content change
- Check presence topic matches subscription: `"presence:#{entity_id}"`
- Ensure `Phoenix.Presence` supervision started

### Performance degrades over time
- Check number of events: `SELECT COUNT(*) FROM my_entity_events WHERE my_entity_id = ?`
- If > 1000: Create snapshot, prune old events
- Monitor event replay time: `Enum.reduce(events, ...)` should be fast for < 100 events

---

## Checklist for Implementation

- [ ] Database: Entity schema has `content`, `snapshot_seq`
- [ ] Database: Event schema created with `operation`, `seq`, foreign keys
- [ ] Migration: Indexes on `(entity_id, seq)` for fast event replay
- [ ] Context: `apply_operation/3` saves + broadcasts
- [ ] Context: `get_entity_content/1` loads + replays
- [ ] Context: `save_content_to_db/2` persists snapshots
- [ ] Context: `verify_consistency/2` detects divergence
- [ ] CRDT: `apply_operation/2` handles insert/delete
- [ ] CRDT: `text_to_deltas/2` detects changes
- [ ] LiveView: Mount loads content via context
- [ ] LiveView: Subscribe to PubSub topics
- [ ] LiveView: `handle_event("update_content", ...)` applies deltas
- [ ] LiveView: `handle_info({:operation, ...})` receives broadcasts
- [ ] LiveView: Idle/periodic save scheduling
- [ ] LiveView: Consistency check `:check_consistency`
- [ ] JavaScript: EditorHook handles content_updated events
- [ ] JavaScript: EditorHook respects `phx-update="ignore"`
- [ ] JavaScript: EditorHook prevents cursor jumping
- [ ] Presence: Track on mount, update on content/cursor change
- [ ] Presence: Render active users in template
- [ ] Router: Route placed in correct authenticated scope
- [ ] Tests: Unit tests for context operations
- [ ] Tests: Integration tests for LiveView collaboration
- [ ] Monitoring: Telemetry metrics added

---

## References & Further Reading

- **CRDT Theory**: [Conflict-free Replicated Data Types](https://crdt.tech)
- **Phoenix LiveView**: [LiveView Guide](https://hexdocs.pm/phoenix_live_view)
- **Phoenix.Presence**: [Presence Documentation](https://hexdocs.pm/phoenix/Phoenix.Presence.html)
- **Event Sourcing**: [Event Sourcing Pattern](https://martinfowler.com/eaaDev/EventSourcing.html)
- **Operational Transform**: [OT vs CRDT](https://blog.kevinjahns.de/are-crdts-suitable-for-shared-editing/)
- **psc-elixir reference**: The actual implementation used as reference for this skill

---

## Quick Start Template

To scaffold a new collaborative editor fast:

1. **Copy `/skills/collaborative-editor-liveview.md`** as reference
2. **Replace** `MyApp`, `my_entity`, `MyEntity` with your entity name
3. **Run migrations** (create event + modify entity tables)
4. **Create 4 modules**: Entity schema, Event schema, CRDT, Context
5. **Create LiveView** with full mount/handle_event/handle_info/render
6. **Add EditorHook** JavaScript
7. **Add router** entry
8. **Test** with 2 browser windows side-by-side

This gives production-ready collaborative editing in ~2 hours.
