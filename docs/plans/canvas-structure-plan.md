# Canvas structure editing — implementation plan

> **Status:** all four tasks done (2026-10-21).
> **Spec:** [canvas-structure.md](../spec/canvas-structure.md).
> **Decision to record:** ADR-033 — a canvas's structure is editable in place (written in
> Task 1, when the behaviour lands).
> **Companion docs:** [AGENTS.md](../../AGENTS.md) (how to work),
> [DEVELOPMENT.md](../../DEVELOPMENT.md) (workflow + environment).

Structure editing brings the designer's grid controls into the canvas editor behind an
owner-only **Edit structure** toggle, makes the picker's no-template option a truly blank
canvas, and turns the built-in PSC into an explicit choice.

Work through the tasks in order. Each one is a commit. Every task ends with the
verification matrix from [AGENTS.md](../../AGENTS.md) green, and updates this document,
the spec and the ADR if the behaviour moved.

## The shape of the work

Four things have to happen, in this order, because each one depends on the one before it:

1. **The operations** — twelve apply clauses in the CRDT, testable purely. Everything the
   UI does goes through these, so the transition rules exist in exactly one place.
2. **Blank and PSC in the picker** — the schema default becomes empty, the PSC becomes an
   explicit constant and its own card. This is what makes "actual blank canvas" exist.
3. **Edit mode in the editor** — the toggle, the toolbar, the inline controls, the empty
   state, and the stale-fullscreen edge.
4. **E2E and docs** — the regression spec, the editor spec, ADR-033.

---

## Task 1 — The structure operations

**Status: done.**

- `Psc.Canvas.UnstrCanvasCRDT.apply_operation/2` gains the twelve clauses from the spec's
  table. Each is a pure function of `(operation, cells) → cells`:
  - `add_row`/`add_column` append the def, extend the matrix, and create the new cells
    with `row`/`column` back-references and `label` = the key (what
    `instantiate_template/3` already does).
  - `remove_row`/`remove_column` drop the def, its matrix slice, and the matching cells.
  - The rest are point updates; `remove_cell_field` deletes the value key and its
    `titles` entry.
- `Psc.Canvas` gains the built-in PSC structure as a public constant (`psc_cells/0`),
  moved verbatim from the schema default, and `create_unstr_canvas/2` gains the two
  explicit paths: blank (empty structure) and PSC.
- `UnstrCanvas.cells` default → the empty structure (`%{"rows" => [], "columns" => [],
  "layout" => [], "cells" => %{}}`).
- ADR-033 added to `docs/design-decisions.md` (index row + section).

**Acceptance**

