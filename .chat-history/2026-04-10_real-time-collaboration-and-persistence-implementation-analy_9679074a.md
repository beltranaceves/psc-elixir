# Real-time collaboration and persistence implementation analysis

| | |
|---|---|
| **Created** | 2026-04-10 12:40:44 |
| **Last Message** | 2026-04-10 12:40:44 |
| **Model** | Claude Haiku 4.5 |
| **Mode** | agent |
| **User** | Unknown |
| **Session ID** | `9679074a-62f4-489c-9019-93f728d2e7d0` |

---

## User

*2026-04-10 12:45:33*

Read both of these files, and their imports. And explain in detail how they implement real-time collaboration and db persistence + user presence, both in backend and front end. Be very thorough and consider edge cases, like the initial data loading from db into memory and frontend

## Assistant (copilot/claude-haiku-4.5)

<details>
<summary>💭 Thinking — Analyzed LiveView files for real-time collaboration features</summary>

The user wants me to explain in detail how the two LiveView files implement real-time collaboration, DB persistence, and user presence, considering both backend and frontend aspects.

I should read both files thoroughly, look at their imports, and then provide a comprehensive explanation. Let me first examine what files I have access to:

1. `c:\\software\\psc-elixir\\lib\\psc_web\\live\\document_live\\editor.ex` - Editor LiveView
2. `c:\\software\\psc-elixir\\lib\\psc_web\\live\\document_live\\index.ex` - Index/Document List LiveView

Both are already attached. Let me analyze them carefully and provide a detailed explanation covering:
- Real-time collaboration
- DB persistence
- User presence
- Frontend implementation
- Backend implementation
- Edge cases and initial data loading

I should look at the imports, understand the dependencies (CRDT, ConsistencyManager, Presence, Documents, etc.), and explain how all these pieces work together.

Let me start by providing a thorough analysis of both files.

</details>

I'll provide a comprehensive analysis of both files, examining their real-time collaboration, DB persistence, and user presence implementation.

