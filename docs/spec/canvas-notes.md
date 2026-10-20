# Canvas notes

## Overview

A **note** is a collaborative Markdown document that belongs to a canvas. It lives
inside the canvas's **Notes** view, is edited by the same people who can edit the
canvas, and disappears with it.

> **Terminology.** A **canvas** is one configurable workspace; a **template** is the
> reusable structure a canvas is created from; a **note** is a piece of shared
> Markdown inside a canvas. The surfaces are `PscWeb.UnstrCanvasLive` (the canvas
> editor, which hosts the Notes view), `PscWeb.NotesLive` (the note editor) and
> `Psc.Documents` (the standalone documents feature, parked — see
> [ADR-018](../design-decisions.md#adr-018--documents-is-parked-as-a-standalone-feature)).
> The tables are `unstr_canvases`, `notes` and `note_events`.

## Design principle

A note is **not** a document with a back-reference. It is a child of a canvas, and
it inherits the canvas's access rules wholesale. There is no second permission
system, no second share dialog and no second list of collaborators: if you can
open the canvas, you can read and edit its notes; if you cannot, the notes are
not reachable at all.

The collaboration machinery is **shared, not copied**. The write-ahead log, the
folded snapshot, the sequence numbering, the pruning and the consistency check
are lifted out of `Psc.Documents` into one generic store that both documents and
notes use.

## Data model

### `notes`

| Column | Type | Notes |
|---|---|---|
| `id` | `binary_id` | Primary key, matching `unstr_canvases`. |
| `canvas_id` | `binary_id` | FK → `unstr_canvases.id`, `on_delete: :delete_all`. **Not null.** |
| `title` | `:string` | Short label, editable. |
| `content` | `:text` | The folded snapshot of the Markdown. This *is* the snapshot — there is no second copy. |
| `snapshot_seq` | `:integer` | How far `content` has been folded through. Default `0`. |
| `created_by_id` | `bigint` | FK → `users.id`, `on_delete: :nilify_all`. **Attribution only** — never used for access control. |
| `inserted_at` / `updated_at` | `:utc_datetime` | |

**There is no `shared_with` column and no owner column.** See
[Permissions](#permissions).

### `note_events`

| Column | Type | Notes |
|---|---|---|
| `id` | `binary_id` | Primary key. |
| `note_id` | `binary_id` | FK → `notes.id`, `on_delete: :delete_all`. **Not null.** |
| `user_id` | `bigint` | FK → `users.id`, `on_delete: :nilify_all`. Who made the edit — used to avoid echoing a user's own operation back to them, and for audit. |
| `operation` | `:map` | The CRDT delta. |
| `seq` | `:integer` | Monotonic per note. |

Unique index on `(note_id, seq)` — the same guarantee `document_events` has.

### Ecto relationships

```elixir
# Psc.Canvas.UnstrCanvas
has_many :notes, Psc.Notes.Note, foreign_key: :canvas_id, on_delete: :delete_all

# Psc.Notes.Note
belongs_to :canvas, Psc.Canvas.UnstrCanvas
belongs_to :created_by, Psc.Accounts.User
has_many :events, Psc.Notes.NoteEvent, foreign_key: :note_id, on_delete: :delete_all

# Psc.Notes.NoteEvent
belongs_to :note, Psc.Notes.Note
belongs_to :user, Psc.Accounts.User
```

Deleting a canvas therefore removes its notes, and deleting a note removes its
events, through the database's own cascades. Nothing has to be cleaned up in
application code.

## Permissions

The canvas is the only permission boundary. A note has no access rules of its own.

| Action | Who can do it | Rule |
|---|---|---|
| See the Notes view | Anyone with canvas access | `Canvas.can_access_unstr_canvas?/2`, checked **once**, when the canvas editor mounts. |
| Read a note | Anyone with canvas access | Same check. There is no per-note check anywhere. |
| Create a note | Anyone with canvas access | Same as editing a cell. |
| Edit a note's content | Anyone with canvas access | Same as editing a cell. |
| Rename a note | Anyone with canvas access | Same as renaming a cell's label. |
| Delete a note | **The canvas author only** | Mirrors the owner-only rule for canvas structure. |

Consequences that are deliberate:

- **Sharing the canvas shares its notes.** The share dialog stays where it is, on
  the canvas header. There is no share control on a note, and no
  `shared_with` column to keep in sync.
- **A note's `created_by_id` is not an access rule.** It records who wrote it.
  Removing a user from the canvas removes their access to the notes they wrote;
  the attribution stays.
- **The canvas editor is the only place access is checked.** The Notes view is a
  tab inside it, so the check has already happened. A note is never loaded
  outside that LiveView, and there is no `/notes/:id` route that would need its
  own check.

## The shared text store

`Psc.Documents` already implements the exact algorithm a note needs: an append-only
event log, a folded snapshot on the row, a `snapshot_seq` marker, pruning of the
events the snapshot covers, and a periodic consistency check that resyncs a
diverged client.

That algorithm is lifted into one place rather than copied.

### `Psc.Text` — the pure text operations

The table-independent half of `Psc.Documents.CRDT`:

- `apply_operation(operation, text)` — apply one delta.
- `text_to_deltas(old_text, new_text)` — diff two strings into deltas.
- `hash(text)` — checksum, for the consistency check.

`Psc.Documents.CRDT` keeps only what is document-specific (`load_events/1`,
`rebuild_text/1`) and delegates the rest to `Psc.Text`.

### `Psc.TextStore` — the log + snapshot algorithm

The table-dependent half, parameterised by the two schema modules:

| Function | Purpose |
|---|---|
| `next_sequence(store, event, id)` | The next monotonic sequence number, floored at `snapshot_seq` (pruned events must not be re-used). |
| `load_content(store, event, id)` | The folded content plus the events recorded after it, replayed in order. |
| `save_content(store, event, id, content)` | Fold the content into the row, advance `snapshot_seq`, and prune the events it covers. Pruning happens only after the marker is durably stored. |
| `apply_operation(store, event, id, user_id, operation, topic)` | Append the event and broadcast it. |
| `pending_event_count(store, event, id)` | How many operations are not yet folded. |
| `sweep_folded_events(store, event)` | Delete events at or below their owner's `snapshot_seq` — for notes abandoned before their first save. |

`Psc.Documents` becomes a thin façade over it, and `Psc.Notes` is the second
caller. The sequence numbering, the flooring rule, the prune-after-durable-marker
rule and the `max(seq)`/`snapshot_seq` comparison exist in exactly one place.

### The free-tier row ceiling

The deployed database caps every table at 10 000 rows. A note that is typed into
continuously must not accumulate event rows, so the same discipline as canvases
applies:

- Every idle save folds the pending operations into `content` and prunes the
  events it covers.
- A fold is also forced when the pending count crosses a threshold, so a
  continuous typing burst cannot outrun the idle timer.
- `Psc.EventsSweeper` gains a third table (`note_events`), so notes abandoned
  before their first save do not keep their event tail forever.

## Behaviour

### The note mode

A template decides how its canvases behave, and the canvas inherits it:

- **`multi`** — a list of notes. The canvas can hold as many as the work needs.
- **`single`** — one scratchpad for the whole canvas.

The single-note mode is deliberately restrictive. For a framework like the
Problem–Solution Canvas, limiting how much can be written down is the point: one
page of thinking, not five.

The mode lives in the template's `layout_map` (`"notes_mode"`), is chosen in the
**template designer**, and is copied onto the canvas as `unstr_canvases.notes_mode`
when the canvas is instantiated. A canvas made before this setting existed gets
`multi`.

**What changes in the single-note mode:**

- The Notes view has **no list** — it is not rendered at all. The editor takes
  the whole view.
- The scratchpad is created the first time the Notes view is opened, so a canvas
  that is never written in costs no rows.
- There is no "New note" action: there is only the one note.
- The note cannot be deleted. Deleting it would simply bring it back on the
  next visit.
- The URL cannot choose a note: a scratchpad canvas ignores a note id.

Everything else is the same — the note is still collaborative Markdown, it still
inherits the canvas's access, and the canvas owner can still rename it.

### Notes a template carries

A template can come with notes. A canvas made from it starts with a copy of
them, the same way it starts with a copy of the template's cells.

The template's notes are part of its definition, so they live in the template's
`layout_map` under `"notes"` — a list of `%{"title" => ..., "content" => ...}`.
The **template designer** authors them in its Notes section: an *Add note*
action, and a card per note with a title and a Markdown body.

- In `multi` mode the designer holds any number of them, and the canvas starts
  with all of them.
- In `single` mode there is only the scratchpad, so the designer holds one —
  switching a template that carries several notes to the scratchpad mode keeps
  the first and drops the rest.

The copy is **independent**: editing a note in the canvas never touches the
template, exactly as editing a cell never does (ADR-009).

### The Notes view

The canvas editor's tab strip already has a **Notes** tab, currently a
placeholder. It becomes the notes view.

**Desktop (from `lg`)** — two panes:

- **Left (260 px):** the list of the canvas's notes, most recently touched
  first: title, a one-line snippet, and the relative time it was last touched.
  A **New note** action at the top.
- **Right:** the selected note's editor, or an empty state.

**Phones and tablets** — one pane at a time: the list, and tapping a note
replaces it with the editor, with a back action to return to the list.

The empty state says so and offers the create action. The list is empty until a
note exists; the view never shows a blank panel.

The note editor sits in the same rounded panel as the grid, so the two views
read as one surface. Its header holds the title, the status pill and — for the
canvas owner — a delete action; the row wraps on a narrow screen.

### The note editor

The editor is the document editor's mechanics, rebuilt as a reusable component
rather than a copy:

- A **title** input at the top.
- A **Markdown editor** with the same inline preview behaviour as the document
  editor: a click on the rendered Markdown opens the textarea, blurring it
  re-renders the preview. There is no "Markdown preview / Editing Markdown"
  banner above it — the state is obvious from what is on screen.

  The editor draws its own frame — rounded, bordered, and the focus
  indication. The textarea inside it has square corners, so a focus ring on
  the *textarea* would cut across the frame's rounded corners; the ring
  belongs to the frame.

**There is no status pill of its own.** The canvas editor has **one** status
pill, in its header (and in the app header on phones), and it reports whichever
surface the user is on: the canvas's cells on the Editor tab, the open note on
the Notes tab. The other surface's figures are listed in the same tooltip, under
a heading, so nothing is lost — the tooltip on the Notes tab shows a **Note**
section and a **Canvas** section, and on the Editor tab it shows just the
canvas's rows, without a heading.

The document editor's hook addresses its parts by **hardcoded ids** (`#editor`,
`#editor-form`, `#document-markdown-preview`), so it can only exist once per
page. The note editor therefore uses a new component, `PscWeb.Components.MarkdownEditor`,
whose hook finds its parts through `data-` attributes — the pattern the canvas
cell fields already use (`MarkdownField`). Migrating the document editor onto it
is a small follow-up that removes the hardcoded ids.

### Collaboration

- A remote edit arrives over the note's own PubSub topic and is applied to the
  local text; a user's own operation is not echoed back to them.
- The consistency check runs every 5 s, exactly as it does for documents, and
  resyncs a diverged client from the server's authoritative text.
- Presence is **canvas-level in the first version**: the header already shows who
  is on the canvas, and that cluster is shown in the Notes view too. A
  note-scoped presence indicator ("X is editing this note") is a follow-up, not a
  blocker — it needs a new field in the canvas presence meta and a second topic.

### Routes

The Notes view is a view *within* the canvas, so it adds no route of its own:

- `/canvas/:id?tab=notes` — the list.
- `/canvas/:id?tab=notes&note=<note_id>` — a note open for editing.

The note id is in the URL, so a note can be linked to and survives a reload. The
tab change already replaces the history entry (ADR-026); the note selection
follows the same rule, so Back returns to the canvas list rather than walking
through the notes.

There is deliberately **no `/notes/:id` route**: a note is only reachable
through its canvas, which is what makes the inherited permission model
airtight.

### The standalone documents section

`/documents` was parked and unlinked (ADR-018). Notes are the integration that
ADR-018 anticipated, and the section is now retired: its routes, LiveViews,
context and tables are gone, and the `documents` and `document_events` tables
were dropped. The collaborative-text machinery it built now lives in
`Psc.TextStore` and serves the notes, and its Markdown editor became the
reusable `PscWeb.Components.MarkdownEditor` — the document editor and the note
editor are the same component, with different events.

## Data model summary

```
users ──┬─< unstr_canvases ──< notes ──< note_events
        │         │              │
        │         │              └── created_by_id → users (attribution only)
        │         │
        │         └── shared_with (array of emails) — the canvas's access list
        │
        └──< unstr_canvas_events
```

## Related documents

- [canvas-editor.md](canvas-editor.md) — the canvas editor that hosts this view.
- [design-decisions.md](../design-decisions.md) — ADR-027 (the data and permission
  model) and ADR-028 (the shared status pill).
- [canvas-notes-plan.md](../plans/canvas-notes-plan.md) — the task breakdown.
