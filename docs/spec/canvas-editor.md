# Canvas editor

## Overview

The canvas editor renders and edits a **canvas**. It is structure-agnostic: it decodes the canvas's `cells` map and renders whatever grid dimensions, cells, and cell fields are defined. All edits flow through CRDT operations for real-time multi-user collaboration.

> **Terminology.** A **canvas** is one configurable workspace; a **template** is the reusable structure a canvas is created from. In code these are the `unstr_canvases` and `canvas_layouts` tables (`Psc.Canvas.UnstrCanvas`, `Psc.Canvas.Layout`), the surfaces are `PscWeb.UnstrCanvasLive` (this canvas editor) and `PscWeb.CanvasLayoutLive` (the template designer), and the routes are `/canvas` and `/templates`.

### Design principle

The editor does **not** hardcode the 12-cell PSC grid. It reads `cells.rows`, `cells.columns`, `cells.layout`, and per-cell field data from the `cells` map and renders dynamically. This means any template (see `template-designer.md`) can be instantiated and edited without editor changes.

## Design System

See `template-designer.md` → **Design System** for the full design direction. The editor follows the same "calm analytical workspace" vibe. Key notes specific to the editor:

### Editor-Specific UI

- **The canvas grid is the hero.** It occupies the full viewport width minus the sidebar. No max-width constraint on the grid itself.
- **Cell cards** have a subtle border that brightens on focus. The cell label sits in a compact header bar. Fields are stacked vertically with 8px gaps.
- **Presence indicators** are a 3px colored dot in the top-right corner of each cell card, with a tooltip showing the username. Multiple users in the same cell show multiple dots.
- **Structure-editing controls** (add/remove row/column, add/remove field) are hidden behind a "Structure" toggle in the editor header. When active, they appear as small outline buttons with accent color on hover.
- **The sidebar** (presence + sharing) is fixed at 280px on the right, collapsible via a button in the header. On mobile, it becomes a slide-over panel.
- **The editor header** contains: canvas name (editable inline), description (editable inline, below name), Structure toggle, Share button, and presence avatars.
- **The description sits close to the grid.** The gap between the description and the table is
  at most 16 px. The share dialog is rendered out of the flow, so its wrapper cannot act as a
  flex item and open a gap of its own between the header and the grid.
- **No manual save button.** Auto-save is indicated by a subtle "Saved" text that appears briefly after each save cycle.
- **The status pill reports more than the state.** The pill (the badge beside the title on
  larger screens, an icon in the app header on phones) opens a tooltip with the details: when
  the last write landed ("just now", "2 min ago"), how many writes this session made, how
  many failed, and how long the last write took. Hovering opens it on a desktop; a tap opens
  it on a phone, where there is no hover. A failed write keeps the state "unsaved", because
  the changes are still only in the event log.

  Both renderings are the *same* badge — the phone only drops the label — so the state
  colours cannot drift apart: **Saved** is the primary colour, **Saving** the secondary one,
  and **Unsaved** the warning colour. The phone pill is a 32 px circle like the presence
  pill and the Share button next to it, so the three read as one cluster.
- **View tabs** switch between Analysis, Notes, Editor, and Agent. The selected view is encoded as
  `?tab=...` for deep links, but selecting tabs replaces the current URL entry so browser Back
  leaves the canvas editor instead of stepping through view selections. The switch itself is
  client-side: every view is rendered and the inactive ones are hidden, so the panel changes
  the moment the tab is clicked (0.4 ms) and the server only confirms it and the URL. The
  selected tab is styled from `aria-selected`, so the client can move the highlight too.
- **The fullscreen cell is a URL state.** On phones the expanded cell is encoded as the
  `#cell-<key>` fragment, so Back returns to the canvas grid instead of leaving the canvas,
  and the view can be linked and reloaded. The fragment is used on purpose: LiveView compares
  only pathname and search, so a fragment change never triggers a server round trip. Swiping
  to a neighbouring cell replaces the fragment instead of adding another history entry.
- **Mobile feedback** appears above the fixed bottom app bar. The shared dialog panel is
  kept inside the visible viewport by moving it with `top` when the virtual keyboard is
  open; it never scrolls the page behind it and never uses a transform, which would
  double up with the `translate` property Tailwind uses to centre the panel.
- **The grid meets the bottom app bar.** Below `lg` the app bar's height (3.75 rem plus the
  phone's safe-area inset) is reserved below the grid, so the table ends just above the bar:
  a 6 px sliver to breathe, not a dead band, and the last row is never hidden behind the bar.
- **Rendered Markdown** is intentionally denser than the editing controls: line height and block
  margins are reduced only inside `.md-render` cells.

### Screenshot Review Loop

Specs and implementations are validated with screenshots. The app is screenshotted in the browser, and the screenshot is analyzed against this design system. Screenshots are the authoritative visual reference.

## Data Model

No schema changes. The editor works entirely within the existing `unstr_canvases.cells` map structure:

