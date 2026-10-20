# Canvas notes — implementation plan

> **Status:** planned, not started (2026-10-20).
> **Spec:** [canvas-notes.md](../spec/canvas-notes.md).
> **Decisions:** [ADR-027](../design-decisions.md#adr-027--a-note-is-a-child-of-its-canvas),
> [ADR-028](../design-decisions.md#adr-028--the-status-pill-is-a-shared-component).
> **Backlog:** [ui-task-list.md](ui-task-list.md) is the active list; this file is
> the breakdown for one feature.

The **Notes** tab of the canvas editor becomes a real surface: collaborative
Markdown notes that belong to the canvas and inherit its access rules.

Work through the tasks in order. Each one is a commit. Every task ends with the
verification matrix from [AGENTS.md](../../AGENTS.md) green, and updates this
document and the spec if the behaviour moved.

## The shape of the work

Four things have to happen, in this order, because each one depends on the one
before it:

1. **Lift the machinery out of Documents** into a shared store, with Documents
   still using it. Nothing changes for the user; the point is that there is now
   one implementation to point a second aggregate at.
2. **The notes aggregate**: schema, migration, context, permissions.
3. **The Notes view**: the tab, the list, the editor.
4. **Retire the standalone documents section** and adopt the shared components.

---

## Task 1 — Extract the shared text store

**Status: done.**

The algorithm in `Psc.Documents` is lifted into two modules; Documents keeps
working exactly as before.

- `Psc.Text` — the table-independent text operations: `apply_operation/2`,
  `text_to_deltas/2`, `hash/1`.
- `Psc.TextStore` — the log-and-snapshot algorithm, parameterised by the store
  and event schema modules: `next_sequence/3`, `load_content/3`,
  `save_content/4`, `apply_operation/6`, `pending_event_count/3`,
  `sweep_folded_events/2`.
- `Psc.Documents.CRDT` keeps `load_events/1` and `rebuild_text/1` and delegates
  the rest to `Psc.Text`.
- `Psc.Documents` becomes a façade over `Psc.TextStore`; its public API does not
  change.

**Acceptance**

- `Psc.Documents`' public API is unchanged; every existing document test passes
  untouched.
- The sequence-numbering, flooring, pruning and consistency rules exist in
  exactly one module — grep finds no second copy of `next_sequence` or of the
  `max(seq)` / `snapshot_seq` comparison.
- The shared store is exercised by the documents' own tests, so it is covered
  before a second aggregate depends on it.

**Verification** — `mix.bat verify`; `mix.bat test test/psc/documents_test.exs`;
the document LiveView and E2E tests.

**Watch out** — the `snapshot_seq` flooring is the subtle part: pruned events
must not be re-used, or a new event lands below the snapshot point and is never
replayed. It is easy to "simplify" this into a bug. See ADR-001/ADR-002.

---

## Task 2 — The notes aggregate

**Status: done.**

- Migration `create_notes_and_note_events`:
  - `notes`: `id` (`binary_id`), `canvas_id` (`binary_id`, FK →
    `unstr_canvases.id`, `on_delete: :delete_all`, not null), `title`, `content`
    (`:text`, default `""`), `snapshot_seq` (default `0`), `created_by_id`
    (`bigint`, FK → `users.id`, `on_delete: :nilify_all`, nullable), timestamps.
  - `note_events`: `id` (`binary_id`), `note_id` (`binary_id`, FK → `notes.id`,
    `on_delete: :delete_all`, not null), `user_id` (`bigint`, FK → `users.id`,
    `on_delete: :nilify_all`, nullable), `operation` (`:map`, not null), `seq`
    (`:integer`, not null), timestamps.
  - Unique index on `note_events (note_id, seq)`; index on `notes (canvas_id)`.
- Schemas: `Psc.Notes.Note`, `Psc.Notes.NoteEvent`, with the relationships in
  the spec. `Psc.Canvas.UnstrCanvas` gains `has_many :notes`.
- `Psc.Notes` context: `list_notes/1`, `get_note/1`, `create_note/2`,
  `update_note/1`, `delete_note/1`, plus the store-backed
  `apply_operation/…`, `save_content_to_db/…`, `build_content_from_events/…`,
  `pending_event_count/1`.
- PubSub topic `note:<id>`, mirroring `document:<id>`.
- `Psc.EventsSweeper` prunes `note_events` as well.

**Acceptance**

- A note has **no** `shared_with` column and **no** owner column. `created_by_id`
  is attribution only.
- Deleting a canvas removes its notes and their events, through the database's
  cascades — no application-level cleanup.
- Deleting a note removes its events.
- The `note_events` table is pruned exactly like `document_events`: a fold
  deletes the events it covers, and the sweeper removes the tail of a note
  abandoned before its first save.
- The context exposes no function that takes a user and decides access —
  access is the canvas's business.

**Verification** — `mix.bat verify`; new context tests in
`test/psc/notes_test.exs`; a migration round-trip test if the project has a
pattern for one.

---

## Task 3 — The status pill becomes a shared component

**Status: done.**

Extract `PscWeb.Components.StatusPill` from the canvas editor's private
`status_pill/1`, taking the save state and the statistics as parameters
(ADR-028). The canvas editor uses it; the note editor will.

**Acceptance**

- The pill, its tooltip and its colours live in one component.
- The colours come from the badge variant, so the phone rendering (the same
  badge, label dropped) cannot drift from the desktop one.
- The canvas editor's existing status-pill tests still pass unchanged.

**Verification** — `mix.bat verify`; the existing status-pill browser tests.

---

## Task 4 — A reusable Markdown editor

**Status: done.**

The document editor's hook addresses its parts by hardcoded ids (`#editor`,
`#editor-form`, `#document-markdown-preview`), so it can only exist once per
page — it cannot be reused for a note inside the canvas editor.

Build `PscWeb.Components.MarkdownEditor` with a hook that finds its parts
through `data-` attributes, following the pattern the canvas cell fields already
use (`MarkdownField`).

**Acceptance**

- The component can be mounted more than once on a page, each instance wired to
  its own textarea and preview.
- It keeps the document editor's behaviour: a click on the rendered Markdown
  opens the textarea, blurring it re-renders the preview, and a remote update
  does not clobber the text while the user is typing in it.
- The document editor is migrated onto it, so the hardcoded ids are gone.

**Verification** — `mix.bat verify`; the document LiveView and E2E tests; a new
browser test that mounts two editors on one page and edits both.

---

## Task 5 — The Notes view

**Status: done.**

The canvas editor's **Notes** tab becomes the notes view.

- The list: the canvas's notes, newest first, showing the title, a one-line
  snippet and the relative time it was last touched. A **New note** action.
  Empty state that says so and offers the create action.
- The editor: title, status pill, Markdown editor.
- Desktop: a 260 px list beside the editor. Phones and tablets: one pane at a
  time, with a back action from the editor to the list.
- The selected note is in the URL: `/canvas/:id?tab=notes&note=<id>`. Selecting
  a note replaces the history entry, like the tab change does.
- A note is opened, edited, renamed and deleted. Deleting is the canvas
  author's alone.

**Acceptance**

- A user who can open the canvas can create, read, edit and rename its notes.
- A user who cannot open the canvas cannot reach the notes: the canvas editor
  redirects before the view is reached, and there is no note route that would
  need its own check.
- A shared user can edit a note's content but cannot delete it.
- The note's content survives a reload, and a second user's edit appears in the
  first user's editor.
- Back from a note returns to the canvas list, not out of the canvas.
- The page still does not scroll vertically on a phone (ADR-024's rule).

**Verification** — `mix.bat verify`; LiveView tests in
`test/psc_web/live/canvas_notes_live_test.exs`; browser tests in
`test/e2e/tests/notes.spec.ts`.

---

## Task 6 — Retire the standalone documents section

**Status: done.**

ADR-018 parked the standalone `/documents` section, and notes are the integration
it anticipated.

- The `documents` and `document_events` tables are dropped. The one document row
  in the deployed database was a deployment smoke-test artefact, and nothing
  linked to the section.
- The `/documents` routes, `PscWeb.DocumentLive` and the `Psc.Documents` context
  are removed — leaving the shared store, which the notes use.
- The document editor became the reusable `PscWeb.Components.MarkdownEditor` in
  task 4, and its status pill became the shared component in task 3, so nothing
  of value was thrown away.

**Acceptance**

- No route, LiveView or navigation entry points at documents.
- The database has no `documents` or `document_events` table.
- The notes feature is unaffected.

**Verification** — `mix.bat verify`; a browser sweep of the old URLs (they
should 404 or redirect, not crash).

---

## Risks and open questions

| Risk | Mitigation |
|---|---|
| The extracted store changes the documents' behaviour. | Task 1 changes no public API and the document tests are the regression net. Land it on its own. |
| The 10 000-row ceiling on `note_events`. | Same fold-and-prune discipline as the other two event tables, plus a sweeper pass. Verify with a synthetic typing burst in a test. |
| Two editors on one page (the Notes view and a canvas cell). | Task 4's data-attribute wiring is the precondition; the canvas cell fields already use that pattern. |
| Note-level presence is missing in the first version. | Deliberate: the canvas-level cluster is shown in the Notes view. A note-scoped indicator needs a new presence field and is a follow-up. |
| The free tier's connection limit (2 connections) makes a second concurrent aggregate expensive. | Notes share the canvas LiveView's connection — no new socket, no new database connection. |

## Definition of done

- [ ] Every task above is committed, with the spec and this document updated.
- [ ] `mix.bat precommit` green (format, no warnings, all tests).
- [ ] The full Playwright suite green, including the new notes tests.
- [ ] The notes feature verified in the browser at phone and desktop sizes.
- [ ] ADR-026 and ADR-027 match what was built.
- [ ] Deployed only when the user asks.
