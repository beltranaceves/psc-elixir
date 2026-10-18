# Design decisions

Decision record for the PSC platform, written to be cited in the project report.
Each entry is an ADR: the situation, the decision, what else was considered, what
it costs, and the evidence it was verified against.

**Status legend:** Accepted (in the code and deployed) · Superseded · Open (needs a decision)

## Index

| ID | Decision | Status | Date |
|----|----------|--------|------|
| [ADR-001](#adr-001--event-sourced-edits-folded-into-a-snapshot-column) | Event-sourced edits folded into a snapshot column | Accepted | 2026-10-18 |
| [ADR-002](#adr-002--snapshot_seq-is-monotonic) | `snapshot_seq` is monotonic | Accepted | 2026-10-18 |
| [ADR-003](#adr-003--coalesce-contiguous-edits-into-one-operation) | Coalesce contiguous edits into one operation | Accepted | 2026-10-18 |
| [ADR-004](#adr-004--canvas-cell-edits-are-whole-value-and-client-debounced) | Canvas cell edits are whole-value and client-debounced | Accepted | 2026-10-18 |
| [ADR-005](#adr-005--debounce-the-document-editor-at-the-transport) | Debounce the document editor at the transport | Accepted | 2026-10-18 |
| [ADR-006](#adr-006--prune-what-is-folded-never-overwrite-the-oldest-rows) | Prune what is folded; never overwrite the oldest rows | Accepted | 2026-10-18 |
| [ADR-007](#adr-007--fold-immediately-when-pending-operations-exceed-a-threshold) | Fold immediately when pending operations exceed a threshold | Accepted | 2026-10-18 |
| [ADR-008](#adr-008--documentscontent-is-the-single-folded-representation) | `documents.content` is the single folded representation | Accepted | 2026-10-18 |
| [ADR-009](#adr-009--creating-a-canvas-from-a-template-goes-through-the-context) | Creating a canvas from a template goes through the context | Accepted | 2026-10-18 |
| [ADR-010](#adr-010--vocabulary-canvas-template-canvas-editor-template-designer) | Vocabulary: canvas, template, canvas editor, template designer | Accepted | 2026-10-18 |

---

## ADR-001 — Event-sourced edits folded into a snapshot column

**Context.** Canvases and documents are edited collaboratively by several clients at
once. Every client's edits must reach the others, the server must be able to rebuild
the current state, and the deployed database is a free-tier Postgres instance that
caps tables at 10k rows. Two aggregates need this: a text document (`documents`) and
the configurable canvas (`unstr_canvases`).

**Decision.** Both aggregates are event-sourced in the same shape:

- An edit produces one or more *operations* — small JSON maps (`insert`, `delete` for
  documents; `update_cell`, `update_name`, `update_description` for canvases).
- Each operation is appended as a row in `document_events` / `unstr_canvas_events`
  with a document-scoped monotonic `seq`.
- A *save* folds the pending operations into a single column — `documents.content`
  (text) or `unstr_canvases.cells` (map) — and records how far it folded in
  `snapshot_seq`.
- Loading is `folded state + replay of operations with seq > snapshot_seq` — normally
  a bare read, because saving deletes the operations it covered.

See [documents_collaboration_flow.md](documents_collaboration_flow.md) and
[canvas_collaboration_flow.md](canvas_collaboration_flow.md) for the
sequence diagrams.

**Alternatives considered.**

- *Store only the current text/cells, no operations.* Simpler storage, but the server
  would have to broadcast the whole document on every change, and there would be no
  way to detect or repair client divergence (see the consistency resync below).
- *Keep the operation log forever, as an audit trail.* Rejected on storage: a single
  pasted document produced one row per character (ADR-003), so one paste could cross
  the 10k-row ceiling on its own.

**Consequences.**

- Storage is bounded by "operations since the last save", not by total edit history.
- **The event tables are a transient write-ahead log, not the version history.** The
  project proposal calls for explicit, delta-based, tree-like version capture with a
  recorded reason for each pivot. Pruning means that feature needs its own substrate
  (explicit version rows), not the operation tables. Recorded as open work below.
- Replay gives a cheap consistency check: the server can rebuild authoritative state
  and resync a diverged client (`Psc.Documents.ConsistencyManager`).

---

## ADR-002 — `snapshot_seq` is monotonic

**Context.** The marker was derived from the operation rows themselves:

```elixir
max_seq = Repo.one(from e in DocumentEvent, ..., select: max(e.seq)) || 0
# ... write snapshot_seq: max_seq, then delete rows with seq <= max_seq
```

The same call pruned the rows it had just measured. Every connected client runs its
own idle and periodic save timer, so a second client (or the same client's next tick)
saved with nothing pending, read `max(seq) = nil`, and wrote **0** back over the
marker — seconds after a correct save. Measured live:

```
t=29s snapshot_seq=1 content_len=38 events=0   ← correct save
t=33s snapshot_seq=0 content_len=38 events=0   ← clobbered by the next save
```

**Decision.** The folded marker is floored at its stored value, and pruning only runs
once the update is durable (`with {:ok, _} <- result`):

```elixir
max_seq = max(max_event_seq, document.snapshot_seq || 0)
```

Applied to both `Psc.Documents.save_content_to_db/2` and
`Psc.Canvas.save_unstr_canvas_content_to_db/2`, which had the identical defect.

**Alternatives considered.** Driving `seq` from a Postgres sequence instead of
`max(seq)`: removes the "restart at 1" hazard, but the marker still has to be
comparable to those values for replay, so the flooring is required regardless.

**Consequences.** `next_sequence/1`'s documented floor (which exists precisely because
pruning restarts `max(seq)` at 1) now holds; the earlier marker is no longer
overwritten. Regression tests added for both aggregates, verified by muting the fix
and watching them fail (`snapshot_seq: 0` instead of `1`).

---

## ADR-003 — Coalesce contiguous edits into one operation

**Context.** `text_to_deltas/2` produced one operation *per character* — "Create one
insert operation per character" in the original code. With a row, an INSERT, and a
PubSub broadcast per operation, pasting a document was a self-inflicted denial of
service: 100,000 characters meant 100,000 rows, and the free tier caps a table at
10,000 rows.

**Decision.** Emit one operation per contiguous run:

- insert → `%{"type" => "insert", "pos" => pos, "text" => text}`
- delete → `%{"type" => "delete", "pos" => pos, "count" => n}`

`apply_operation/2` accepts both these and the legacy shapes stored in existing
databases (`"char"`, and a delete with no `"count"`), so recorded history still
replays. The recursive common-prefix scan also had its `String.length/1` calls hoisted
out of the recursion, where they recomputed the length of the text on every step.

**Alternatives considered.**

- *One row per keystroke batch, holding a JSONB array of the old single-character
  operations.* Same row reduction, but nests a list inside every replay path for no
  extra benefit — the flat `text`/`count` form carries the same information.
- *Keep per-character operations and rely on the sweeper.* The burst is written before
  any sweep runs, so it hits the ceiling first (see ADR-006).

**Consequences and measurement.**

| | Before | After |
|---|---|---|
| 100,000-char paste | 100,000 ops → 100,000 rows / INSERTs / broadcasts | **1 op → 1 row** |
| Replay of 10,000 ops | 58.8 ms | **0.0 ms** |
| Replay of 100,000 ops | (n/a) | 0.10 ms |

Observed live in the browser: a 5,005-character paste produced `events=1`, folded to
`content_len=5049` at `snapshot_seq=7`.

**Known limitation.** `text_to_deltas/2` only handles pure insertions and pure
deletions. A same-length replacement (`"hello world"` → `"HELLO WORLD"`) returns no
operations, so no broadcast is emitted; other clients converge only through the 5 s
consistency resync. Recorded as open work below.

---

## ADR-004 — Canvas cell edits are whole-value and client-debounced

**Context.** A canvas cell field holds independent markdown text (e.g.
`cells["leverage"]["components"]`). Several users can edit *different* fields, and the
same field only rarely. The document editor, by contrast, needs positional deltas
because everyone types into one shared character stream.

**Decision.** A canvas operation carries the **whole value** of one field —
`%{"type" => "update_cell", "cell_key" => k, "field" => f, "value" => v}` — and the
client debounces at 500 ms (`DEBOUNCE_MS` in `assets/js/hooks/markdown_field.js`)
before pushing it. Folding into `unstr_canvases.cells` happens on the idle (1.5 s) and
periodic (10 s) timers, exactly as for documents.

**Alternatives considered.** Sending positional deltas per keystroke, as documents do.
Rejected as unnecessary: fields are independent, so there is nothing to merge
character-wise, and the whole-value form makes replay trivially idempotent.

**Consequences.**

- Row count is proportional to *edit pauses*, not keystrokes.
- Each row carries the full field text (~97 B average in the development database,
  growing with the cell). Values above ~2 KB start being TOASTed, so the storage cost
  of a large cell is paid on every edit of that cell.
- Conflict resolution within one field is last-write-wins — concurrent edits to the
  *same* field can lose one side. Acceptable for the MVP; different fields never
  conflict.
- **Asymmetry to note:** documents fold early when pending operations pass a threshold
  (ADR-007); canvases rely on idle/periodic timers only.

---

## ADR-005 — Debounce the document editor at the transport

**Context.** The document editor binds `phx-change="update_content"` on the form, so
every keystroke round-tripped to the server and produced an operation.

**Decision.** `phx-debounce="300"` on that form. Form-level debounce was verified in
the vendored LiveView source rather than assumed: the JS resolves
`el.getAttribute("phx-debounce")` and has a dedicated `form` branch for binding the
debounce cycle.

**Consequences.** One round trip per ~300 ms of typing instead of one per keystroke,
combined with ADR-003's coalescing. Note the editor still sends the *full text*, and
the server diffs it (`text_to_deltas/2`) — the client is not authoritative about
operations.

---

## ADR-006 — Prune what is folded; never overwrite the oldest rows

**Context.** The question that started this work: *should we cap the total size of the
change history and start overwriting old rows once it is exceeded?* The premise is
worth testing, because the code already deletes what it has folded.

**Decision.** Two mechanisms, both anchored on `snapshot_seq`:

1. **Prune on fold** — the save that records a marker also deletes the rows it
   covered, but only after the update is durable.
2. **Sweep opportunistically** — `Psc.EventsSweeper` deletes any row with
   `seq <= snapshot_seq`, at boot (5 s) and every 6 hours, for both event tables. It
   exists because pruning is opportunistic: a document abandoned before its first save
   keeps its whole tail forever.

**Alternatives considered and rejected.**

- **Cap the history and overwrite the oldest rows.** This was rejected because it is
  unsafe, not merely unnecessary. The only rows in the table are either (a) at or
  below `snapshot_seq` — already folded into `content`/`cells`, pure dead weight — or
  (b) above it, **load-bearing**: `load_with_snapshot/1` replays exactly those rows to
  rebuild state. Overwriting oldest-first deletes from set (b) during the very burst
  the cap was meant to survive, silently discarding operations that never reached the
  folded column. The safe form of the same idea is fold-then-delete, which is what
  mechanism 1 already does.
- **Leave pruning to saves only.** This is what produced 297 orphan rows (65
  `document_events` + 232 `unstr_canvas_events`) written hours before pruning shipped,
  in documents never edited again. The sweeper reclaimed them on its first boot:

  ```
  [info] EventsSweeper pruned 65 document_events and 232 unstr_canvas_events rows
  ```

**Consequences and size budget.** With ADR-003 and ADR-007, a document's un-pruned
tail is at most ~1.5 s of edits (or 500 operations). Measured marginal cost per row,
including indexes:

| Table | Row payload | Indexes | ~Cost/row | 10k rows | 1M rows |
|---|---|---|---|---|---|
| `document_events` | 125 B (54 B op) | 3 btrees | ~200 B | ~2 MB | ~200 MB |
| `unstr_canvas_events` | 184 B (97 B op) | 2 btrees | ~230 B | ~2.3 MB | ~230 MB |

Both tables measured **0 rows after the sweep** in development *for folded rows*: the
sweeper left 25 `unstr_canvas_events` rows in place because they sit above their
canvas's marker (unfolded work from a session interrupted before its save), which is
exactly the distinction the marker encodes. Production had nothing to reclaim at
deploy time.

---

## ADR-007 — Fold immediately when pending operations exceed a threshold

**Context.** Folding waited for 1.5 s of idle time (or the 10 s periodic tick). A
client that never pauses — or a burst — leaves operations un-pruned for that whole
window.

**Decision.** The document editor counts the operations it has applied in the socket
and folds as soon as the count reaches `@max_pending_events` (500), resetting the
counter on any successful save (idle, periodic, or threshold).

**Alternatives considered.** A `COUNT(*)` per keystroke to consult the true pending
count: rejected as a database round trip per keystroke; the in-socket counter is
free and errs only in the harmless direction. Relying on the 10 s periodic save:
rejected for leaving up to 10 s of rows.

**Consequences.** A hard ceiling per document, without dropping anything (unlike a cap
that overwrites). Covered by a LiveView test that drives 499 changes, asserts 499
pending rows, then crosses the threshold and asserts 0.

---

## ADR-008 — `documents.content` is the single folded representation

**Context.** `SnapshotManager` maintained a *second* full copy of the text in
`documents.snapshot_content`, written by `create_snapshot/1` on a 10 s timer. The load
path reads `documents.content`; `snapshot_content` was read only by
`rebuild_from_snapshot/1`, which `create_snapshot/1` was the only caller of. In
practice the column held 1 byte in every row — the feature never fired.

**Decision.** Drop the column (migration `20261018003348`), remove the field from the
schema, and delete `create_snapshot/1`, `rebuild_from_snapshot/1` and
`should_create_snapshot?/1`. `SnapshotManager` is now `load_with_snapshot/1` plus
`get_stats/1`. The document editor's `:check_snapshot` timer is gone; its job — keep
the folded state current — is what ADR-007 does inline.

`get_stats/1` also had its accounting corrected: it previously reported
`events_since_snapshot = total_events - snapshot_seq`, subtracting a *max seq* from a
*row count*, which goes negative once rows are pruned. It now counts operations above
the marker.

**Consequences.** One representation of the folded state, so the two can never
disagree. **Deployment note:** the migration is destructive, and the released code
before it selects the column — rolling back past this release fails until the column
is re-added. The migration ran at boot on the first deploy after this change
(`Migrated 20261018003348 in 0.2s`, production).

---

## ADR-009 — Creating a canvas from a template goes through the context

**Context.** Templates store cell data nested (`layout_map["cells"]["r1_c1"] = %{label, semantics, fields, defaults}`), while a canvas stores it flat (`cells["r1_c1"] = %{row, column, content, …}`). `Canvas.instantiate_template/2` performs that transformation, but the Canvas list page's create form didn't call it — it copied the template's `layout_map` straight into the canvas:

```elixir
case Canvas.get_canvas_layout(layout_id) do
  %{} = layout -> Map.put(attrs, "cells", layout.layout_map || %{})
```

`UnstrCanvas.validate_cells_structure/1` requires a flat entry for every key in `layout`, so the changeset rejected it and the user saw "Failed to create canvas". Proven in a rolled-back transaction:

```
PATH A (index: copies layout_map verbatim):
  FAILED validation: [cells: {"Missing cell data for keys: r1_c1", []}]
PATH B (spec: Canvas.instantiate_template/2):
  created, cells keys = ["columns", "layout", "r1_c1", "relations", "rows"]
```

The Templates library's "Use template" button was already correct — only this second entry point was broken. It is the same failure mode as ADR-002: a tested context function that the UI bypassed.

**Decision.** The create form instantiates through the context, and only from a template the user may use:

```elixir
defp create_canvas(user, name, description, template_id) do
  case template_for(user, template_id) do
    {:ok, template} -> Canvas.instantiate_template(template, user.id, %{"name" => name, ...})
    :blank          -> Canvas.create_unstr_canvas(user.id, %{"name" => name, ...})
    {:error, reason} -> {:error, reason}
  end
end
```

`instantiate_template/3` gained an `overrides` argument so the name and description the user typed win over the template's own. The dropdown is populated by the scoped `Canvas.list_templates/1` (own templates plus ones shared with the user), not the unscoped `Canvas.list_canvas_layouts/0` — which previously listed **every** template in the database, i.e. a name leak that would have become un-authorised instantiation once the transformation was fixed. The handler also re-checks `can_access_template?/2`, so a forged id is refused rather than trusted.

**Consequences.** There is now one path from template to canvas, and the access rule is enforced at the point of use rather than by UI omission. Covered by `test/psc_web/live/unstr_canvas_live_test.exs`: template create produces flat cell keys, blank create still yields the default PSC structure, the options exclude other users' templates, and a forged id leaves the canvas list empty.

---

## ADR-010 — Vocabulary: canvas, template, canvas editor, template designer

**Context.** The codebase accumulated four names for two concepts: an *unstructured canvas* / *unstr canvas* / *canvas instance*, and a *canvas layout* / *layout* / *template* / *creator*. The routes made it worse — `/canvas-designer` was the canvas **editor** while `/canvas-layouts` was the **template** designer — and `/canvases` was already taken by the earlier fixed-12-cell PSC implementation, which duplicated the newer one. For a report and for users, this is noise.

**Decision.** Two nouns, two surface names:

| Domain | Table | Schema | Route | Surface |
|---|---|---|---|---|
| **Canvas** | `unstr_canvases` | `Psc.Canvas.UnstrCanvas` | `/canvases` | **canvas editor** (`PscWeb.UnstrCanvasLive`) |
| **Template** | `canvas_layouts` | `Psc.Canvas.Layout` | `/templates` | **template designer** (`PscWeb.CanvasLayoutLive`) |
| Problem–Solution Canvas (fixed 12 cells) | `canvases` | `Psc.Canvas.Canvas` | `/psc-canvas` | legacy canvas |

- `/canvas-designer` → `/canvases`; `/canvas-layouts` → `/templates`.
- UI text follows the nouns (nav reads Documents · Canvases · Templates; the create form's "Layout" selector is now "Template"; the template designer's heading is "Template designer").
- Docs follow too: `docs/spec/creator.md` → `template-designer.md`, `docs/spec/editor.md` → `canvas-editor.md`, and `unstr_canvas_collaboration_flow.md` → `canvas_collaboration_flow.md`. Each spec opens with a table bridging the domain words to the identifiers.
- **Module, table and function names are unchanged.** Renaming `unstr_canvases`/`canvas_layouts` would mean a table migration and a wide rename for no user-visible gain; instead the mapping is documented once ([data_model.md](data_model.md)) and repeated at the top of each spec.

**Alternatives considered.** A full rename of tables and modules to match the vocabulary — deferred as churn with migration risk. Keeping the old routes as redirects — skipped because the app is pre-release and no external links depend on them.

**Consequences.** The legacy fixed-PSC canvas moved from `/canvases` to `/psc-canvas`; it is unreachable from the navigation and its fate (retire, or fold its data into a built-in template) is an open question, recorded below rather than decided here.

---

## Measurement summary

Numbers referenced above, all taken on 2026-10-18 against a local Postgres and the
deployed Gigalixir instance:

| Measurement | Value |
|---|---|
| Paste of 100,000 characters, operations produced | 1 (was 100,000) |
| Replay of 10,000 operations | 0.0 ms (was 58.8 ms) |
| Live paste of 5,005 characters → event rows | 1, folded to `snapshot_seq=7`, `content_len=5049` |
| Orphan event rows reclaimed by the first sweep | 297 (65 + 232) |
| Test suite | 228 passing (was 215) |
| Deploy | release 7, healthy, migration applied at boot, no errors in logs |

---

## Open issues

1. **Version capture needs its own substrate.** The pruned operation tables cannot
   serve the proposal's delta-based, tree-like versioning with pivot reasons
   (ADR-001). A dedicated versions table is required.
2. **Same-length replacements emit no operations** (ADR-003), so they are not
   broadcast; clients converge via the 5 s consistency resync.
3. **No threshold fold for canvases** (ADR-004) — documents fold at 500 pending
   operations, canvases rely on idle/periodic timers.
4. **Last-write-wins per canvas field** (ADR-004) — concurrent edits to the same cell
   field can lose one side.
5. **Free-tier row ceiling** (ADR-006) — the numbers above make a single document fit
   comfortably, but the ceiling is still a design constraint for the analytics work in
   the proposal.
6. **The legacy fixed-PSC canvas** (`/psc-canvas`, ADR-010) is still routed and tested
   but unreachable from the navigation; decide whether to retire it or express the PSC
   as a built-in template for the configurable canvas.
7. **Canvas structure editing is template-only** — the canvas editor spec defines
   `add_row` / `remove_row` / `add_column` / `remove_column` / `add_cell_field` /
   `remove_cell_field` as CRDT operations, but grid structure can currently only be
   changed in the template designer.