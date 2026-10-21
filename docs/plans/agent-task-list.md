# Agent task list — MVP completion and hardening

> **Historical record — not a backlog and not a work queue.** This document is kept as a
> description of known gaps and their rationale at the time it was written. Nothing here is
> scheduled, assigned, or awaiting an agent. Do not pick a task from it; work only from what
> the user explicitly asks for.

**Prepared:** 2026-10-19 against `a56d820` (deployed as Gigalixir release 10, Healthy).
**Companion docs:** [AGENTS.md](../../AGENTS.md) (context and conventions),
[DEVELOPMENT.md](../../DEVELOPMENT.md) (environment), [design-decisions.md](../design-decisions.md)
(ADRs 001–021), [template-designer.md](../spec/template-designer.md),
[canvas-editor.md](../spec/canvas-editor.md), [project_proposal.md](../project_proposal.md).

---

## How to read this document

1. **It is reference.** The *Why*, *Scope*, and *Pitfalls* sections explain how a part of the
   system works and what was learned; they are useful when a user's request touches that area.
2. **Statuses are snapshots, not assignments.** `todo` means "observed as missing at the time
   of writing", not "someone should start this now".
3. **Nothing here is an instruction.** Follow the user's request first; consult the matching
   section only if it helps answer that request.

### Definition of done (applies to every task)

- [ ] Behaviour matches the task's acceptance criteria, verified in a running app where visual.
- [ ] `mix.bat verify` green (format, zero warnings, all tests).
- [ ] New behaviour covered by tests at the right level (context → `test/psc/…`,
      LiveView → `test/psc_web/live/…`, flow → `test/e2e/tests/…`).
- [ ] No new `100vh`/hardcoded light-dark colours; use theme tokens (ADR-015) and the
      existing flex layout (ADR-020/021).
- [ ] Docs updated when behaviour or data shape changed.
- [ ] Deployed? Only when the user asks — then `scripts\deploy.ps1`.

### Ground rules / invariants

- **Event sourcing with pruning (ADR-001, 002, 006).** Edits are rows in
  `unstr_canvas_events` / `document_events`; a save folds them into the `cells`/`content`
  snapshot, advances `snapshot_seq` *monotonically* and deletes events `seq <= snapshot_seq`.
  Never write `snapshot_seq` backwards, never delete un-folded events.
- **Free-tier DB ceiling (ADR-006).** 10k rows per table. Any feature that writes per-edit
  rows must prune or aggregate. Bounded history (tasks P1-*) must not grow unboundedly.
- **Per-field last-write-wins (ADR-004).** A canvas operation carries the whole field value;
  no OT/merge per field. Do not assume character-level merging on canvases.
- **Template → canvas is a copy (ADR-009).** `Canvas.instantiate_template/3` goes through the
  context; editing a template never mutates existing canvases.
- **Auth is `current_scope`-based** (`phx.gen.auth`); pass it to contexts, never read
  `current_user`.
- **UI kit is SaladUI** (`lib/psc_web/components/ui/*`), imported qualified where a name clashes
  (`UIButton`, `UIInput`, `UIForm`). Icons via `PscWeb.Components.UI.Icon` or `<.icon>`.
- **Density rules for the canvas grid (ADR-020):** square cells, no padding between table and
  cell card, no rounded corners inside the grid; only the outer panel is rounded.
- **Layout rules (ADR-020/021):** the canvas editor opts into `fill_height` + `main_class`;
  the mobile header uses the `<details data-menu>` menu below `lg`.

---

## Gotchas learned in this codebase (verified the hard way)

- **Colocated hook names must be literal.** `phx-hook={some_condition && ".MyHook"}` is **not**
  rewritten to `Module.MyHook`; only a literal string starting with `.` is. The symptom is a
  browser console error `unknown hook found for ".MyHook"`. Always write `phx-hook=".MyHook"` and
  decide inside the hook whether to act.
- **A fixed-layout `<table>` ignores flex sizing.** `table-fixed` + `flex-1`/`height: 100%` only
  stretches when an ancestor has a *definite* height (`h-dvh` shell → `flex-1 min-h-0` → table
  `h-full min-h-0 flex-1`). Then `<tr>` heights distribute automatically; do not size rows.
- **Rounded outer frames need the inner table borderless on the outside.** The panel draws the
  rounded `border` + `overflow-hidden`; zero the table's first/last column and first/last row
  borders, or the corners look reconstructed (double seam).
- **`field-sizing-content` + a bottom border overflows by the border width.** Add `box-content`
  to a growing textarea, otherwise a 2 px scrollbar appears at the exact fitted height.
- **Documents' CRDT drops same-length replacements** (`text_to_deltas/2` → `[]`), so they are not
  broadcast. Canvases are unaffected (whole-value operations). See P4-1.
- **Test-hook ids are contract.** `#canvas-header`, `#canvas-grid`, `#cell-card-<key>`,
  `#md-<key>-<field>`, `#md-render-<key>-<field>`, `#active-users-tooltip`, `#cell-r1_c1`,
  `<field-id>-error`. Renaming one breaks LiveView and Playwright tests — grep before renaming.