```elixir
%{
  "rows" => [%{"id" => "r1", "label" => "Rationale"}, ...],
  "columns" => [%{"id" => "c1", "label" => "Perceive"}, ...],
  "layout" => [["r1_c1", "r1_c2", ...], ...],
  "r1_c1" => %{
    "row" => "r1",
    "column" => "c1",
    "content" => "user-edited text",
    "custom_field" => "more text"
  },
  ...
}
```

The editor treats everything except `rows`, `columns`, and `layout` as a cell key. Each cell's fields are whatever keys are present **beyond the metadata keys** — `row` and `column`, plus `label` (rendered as the cell header). Metadata is never rendered as an editable content field. Older canvases may still contain a `semantics` key from earlier templates; it is filtered out and never shown.

## File Plan

| File | Action | Purpose |
|------|--------|---------|
| `lib/psc/canvas/unstr_canvas_crdt.ex` | **modify** | Add grid-structure operations (add/remove row/column, add/remove cell field) |
| `lib/psc/canvas.ex` | **modify** | Add context helpers for grid-structure mutations |
| `lib/psc_web/live/unstr_canvas_live/editor.ex` | **modify** | Dynamic grid rendering, cell field editing, cursor presence, structure editing UI |
| `lib/psc_web/live/unstr_canvas_live/index.ex` | **modify** | Template selection on create (dropdown of available templates) |
| `test/psc/canvas/unstr_canvas_crdt_test.exs` | **create** | Unit tests for all CRDT operations including new grid operations |
| `test/psc_web/live/unstr_canvas_live_test.exs` | **create** | LiveView tests for editing, presence, cursors, structure editing |

## CRDT Operations

The existing operations (`update_cell`, `update_name`, `update_description`) are kept. New operations are added for grid-structure editing:

### Existing operations (unchanged)

```elixir
%{"type" => "update_cell", "cell_key" => key, "field" => field, "value" => value}
%{"type" => "update_name", "value" => value}
%{"type" => "update_description", "value" => value}
```

### Accents (read-only in the editor)

Accents are authored exclusively in the template designer and stored in the template's
`layout_map` JSON (`rows[].accent` / `columns[].accent`, tokens from
`Psc.Canvas.Accent`). `Canvas.instantiate_template/3` copies the row/column metadata
verbatim, so the canvas editor renders the bars from its own `cells` JSON:

- `accent_bar` on the top edge of each column header (`accent-bar-column-<id>`).
- `accent_bar` on the left edge of each row header (`accent-bar-row-<id>`).

There is **no picker and no accent operation** in the editor — no
`update_column_accent` / `update_row_accent` CRDT ops exist. Recolouring a template does
not retro-update canvases already created from it (same rule as labels). See ADR-011.

### New operations

```elixir
# Add a row at the end of the grid
%{"type" => "add_row", "row_id" => "r9", "row_label" => "New Row"}

# Remove a row (and all its cells from the layout)
%{"type" => "remove_row", "row_id" => "r9"}

# Add a column at the end of the grid
%{"type" => "add_column", "column_id" => "c9", "column_label" => "New Column"}

# Remove a column (and all its cells from the layout)
%{"type" => "remove_column", "column_id" => "c9"}

# Add a new field to an existing cell
%{"type" => "add_cell_field", "cell_key" => "r1_c1", "field" => "new_field"}

# Remove a field from a cell
%{"type" => "remove_cell_field", "cell_key" => "r1_c1", "field" => "new_field"}
```

### Operation semantics

- `add_row` appends to `cells.rows` and appends a new empty row to `cells.layout`. New cell keys are NOT pre-created — cells are lazily created on first edit.
- `remove_row` removes from `cells.rows`, removes the row from `cells.layout`, and deletes all cell keys matching `"#{row_id}_*"`.
- `add_column` / `remove_column` follow the same pattern for columns.
- `add_cell_field` adds the field key to the cell's data map with value `""`.
- `remove_cell_field` removes the field key from the cell's data map.

All operations follow the same event-sourcing pattern: insert `UnstrCanvasEvent` with monotonically increasing `seq`, broadcast via PubSub, and update the in-memory `cells` map.

## Context API

New functions in `Psc.Canvas`:

```elixir
# Grid structure operations (all return {:ok, cells} | {:error, reason})
add_row(canvas_id, user_id, row_id, row_label) :: {:ok, map}
remove_row(canvas_id, user_id, row_id) :: {:ok, map}
add_column(canvas_id, user_id, column_id, column_label) :: {:ok, map}
remove_column(canvas_id, user_id, column_id) :: {:ok, map}
add_cell_field(canvas_id, user_id, cell_key, field) :: {:ok, map}
remove_cell_field(canvas_id, user_id, cell_key, field) :: {:ok, map}
```

These follow the same pattern as `apply_unstr_canvas_operation/4`: insert event, broadcast, return updated cells.

## UI Behavior

### Canvas library

The canvas library at `/canvas` uses the shared app header as its single page-level
heading (`Canvases`); the main content begins with the canvas creation form and does
not repeat that heading.

