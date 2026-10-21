# Canvas structure editing

## Overview

Today a canvas is frozen at the shape it was instantiated with: rows, columns, cell
labels, fields and accents are authored in the template designer, copied once by
`instantiate_template/3`, and never editable again. To change a canvas's structure, the
user throws it away and starts over.

**Structure editing** brings the designer's grid controls into the canvas editor behind an
**Edit structure** toggle (owner-only). Rows and columns can be added, removed, renamed and
accented; cells can be renamed, gain and lose fields, and re-title their sections. It also
makes the **truly blank canvas** viable: the picker's no-template option becomes an empty
grid that the owner builds in place, with the built-in PSC one click away as its own
explicit choice.

> **Terminology.** A **canvas** is one configurable workspace (`unstr_canvases` /
> `Psc.Canvas.UnstrCanvas`, edited at `/canvas/:id` by `PscWeb.UnstrCanvasLive`). Its
> **structure** is the `rows`, `columns`, `layout` and per-cell metadata inside its `cells`
> map — everything except the field values the collaborators type.

### Design principle

A canvas is a **living document**; a template is a starting point (ADR-009). Structure
editing follows the canvas's own philosophy — every change is an operation, applied
immediately, autosaved — not the designer's explicit-save model, because a canvas has no
"save" to defer to.

## Decisions

1. **Granular operations, not one big restructure.** Each structure change is its own
   operation in the existing event log (`add_row`, `remove_column`, `update_cell_label`,
   …), applied by `UnstrCanvasCRDT.apply_operation/2` like `update_cell` today.
   *Why:* the ops compose (a rename and an add from two tabs both land), each is small and
   self-contained, and replay stays deterministic. The alternative — one `restructure` op
   carrying the whole new shape — was rejected: it is last-write-wins on the entire
   structure, its payload is large, and it would drag the designer's draft-and-apply dance
   into a surface that autosaves.
2. **Owner-only.** Only the canvas's author sees the toggle and can create structure
   operations; shared users keep content-only editing, exactly as the canvas-editor spec
   already promises. The guard lives where the operation is *created* (the LiveView
   handler, like `delete_note`), not in the CRDT apply — collaborators must still
   *receive* and apply structure ops to see the new grid.
3. **The toggle reveals controls; it never locks content.** "Edit structure" shows the
   designer-style controls on the grid; filling in cells keeps working throughout, because
   the two never touch the same keys. (The word "mode" would imply a lock-out that does
   not exist.)
4. **The picker gains a truly blank card, and the built-in PSC becomes explicit.** Three
   kinds of card: **Blank canvas** (empty grid, default-selected), **PSC canvas** (the
   built-in 12-cell grid, one click away), then the user's templates. The PSC structure
   moves from the schema's `cells` default to an explicit constant the create path passes;
   the schema default becomes the empty structure. *Why blank first:* "start a canvas"
   should start empty for a tool that is about configurable structures, and the PSC is one
   click — but this is a deliberate shift for existing users, recorded in ADR-033.
5. **Removing a row or column that holds content confirms first.** The operation is
   destructive and irreversible (the event log keeps the old values only until pruning
   folds them). An empty row or column goes immediately. The confirm is the house
   `UIDialog` pattern.
6. **Ids are generated once, server-side, and travel inside the operation.** A new
   row/column gets the next free `rN`/`cN` index (scanning existing ids, not
   `length + 1` — which collides after a removal, a latent bug the designer still has).
   With the id in the payload, every client applying the ops in sequence order reaches the
   same state.
7. **No migration, no new table.** `cells` is a map; structure operations are events like
   any other, and the existing fold-and-prune path bounds the log (ADR-006). Existing
   canvases are untouched.

## The operations

All of them are plain maps applied by `UnstrCanvasCRDT.apply_operation/2`, inserted through
the existing `apply_unstr_canvas_operation/4` (event + broadcast), and folded into the
snapshot by the existing save path. Each is deterministic: same op, same transition, from
any state.

| Operation | Payload | Apply |
|---|---|---|
| `add_row` | `id`, `label` | Append the row def; append a layout row of `"#{id}_#{col}"` keys; create each cell with `row`/`column` back-references and `label` = its key |
| `add_column` | `id`, `label` | Mirror of `add_row` across the matrix |
| `remove_row` | `id` | Drop the row def, its layout row, and every cell whose `row` is the id |
| `remove_column` | `id` | Mirror across |
| `update_row_label` / `update_column_label` | `id`, `label` | Set the def's label |
| `set_row_accent` / `set_column_accent` | `id`, `accent` (nil clears) | Set the def's accent token |
| `update_cell_label` | `cell_key`, `label` | Set the cell's `label` |
| `add_cell_field` | `cell_key`, `field` | Add `cells[key][field] = ""` and `titles[field] = ""` (untitled) |
| `remove_cell_field` | `cell_key`, `field` | Delete the value key and its `titles` entry |
| `update_cell_field_title` | `cell_key`, `field`, `title` | Set `titles[field]` |