- **Two servers, two databases.** Dev runs on 4000 with `psc_dev`; Playwright owns 4001 with
  `psc_e2e` and reuses an already-running server. Never point E2E at the dev database.
- **`gigalixir logs` streams forever** — it does not exit. Use `gigalixir ps` for release state
  and an HTTP probe for liveness instead of a log tail in scripts.
- **`mix verify` formats `.ex/.exs/.heex` only.** Markdown docs are not checked by any task;
  proofread them yourself.

---

## Where the product stands (verified at `a56d820`)

| Area | State | Evidence |
|---|---|---|
| Auth (email + password, auto-confirm at signup) | Working; magic-link login; no password reset | `lib/psc_web/user_auth.ex`, `user_session_controller.ex` |
| Auth feedback UI | Inline chips + feedback cards, a11y wiring | ADR-019 |
| Template designer | Grid, inline cell editing, optional section titles, accents, sharing, explicit save + discard guard | ADR-013/014/016/020, `docs/spec/template-designer.md` |
| Canvas editor | Instantiate from template, inline Markdown fields, click-anywhere editing, presence, autosave, fixed uniform grid, mobile header | ADR-004/020/021 |
| Collaboration | PubSub broadcast + CRDT fold + presence; per-field LWW | `lib/psc/canvas/unstr_canvas_crdt.ex` |
| Sharing | One `ShareDialog` for template/canvas/document | ADR-016 |
| Documents | **Parked** — routes live, no nav entry | ADR-018 |
| Pivot / version system | **Not started** (Core MVP milestone 4 missing) | `docs/project_proposal.md` §roadmap |
| Analytics / insights / telemetry | Placeholders only | `docs/spec/analytics.md` etc. |
| CI | None (no `.github/workflows`) | — |
| Health endpoint | None | `lib/psc_web/router.ex` |
| Deployment | `scripts/deploy.ps1` → Gigalixir, migrations at boot | AGENTS.md §Deployment |

---

## Task index