> **🔧 ✓ Reading [](file:///c%3A/software/psc-elixir/lib/psc_web/live/document_live/editor.ex#1-1), lines 1 to 100**

> **🔧 ✓ Reading [](file:///c%3A/software/psc-elixir/lib/psc_web/live/document_live/index.ex#1-1), lines 1 to 80**

> **🔧 ✓ Searching for regex `defmodule Psc.Documents|defmodule Psc.Documents.CRDT|defmodule Psc.Documents.ConsistencyManager|defmodule PscWeb.Presence`**

<details>
<summary>💭 Thinking — Reviewed 2 files and searched for regex patterns</summary>

Good, now let me read more of both files and also the supporting modules to understand the full picture.

</details>

Let me read more of the editor file and the supporting modules to get the complete picture:

> **🔧 ✓ Reading [](file:///c%3A/software/psc-elixir/lib/psc/documents/crdt.ex#1-1), lines 1 to 80**

> **🔧 ✓ Reading [](file:///c%3A/software/psc-elixir/lib/psc/documents.ex#1-1), lines 1 to 100**

> **🔧 ✓ Reading [](file:///c%3A/software/psc-elixir/lib/psc_web/presence.ex)**

> **🔧 ✓ Reading [](file:///c%3A/software/psc-elixir/lib/psc/documents/consistency_manager.ex#1-1), lines 1 to 60**

<details>
<summary>💭 Thinking</summary>

Great, I have good context now. Let me continue reading more to get

</details>

> **🔧 ✓ Reading [](file:///c%3A/software/psc-elixir/lib/psc/documents/crdt.ex#1-1), lines 1 to 80**

> **🔧 ✓ Reading [](file:///c%3A/software/psc-elixir/lib/psc/documents.ex#1-1), lines 1 to 100**

> **🔧 ✓ Reading [](file:///c%3A/software/psc-elixir/lib/psc_web/presence.ex)**

> **🔧 ✓ Reading [](file:///c%3A/software/psc-elixir/lib/psc/documents/consistency_manager.ex#1-1), lines 1 to 60**

<details>
<summary>💭 Thinking</summary>

Great, I have good context now. Let me continue reading more to get a fuller picture. I need to understand:

1. How documents are persisted
2. How events are stored
3. How operations are applied
4. The JS hook for the editor
5. The full editor.ex file

Let me continue reading.

</details>

> **🔧 ✓ Reading [](file:///c%3A/software/psc-elixir/lib/psc/documents.ex#100-100), lines 100 to 230**

> **🔧 ✓ Reading [](file:///c%3A/software/psc-elixir/lib/psc/documents/crdt.ex#80-80), lines 80 to 142**

> **🔧 ✓ Reading [](file:///c%3A/software/psc-elixir/lib/psc_web/live/document_live/editor.ex#120-120), lines 120 to 280**

<details>
<summary>💭 Thinking</summary>

Good, I have enough context. Now let me check if there's a JavaScript hook for the editor component so I can explain the frontend piece completely.

</details>

> **🔧 ✓ Searching for files matching `**/assets/js/hooks/**/*.js`**

> **🔧 ✓ Reading [](file:///c%3A/software/psc-elixir/lib/psc_web/live/document_live/editor.ex#280-280), lines 280 to 360**

<details>
<summary>💭 Thinking</summary>

Great! Now let me read the EditorHook JavaScript file to complete my understanding of how the frontend works.

</details>

> **🔧 ✓ Reading [](file:///c%3A/software/psc-elixir/assets/js/hooks/editor_hook.js)**

<details>
<summary>💭 Thinking</summary>

Perfect! Now I have a complete picture. Let me also check if there's any Document schema to understand how the data is stored in the database.

</details>

> **🔧 ✓ Searching for text `DocumentEvent` (`**/lib/psc/documents/*.ex`)**

> **🔧 ✓ Reading [](file:///c%3A/software/psc-elixir/lib/psc/documents/document.ex)**

<details>
<summary>💭 Thinking</summary>

Good. Let me also read the DocumentEvent schema to understand how events are structured.

</details>

> **🔧 ✓ Reading [](file:///c%3A/software/psc-elixir/lib/psc/documents/document_event.ex)**

> **🔧 ✓ Reading [](file:///c%3A/software/psc-elixir/lib/psc/documents/snapshot_manager.ex#1-1), lines 1 to 80**

<details>
<summary>💭 Thinking — Reviewed 6 files and searched for DocumentEvent</summary>

Excellent! Now I have all the information I need to write a thorough explanation of how this system works. I have:

1. **Backend**:
   - LiveView mounted behavior for editor.ex
   - Document.ex schema - stores document metadata and snapshots
   - DocumentEvent.ex schema - stores individual CRDT operations
   - CRDT.ex - CRDT algorithm implementation for delta-based operations
   - ConsistencyManager.ex - periodic consistency checks
   - SnapshotManager.ex - snapshot management for efficient loading
   - Documents.ex - business logic for document operations
   - PubSub topic subscription and broadcasting

2. **Frontend**:
   - HEEx template with reactive bindings
   - EditorHook.js - JavaScript hook that manages the textarea element
   - Event handling for content updates
   - Presence sidebar showing active users
   - Save status indicator

3. **Real-time collaboration**:
   - Phoenix.PubSub for broadcasting operations
   - CRDT delta operations (insert/delete)
   - Operation sequence tracking
   - Event broadcasting to all connected clients

4. **DB Persistence**:
   - Initial load from content snapshot
   - Replay of recent events
   - Idle save (1.5 seconds)
   - Periodic save (10 seconds) as fallback
   - Snapshot creation every 100 operations

5. **User Presence**:
   - Phoenix.Presence for tracking connected users
   - Cursor position updates
   - Active users sidebar

Now let me structure this into a comprehensive explanation.

</details>

Now I have all the pieces. Let me provide you with a detailed, thorough explanation of how this system implements real-time collaboration, DB persistence, and user presence:

---

## **Comprehensive Architecture Overview**

This system uses a **hybrid CRDT + Event Sourcing + Snapshots** approach built on Phoenix LiveView, PubSub, and PostgreSQL. Here's the complete flow:

---

## **Backend Architecture**

### **1. Database Schema & Persistence Model**

**Document Schema** (Document.ex):
```elixir
schema "documents" do
  field :title, :string
  field :content, :string              # Periodically saved snapshot of current content
  field :snapshot_content, :string     # Legacy snapshot field
  field :snapshot_seq, :integer        # Sequence number up to which content is built
  field :shared_with, {:array, :string}
  field :crdt_state, :string           # Reserved for future extended CRDT state
  
  belongs_to :user
  has_many :events                     # The event log - source of truth for collaboration
end
```

**DocumentEvent Schema** (DocumentEvent.ex):
```elixir
schema "document_events" do
  field :operation, :map               # The delta operation: %{"type" => "insert"|"delete", ...}
  field :seq, :integer                 # Monotonically increasing sequence number
  
  belongs_to :document
  belongs_to :user                     # Tracks which user made the change
  timestamps()                         # Records when the operation occurred
end
```

**Why this architecture?**
- **Content field** = cached snapshot for fast loads
- **snapshot_seq** = marker indicating up to which event seq the content is built
- **Events table** = immutable event log (source of truth for collaboration)
- **seq counter** = ensures causal ordering across all users editing same document

---

### **2. Initial Data Loading from DB → Memory**

When a LiveView mounts ([editor.ex lines 17-47](lib/psc_web/live/document_live/editor.ex#L17-L47)):

```
MOUNT FLOW:
1. Get document from DB with user preload → Authorization check
2. Load document content via SnapshotManager.load_with_snapshot(document_id)
3. Populate socket assigns:
   - @content = currently displayed content
   - @last_saved_content = tracks what's been saved to DB
   - @save_state = :saved (shows user save status)
   - @user_id, @username, @document_id
   - @presence = {} (empty initially)
```

The **SnapshotManager.load_with_snapshot/1** function ([snapshot_manager.ex lines 50-68](lib/psc_web/live/document_live/editor.ex#L50-L68)) is critical:

```elixir
def load_with_snapshot(document_id) do
  document = Repo.get!(Document, document_id)
  
  # Load the cached snapshot
  content = document.content || ""
  snapshot_seq = document.snapshot_seq || 0
  
  # Only load events AFTER the snapshot (not all 10,000 events!)
  events = 
    from(e in DocumentEvent,
      where: e.document_id == ^document_id and e.seq > ^snapshot_seq,
      order_by: [asc: e.seq]
    ) |> Repo.all()
  
  # Replay only recent events on top of cached content
  Enum.reduce(events, content, &CRDT.apply_operation/2)
end
```

**Edge case handling:**
- **Brand new document**: No events exist, returns empty string
- **Document with 1000s of events**: Only replays events after the snapshot_seq marker
- **Long disconnect→reconnect**: Load assumes database is authoritative; no lost events

---

### **3. Real-Time Collaboration: The CRDT Delta Operations**

When user types in the textarea, the flow is:

**A. Client-side detection** ([editor.ex line 83](lib/psc_web/live/document_live/editor.ex#L83)):
```elixir
def handle_event("update_content", %{"content" => new_content}, socket) do
  old_content = socket.assigns.content
  
  # Detect minimal changes between old and new
  operations = Documents.text_to_operations(old_content, new_content)
```

**B. Delta diff algorithm** ([crdt.ex lines 85-135](lib/psc_web/live/document_live/editor.ex#L85-L135)):

```elixir
# If inserting "hello" → Find the first character that differs
# Elixir represents operations as:
%{"type" => "insert", "pos" => 5, "char" => "h"}
%{"type" => "insert", "pos" => 6, "char" => "e"}
%{"type" => "insert", "pos" => 7, "char" => "l"}
# ... one operation per character

# For deletions: Same approach, just track position
%{"type" => "delete", "pos" => 5}
```

**Why per-character deltas?**
- Handles concurrent edits better (OT/CRDT friendly)
- Enables fine-grained per-character attribution
- If User A deletes "he" and User B deletes "llo" concurrently, operations replay correctly

**C. Broadcast to all clients** ([documents.ex lines 110-145](lib/psc/documents.ex#L110-L145)):

```elixir
def apply_operation(document_id, user_id, operation) do
  # Get next sequence number
  seq = next_sequence(document_id)  # Query MAX(seq) + 1
  
  # Save to event log (DB)
  event_attrs = %{
    operation: operation,
    seq: seq,
    document_id: document_id,
    user_id: user_id
  }
  Repo.insert(DocumentEvent.changeset(%DocumentEvent{}, event_attrs))
  
  # Broadcast immediately to all others
  Phoenix.PubSub.broadcast(
    Psc.PubSub,
    "document:#{document_id}",           # Topic: document:{id}
    {:operation, user_id, operation, seq}
  )
end
```

**D. Receive broadcasts on other clients** ([editor.ex lines 244-258](lib/psc_web/live/document_live/editor.ex#L244-L258)):

```elixir
@impl true
def handle_info({:operation, user_id, operation, _seq}, socket) do
  # Avoid echo: don't apply operations originating from self
  if user_id != socket.assigns.user_id do
    # Apply the delta operation directly to current content
    new_content = CRDT.apply_operation(operation, socket.assigns.content)
    
    # Push event to JavaScript hook for UI update
    socket = push_event(socket, "content_updated", 
                       %{"newContent" => new_content, "fromUserId" => user_id})
    
    {:noreply, assign(socket, content: new_content)}
  else
    {:noreply, socket}  # Ignore echoes
  end
end
```

**Critical edge case - Echo suppression:**
The system has **dual echo-suppression**:
1. **Server side** (line 246): Don't apply operations back to originating user
2. **Client side** (EditorHook.js): Skip updates if user is actively typing in the textarea

---

## **DB Persistence: Multi-Layer Save Strategy**

The system uses **3 different save mechanisms** working in concert:

### **Layer 1: Idle Save (1.5 seconds after last keystroke)**

```elixir
# When user stops typing for 1.5 seconds
def handle_info(:idle_save, socket) do
  if socket.assigns.content != socket.assigns.last_saved_content do
    case Documents.save_content_to_db(socket.assigns.document_id, socket.assigns.content) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:last_saved_content, socket.assigns.content)
         |> assign(:save_state, :saved)
         |> assign(:idle_timer_ref, nil)}
```

When user types:
1. Cancel pending idle timer
2. Schedule new 1.5-second timer
3. Only fire once → User types continuously for 10 seconds, only saves once at the end

### **Layer 2: Periodic Save (every 10 seconds, safety fallback)**

```elixir
def handle_info(:periodic_save, socket) do
  socket =
    if socket.assigns.content != socket.assigns.last_saved_content do
      # Save if content changed
      Documents.save_content_to_db(socket.assigns.document_id, socket.assigns.content)
```

This is a **safety net**: if idle save fails or doesn't fire, content saves anyway every 10 seconds.

### **Layer 3: What Actually Gets Saved?**

```elixir
def save_content_to_db(document_id, content) do
  # Get the current max sequence number
  max_seq = Repo.one(
    from(e in DocumentEvent,
      where: e.document_id == ^document_id,
      select: max(e.seq)
    )
  ) || 0
  
  # Save TWO things:
  document
  |> Document.changeset(%{
    content: content,           # The current text
    snapshot_seq: max_seq       # Up to which event seq it's built
  })
  |> Repo.update()
end
```

**Why snapshot_seq?**
- When loading next time, only replay events AFTER this seq
- Example: Save at seq=50, later 10 more events occur (seq 51-60)
- Load: use cached content + replay only seq 51-60 (10 replays vs 60)

---

### **Snapshots: Heavy Optimization for old documents**

After **100 operations**, create a full snapshot:

```elixir
def create_snapshot(document_id) do
  document = Repo.get!(Document, document_id)
  
  max_seq = Repo.one(
    from(e in DocumentEvent,
      where: e.document_id == ^document_id,
      select: max(e.seq)
    )
  ) || 0
  
  # Rebuild content from ALL events (expensive but infrequent)
  content = rebuild_from_snapshot(document_id)
  
  # Store snapshot
  document
  |> Document.changeset(%{
    snapshot_content: content,
    snapshot_seq: max_seq  # Reset: next load only replays seq > max_seq
  })
  |> Repo.update()
end
```

**Timeline:**
- Operations 1-100: accumulate in events table
- At 101: DB triggers snapshot, content saved + snapshot_seq = 100
- Operations 101-200: accumulate  
- At 201: Snapshot again
- Load at 250: 0 events to replay! (All baked into content at seq 200)

---

## **Consistency: The 5-Second Heartbeat Check**

Every 5 seconds, each client verifies it hasn't diverged from server truth:

```elixir
def handle_info(:check_consistency, socket) do
  case ConsistencyManager.verify_consistency(
    socket.assigns.document_id, 
    socket.assigns.content
  ) do
    :ok ->
      # Consistent, schedule next check
      Process.send_after(self(), :check_consistency, @consistency_check_interval)
      {:noreply, socket}
      
    {:diverged, server_text} ->
      # CRITICAL: Client diverged! Force resync to server truth
      socket = push_event(socket, "content_updated", %{
        "newContent" => server_text,
        "fromUserId" => -1  # Special ID = server resync
      })
      
      # Log for debugging
      :telemetry.execute(
        [:psc, :document, :consistency_divergence],
        %{document_id: socket.assigns.document_id, user_id: socket.assigns.user_id}
      )
      
      {:noreply, assign(socket, content: server_text)}
  end
end
```

**Edge cases caught:**
- Network packet loss causing operations not to broadcast
- Database write failures not reflected to client
- Browser local memory corruption
- Multiple tabs (rare, but handled)

---

## **User Presence Tracking**

### **Server Side: Phoenix.Presence**

```elixir
defp subscribe_to_document(socket, document_id) do
  if connected?(socket) do
    # Subscribe to presence change broadcasts
    Phoenix.PubSub.subscribe(Psc.PubSub, "presence:#{document_id}")
    
    # Track THIS user
    Presence.track(self(), "presence:#{document_id}", socket.assigns.user_id, %{
      username: socket.assigns.username,
      cursor_pos: 0
    })
```

`Presence.track/4` usage:
- **self()** = current LiveView process
- **"presence:#{document_id}"** = presence topic (separate from operation topic)
- **user_id** = unique key for this user in this document
- **metadata map** = data to track (username, cursor_pos)

### **Cursor Updates**

When user moves cursor or types:

```elixir
def handle_event("update_cursor", %{"pos" => pos}, socket) do
  Presence.update(self(), "presence:#{socket.assigns.document_id}", 
                 socket.assigns.user_id, %{
    username: socket.assigns.username,
    cursor_pos: pos  # Client sends cursor position
  })
  
  {:noreply, assign(socket, cursor_pos: pos)}
end
```

When content updates (typing):

```elixir
def handle_event("update_content", %{"content" => new_content}, socket) do
  # ... apply operations ...
  
  # Also update presence with new cursor
  Presence.update(self(), "presence:#{socket.assigns.document_id}", 
                 socket.assigns.user_id, %{
    username: socket.assigns.username,
    cursor_pos: String.length(new_content)  # Cursor at end
  })
```

### **Rendering Active Users**

```heex
<div class="w-64 border-l border-gray-300 bg-white p-4">
  <h3>Active Users</h3>
  <%= for {user_id, %{metas: metas}} <- @presence do %>
    <% meta = List.first(metas) %>
    <div class="text-sm text-gray-900 p-3 rounded-lg">
      <div class="font-medium"><%= meta[:username] %></div>
      <div class="text-xs text-gray-600">
        Cursor: <span class="font-mono"><%= meta[:cursor_pos] %></span>
      </div>
    </div>
  <% end %>
</div>
```

**How @presence gets updated:**

```elixir
def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
  {:noreply, handle_presence_change(socket, socket.assigns.document_id)}
end

defp handle_presence_change(socket, document_id) do
  presence_list = Presence.list("presence:#{document_id}")
  assign(socket, presence: presence_list)
end
```

Phoenix.Presence automatically broadcasts "presence_diff" when users join/leave/update.

---

## **Frontend: JavaScript Hook Integration**

The **EditorHook.js** manages the textarea with special logic:

```javascript
mounted() {
  this.currentUserId = this.el.dataset.currentUserId;
  
  // Listen for server-pushed events
  this.handleEvent("content_updated", ({ newContent, fromUserId }) => {
    const isServerResync = fromUserId == -1;
    
    // CRITICAL: Skip if user is actively typing their own change
    if (!isServerResync && this.currentUserId == fromUserId && 
        document.activeElement === this.el) {
      return;  // User is typing, don't overwrite
    }
    
    // Get current cursor to preserve it
    const cursorPos = this.el.selectionStart;
    
    // Update textarea
    this.el.value = newContent;
    
    // Restore cursor if possible
    if (cursorPos <= newContent.length) {
      this.el.setSelectionRange(cursorPos, cursorPos);
    }
  });
}
```

**Why this matters:**
- User types "hello" locally
- Server broadcasts their operation back to them (echo from others)
- Hook sees `` + textarea is focused
- Skips the update, prevents cursor jumping
- But if server-sync happens (``), always applies regardless

---

## **The Index/DocumentLive.Index Component**

Less complex, but uses PubSub for document list updates:

```elixir
def mount(_params, _session, socket) do
  if connected?(socket) do
    # Subscribe to user-specific document events
    Phoenix.PubSub.subscribe(
      Psc.PubSub, 
      "user:#{socket.assigns.current_scope.user.id}:documents"
    )
  end
  
  # Load user's documents and shared documents
  user_email = socket.assigns.current_scope.user.email
  documents = Documents.list_user_documents(socket.assigns.current_scope.user.id)
  shared_documents = Documents.list_shared_documents(user_email)
```

When a new document is created:

```elixir
def handle_event("create_document", %{"title" => title}, socket) do
  case Documents.create_document(socket.assigns.current_scope.user.id, 
                                %{title: title_trimmed}) do
    {:ok, document} ->
      # Broadcast to all connected sessions of this user
      Phoenix.PubSub.broadcast(
        Psc.PubSub,
        "user:#{socket.assigns.current_scope.user.id}:documents",
        {:document_created, document}
      )
      
      {:noreply, socket |> assign(show_new_form: false) 
                        |> put_flash(:info, "Document created")}
```

```elixir
def handle_info({:document_created, document}, socket) do
  # Refresh the user's document lists
  documents = Documents.list_user_documents(socket.assigns.current_scope.user.id)
  shared_documents = Documents.list_shared_documents(user_email)
  {:noreply, assign(socket, documents: documents, shared_documents: shared_documents)}
end
```

This handles the edge case where the user opens the index in 2 tabs and creates a document in one → the other tab refreshes automatically.

---

## **Edge Cases Handled**

| Edge Case | Handling |
|-----------|----------|
| User A deletes "test", User B types "ing" concurrently | CRDT deltas applied at correct positions due to seq ordering |
| Network drops for 30 seconds | Operations accumulate in DB, consistency check resyncs on reconnect |
| User has document open in 2 browser tabs | Tab 1 types → DB saved → Tab 2's consistency check fires, resyncs |
| Database write fails | Idle save queues retry in next timer, shows "Unsaved" to user |
| 1000+ operations on document | Snapshot mechanism kicks in, future loads instant |
| User loses focus mid-operation | Presence.update still fires with cursor pos |
| Server resync needed | fromUserId = -1 forces update even if user is typing |

---

## **Summary of Data Flow**

```
EDITING FLOW:
User types → textarea fires phx-change → handle_event detects delta
→ Creates operations per character → Calls Documents.apply_operation
→ Saves to document_events table → PubSub broadcasts immediately
→ All connected clients receive {:operation, ...} message
→ Handle_info applies CRDT.apply_operation → Pushes event to JS hook
→ EditorHook updates textarea (if not from current user)
→ Every 1.5s idle: Content saved to documents.content + snapshot_seq

LOADING FLOW:
New user mounts → Documents.get_document_content
→  SnapshotManager.load_with_snapshot(doc_id)
→ Load documents.content (), always applies regardless

---

## **The Index/DocumentLive.Index Component**

Less complex, but uses PubSub for document list updates:

```elixir
def mount(_params, _session, socket) do
  if connected?(socket) do
    # Subscribe to user-specific document events
    Phoenix.PubSub.subscribe(
      Psc.PubSub, 
      "user:#{socket.assigns.current_scope.user.id}:documents"
    )
  end
  
  # Load user's documents and shared documents
  user_email = socket.assigns.current_scope.user.email
  documents = Documents.list_user_documents(socket.assigns.current_scope.user.id)
  shared_documents = Documents.list_shared_documents(user_email)
```

When a new document is created:

```elixir
def handle_event("create_document", %{"title" => title}, socket) do
  case Documents.create_document(socket.assigns.current_scope.user.id, 
                                %{title: title_trimmed}) do
    {:ok, document} ->
      # Broadcast to all connected sessions of this user
      Phoenix.PubSub.broadcast(
        Psc.PubSub,
        "user:#{socket.assigns.current_scope.user.id}:documents",
        {:document_created, document}
      )
      
      {:noreply, socket |> assign(show_new_form: false) 
                        |> put_flash(:info, "Document created")}
```

```elixir
def handle_info({:document_created, document}, socket) do
  # Refresh the user's document lists
  documents = Documents.list_user_documents(socket.assigns.current_scope.user.id)
  shared_documents = Documents.list_shared_documents(user_email)
  {:noreply, assign(socket, documents: documents, shared_documents: shared_documents)}
end
```

This handles the edge case where the user opens the index in 2 tabs and creates a document in one → the other tab refreshes automatically.

---

## **Edge Cases Handled**

| Edge Case | Handling |
|-----------|----------|
| User A deletes "test", User B types "ing" concurrently | CRDT deltas applied at correct positions due to seq ordering |
| Network drops for 30 seconds | Operations accumulate in DB, consistency check resyncs on reconnect |
| User has document open in 2 browser tabs | Tab 1 types → DB saved → Tab 2's consistency check fires, resyncs |
| Database write fails | Idle save queues retry in next timer, shows "Unsaved" to user |
| 1000+ operations on document | Snapshot mechanism kicks in, future loads instant |
| User loses focus mid-operation | Presence.update still fires with cursor pos |
| Server resync needed | fromUserId = -1 forces update even if user is typing |

---

## **Summary of Data Flow**

```
EDITING FLOW:
User types → textarea fires phx-change → handle_event detects delta
→ Creates operations per character → Calls Documents.apply_operation
→ Saves to document_events table → PubSub broadcasts immediately
→ All connected clients receive {:operation, ...} message
→ Handle_info applies CRDT.apply_operation → Pushes event to JS hook
→ EditorHook updates textarea (if not from current user)
→ Every 1.5s idle: Content saved to documents.content + snapshot_seq

LOADING FLOW:
New user mounts → Documents.get_document_content
→  SnapshotManager.load_with_snapshot(doc_id)
→ Load documents.content (the cached snapshot)
→ Load events where seq > snapshot_seq
→ Replay recent events to rebuild current state
→ Return full content, populate socket

CONSISTENCY FLOW:
Every 5 seconds → Server builds content from all events
→ Compares with client's assumed content
→ If diverged → Force resync (fromUserId = -1)
→ Client receives and applies regardless of focus state
```

This architecture elegantly balances **real-time collaboration** (instant broadcasts), **eventual consistency** (periodic verification), and **data durability** (multiple save layers).

---

## User

*2026-04-10 12:47:42*

using all of this information, develop and write an agent SKILL to create a collaborative editor liveview for any ui/structure the user desires, or convert a current liveview to a collaborative one

## Assistant (copilot/claude-haiku-4.5)

<details>
<summary>💭 Thinking</summary>

The user wants me to create an agent SKILL file that can help users create or convert LiveView components

</details>

<details>
<summary>💭 Thinking</summary>

The user wants me to create an agent SKILL file that can help users create or convert LiveView components into collaborative editors based on the patterns I just analyzed from their codebase.

A SKILL file is a special file used to customize VS Code agents' behavior. Looking at the agent-customization skill description, I need to understand what a SKILL.md file should contain.

This should be a comprehensive skill that:
1. Understands the collaborative editor architecture (CRDT, events, snapshots, presence)
2. Can convert existing LiveViews to collaborative editors
3. Can scaffold new collaborative editors from scratch
4. Knows all the patterns from the psc-elixir codebase

Let me create a well-structured SKILL.md file that would guide an agent (or the user) through creating/converting collaborative editors.

</details>

> **🔧 ✓ Tool call**

> **🔧 ✓ Creating [](file:///c%3A/software/psc-elixir/skills/collaborative-editor-liveview.md)**

> *[Code edit applied]*

<details>
<summary>💭 Thinking — Created collaborative-editor-liveview.md</summary>

Great! I've created a comprehensive SKILL file for collaborative editor LiveViews. Now I should provide a brief summary to the user explaining what was created and how they can use it.

</details>

I've created a comprehensive **Collaborative Editor LiveView Skill** at `collaborative-editor-liveview.md` that serves as a complete guide for building or converting LiveViews into collaborative editors.

## What the Skill Covers

### **For Creating New Editors:**
- **Step-by-step workflow** with all required modules (Entity schema, Event schema, CRDT, Context, LiveView, JavaScript hook)
- **Complete code templates** for every component
- **Database schema patterns** with migrations
- **Authorization patterns** for sharing

### **For Converting Existing LiveViews:**
- **Analysis checklist** to identify what needs changing
- **Migration steps** showing before/after code
- **Gradual conversion path** (don't rewrite everything at once)

### **Advanced Customizations:**
- Rich text/Markdown support strategies
- Multiple concurrent text fields
- Comments & annotations with offset tracking
- User permission levels (read-only, editor, owner)
- Offline support patterns
- Real-time cursor position sharing
- Conflict resolution strategies
- Telemetry & production monitoring

### **Quality Assurance:**
- Unit testing patterns for context operations
- Integration testing for LiveView collaboration
- Property-based tests for CRDT correctness
- Troubleshooting guide for common issues
- Complete implementation checklist
- Performance monitoring

## Key Architecture Points Documented

The skill captures all the patterns from `psc-elixir`:

✅ **CRDT Delta Operations** – Per-character insert/delete for eventual consistency  
✅ **Event Sourcing** – Immutable event log as source of truth  
✅ **Snapshot Optimization** – Periodic snapshots reduce event replay overhead  
✅ **Multi-layer Persistence** – Idle save + periodic save + DB event log  
✅ **User Presence** – Phoenix.Presence for active editors & cursor positions  
✅ **Consistency Verification** – 5-second heartbeat to detect and fix divergence  
✅ **Echo Suppression** – Dual layer protection against self-updates  
✅ **Browser Compatibility** – EditorHook prevents cursor jumping & preserves focus

## How to Use

**For an Agent:**
An agent can use this skill to intelligently scaffold or modify collaborative editor LiveViews by understanding the complete architecture, database design, and code patterns.

**For You:**
- **Quick reference** when building new collaborative features
- **Copy-paste templates** to accelerate development
- **Troubleshooting guide** when things go wrong
- **Testing strategies** for validation

The skill includes a **Quick Start section** at the end that lets you scaffold a new collaborative editor in ~2 hours.

---

