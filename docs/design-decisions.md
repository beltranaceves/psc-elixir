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
| [ADR-011](#adr-011--rowcolumn-accents-are-tokens-inside-the-structure-maps) | Row/column accents are tokens inside the structure maps | Accepted | 2026-10-18 |
| [ADR-012](#adr-012--remove-the-unused-cell-semantics-field) | Remove the unused cell `semantics` field | Accepted | 2026-10-18 |
| [ADR-013](#adr-013--cell-details-are-edited-inline-in-the-template-grid) | Cell details are edited inline in the template grid | Accepted | 2026-10-18 |
| [ADR-014](#adr-014--templates-save-explicitly-with-a-cancel-escape-hatch) | Templates save explicitly, with a Cancel escape hatch | Accepted | 2026-10-18 |
| [ADR-015](#adr-015--light-mode-contrast-comes-from-theme-tokens-not-white-alpha) | Light-mode contrast comes from theme tokens, not white alpha | Accepted | 2026-10-18 |
| [ADR-016](#adr-016--one-share-modal-component-for-templates-canvases-and-documents) | One Share modal component for templates, canvases and documents | Accepted | 2026-10-18 |
| [ADR-017](#adr-017--remove-the-unused-relations-metadata) | Remove the unused `relations` metadata | Accepted | 2026-10-18 |
| [ADR-018](#adr-018--documents-is-parked-as-a-standalone-feature) | Documents is parked as a standalone feature | Accepted | 2026-10-18 |
| [ADR-019](#adr-019--auth-feedback-inline-validation-plus-feedback-cards) | Auth feedback: inline validation plus feedback cards | Accepted | 2026-10-18 |
| [ADR-020](#adr-020--optional-cell-section-titles-and-a-dense-square-grid) | Optional cell section titles, and a dense square grid | Accepted | 2026-10-19 |
| [ADR-021](#adr-021--mobile-top-bars-one-menu-and-a-stacked-canvas-header) | Mobile top bars: one menu and a stacked canvas header | Accepted | 2026-10-19 |
| [ADR-022](#adr-022--ui-consolidation-one-canvas-model-one-creation-path) | UI consolidation: one canvas model, one creation path | Accepted | 2026-10-19 |
| [ADR-023](#adr-023--the-canvas-tabs-follow-the-space-they-have) | The canvas tabs follow the space they have | Accepted | 2026-10-20 |
| [ADR-024](#adr-024--mobile-feedback-and-dialogs-stay-in-the-visible-viewport) | Mobile feedback and dialogs stay in the visible viewport | Accepted | 2026-10-20 |
| [ADR-025](#adr-025--the-app-header-owns-index-page-titles) | The app header owns index page titles | Accepted | 2026-10-20 |
| [ADR-026](#adr-026--view-state-lives-in-the-url-not-in-the-page) | View state lives in the URL, not in the page | Accepted | 2026-10-20 |

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

**Context.** Templates store cell data nested (`layout_map["cells"]["r1_c1"] = %{label, fields, defaults}`), while a canvas stores it flat (`cells["r1_c1"] = %{row, column, content, …}`). `Canvas.instantiate_template/2` performs that transformation, but the Canvas list page's create form didn't call it — it copied the template's `layout_map` straight into the canvas:

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

**Context.** The codebase accumulated four names for two concepts: an *unstructured canvas* / *unstr canvas* / *canvas instance*, and a *canvas layout* / *layout* / *template* / *creator*. The routes made it worse — `/canvas-designer` was the canvas **editor** while `/canvas-layouts` was the **template** designer — and `/canvas` was already taken by the earlier fixed-12-cell PSC implementation, which duplicated the newer one. For a report and for users, this is noise.

**Decision.** Two nouns, two surface names:

| Domain | Table | Schema | Route | Surface |
|---|---|---|---|---|
| **Canvas** | `unstr_canvases` | `Psc.Canvas.UnstrCanvas` | `/canvas` | **canvas editor** (`PscWeb.UnstrCanvasLive`) |
| **Template** | `canvas_layouts` | `Psc.Canvas.Layout` | `/templates` | **template designer** (`PscWeb.CanvasLayoutLive`) |
| Problem–Solution Canvas (fixed 12 cells) | `canvases` | `Psc.Canvas.Canvas` | `/psc-canvas` | legacy canvas |

- `/canvas-designer` → `/canvas`; `/canvas-layouts` → `/templates`.
- UI text follows the nouns (nav reads Canvases · Templates — Documents is parked, see ADR-018; the create form's "Layout" selector is now "Template").
- Docs follow too: `docs/spec/creator.md` → `template-designer.md`, `docs/spec/editor.md` → `canvas-editor.md`, and `unstr_canvas_collaboration_flow.md` → `canvas_collaboration_flow.md`. Each spec opens with a table bridging the domain words to the identifiers.
- **Module, table and function names are unchanged.** Renaming `unstr_canvases`/`canvas_layouts` would mean a table migration and a wide rename for no user-visible gain; instead the mapping is documented once ([data_model.md](data_model.md)) and repeated at the top of each spec.

**Alternatives considered.** A full rename of tables and modules to match the vocabulary — deferred as churn with migration risk. Keeping the old routes as redirects — skipped because the app is pre-release and no external links depend on them.

**Consequences.** The legacy fixed-PSC canvas moved from `/canvas` to `/psc-canvas`; it is unreachable from the navigation and its fate (retire, or fold its data into a built-in template) is an open question, recorded below rather than decided here.

---

## ADR-011 — Row/column accents are tokens inside the structure maps

**Context.** Both surfaces need to let authors colour-code rows and columns — a thin
colour line on the top edge of a column header and the left edge of a row header — so a
dense grid can be scanned by band rather than read label by label. That requires
persisting a colour for structure metadata that is *not* cell content.

**Decision.** Store an optional `"accent"` key on each row/column entry, holding a token
from a fixed palette (`sky`, `violet`, `emerald`, `amber`, `rose`, `teal`, `indigo`,
`slate`); `nil` means no accent.

- Accents are authored **only in the template designer** and recorded inside the
  template's JSON (`canvas_layouts.layout_map.rows/columns`) — the map embedded in the
  Ecto entity. No new column and **no migration**.
- `instantiate_template/3` already copies `rows`/`columns` verbatim into
  `unstr_canvases.cells`, so the canvas editor reads the accents straight from its own
  JSON structure. The canvas editor renders them **read-only**: there is no picker, and
  no accent CRDT operation exists.
- **Tokens, not hex.** `Psc.Canvas.Accent` owns the palette and validity;
  `PscWeb.Components.Accent` maps each token to *static* Tailwind classes and renders the
  bar. Tailwind never sees a runtime-composed class, and both themes stay legible.
- **Copy-on-instantiate**, exactly like row/column labels: recolouring a template later
  does not retro-update canvases that were already created from it.
- **Defensive validation** in `Psc.Canvas.Layout.changeset/2` rejects unknown tokens.

**Alternatives considered.** Raw hex per header (arbitrary, unbounded contrast problems,
and requires inline styles); a separate accents table (new schema and joins for
presentation metadata); canvas-side recolouring via CRDT ops (rejected: styling is a
template concern, and it duplicated the palette in a second authoring surface); tinted
header backgrounds (fights Markdown text contrast); colour dots before labels (too weak to
scan, kept only as the picker swatch).

**Consequences.** Styling lives with the structure it describes. The canvas editor is a
pure consumer: it renders whatever the template's JSON carried at instantiation, so
canvases created before an accent existed stay unchanged until they are recreated — the
same rule already applied to row/column labels. Colour is never the only carrier of
meaning: labels remain, bars are `aria-hidden`, and each swatch is a labelled button.
Clearing an accent writes `nil`, and existing templates/canvas without the key render
exactly as before.

---

## ADR-012 — Remove the unused cell `semantics` field

**Context.** Templates carried a per-cell `semantics` string (`free` | `problem` |
`solution` | `evidence` | `note`) chosen from a dropdown, copied into each canvas at
instantiation and then explicitly excluded from canvas editing. A full search of `lib/`,
`assets/`, tests and specs found no consumer: no icon, style, filter, relation rule,
analytics query, export or validation read it. The field was authored, stored and
copied — and never used. Its documented purpose ("iconography and future insights") was
never implemented, so the dropdown asked users to classify cells with no observable
effect.

**Decision.** Remove the field from the model and from both surfaces:

- The template designer no longer offers the dropdown and no longer writes the key:
  `empty_cell_meta/0` and the index page's default layout map dropped it, and the
  `@semantics_options` assign is gone.
- `Canvas.instantiate_template/3` no longer copies `semantics` into canvas cells.
- The canvas editor **keeps** filtering a `semantics` key when reading cells, so canvases
  persisted before this change cannot surface it as an editable Markdown field.

**Alternatives considered.** Keep it dormant for a future iconography feature (dead
metadata is what prompted the review; a real feature can add a properly named, validated
field); rename it to `role`/`cell_type` and implement icons now (real scope, deferred as
its own feature); migrate stored JSON to strip the key (nothing reads it and the editor
already ignores it, so an irreversible data rewrite buys nothing).

**Consequences.** No migration. Old templates and canvases keep an inert key — it
survives in stored JSON because template/canvas edits are field-level updates — but it is
never displayed, never copied into new canvases, and never writable. Cell details are now
only label, fields and defaults (edited inline in the grid — see ADR-013). If cell roles
become a real feature, they return as a first-class, validated property with an actual
renderer and a user-facing name.

---

## ADR-013 — Cell details are edited inline in the template grid

**Context.** Cell metadata (label, fields, per-field defaults, add/remove field) was
edited in a separate panel: clicking a cell set `@selected_cell` and a sticky side
column rendered the inputs. The grid therefore had to be paired with an always-present
1/3-width panel that was empty (or a hint) most of the time, and every edit required a
select-then-edit round trip. On narrower screens the panel stacked below the grid,
separating the control from the cell it described.

**Decision.** Edit cell details directly in the grid. Each cell renders its own label
input, one row per field (key, default input, remove button) and an inline "add field"
form. `select_cell` / `@selected_cell` and the side panel are gone; the designer is now a
single full-width column (template form → grid).

**Alternatives considered.** A modal/drawer opened from the cell (still a select-then-edit
hop, and hides the grid while editing); expanding the clicked cell in place while keeping
the grid width (complex table reflow); keeping the panel but auto-selecting the first
cell (better, but still duplicates the interaction). Direct inline editing is the
simplest model that keeps control and content in the same visual place.

**Consequences.** The grid gets the full width, which matters now that cells contain
inputs rather than badges. Every cell repeats its own form markup, so the table is denser
and fields must stay compact (micro-labels + small inputs). Because each cell has its own
`phx-submit="add_cell_field"` form, the grid cannot be wrapped in another `<form>` — the
template name/description form stays a separate block above it.

LiveView 1.x **throws** when `phx-change` is bound to an input that is not inside a form
(`form events require the input to be inside a form`), and the failure is silent in the
UI: the event never reaches the server, so the next re-render restores the old value.
Every inline input is therefore wrapped in its own tiny form carrying hidden
`cell_key`/`field` (or `index`) inputs instead of `phx-value-*` attributes. This also
fixed the pre-existing column and row label inputs, which had the same defect and had
never actually persisted edits in a browser. Editing remains in-memory until "Save
Template", unchanged from before.

---

## ADR-014 — Templates save explicitly, with a Cancel escape hatch

**Context.** Canvases and documents autosave (idle + periodic folds into a snapshot), so
the platform was inconsistent: the template designer edits in memory and persists only on
**Save Template**. Nothing on screen said so — no dirty indicator and no way to abandon a
draft other than navigating away — which made the save model genuinely ambiguous to users.

**Decision.** Keep explicit saving for templates (a template is a schema other canvases
are instantiated from, so half-saved structure is worse than a lost draft), but make the
model visible and give it a deliberate exit:

- Any edit — grid structure, cell label/field/default, field removal, accent,
  name or description — sets a `@dirty?` flag (structure edits via `update_layout/2`,
  text fields via `phx-change="mark_dirty"` on the save form).
- While dirty, the form shows an **“Unsaved changes”** hint beside the actions.
- **Cancel** (`#cancel-template-editing`) opens a `UIDialog` confirmation
  (`#discard-template-dialog`) when the draft is dirty — **Keep editing** closes it,
  **Discard and leave** abandons the draft and returns to the template library. Escape,
  an outside click and the dialog’s × all just close it, via the dialog’s mapped
  `on-close` event resetting `@confirm_leave?`. Cancelling with nothing dirty skips the
  modal entirely.
- **Save Template** remains the only persistence path (`Canvas.create_template/2` /
  `Canvas.update_template/2` → `Layout.changeset/2`).

**Alternatives considered.** Autosave templates like canvases (structure changes are
schema edits with validation — a debounced autosave would surface failures mid-edit and
let incompatible structures land without intent); save-on-navigate (surprising and
impossible to cancel); Cancel-as-“revert and stay” (ambiguous for a brand-new template
where there is nothing to revert to, so Cancel consistently means “leave without saving”);
a native `confirm()` (no styling, blocks the event loop, and cannot be driven by LiveView
state — replaced by the modal).

**Consequences.** Templates and canvases now differ on purpose, and the difference is
visible in the UI rather than implied. Because nothing is written until submit, the dirty
flag is best-effort: it starts `false` and only ever turns `true` during a session, so
editing back to the original values still shows the indicator — acceptable for a
boolean, and cheaper than deep-comparing the whole `layout_map` (including template name
and description held in a separate form) on every keystroke.

Fixing the modal surfaced a defect in the shared dialog component: `activateOpenState/0`
calls `this.el.focus()` on the dialog root, but a non-focusable `<div>` ignores it, so
focus stayed on the trigger and **Escape never closed any dialog in the app**. The dialog
and alert-dialog roots now carry `tabindex="-1"`, which makes the existing focus call
effective and restore Escape-to-close (verified in the browser: focus lands on
`#discard-template-dialog`, Escape closes it, and the draft survives).

---

## ADR-015 — Light-mode contrast comes from theme tokens, not white alpha

**Context.** The product was designed dark-first, and subtle surfaces were expressed as
white overlays: `border-white/10` on 84 elements, `bg-white/5` and `hover:bg-white/5` on
cards and rows, plus `ring-white/20`. On the dark theme those read correctly; on the light
theme (near-white `base-100`) a 10 % white border is literally invisible, so cards, table
cells and inputs lost their edges and the UI looked flat and low-contrast. Markdown was
rendered with `prose-invert`, which forced light text on what is, in light mode, a light
surface.

**Decision.** Express subtle emphasis with **theme tokens derived from `base-content`**,
which flip with the theme: `border-base-content/10`, `bg-base-content/5`,
`hover:border-base-content/25`, `ring-base-content/20`, and let Markdown use
`prose dark:prose-invert`. Supporting changes:

- **A real `dark:` variant** bound to daisyUI’s theme rather than the OS default:
  `@custom-variant dark` matches `[data-theme="dark"]`, and also
  `prefers-color-scheme: dark` when no `data-theme` is set (the “system” setting removes
  the attribute).
- **Light theme tuning**: `base-200` 96 %→95 % and `base-300` 92 %→89.5 % so cards and
  insets separate from the 98 % page; SaladUI `--border`/`--input` 12 %→20 %; the primary
  orange darkened from `oklch(70%)` to `oklch(62%)` so white text on it is legible.
- **A regression guard**: `PscWeb.ThemeContrastTest` scans `lib/psc_web/live/**/*.ex` and
  fails on any `bg|text|border|ring|divide-(white|black)/*` utility.

**Alternatives considered.** Duplicating every surface with `dark:` variants (doubles the
class soup and still forgets cases); a light-only stylesheet override (fragile, invisible
to readers of the markup); leaving the light theme rough (it is user-selectable, so it is a
supported surface); using raw hex colors (no theme awareness at all).

**Consequences.** One vocabulary for depth across both themes: `base-content/N` reads as
“10 % of the foreground”, which is exactly the intent. The dialog overlay keeps
`bg-black/80` deliberately — a modal scrim should stay dark in both themes. Colour-coded
chips (`amber-600 dark:amber-300`) now need explicit pairs, which the `dark:` variant makes
possible for the first time. Verified with light-mode screenshots of the template designer,
canvas editor and documents index, and a dark-mode regression screenshot.

---

## ADR-016 — One Share modal component for templates, canvases and documents

**Context.** Sharing existed three times with three different shapes: a collapsible inline
panel in the template designer, a block inside the canvas editor's presence sidebar, and a
block with a copy-link row in the document editor's sidebar. Each duplicated the invite
form, the shared-with list and the remove control, and none of them could be opened from
the header where users look for actions. The remove affordance had also drifted (text
link, plain ×, bordered icon).

**Decision.** Extract one component, `PscWeb.Components.ShareDialog`, with two parts:

- `share_button/1` — a **combo button**: the `hero-share` icon beside the current label
  ("Share"), with the event name supplied by the caller.
- `share_dialog/1` — a `UIDialog` modal holding the invite form, the "People with access"
  list (each row with the shared remove-icon button), an optional copy-link row, and a
  Done action. It takes `manage?`, `shared_with`, `share_event`, `remove_event`,
  `on_close` and `link`, so each context keeps its own server events
  (`share_template`/`unshare_template`, `share_canvas`/`remove_access`,
  `share_document`/`remove_access`). The panel is rounded and keeps a 16 px gutter on
  phones, so the modal reads as a card instead of a full-bleed sheet.

Each LiveView owns a boolean `@share_open` (`open_share` / `share_closed`), mirroring the
Cancel-dialog pattern from ADR-014. The inline share blocks are gone; the canvas sidebar
keeps presence only, and the document sidebar now just points at the header button.

**Alternatives considered.** A shared function that returns markup (harder to parameterise
cleanly in HEEx); keeping per-surface markup and only restyling it (the drift returns); a
native `confirm()`/`prompt()` (no, per ADR-014); a full-page share route (leaves context
and costs a navigation).

**Consequences.** One `id` convention drives the tests: `#share-<x>-button`,
`#share-<x>-dialog`, `#share-<x>-dialog-form`, `#share-<x>-dialog-link`. The dialog stays
open after an invite so several people can be added, and closes through Done, Escape,
outside click or its ×. Because the modal owns the link row, the document's copy-link
finally lives next to the people list instead of under a heading in the sidebar.

---

## ADR-017 — Remove the unused `relations` metadata

**Context.** Templates carried a `relations` list (`%{"from" => cell_key, "to" => cell_key,
"label" => string}`) authored in a designer card with two cell dropdowns and an optional
label. `instantiate_template/3` copied it into every canvas, but nothing ever rendered it —
no arrows, no list — and both specs listed arrow drawing as out of scope. It was write-only
metadata. Reviewing it surfaced two defects: (1) deleting a row/column left **dangling
relations that still saved**, because `remove_row/remove_column` never prune `cells`,
`normalize_layout_map/1` only adds keys, and `broken_relations?/2` therefore still found
the removed cell; (2) duplicates were allowed and self-loops were blocked only in the UI
handler, not by the changeset.

**Decision.** Remove relations entirely:

- **Designer:** the Relations card, the `add_relation` / `remove_relation` handlers, and
  the `relations` key in new layout maps are gone. The designer is now form → grid.
- **Validation:** `broken_relations?/2` and its error are gone from `Layout.changeset/2`.
- **Instantiation:** `instantiate_template/3` no longer copies `relations` into the canvas.
- **Legacy data:** existing templates and canvases keep an inert `relations` key; nothing
  reads it, and new writes never create it.

**Alternatives considered.** Keep the card but label it “metadata only” (asks users to
author data with no effect); finish arrow rendering now (a real feature needing hit
testing, overlap handling and accessibility — not a half-hidden list); keep only the
validation (dead rules with no UI). The dangling-relation bug argued for removing the
source rather than patching validation.

**Consequences.** Fewer concepts in the template JSON, and removing an axis can no longer
strand edges because there are none. If relations return, they should arrive as a
first-class feature — typed edges, rendered arrows with a table/legend view, duplicate and
self-loop rules — rather than as invisible metadata.

---

## ADR-018 — Documents is parked as a standalone feature

**Context.** The app shipped a standalone `/documents` section (index + editor with
collaborative Markdown, inline preview and sharing) alongside Canvases and Templates. It
was exposed as the first item in the primary navigation, implying it was a core product
surface. Product direction has changed: a document should eventually live **inside** a
canvas cell/region rather than as a separate destination, so advertising it as a
first-class route misrepresents the platform and splits the mental model.

**Decision.** Remove Documents from the UI for now:

- The primary nav is **Canvases · Templates** (still rendered only for signed-in users).
- The `/documents` and `/documents/:id` routes and their LiveViews remain in the codebase
  for the planned integration; they are simply not linked from anywhere in the UI.
- The Markdown renderer, inline preview and sharing component they use are shared
  (`PscWeb.Markdown`, `PscWeb.Components.ShareDialog`), so that work carries over.

**Alternatives considered.** Delete the routes and LiveViews (throws away the editor,
inline preview and CRDT document work that the canvas integration will reuse); keep the
nav item but flag it as experimental (still advertises a standalone feature that is not
part of the product); redirect `/documents` to `/canvas` (surprising for anyone with a
bookmark and hides the parked state).

**Consequences.** The platform now presents two nouns — Canvases and Templates — matching
the product story. `/documents` remains reachable by direct URL until the integration
lands; if that is unwanted, the routes can be removed (or redirected) with a one-line
change. `docs/spec/` still describes the document editor, now explicitly as parked work.

---

## ADR-019 — Auth feedback: inline validation plus feedback cards

**Context.** The log-in and sign-up pages signalled problems in three inconsistent ways:
native browser bubbles (log-in email), plain red text under fields (sign-up), and a
daisyUI `.toast`/`.alert` flash that overlapped the header, could only be dismissed with
the mouse, and never went away on its own. Screen readers got nothing — inputs had no
`aria-invalid`/`aria-describedby`, the log-in form could not show field errors at all
(it was built from a plain params map), and only the first error per field was rendered.

**Decision.** One feedback language across both pages:

- **Inline errors** are destructive-outlined chips with an icon, one per error (not just
  the first), inside a persistent `aria-live="polite"` region. Labels turn destructive and
  inputs carry `aria-invalid="true"` plus `aria-describedby` pointing at the message
  region — implemented once in `UI.Form.form_message/1` and `UI.Input`/`UI.Textarea`.
- Forms opt out of native bubbles (`novalidate`) so all validation is rendered by the
  app; `type`/`required` stay for semantics.
- The log-in form validates presence and email shape with a schema-less changeset before
  handing off to the session controller. Credentials stay generic ("Invalid email or
  password") to avoid user enumeration.
- **Flash** renders as a **feedback card**: icon badge, title/message, tinted border
  (`primary` for info, `destructive` for error), entrance animation and a real focusable
  close button. The stack sits below the header (`top-16`) instead of covering the nav.
  Info cards auto-dismiss after 6 s with a progress bar and clear the server flash through
  a colocated hook; error cards persist until dismissed.
- The **dark theme's** `--destructive`/`--color-error` were brightened from
  `oklch(58% 0.253 17.585)` to `oklch(70% 0.19 22)` (2.94:1 → 4.65:1 against the dark
  background), with a dark `--destructive-foreground`/`--color-error-content` so solid
  destructive buttons keep their contrast. Light mode keeps its original red.

**Alternatives considered.** Reusing the bundled SaladUI `toaster` (a second notification
system with its own JS stack, and its flash adapter would duplicate `flash_group`);
keeping native browser validation (unstyleable, inconsistent between the two pages);
rendering only the first error per field (cheap, but hides simultaneous problems); a
tinted background behind inline errors (measured 3.2:1 in light mode, below AA, so the
tint was dropped and the theme's destructive colour kept).

**Consequences.** Error UI is consistent, keyboard- and screen-reader-accessible, and
addressable by stable ids (`<field-id>-error`). A blank email now reports only
"can't be blank" (the format check is skipped when blank) instead of stacking two
messages. The short-password copy is "should be at least 12 characters", which required
updating two test assertions. Info flashes disappear on their own, so anything depending
on them must read the server flash rather than the DOM.

---

## ADR-020 — Optional cell section titles, and a dense square grid

**Context.** Canvas cells rendered the raw field key as a section heading, so the
conventional `content` body field showed a "CONTENT" label that wasted vertical space,
and every cell repeated its own key under the cell label ("problem / problem"). The grid
also carried generous padding (cell + card + markdown) and rounded corners, which fights
the space-constrained nature of the canvas.

**Decision.**
- Template cells may carry an optional `"titles"` map keyed by field. A non-empty value
  is the section heading, an empty value hides it, and a missing entry falls back to the
  field key — except the conventional `content` field, which is untitled by default.
  `Psc.Canvas.field_title/2` is the single source of truth, and template instantiation
  copies the map into the canvas cell.
- The template designer edits the title per field (placeholder = the key, clearing it is
  allowed and stored explicitly).
- The canvas editor no longer repeats the cell key under the cell label.
- The grid is dense and square: no padding between the table and the cell card, 8 px card
  padding, 2–4 px label/field gaps, 4 px markdown padding, trimmed prose margins, and no
  rounded corners anywhere in the grid (panel, cells, previews, inline editor).
- Grid lines use `base-content/20` rather than `/10`, so light mode keeps visible
  separators. Editing a cell replaces the browser's default focus/selection styling with a
  soft inset primary ring around the **whole cell** and a brand-tinted text selection.

**Alternatives considered.** Keeping the key as the only heading (no way to make a
section untitled); special-casing only `content` in the editor (no per-template control);
retaining rounded corners and padding for looks (rejected: density wins here).

**Consequences.** Existing templates render as before (keys stay headings, except
`content`), while templates saved from the designer can rename or hide headings. Canvases
keep the titles they were instantiated with; editing the template afterwards does not
affect them, matching the rule for the rest of the structure.

---

## ADR-021 — Mobile top bars: one menu and a stacked canvas header

**Context.** At phone widths (~390 px) the app header overflowed: logo + section title +
nav (Canvases/Templates) + theme toggle + email + Settings + Log out cannot share a
single 56 px row, so the account actions were clipped. The canvas header had the opposite
problem: title and description competed for one flex row, squeezing the description to
zero width and truncating the title.

**Decision.**
- **App header.** Below `lg` the section title becomes the flexible, truncated element;
  the nav and the account actions move into a single hamburger `<details>` menu (email as
  the menu header, then Canvases, Templates, Settings, Log out). Only the logo, title,
  theme toggle and menu button stay on the row. At `lg`+ the full desktop row returns.
  Below `sm` the wordmark and the guest *Register* link are hidden to save space. The
  menu closes on outside click and on Escape.
- **Canvas header.** Below `sm` the header stacks: the title takes its own full-width
  line, the description follows beneath it (wrapping to two lines), then the presence
  pill / save state / Share row. From `sm` up the compact single-row layout is restored.
  (Superseded by [ADR-023](#adr-023--the-canvas-tabs-follow-the-space-they-have), which
  moves the save state next to the title and gives the description its own row.)

**Alternatives considered.** Horizontally scrolling the header (hides affordances); a
second header row for the nav (costs vertical space on a dense canvas); icon-only nav
(ambiguous without labels).

**Consequences.** The header never overflows down to 320 px and the canvas keeps its
height (phones add ~54 px to the header). The account actions exist in two renderings
(desktop block and mobile menu), so changes must be mirrored.

**Addendum (2026-10-20): the bottom app bar owns the space below the grid.** The
canvas editor's bottom app bar has a known height (`--canvas-tab-bar-height`,
3.75 rem) plus the phone's safe-area inset, and the editor reserves exactly the
same amount below the grid. The table therefore ends where the bar starts: no dead
band under it, and the last row is never hidden behind the bar, so the grid does not
need scrolling to reach it. The bar's own padding keeps the tab labels clear of the
home indicator.

---

## ADR-022 — UI consolidation: one canvas model, one creation path

**Context.** After the canvas-editor rework the app had accumulated UI debt: two canvas
implementations (the fixed 12-cell PSC and the configurable canvas), two different ways to
create a template, doubled page padding, inconsistent buttons in the template library,
auth inputs small enough to trigger iOS focus zoom, a success message rendered as neutral
info, and a tooltip that could leave the viewport and stay open after a tap.

**Decision.**
- **One canvas model.** Removed the legacy fixed canvas: `/psc-canvas` routes,
  `PscWeb.CanvasLive.*`, `Psc.Canvas.Canvas` plus its 15 embedded cell schemas, their context
  functions and tests. The configurable canvas is the only canvas; its routes moved from
  `/canvases` to **`/canvas`** (and `/canvas/:id`), with `RedirectController` keeping the old
  URLs alive for bookmarks.
- **One template creation path.** The template library no longer carries an inline
  "Create New Template" form; **New Template** opens the designer (the only place a structure
  is authored). Card actions all use the same button family (primary *Use Template*;
  outline *Edit* / *Share* / *Delete*) at the same height, radius and font.
- **Template-first canvas creation.** The canvas list's create section is **"Start a canvas"**
  with the **"Start from"** template picker first, then name and description.
- **Density.** The app shell's vertical padding dropped from 32 px to 24 px and page-level
  wrappers no longer add their own `py-*`; the default container gained `w-full` because an
  auto-margined flex item otherwise shrinks to fit-content instead of filling the page.
- **The app header adapts to the viewport.** On phones and tablets the header carries only
  the logo, the page title and a menu; the **theme switch (system / light / dark) lives inside
  that menu**, together with the section links and the account actions. From large screens
  (`xl`) up, the theme switch and the account actions return to the bar and the menu
  disappears. Guests get the same menu, so the theme is reachable at every width.
- **The canvas editor is a tabbed surface.** The header carries a tab strip — **Analysis ·
  Notes · Editor · Agent** — and the panel below renders the selected view. The grid
  (Editor) is the only implemented view; the others are placeholders. The tab lives in the
  URL (`?tab=…`) so a view can be linked and the browser's back button works; the default
  is the editor. The strip is rendered in the **app header** (the free space between the
  page title and the section nav) on large screens, where it reads as an outlined
  segmented control, and as a **bottom app bar** on phones and tablets. Where the strip
  lives, and whether it shows names or only icons, is decided by the room it actually
  has — see [ADR-023](#adr-023--the-canvas-tabs-follow-the-space-they-have).
- **Accent combination on cells (fullscreen only).** A template accent belongs to a row or a
  column, but the interesting thing is the *pair*: in the **mobile fullscreen cell** the
  column's colour is drawn on the top edge and the row's colour on the left edge, so the
  single cell shows which column and row it belongs to. In the grid the combination stays
  hidden — it would only add noise to every cell edge — and the designer keeps the plain
  header bars for authoring.
- **Editor gutters on phones.** The template designer and canvas editor drop to 8 px horizontal
  page gutters below `sm`, and the designer's grid card is full-bleed (its "Grid" header keeps
  its own padding), so the table starts ~9 px from the viewport edge instead of 41 px.
- **The grid scrolls without a scrollbar on touch.** When the columns cannot have their
  minimum width the grid scrolls horizontally. On phones and tablets (and on any coarse
  pointer) the scrollbar is hidden — it is noise and it steals ~15 px of the grid — and the
  column cut off at the edge is the affordance. Where a bar does show (fine pointers), it is
  a slim, low-contrast one instead of the platform default.
- **The theme switch does not eat its own clicks.** The three-way switch draws a sliding
  thumb over the segment of the current theme; the thumb is decoration only and is
  `pointer-events-none`, so picking the theme you are already on still works. Its icons are
  centred in their segments, which matters in the menu, where the switch spans the width of
  the menu.
- **Auth on phones.** Auth inputs are 16 px / 44 px below `sm` (below 16 px iOS zooms the page
  on focus) and the form container is `max-w-md`, giving ~92 % of a 390 px viewport.
- **Success is green.** Flash gained a `:success` kind (green border/badge, check icon,
  auto-dismiss) used for positive outcomes; `:info` stays neutral (welcome, logged out) and
  `:error` unchanged.
- **Tooltip robustness.** The positioner clamps into the viewport after flipping; tooltips
  close on an outside press (mouse or touch) and toggle on tap where hover is unavailable; the
  JS hide timer matches the CSS exit animation so the fade is not cut short.
- **Designer on phones.** The designer grid keeps a computed minimum width and pans
  horizontally instead of squeezing every input to a few pixels.
- **Fullscreen cells on phones.** A first tap on a canvas cell expands it to the viewport
  (scroll locked, floating close button, Escape also closes); a second tap enters editing, so
  cramped grid cells are readable and editable without fighting the grid. The expansion
  animates in/out (respecting `prefers-reduced-motion`) and swiping left/right/up/down inside
  the fullscreen cell moves to the neighbouring cell on that axis — vertical swipes scroll
  instead when the content is taller than the screen. The first tap is intercepted in the
  **capture phase**, because the markdown display has its own click listener that would
  otherwise open the editor immediately; gestures are read from touch events (with
  `touch-action: pan-y` so the browser keeps vertical panning) and the cell slides out in the
  direction of the finger while the next one arrives from the opposite edge. Once the
  slide-in has played, the cell is parked in a `is-settled` state so the fullscreen
  animation cannot replay (that replay looked like the cell reloaded itself).

**Alternatives considered.** Keeping both canvas models (two vocabularies, dead routes, more
tests); keeping the inline template form (two creation flows, list buried below the fold on
mobile); shrinking fonts to fit the designer grid (unusable inputs); fixing the tooltip only
at the usage site (the bug is in the shared component); mapping `:info` to green globally
(loses the neutral-information channel).

**Consequences.** `grep -r unstr` still shows the `UnstrCanvas*` module names and
`grep -ri "canvas"` is still frequent — deleting the legacy generation removed the largest
block (≈18 modules), but renaming `UnstrCanvas` → `Canvas`, `Layout` → `Template` and
`CanvasLayoutLive` → `TemplateLive` is a separate mechanical refactor that was **not** done
here. Old `/canvases` URLs redirect through the authenticated scope, so they require a session
just like the new ones.

---

## ADR-023 — The canvas tabs follow the space they have

**Context.** The canvas tab strip was added to the app header, and the first placement
guessed at the available room with viewport breakpoints: icons only between `md` and
`xl`, full names from `xl`, bottom app bar below `md`. Three things were wrong with it.
The strip was **left aligned** in the header instead of centred in the space between the
page title and the section nav. The switch to **full names happened too late** (1280 px),
so a 1024 px tablet got four bare icons where there was room for the words, while the
switch to the **bottom app bar happened too late** as well (768 px), so tablets kept a
strip that only half fitted. And the canvas header on a phone was still cramped: the
title, the description, the presence pill, the save state and the Share button were
stacked without a clear hierarchy, the description pushed the actions off the screen, and
the presence pill showed a full e-mail address where it had no room for one.

**Decision.**
- **The header slot is a container.** `Layouts.app` renders `:header_nav` inside a
  `@container` wrapper that is `justify-center`, so whatever is placed there is centred
  in the free space between the page title and the section nav, not left aligned.
- **Two renderings, one set of tabs.** The header strip (`#canvas-tabs`) is shown from
  `lg` (1024 px) up; below that the same tabs are rendered as a fixed **bottom app bar**
  (`#canvas-tabs-bar`), the way native apps switch sections. Both carry the same
  `role="tablist"`, the same `select_tab` event and the same `?tab=` deep link; the one
  that is not on screen is `display: none` and therefore out of the accessibility tree.
- **Names follow the room, not the viewport.** The strip's labels are hidden by a
  **container query** (`@max-[23rem]:hidden`) on the header slot: when the free space
  drops below the width the four names need (≈ 350 px), the strip falls back to icons
  instead of overflowing into a scrollbar. A long page title or a narrow window
  therefore degrades gracefully at any viewport width.
- **The canvas header has a hierarchy.** On phones and tablets the header is
  title + save state on the first line, the description on its own line (two lines at
  most), then the presence pill and the Share button on the last line (Share pushed to
  the right). From `lg` up it is a single row again: title, description, presence, save
  state, Share.
- **Presence is compact where space is short.** Below `lg` the pill reads "1 online" /
  "N online" instead of the full e-mail address; the full list is always in the tooltip.
- **On phones the editor header is only the title and the description.** The grid is the
  point of the screen, so the presence, the save state and Share move into the **app
  header** as a minimal cluster (a presence count, a save-state icon, an icon-only Share
  button) and the editor header drops to two rows. From `sm` up the full controls stay
  with the canvas header, where there is room for them. The cluster lives in a new
  `Layouts.app` `:header_actions` slot.

**Alternatives considered.** Keeping one element and repositioning it with CSS (the
container query then also applied to the fixed bottom bar, whose ancestor became a
containing block and broke the fixed positioning); guessing the breakpoints with
viewport widths only (the icons-only state appeared far too late); keeping the e-mail
address in the presence pill (it ate a third of a phone's header row).

**Consequences.** The tab strip is rendered twice in the DOM, so the two sets of buttons
need distinct ids (`canvas-tab-*` in the header, `canvas-tab-bar-*` in the app bar); the
tab panel's `aria-labelledby` points at the header button, whose text still names the
panel when it is off screen. The E2E suite drives the header strip (its viewport is
1280 px), and the LiveView test asserts that both sets exist and switch tabs.

**Addendum (2026-10-20): the tab switch is client-side.** Clicking a tab used to wait
for the server: the click pushed a patch, the server re-rendered the whole view
(including the canvas grid and every cell's Markdown) and the client applied the
result. On a phone that is a network round trip on the critical path, which read as a
lag after every click.

Now every view is rendered — the grid and the three placeholders — and the inactive
ones are hidden. A `CanvasTabs` hook swaps the panel the moment the tab is clicked
(measured: 0.4 ms, synchronous with the click) and the server confirms the choice and
the URL a moment later. The selected tab is styled from `aria-selected` in CSS, so the
client can update the highlight without knowing the utility classes. The server keeps
the authority: it owns the state, the URL and the rendering.

## ADR-024 — Mobile feedback and dialogs stay in the visible viewport

**Context.** The canvas editor uses a fixed bottom app bar below the large-screen
breakpoint. Feedback cards rendered at the top of the viewport steal space from the
grid on phones, while a share dialog can be covered by the virtual keyboard after
its first input receives focus. Tab changes also represent view state inside one
canvas rather than a sequence of separate pages.

**Decision.**

- Render feedback cards at the bottom on phones and tablets, with enough safe-area
  space to sit above the bottom app bar; retain the top-right placement on large
  screens.
- Give dialogs a viewport-relative maximum height and an internal scroll region.
  The shared dialog component watches `visualViewport` on compact screens and
  keeps the panel inside the visible area when the keyboard resizes or scrolls
  that viewport.
- Change the canvas tab picker to use `push_patch(..., replace: true)`. The selected
  tab remains deep-linkable, but browser Back returns to the canvas list instead of
  replaying each tab selection.
- Keep Markdown density changes scoped to `.canvas-cell .md-render`; reduce line
  height and block margins without changing the editor input styles.
- Row and column accents remain tokens in the template `layout_map`. Save/reopen
  coverage verifies that selected and cleared accents survive an explicit template
  save and are still available for canvas instantiation.

**Alternatives considered.** Keeping feedback at the top on all screens (it competes
with the grid and the bottom app bar); relying only on `scrollIntoView` once (the
keyboard changes the visual viewport after focus); pushing every tab into history
(Back becomes a tab undo stack rather than leaving the editor); and applying a
global typography reset (it would alter documents and form controls).

**Consequences.** Dialog positioning now has a small client-side visual-viewport
policy shared by all dialogs, and mobile feedback cards use the bottom safe-area
offset. Canvas tabs still update the URL and invoke `handle_params/3`, but do not
create browser-history entries. Existing canvases remain unchanged when a template
accent is later edited.

## ADR-025 — The app header owns index page titles

**Context.** The shared app header already identifies the current route, but the
Canvases and Templates index pages repeated the same label as a large `h1` in the
main body. That duplicate hierarchy consumed vertical space and made the page
content feel like it had two competing titles.

**Decision.** Render the shared route title as the single semantic `h1` in the app
header, with a stronger responsive treatment (`text-base` on phones and `text-lg`
from `sm` upward). Remove the duplicate body heading from the Canvases and
Templates index pages; keep their page-specific controls and section headings.

A page's primary action belongs to the list it acts on. The Templates library
opens with a **New Template** card — the first tile of the grid, the same size as
a template card, drawn with a dashed border to mark it as the create action. The
header stays free of page actions, so the route title keeps the space.

**Alternatives considered.** Keeping both headings (redundant and less space for
the actual library/forms), removing the header title (loses the persistent route
context), hiding the body heading visually while leaving it in the accessibility
tree (preserves duplicate semantics), putting the action in the header next to the
title (the header becomes a second toolbar), and leaving a right-aligned button
stranded above the library (it reads as detached from the content it acts on).

**Consequences.** The shell owns the page-level heading for routes that provide
`header_title`. Index pages start directly with their primary content, and the
template library's create action is a grid tile, so the library reads as one
uniform grid. Browser and LiveView tests assert the header heading, the tile's
placement, and the absence of a `main h1`.

## ADR-026 — View state lives in the URL, not in the page

**Context.** The canvas editor has two kinds of view state: the selected tab
(Analysis, Notes, Editor, Agent) and, on phones, the cell that is expanded to
the full screen. The tab was already in the URL. The fullscreen cell was not:
it was a client-side class, so pressing Back left the canvas entirely and
landed on the canvas list, and the view could not be linked or reloaded.

**Decision.**

- The expanded cell is encoded as the URL fragment `#cell-<key>`. Entering the
  fullscreen view pushes a history entry, so Back collapses the cell and
  returns to the canvas grid; leaving it removes the fragment.
- The fragment is deliberate. LiveView decides whether a history entry is its
  own by comparing pathname and search, so a fragment-only change is invisible
  to it and costs no server round trip. A query parameter would have made
  every expand and collapse a LiveView navigation.
- Swiping to a neighbouring cell replaces the fragment instead of adding an
  entry: it is the same fullscreen view, only a different cell.
- A URL that already names a cell opens that cell full screen, so the view can
  be shared and survives a reload.
- The shared dialog no longer calls `scrollIntoView`. The panel is fixed and
  centred, and it is kept inside the visible viewport by moving it with `top`;
  scrolling the document made the canvas editor's own scroll area jump behind
  the modal. The nudge must not be a transform: Tailwind v4 centres the panel
  with the `translate` property, so a transform on top of it is a *second*
  translation, which pushed half of the panel off the screen whenever the
  keyboard was open.

**Alternatives considered.** Leaving the cell out of the URL (Back leaves the
canvas); a query parameter such as `?cell=` (every expand becomes a LiveView
navigation and a server round trip); pushing a history entry per swipe (the
Back button would walk through cells); and `scrollIntoView` for the dialog (it
scrolls the nearest scrollable ancestor, which is the editor's grid).

**Consequences.** The fullscreen cell is linkable, reload-safe, and Back
returns to the canvas. The browser and LiveView tests assert the fragment, the
Back behaviour, and that opening the share modal does not move the page.

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