| ID | Title | Size | Priority | Depends on | Status |
|---|---|---|---|---|---|
| [P0-1](#p0-1--fold-canvas-events-on-a-threshold) | Fold canvas events on a threshold | S | P0 | — | todo |
| [P0-2](#p0-2--retire-the-legacy-fixed-psc-canvas) | Retire the legacy fixed-PSC canvas | M | P0 | — | todo |
| [P0-3](#p0-3--add-a-consistency-resync-to-the-canvas-editor) | Add a consistency resync to the canvas editor | S | P0 | — | todo |
| [P1-1](#p1-1--pivot-data-model-and-migration) | Pivot data model and migration | M | P1 | — | todo |
| [P1-2](#p1-2--pivot-context-api) | Pivot context API | M | P1 | P1-1 | todo |
| [P1-3](#p1-3--pivot-ui-create-browse-compare) | Pivot UI: create, browse, compare | L | P1 | P1-2 | todo |
| [P1-4](#p1-4--restore-and-fork-from-a-pivot) | Restore and fork from a pivot | M | P1 | P1-3 | todo |
| [P1-5](#p1-5--structure-editing-in-the-canvas-editor) | Structure editing in the canvas editor | L | P1 | — | todo |
| [P2-1](#p2-1--password-reset-flow) | Password reset flow | M | P2 | — | todo |
| [P2-2](#p2-2--ci-pipeline) | CI pipeline | M | P2 | — | todo |
| [P2-3](#p2-3--health-endpoint-and-uptime-probe) | Health endpoint and uptime probe | S | P2 | — | todo |
| [P2-4](#p2-4--liveview-crash-visibility) | LiveView crash visibility | S | P2 | — | todo |
| [P3-1](#p3-1--clamp-tooltips-on-narrow-screens) | Clamp tooltips on narrow screens | S | P3 | — | todo |
| [P3-2](#p3-2--keyboard-editing-in-canvas-cells) | Keyboard editing in canvas cells | M | P3 | — | todo |
| [P3-3](#p3-3--overflow-affordance-and-sticky-grid-headers) | Overflow affordance and sticky grid headers | M | P3 | — | todo |
| [P3-4](#p3-4--template-library-search) | Template library search | S | P3 | — | todo |
| [P3-5](#p3-5--first-run-guidance) | First-run guidance | S | P3 | — | todo |
| [P4-1](#p4-1--decide-the-fate-of-documents) | Decide the fate of Documents | S | P4 | — | todo |
| [P4-2](#p4-2--telemetry-export-foundation) | Telemetry export foundation | L | P4 | P1-1 | todo |

Sizes: S ≈ half a day, M ≈ 1 day, L ≈ 2–3 days for one agent.

**Keeping this table honest.** Update the `Status` cell as you work: `todo` → `in progress
(agent, date)` → `done (commit <sha>)`. If a task is abandoned or re-scoped, say so there and
leave the original text intact so the next agent understands why.

---

# P0 — Correctness and cleanup

## P0-1 — Fold canvas events on a threshold

**Why.** The document editor folds pending operations into the snapshot after
`@max_pending_events 500` (`lib/psc_web/live/document_live/editor.ex`), but the canvas editor
only folds on its idle (1.5 s) and periodic (10 s) timers. A fast paste/edit burst can write
thousands of event rows before either timer fires; the free tier caps tables at 10k rows
(ADR-006). Open issue 3 in `docs/design-decisions.md`.

**Scope**
- Add a pending-operation counter to `PscWeb.UnstrCanvasLive.Editor`, mirroring the document
  editor: increment per applied local operation, reset on fold.
- When the counter crosses the threshold (reuse 500, define one module attribute), call
  `Psc.Canvas.save_unstr_canvas_content_to_db/2` with the current `cells` immediately.
- Ensure the fold is idempotent with the periodic timer (no double-save races), and that the
  sequential `snapshot_seq` floor logic in `next_unstr_canvas_sequence/1` is preserved.

**Out of scope.** Changing the document editor's threshold; changing the fold-on-idle timers.

**Acceptance criteria**
- [ ] A burst of ≥500 operations folds once, without waiting for a timer.
- [ ] The resulting canvas still replays identically (`get_unstr_canvas_content/1` matches the
      in-socket `cells`).
- [ ] `snapshot_seq` never regresses when a save races the periodic timer.
- [ ] A test drives the counter across the threshold and asserts one snapshot save plus pruned
      events.

**Files.** `lib/psc_web/live/unstr_canvas_live/editor.ex`, `lib/psc/canvas.ex`,
`test/psc/canvas_test.exs` (or a new editor test file), `docs/design-decisions.md` (close open
issue 3).

**Verification.** `mix.bat test test/psc/canvas_test.exs` plus the editor LiveView tests;
`mix.bat verify`. Browser smoke: type/paste in a cell, wait, reload, content persists.

**Pitfalls.** Do not reset the counter before the save returns; a failed save must not drop
events. The `:idle_save` message may arrive while a threshold fold is in flight — guard with the
existing `last_saved_cells` comparison rather than adding a boolean flag that can stick.

---

## P0-2 — Retire the legacy fixed-PSC canvas

**Why.** `/psc-canvas` and `/psc-canvas/:id` still route to `CanvasLive.Index`/`CanvasLive.Editor`
— a fixed 12-cell PSC editor that is unreachable from the navigation and superseded by
templates (ADR-010, open issue 6). It costs tests, routes and reviewer attention, and its
`Canvas`/`Document`-era context functions blur the model.

**Scope (recommended option A)**
- Add a seeded built-in template that reproduces the fixed PSC structure (3 rows × 4 columns,
  12 cells) so nothing is lost. Seed it in `priv/repo/seeds.exs` idempotently, and make it
  discoverable in the template library.
- Delete the `/psc-canvas` routes and the `PscWeb.CanvasLive.*` modules, their tests and any
  now-unused `Psc.Canvas` functions (`create_canvas`, `get_canvas*`, `update_canvas`,
  `update_cell`, `list_*_canvases`, `share_canvas_with/2`, …) only if unused by the template
  flows.
- Keep the `canvases` table/schema or drop it in a follow-up migration — decide in the PR and
  document it.

**Option B (cheaper, if A looks risky):** delete the routes only, leave the modules and their
tests untouched, and note them as dead code.

**Acceptance criteria**
- [ ] No route serves the fixed PSC editor; `grep -r "psc-canvas" lib test` is clean.
- [ ] The built-in PSC template produces the same 12-cell structure as the old editor.
- [ ] `mix.bat verify` green; no test references a removed route.

**Files.** `lib/psc_web/router.ex`, `lib/psc_web/live/canvas_live/*`, `priv/repo/seeds.exs`,
`lib/psc/canvas.ex`, tests, `docs/routing_map.md`, `docs/design-decisions.md` (close issue 6).

**Verification.** `mix.bat test`; browser: `/psc-canvas` returns 404, template list shows the
PSC template, instantiating it renders the 12 cells.

**Pitfalls.** `priv/repo/seeds.exs` runs in `mix ecto.setup` and must stay idempotent. Do not
break `priv/repo/e2e_seeds.exs` (used by Playwright).

---

## P0-3 — Add a consistency resync to the canvas editor

**Why.** `DocumentLive.Editor` verifies its local state every 5 s against the server
(`Psc.Documents.ConsistencyManager.verify_consistency/2`) and pushes a full reload when it has
diverged. `UnstrCanvasLive.Editor` has **no equivalent**: it relies entirely on broadcast
`{:operation, …}` messages. If one is missed (socket drop, reconnect, a rejected insert, or the
pruned-event window described in ADR-001), the canvas shows stale content until a manual reload —
and the presence of other users makes that look like a sync bug rather than a missed message.

**Scope**
- Mirror the document pattern: a `@consistency_check_interval` (5 000 ms) `:check_consistency`
  message in `UnstrCanvasLive.Editor` that compares the socket `cells` with
  `Psc.Canvas.get_unstr_canvas_content(canvas_id)` (the authoritative snapshot).
- On divergence, push a full-state event to the client (`cell_updated` per changed field, or a
  single `canvas_resynced` payload the `CellFocus`/`MarkdownField` hooks understand) and update
  the socket assigns. Use a `from_user_id: -1` sentinel like the document editor so clients
  treat it as authoritative.
- Emit a telemetry event (`[:psc, :canvas, :consistency_divergence]`) for observability.
- Make sure the check does not fight in-flight local edits: skip while a local save/idle fold is
  pending, and compare against the socket state *after* applying the pending operations.

**Out of scope.** Replacing broadcast with polling (this is a safety net, not the transport);
changing the document editor.

**Acceptance criteria**
- [ ] Divergence is repaired within ~5 s without a reload, in a test that fabricates a stale
      socket state (call the handler directly with a mismatched `cells` assign).
- [ ] A consistent client produces no events and no re-render (no DOM churn).
- [ ] A local edit in flight is never overwritten by a stale resync.
- [ ] Telemetry event fires once per divergence.

**Files.** `lib/psc_web/live/unstr_canvas_live/editor.ex`,
`lib/psc/canvas.ex` (if a helper is needed), `assets/js/hooks/markdown_field.js` (if the payload
shape changes), `test/psc_web/live/unstr_canvas_live_test.exs`, `docs/design-decisions.md`.

**Verification.** `mix.bat test test/psc_web/live/unstr_canvas_live_test.exs`; `mix.bat verify`;
two-browser smoke test with one tab's socket throttled offline.

**Pitfalls.** `get_unstr_canvas_content/1` reads the **snapshot**, which lags the event log until
the idle/periodic fold — so compare against `snapshot + pending events`, not the snapshot alone,
or you will "repair" fresh edits away. Prefer reusing `UnstrCanvasCRDT.rebuild_state/2` on the
pruned-events-after-snapshot list.

---

# P1 — Core MVP completion

## P1-1 — Pivot data model and migration

**Why.** The product proposal's Core MVP milestone 4 is the **pivot system**: named snapshots
with rationale, navigable history, comparison, and restore/fork. None of it exists. The pruned
event tables cannot serve it (open issue 1), so it needs its own substrate.

**Decision to make (recommended default).** Store a pivot as a **full snapshot of the canvas
cells map** plus a `parent_id` (tree) — not a delta — because canvases are small maps and the
free-tier row budget is fine with a few dozen pivots per canvas. Rationale: delta history would
require the very event rows pruning removes.

**Schema (`unstr_canvas_pivots`)**
- `id` binary_id PK, `unstr_canvas_id` FK (`on_delete: :delete_all`), `author_id` FK.
- `name` string (required, ≤120 chars), `rationale` string (required — it is the point of a
  pivot, ≤2000 chars).
- `cells` map (the snapshot at creation), `snapshot_seq` integer (event seq folded into it).
- `parent_id` self-FK nullable (`on_delete: :nilify_all`) → forms a tree/DAG.
- `timestamps()`; index on `(unstr_canvas_id, inserted_at)`.

**Acceptance criteria**
- [ ] Migration creates the table with FKs and the index; `mix.bat ecto.migrate` clean.
- [ ] Ecto schema + changeset validate required fields and lengths, and reject a `parent_id`
      from a different canvas.
- [ ] Deleting a canvas deletes its pivots; deleting a parent pivot nullifies children.
- [ ] Tests cover the changeset and cascade behaviour.

**Files.** `priv/repo/migrations/<timestamp>_create_unstr_canvas_pivots.exs`,
`lib/psc/canvas/unstr_canvas_pivot.ex`, `lib/psc/canvas/unstr_canvas.ex` (association),
`test/psc/canvas_test.exs`.

**Verification.** `mix.bat verify`; `mix.bat ecto.migrate` twice (idempotent on the second boot
path — `Psc.Release.migrate/0`).

**Pitfalls.** `binary_id` for FKs (`@foreign_key_type :binary_id`), matching the other canvas
schemas. Migrations run at boot on Gigalixir — keep them fast and reversible enough to be safe.

---

## P1-2 — Pivot context API

**Why.** The LiveViews must not touch the repo directly (ADR-009 precedent: all aggregate
writes go through `Psc.Canvas`).

**Scope — `Psc.Canvas` functions**
- `create_pivot(canvas, user_id, %{name:, rationale:, parent_id: nil, cells: nil})` — defaults
  to the canvas's current `cells`, stores the current `snapshot_seq` as its marker.
- `list_pivots(canvas_id)` — newest first, with author preloaded.
- `pivot_tree(canvas_id)` — pivots arranged as `%{nodes:, roots:}` or a nested map for rendering.
- `get_pivot!/1`, `delete_pivot/1` (author or canvas owner only).
- `diff_pivots(a, b)` — `%{"added" => keys, "removed" => keys, "changed" => [{key, field, before, after}]}`
  computed field-wise from the two cells maps (ignore `$name`/`$description` unless mapped).
- `restore_pivot(canvas, pivot, user_id)` / `fork_pivot(canvas, pivot, user_id)` — see P1-4 for
  semantics; the API lands here, the UI in P1-4.

**Acceptance criteria**
- [ ] Creating a pivot stores the exact cells map the canvas had at that moment and a
      `snapshot_seq` that never exceeds the canvas's marker.
- [ ] Pivots are scoped to a canvas and to users with access; a stranger gets `nil`/`{:error, :unauthorized}`.
- [ ] `diff_pivots/2` is symmetric for added/removed and deterministic for changed fields (sorted).
- [ ] Unit tests cover create, tree shape, diff (add/remove/change/no-op) and authorisation.

**Files.** `lib/psc/canvas.ex`, `test/psc/canvas_test.exs`, `docs/data_model.md`,
`docs/design-decisions.md` (new ADR for the pivot substrate; close open issue 1).

**Verification.** `mix.bat test test/psc/canvas_test.exs`; `mix.bat verify`.

---

## P1-3 — Pivot UI: create, browse, compare

**Why.** Milestone 4 is only valuable if a user can see and navigate history.

**Scope**
- **Create:** a "Pivot" action in the canvas header (next to Share, owner + editors) opening a
  `UIDialog` with *Name* (required), *Rationale* (textarea, required), and an optional "parent
  pivot" select (default: latest). Uses the existing dialog/button/form components and the
  feedback-card flash on success/failure.
- **Browse:** a collapsible history panel (right side on desktop, sheet/drawer on mobile)
  listing pivots newest-first with name, author, relative time and rationale preview; the tree
  renders parent → children with indentation, not a graph.
- **Compare:** selecting two pivots (or a pivot vs current) opens a read-only comparison: cells
  grouped by row/column with *added / removed / changed* highlighting using theme tokens
  (`success`, `warning`, `destructive`) and `diff_pivots/2`.
- Keep the grid's density rules; the panel must not resize the canvas (overlay, `z-30`, same
  pattern as the editing cell overlay).

**Out of scope.** Restore/fork (P1-4), graphs/visual trees with edges, comments, collaboration
cursors inside the history panel.

**Acceptance criteria**
- [ ] Creating a pivot from the canvas stores it and shows it in the panel without a reload.
- [ ] Pivots are only listed for users with access; non-editors see a read-only panel.
- [ ] Comparison highlights added/removed/changed cells and matches `diff_pivots/2` output.
- [ ] Usable at 390 px (panel becomes a full-screen sheet; no horizontal overflow).
- [ ] LiveView tests for create/list/compare; one E2E happy path.

**Files.** new `lib/psc_web/live/unstr_canvas_live/components/pivot_*.ex` (or functions in the
editor), `lib/psc_web/components/ui/*` reuse only, `test/psc_web/live/unstr_canvas_live_test.exs`,
`test/e2e/tests/canvas.spec.ts`, `docs/spec/canvas-editor.md`.

**Verification.** `mix.bat verify`; `npx.cmd playwright test`; browser check in dark + light,
desktop + 390 px.

**Pitfalls.** The canvas header is already dense — add the action to the action cluster, not a
new row. Do not introduce a second flash system; use `put_flash`.

---

## P1-4 — Restore and fork from a pivot

**Why.** History without the ability to act on it is a viewer, not a version system.

**Semantics (decide and document in the ADR)**
- **Restore** — overwrite the canvas's current `cells` with the pivot's, as a normal
  `save_unstr_canvas_content_to_db/2` (advancing `snapshot_seq`, pruning events). Destructive
  history: record a *new* pivot named "Restored from <name>" automatically so the act is
  auditable. Owner only.
- **Fork** — create a **new canvas** authored by the acting user (or the original author when
  they fork their own), name defaulting to "<canvas name> (fork)", cells copied from the pivot,
  and a first pivot linking back to the source (`parent_id` refers to a pivot of the *source*
  canvas — store `source_pivot_id` if you want a cross-canvas link, or keep it simple and just
  record it in the new pivot's rationale).
- Broadcast the restore so connected clients converge (reuse the operation broadcast path with a
  `replace_cells` operation, or force a resync push).

**Acceptance criteria**
- [ ] Restore is owner-only, creates an audit pivot, and all connected clients converge without
      a manual reload.
- [ ] Fork creates an independent canvas; editing it never touches the source.
- [ ] Both actions are confirmed in a dialog ("This replaces the current content").
- [ ] Tests: restore concurrency (two clients), fork isolation, permissions.

**Files.** `lib/psc/canvas.ex`, `lib/psc/canvas/unstr_canvas_crdt.ex` (new op type),
editor + pivot UI modules, tests, `docs/design-decisions.md`.

**Verification.** `mix.bat verify`; multi-user E2E: user A restores, user B sees the change.

**Pitfalls.** `replace_cells` must be applied by `UnstrCanvasCRDT.apply_operation/2` during
replay too, otherwise a reload diverges from the live view. Add the op to the CRDT tests first.

---

## P1-5 — Structure editing in the canvas editor

**Why.** `docs/spec/canvas-editor.md` (lines 202–206) requires an owner to add/remove rows,
columns and cell fields in the **canvas**, not only in the template. Open issue 7. Today the
structure is frozen at instantiation.

**Scope**
- New CRDT operations: `add_row`, `remove_row`, `add_column`, `remove_column`,
  `add_cell_field`, `remove_cell_field`, `rename_row`, `rename_column` — each with a
  deterministic target id (e.g. `"r" <> unique integer` supplied by the client or derived
  server-side from the layout length) so replays converge.
- Implementation in `UnstrCanvasCRDT.apply_operation/2` + `Psc.Canvas` helpers that keep
  `rows`, `columns`, `layout` and the flat cell keys consistent (a new position needs a cell
  entry with `row`/`column` metadata and default fields).
- Owner-only controls in the canvas editor: hover affordances on row/column headers (same
  pattern the template designer uses), an "Add row/column" control, and per-cell field
  add/remove. Shared editors see none of them.
- Broadcast each structural change like content edits, with tests for replay convergence.

**Out of scope.** Reordering rows/columns (drag), nested grids, per-cell accents in the canvas
editor (accents stay template-authored and read-only per ADR-011).

**Acceptance criteria**
- [ ] Owner can add/remove a row and a column; every connected client updates.
- [ ] Removing a row/column removes its cells from the map (no orphans) and is confirmed.
- [ ] Owner can add/remove a field in a cell; the new field renders and persists.
- [ ] Shared (non-owner) users see no structure controls and get `{:error, :unauthorized}` if
      they push the events.
- [ ] Replaying the events recreates the same grid (`rebuild_state/2` test).
- [ ] E2E: owner restructures a canvas; a second user sees the new grid.

**Files.** `lib/psc/canvas/unstr_canvas_crdt.ex`, `lib/psc/canvas.ex`,
`lib/psc_web/live/unstr_canvas_live/editor.ex`, tests (context + LiveView + E2E),
`docs/spec/canvas-editor.md`, `docs/design-decisions.md`.

**Verification.** `mix.bat verify`; `canvas.spec.ts` multiplayer case extended.

**Pitfalls.** Cell keys are `"<row_id>_<column_id>"` — removal must not collide with a later
re-add; prefer monotonically increasing ids. The template designer's rules (unique field keys,
valid lowercase keys) must be enforced here too, via a shared validator.

---

# P2 — Deployed-product essentials

## P2-1 — Password reset flow

**Why.** The app is live with email + password auth but has **no reset path**: a user who
forgets the password is permanently locked out. `phx.gen.auth` normally ships this; this codebase
does not.

**Scope**
- `Accounts.deliver_reset_password_instructions/2` + token lookup (reuse `users_tokens` with
  `context: "reset_password"`), 60-minute expiry, single-use.
- Routes: `/users/reset-password` (LiveView, request form), `/users/reset-password/:token`
  (LiveView, set new password). Place them in the public `live_session` with
  `mount_current_scope`.
- **No mailer is configured** (ADR/AGENTS: "no email confirmation, no mailer needed"). Two
  options — pick one and document it:
  - **(default, no new dependency)** render the reset link in the UI/flash in dev and log it,
    gated to `config :psc, :env in [:dev, :test]`, and return the same generic message in prod;
  - or add Swoosh + a real provider (out of scope for the free tier).
  If only the dev path exists, make the UI state that email delivery is not enabled, rather
  than sending users into a dead end.
- Reuse the auth error UI (ADR-019): chips + feedback card, `novalidate`, `aria-invalid`.

**Acceptance criteria**
- [ ] Requesting a reset for an unknown email shows the same message as a known one
      (no user enumeration) and creates no token.
- [ ] A valid token sets a new password, logs the user in, and invalidates other sessions.
- [ ] Expired/used tokens show a clear error and a link back to request another.
- [ ] Rate limiting: at most one token per email per minute.
- [ ] Tests: request (known/unknown), reset (valid/expired/reused), session invalidation.

**Files.** `lib/psc/accounts.ex`, `lib/psc_web/router.ex`, new
`lib/psc_web/live/user_live/reset_password.ex`, `lib/psc_web/user_auth.ex`,
`test/psc/accounts_test.exs`, `test/psc_web/live/user_live/*`.

**Verification.** `mix.bat verify`; browser: request → follow link → new password → log in.

**Pitfalls.** Do not leak whether the email exists. Reuse `update_user_password/2` so the
logout-all-sessions behaviour is preserved.

---

## P2-2 — CI pipeline

**Why.** There is no `.github/workflows`. Every regression so far was caught by a human running
the suite locally.

**Scope**
- GitHub Action on `push`/`pull_request` to `main`:
  1. setup Elixir/OTP matching `elixir_buildpack.config` (**Elixir 1.20.4 / Erlang 29.1** — keep
     in sync if the buildpack changes),
  2. cache `deps` and `_build`,
  3. `mix deps.get`, `mix assets.build` (or `tailwind`/`esbuild` install),
  4. `mix verify`,
  5. Postgres service + `mix test` (the `test` alias creates/migrates),
  6. optionally a separate job for Playwright (Node + `npx playwright install --with-deps`),
     or keep E2E local and document why.
- Cache/keys must not break on Windows-local artefacts (`_build` is not portable).
- Add a `ci` badge to `README.md` if it exists.

**Acceptance criteria**
- [ ] A PR with a deliberately broken test fails CI; the same PR green after the fix.
- [ ] CI runtime under ~10 minutes with caches.
- [ ] No secrets required (test DB is local to the runner).

**Files.** `.github/workflows/ci.yml`, `README.md`.

**Verification.** Push a branch and watch the run; re-run to confirm caching.

---

## P2-3 — Health endpoint and uptime probe

**Why.** Gigalixir's health check polls the port, but there is no cheap endpoint that also
proves the **DB** is reachable — the failure mode hit during deployment (missing SSL) booted
Healthy while every query hung.

**Scope**
- `GET /health` in `PscWeb.HealthController` (outside `:browser`): runs `Ecto.Adapters.SQL.query`
  `SELECT 1`, returns `{"status":"ok","release":"<sha from System.get_env>","db":"ok"}` with
  200, or 503 with the failing component.
- Do **not** expose secrets, hostnames or stack traces.
- Wire the deploy script (`scripts/deploy.ps1`) to probe `/health` instead of the login page.

**Acceptance criteria**
- [ ] 200 with a reachable DB; 503 when the DB is down (simulate by pointing the repo at a bad
      host in a test or by stubbing the query).
- [ ] No PII or secrets in the body; no session/cookie requirements.
- [ ] Deploy script prints the health payload.

**Files.** `lib/psc_web/controllers/health_controller.ex`, router, `test/psc_web/controllers/`,
`scripts/deploy.ps1`.

**Verification.** `mix.bat verify`; after deploy, `curl https://psc.gigalixirapp.com/health`.

---

## P2-4 — LiveView crash visibility

**Why.** A crashing LiveView currently only shows the client-error toast
(ADR-019). Server-side there is no aggregation, so a recurring crash in production is invisible.

**Scope**
- Attach a `:telemetry` handler for `[:phoenix, :live_view, :terminate]` (or the router's
  `phoenix_live_view` logger) that logs a structured line with `module`, `reason`, `user_id`
  when available, and increments a counter.
- On Gigalixir, structured logs are enough (no paid APM). Ensure the reason is logged without
  dumping the socket assigns (PII: emails).
- Optional: a dev-only `/dev/crashes` page is **not** required.

**Acceptance criteria**
- [ ] A forced crash (test endpoint or unit-invoked handler) emits exactly one structured log
      event containing the module and reason, with no assigns dump.
- [ ] No PII (emails) in the log line.

**Files.** `lib/psc/application.ex`, `lib/psc_web/telemetry.ex` (new or existing), tests.

**Verification.** `mix.bat verify`; `gigalixir logs -a psc` after a manual crash in dev-like
conditions.

---

# P3 — UX debt from the last UI pass

## P3-1 — Clamp tooltips on narrow screens

**Why.** Noted while testing mobile: the active-users tooltip (`#active-users-tooltip`) can
extend past the left edge when its trigger sits near the screen edge.

**Scope.** Constrain the SaladUI tooltip content to the viewport (max-width + collision
padding), or choose the side dynamically. Verify with the existing tooltip component at 390 px.

**Acceptance criteria**
- [ ] Tooltip stays fully visible at 320/390 px for triggers at the left, centre and right.
- [ ] Desktop behaviour unchanged.

**Files.** `lib/psc_web/components/ui/tooltip.ex` (or the editor usage), E2E or browser check.

---

## P3-2 — Keyboard editing in canvas cells

**Why.** Cells are click-to-edit only; keyboard users must Tab into a hidden textarea. This is
an accessibility gap in the product's main interaction.

**Scope.** Enter/Space on a focused cell opens its field (the `CellFocus` hook already centralises
click handling — add a `keydown` path). Escape closes the field and returns focus to the cell.
Tab moves between fields and then out of the cell. The cell card becomes focusable
(`tabindex="0"`, `role="group"` or a button-like semantics) with a visible focus ring distinct
from the editing ring.

**Acceptance criteria**
- [ ] Keyboard-only: Tab to a cell → Enter → type → Tab/Escape → next cell.
- [ ] Escape never loses the current text (blur saves, as today).
- [ ] Focus ring visible in light and dark; `aria-label` announces the cell title.
- [ ] LiveView/E2E test for the keyboard path.

**Files.** `lib/psc_web/live/unstr_canvas_live/editor.ex`, `assets/js/hooks/cell_focus.js`,
`assets/css/app.css`, tests.

---

## P3-3 — Overflow affordance and sticky grid headers

**Why.** Cells clip overflow behind a fade (ADR-020) — good — but at a glance users cannot tell
"empty" from "more content". On mobile, headers scroll away while the body scrolls
horizontally.

**Scope.** Add a subtle "more" marker only when a cell's body actually overflows (measure in the
hook, toggle a data attribute; no server round-trip). Make the header row sticky vertically and
the row-label column sticky horizontally inside the grid scroller, with the correct z-index and
background so borders do not double.

**Acceptance criteria**
- [ ] Only overflowing cells show the marker; it disappears when the cell is edited/expanded.
- [ ] Headers stay visible while scrolling in both axes; no visual seam at the sticky edge.
- [ ] No layout shift (CLS) when the marker appears.

**Files.** `assets/js/hooks/cell_focus.js` (or a new hook), `assets/css/app.css`, editor markup.

---

## P3-4 — Template library search

**Why.** The library lists every accessible template in one flat list. With a few dozen
templates, finding one becomes scroll-hunting.

**Scope.** A client-side filter input over name/description/author (LiveView `phx-change` with
debounce, `stream/3` reset semantics), an empty state, and a count. Server-side search is out of
scope until pagination is needed.

**Acceptance criteria**
- [ ] Typing filters the list within ~300 ms; clearing restores it.
- [ ] Empty state distinguishes "no templates" from "no matches".
- [ ] Works with the existing Owner/Shared badges and actions.

**Files.** `lib/psc_web/live/canvas_layout_live/index.ex`, tests.

---

## P3-5 — First-run guidance

**Why.** A brand-new account lands on an empty Canvases page with a create form; nothing explains
what a template or a canvas is, or that templates are the way to start.

**Scope.** An empty-state block on `/canvas` (and `/templates`): one sentence each for canvas
and template, a primary "Start from a template" action, and a secondary "Create blank canvas".
Show a compact hint only when the user has zero canvases and zero templates.

**Acceptance criteria**
- [ ] New account sees guidance; it disappears once a canvas or template exists.
- [ ] Copy matches the vocabulary in ADR-010 (canvas, template, canvas editor, template designer).
- [ ] No new nav items.

**Files.** `lib/psc_web/live/unstr_canvas_live/index.ex`,
`lib/psc_web/live/canvas_layout_live/index.ex`, tests.

---

# P4 — Research extensions (do not start without an explicit request)

## P4-1 — Decide the fate of Documents

**Why.** ADR-018 parked Documents: routes exist, nav does not. That is a deliberate holding
state, but it keeps untested-by-users code alive and the `/documents` URL reachable.

**Options.** (a) Redirect `/documents` → `/canvas` and keep the code for the future
cell-integration; (b) delete routes + LiveViews + context and re-add later; (c) integrate a
document field into canvas cells (large, overlaps P1-5).

**Recommendation.** (a) now, (c) as a separate spec once pivots ship.

**Known bug to fix if Documents is revived.** `Psc.Documents.CRDT.text_to_deltas/2`
(`lib/psc/documents/crdt.ex`) returns `[]` for a same-length replacement, so that edit is never
broadcast and other clients only converge through the 5 s consistency resync (open issue 2). The
minimal fix is to fall back to a `delete` + `insert` pair (or a `replace` delta) when
`byte_size(old) == byte_size(new) and old != new`, plus a unit test. Canvases are unaffected
because they send whole field values.

**Acceptance criteria (for (a)).** Anonymous/protected behaviour preserved, redirect in tests,
ADR-018 annotated with the outcome.

---

## P4-2 — Telemetry export foundation

**Why.** The proposal's research extensions need interaction data, but nothing exports it.

**Scope (first slice only).** Define an event taxonomy (template instantiated, cell edited,
collaborator joined/left, pivot created, canvas created/deleted), ensure each is already written
to `unstr_canvas_events` or a new append-only `audit_events` table with a bounded retention
policy (free tier!), and add an owner-only CSV export endpoint for their own canvas.
Respect privacy: no cell contents in telemetry events, only keys and timings.

**Acceptance criteria.** Taxonomy documented; events emitted; export returns a CSV with a header
row; retention documented and enforced; tests for the exporter and the retention sweep.

**Depends on.** P1-1 (pivot events exist).

---

## Suggested batching

1. **Batch 1 (half day):** P0-1, P0-3 — small, high-confidence correctness fixes, both covered
   by tests, no UI churn.
2. **Batch 2 (1–2 days):** P0-2 — delete dead surface, seed the PSC template.
3. **Batch 3 (4–6 days):** P1-1 → P1-2 → P1-3 → P1-4 — the missing Core MVP milestone. Ship the
   data model and API before any UI, and merge each as its own commit.
4. **Batch 4 (2–3 days):** P1-5 — structure editing; shares the CRDT code with P1-4
   (`replace_cells`), so land P1-4 first.
5. **Batch 5 (1–2 days):** P2-1, P2-3 — a live product needs a reset path and a DB-aware probe.
6. **Batch 6 (1 day):** P2-2, P2-4 — CI + crash visibility protect everything above.
7. **Batch 7 (1–2 days):** P3-1 → P3-5 — polish, one commit each.
8. **P4:** only with an explicit product decision.

---

## Open product decisions (defaults chosen so work can start)

| Question | Default to proceed with | Where to record |
|---|---|---|
| Who can create a pivot? | Any user with edit access; restore is owner-only | new ADR (P1-1/P1-4) |
| Pivot parent model | Free tree via `parent_id`; UI renders indentation, not a graph | P1-1 |
| Restore semantics | Overwrite current cells + auto-create an audit pivot | P1-4 |
| Fork ownership | Fork is authored by the acting user | P1-4 |
| Password reset delivery | Dev-visible link, generic message in prod until a mailer exists | P2-1 |
| Documents | Redirect `/documents` → `/canvas`, keep code | P4-1 |
| Structure editing permissions | Owner only (matches template designer) | P1-5 |

If a decision changes, update this table **and** the ADR in the same commit.

---

## Task template (copy for new work)

```markdown
## <ID> — <Title>

**Why.** <problem, with a link to the ADR/spec/open issue>

**Scope** — <bullets>
**Out of scope** — <bullets>

**Acceptance criteria**
- [ ] <observable behaviour>
- [ ] <test coverage>
- [ ] <docs updated>

**Files.** <paths>
**Verification.** `mix.bat verify`; <targeted tests>; <browser/E2E check>
**Pitfalls.** <known traps>
```