Each canvas card shows the name and description inside the card. Long text never
paints outside it: names break on word boundaries, and descriptions break long
tokens and are clamped to two lines so the grid rows stay even. The same rule
applies to the template cards in the template library.

### Grid rendering

The editor renders a CSS grid based on `cells.rows` and `cells.columns`:

1. Read `cells.rows` and `cells.columns` to determine grid dimensions.
2. Read `cells.layout` (2D array of cell keys) to determine which cell goes in which position.
3. For each cell key in the layout, look up the cell data in the `cells` map.
4. Render the cell's fields as text inputs / textareas, in the order they appear in the cell map.

### Cell editing

- Each cell renders as a card with a header (cell label from template or `"Cell {key}"`) and one input per field.
- Editing a field sends a `update_cell` CRDT operation with `{cell_key, field, value}`.
- The cell shows a subtle highlight when another user is editing it (from cursor presence).

### Cursor presence (cell-level)

Presence meta is extended from `%{username: "..."}` to `%{username: "...", cell_key: "r1_c1" | nil}`:

- When a user focuses a cell input, push presence with `cell_key` set.
- When a user blurs the input or navigates away, push presence with `cell_key: nil`.
- The editor renders a colored indicator on each cell showing which users are currently editing it.
- The active-users sidebar shows each user's name and which cell they're editing (or "—" if not in a cell).

### Grid structure editing

A "Structure" toggle in the editor header reveals grid-editing controls:

- **Add row** button — prompts for row ID and label, sends `add_row` operation.
- **Add column** button — prompts for column ID and label, sends `add_column` operation.
- Each row/column header has a small × button to remove it (sends `remove_row` / `remove_column`).
- Each cell has an "Add field" button in its header (sends `add_cell_field`).
- Each field label in a cell has a small × to remove it (sends `remove_cell_field`).

Structure editing is **owner-only** — shared users can edit cell content but not the grid structure. (This is the binary role boundary.)

### Sharing UI

- A **Share** combo button in the header (heroicons `hero-share` + label), visible to the owner.
- It opens the shared `PscWeb.Components.ShareDialog` modal: email invite form, the list of people with access (each with a remove ×), and a Done action. The old inline sidebar sharing block is gone; the sidebar keeps presence badges only.
- `can_access_canvas?` gates the entire editor route.

### Auto-save

Unchanged from existing implementation:
- Debounced: on idle (no CRDT operation for N seconds), call `save_unstr_canvas_content_to_db`.
- Periodic: on a timer interval, save if dirty.
- Saves the full `cells` map as the snapshot and updates `snapshot_seq`.

### Create flow (index page)

The **Start a canvas** card at the top of the index page holds the creation form:

- **Template picker** — a row of cards, a **Blank canvas** card first, then one per
  template the user can access (own + shared). Each card shows a schematic preview of the
  template's grid (`PscWeb.Components.TemplatePreview.mini_preview`), its name and its
  dimensions; the selected card carries the primary border and tint. The choice is made
  with the eyes: a layout is the one thing a dropdown cannot show. The selected id rides
  to the submit in a hidden input, and only ids the picker offered are accepted.
- **Name** text input, **Description** textarea.
- **Create** button — calls `instantiate_template` (if a template is selected) or
  `create_unstr_canvas` (if blank), then **navigates to the new canvas's editor**. Creating
  is the start of work, not a list update.

## Acceptance Criteria

- [ ] Editor renders a 3×4 canvas with the correct grid layout from the template
- [ ] Editing a cell field sends a CRDT operation and broadcasts to other connected users
- [ ] Two users editing the same canvas see each other's changes in real time
- [ ] Focusing a cell shows the user's name/cursor on that cell for other users
- [ ] Active-users sidebar shows who is online and which cell they're editing
- [ ] Owner can add a row — it appears on all connected clients
- [ ] Owner can remove a column — it disappears on all connected clients
- [ ] Owner can add a field to a cell — it appears as a new input
- [ ] Owner can remove a field from a cell — the input disappears
- [ ] Shared user can edit cell content but does not see structure-editing controls
- [ ] Auto-save persists the `cells` map to the database on idle
- [ ] Creating a canvas from a template copies the template's structure into the new canvas
- [ ] Creating a blank canvas produces an empty 1×1 grid with one cell

## Out of Scope

- Inline comments or discussion threads on cells
- Drag-and-drop cell reordering or resizing
- Export or import of canvas content
- User-facing version history or undo UI (CRDT log is internal only)
- Telemetry or analytics instrumentation
- Conflict resolution UI (CRDTs converge automatically; no manual merge)

## Verification Methods

- **Unit tests** (`unstr_canvas_crdt_test.exs`): all CRDT operations produce correct `cells` map state; event log replays correctly
- **LiveView tests** (`unstr_canvas_live_test.exs`): editing, presence join/leave, cursor tracking, structure editing, access control
- **Browser test**: two browser contexts editing the same canvas, verifying real-time sync and cursor visibility