- Every op applies correctly from a representative state (an instantiated template's
  cells, and the PSC default's shape), and applying a sequence of ops then replaying them
  through `get_unstr_canvas_content/1` after a save reaches the same state — the ops are
  replay-safe.
- `remove_row`/`remove_column` cascade: the def, the matrix slice and the cells all go;
  surviving cells keep their content untouched.
- `add_cell_field` rejects the reserved keys (`row`, `column`, `label`, `titles`) and a
  duplicate field; `set_row_accent` rejects an unknown token.
- A blank canvas (empty structure) passes `validate_cells_structure/1`.
- Creating with no template yields the empty structure; creating with the PSC choice
  yields the 12-cell grid; `instantiate_template/3` is unchanged.

**Verification** — `mix.bat verify`; `mix.bat test test/psc/canvas_test.exs`.

**Watch out** — the ops must never assume the state they arrive at: replay applies them
after the snapshot, so `add_row` has to work on whatever rows exist, and `remove_row` on a
row that may already be gone (make removal idempotent). And the new-id rule is *next free
index*, scanning existing ids — `length + 1` collides after a removal, which is the
designer's latent bug; do not copy it.

---

## Task 2 — Blank and PSC in the picker

**Status: done.**

- `PscWeb.UnstrCanvasLive.Index` renders three kinds of card: **Blank canvas** (empty
  preview, default-selected, id `""`), **PSC canvas** (the built-in grid, id `"psc"`),
  then the user's templates as today.
- `create_canvas/4` routes: `""` → blank, `"psc"` → the PSC constant, anything else →
  `template_for/2` as today (the access check unchanged).
- The e2e helpers that create a working canvas click the **PSC canvas** card explicitly —
  a blank canvas has no cells to edit, and the helpers' job is a canvas with structure.

**Acceptance**

- The picker shows both cards with the right previews; blank is selected on mount.
- Creating blank yields a canvas with no rows/columns; creating from the PSC card yields
  the 12-cell grid; a template card behaves exactly as before.
- The forged-id guard still refuses a template the user cannot access, and `"psc"` is not
  mistaken for a template id.

**Verification** — `mix.bat verify`;
`mix.bat test test/psc_web/live/unstr_canvas_live_test.exs`.

**Watch out** — `"psc"` must never reach `template_for/2` (there is no template with that
id, but the guard should be explicit, not accidental). And the schema default change is
invisible to `instantiate_template/3`, which builds cells explicitly — assert that in the
tests so nobody "simplifies" it later.

---

## Task 3 — Edit mode in the editor

**Status: done.**

- An owner-only toolbar above the grid: the **Edit structure** toggle, and — while on —
  **Add Column** / **Add Row**. Shared users see nothing.
- While the toggle is on, the grid renders the designer's controls: row/column headers as
  label inputs with an accent swatch and a remove ×; per-cell label input, per-field
  section-title input and remove ×, and the add-field form. Every control fires its
  operation through `apply_unstr_canvas_operation/4` and applies it locally, exactly as
  `update_cell` does.
- Removing a row/column whose cells hold any content opens the house `UIDialog` confirm;
  empty ones go straight away.
- The empty state: no rows or no columns renders "Add row" / "Add column" for the owner
  and an explanatory line for a shared user.
- A fullscreen cell whose key disappears (its row was removed) falls back to the grid.
- The editor spec's structure section written; `docs/data_model.md` notes the cells
  default.

**Acceptance**

- The toggle is visible to the owner and invisible to a shared user; a shared user forging
  a structure event gets the forged-delete treatment (no-op, no error crash).
- Every control's operation lands: add, remove, rename, accent, cell label, fields,
  titles — each verified by the cells map after the event.
- The confirm appears only when the row/column holds content, and "keep editing" cancels.
- Content editing keeps working while Edit mode is on.
- A structure change survives the idle save and a reload (the folded snapshot carries it).

**Verification** — `mix.bat verify`;
`mix.bat test test/psc_web/live/unstr_canvas_live_test.exs`; a browser pass on the toggle,
the controls and the empty state.

**Watch out** — the originator does not receive its own broadcast (the `client_id` check
skips it), so every handler must apply the op to its local `cells` itself, exactly as
`update_cell` does — miss that and the owner's grid lags one action behind. And the
remove-confirm's "which cells have content" check reads the *current* cells at click time,
not a stale assign.

---

## Task 4 — E2E regression

**Status: done.**

- `test/e2e/tests/structure.spec.ts`:
  - create a blank canvas, build it in place (add rows/columns, rename, add a field),
    reload, and assert the structure survived;
  - open a PSC canvas, remove a row with content (confirm), remove an empty column
    (no confirm), and assert the grid;
  - a shared user sees no toggle and cannot forge an op (the API-level guard is covered in
    the LiveView tests; here, the absence of controls).
- The four `createCanvasAndOpen` helpers click the **PSC canvas** card.

**Acceptance**

- The spec passes alongside the existing 46, and the whole suite stays green.

**Verification** — `npx.cmd playwright test` from `test/e2e`; `mix.bat precommit`.

**Watch out** — the helpers now interact with the picker before creating, so they must
wait for `.phx-connected` first (the house rule that saved the tab strip); and the blank
canvas's editor has no table, so anything that waits for grid selectors must wait for the
empty state instead.

**Found while building it** — the edit-mode inputs need **stable ids** (the designer's
inputs all have them). Without one, a patch re-renders the input as a new node, and a
pending `phx-debounce` dies with the old node: the row-rename's patch (which resizes the
label column) silently ate the column rename typed a moment later. The change event's
debounce callback checks `document.body.contains(el)` and drops the change when the
element was detached. Every edit-mode input now carries the designer's id scheme.

---

## Definition of done (applies to every task)

- [ ] Behaviour matches the task's acceptance criteria, verified in a running app where visual.
- [ ] `mix.bat verify` green (format, zero warnings, all tests).
- [ ] New behaviour covered by tests at the right level (context → `test/psc/…`,
      LiveView → `test/psc_web/live/…`, flow → `test/e2e/tests/…`).
- [ ] No new `100vh`/hardcoded light-dark colours; use theme tokens (ADR-015) and the
      existing flex layout (ADR-020/021).
- [ ] Docs updated when behaviour or data shape changed (`canvas-editor.md`,
      `data_model.md`, the ADR).
- [ ] Deployed? Only when the user asks — then `scripts\deploy.ps1`.