Notes on the shape:

- **Field order is not a maintained property.** Canvas cells live in Postgres `jsonb`,
  which does not preserve key order; the editor already renders a cell's fields in map
  order. Adding a field adds a key — where it lands in the render is jsonb's business, the
  same as today.
- **The reserved keys** (`row`, `column`, `label`, `titles`, and the canvas-level
  `$name`/`$description`) are never touchable as fields; `add_cell_field` rejects them.
- **A removed cell's content is gone.** The confirm in decision 5 is the only guard.

## UI

### The toggle and the toolbar

A slim **owner-only** toolbar sits above the grid: **Edit structure** (a toggle), and —
while it is on — **Add Column** and **Add Row**. Shared users see no toolbar at all. The
toggle's state is a LiveView assign, not URL state (ADR-026): it is a working mode of the
owner's session, like the designer's accent picker, not a view someone would link to.

### The grid, in Edit mode

The designer's controls, applied to the canvas's own map:

- Row and column headers become **inputs** (label), with an **accent swatch** opening the
  inline palette, and a **remove ×** (confirming when the row/column holds content).
- Each cell gains a **label input** and, per field, a **section-title input** and a
  **remove ×**; an **add-field** form sits at the bottom of the cell — the designer's cell
  editing, verbatim in interaction.
- Content inputs keep working the whole time.

### The empty canvas

With no rows or no columns, the grid area renders an empty state instead of a table: for
the owner, **Add row** / **Add column** buttons (the same operations, so a blank canvas is
built in place); for a shared user, "The owner hasn't built this canvas yet". A canvas
created from the **Blank canvas** card starts here.

### Collaborators and stale references

Structure operations arrive through the existing PubSub topic and are applied by every
other connected client, which re-renders the grid from the new `cells`. A cell that is
fullscreen (its key in the URL, ADR-026) and then removed falls back to the grid rather
than rendering a ghost.

## Validation rules

- The owner guard is enforced server-side at every structure event; a shared user forging
  one gets the same treatment as a forged note delete.
- `add_cell_field` rejects the reserved keys and a field the cell already has.
- Accent tokens must be known (`Psc.Canvas.Accent.valid?/1`) or nil.
- New row/column ids never collide with existing ones (next free index).
- The changeset's `validate_cells_structure/1` already guarantees every layout key has a
  cell entry; the ops maintain that invariant, and the empty structure passes it.

## File plan

| File | Action | Purpose |
|------|--------|---------|
| `lib/psc/canvas/unstr_canvas_crdt.ex` | modify | The twelve apply clauses |
| `lib/psc/canvas.ex` | modify | The PSC constant; blank/PSC create paths |
| `lib/psc/canvas/unstr_canvas.ex` | modify | `cells` default → empty structure |
| `lib/psc_web/live/unstr_canvas_live/index.ex` | modify | The picker's Blank and PSC cards |
| `lib/psc_web/live/unstr_canvas_live/editor.ex` | modify | The toggle, the toolbar, the controls, the empty state |
| `test/psc/canvas_test.exs` | modify | Op apply/replay tests |
| `test/psc_web/live/unstr_canvas_live_test.exs` | modify | Picker, permissions, empty state |
| `test/e2e/tests/structure.spec.ts` | create | Build a blank canvas in place; restructure a PSC canvas |
| `docs/spec/canvas-editor.md` | modify | The create flow and the structure section |
| `docs/data_model.md` | modify | The cells default note |
| `docs/design-decisions.md` | modify | ADR-033 |

## Acceptance criteria

- [ ] The owner can toggle Edit structure and add, remove, rename and accent rows and columns; a shared user sees none of it and forges nothing
- [ ] Every structure change is visible live to other connected clients
- [ ] Removing a row or column with content asks first; removing an empty one does not
- [ ] Cells can be renamed, gain fields, lose fields and re-title sections in place
- [ ] The picker offers Blank canvas (empty) and PSC canvas (the built-in 12-cell grid); blank is the default
- [ ] A blank canvas is built in place from the empty state, and survives a reload (the folded snapshot carries the structure)
- [ ] A cell that is fullscreen when its row is removed falls back to the grid
- [ ] The event log stays bounded: structure ops fold and prune like cell ops
