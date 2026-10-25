# Bento boards

A bento canvas is the same cells as the table canvas arranged as free-form cards on a
fixed column grid. The mode is chosen when the template is created and is copied to every
canvas made from it (ADR-035). Existing canvases and templates are unaffected: a map
without `"layout_mode"` keeps rendering as a table.

## Shape

A bento canvas (and a bento template) is flat, exactly like a canvas's `cells`:

```json
{
  "layout_mode": "bento",
  "bento_columns": 12,
  "bento_rows": 5,
  "big_picture": {
    "label": "Big picture",
    "content": "",
    "titles": {},
    "placement": { "x": 0, "y": 0, "w": 8, "h": 3 },
    "accent": "sky"
  }
}
```

| Key | Meaning |
|---|---|
| `layout_mode` | `"bento"`. Absent means a table. |
| `bento_columns` | 4–16, default 12 |
| `bento_rows` | 1–64, default 4. The container height: a board can reserve empty rows below its cards |
| `placement` | `x`, `y`, `w`, `h` in half units, 0-based. `h` is a **minimum** |
| `accent` | optional token from `Psc.Canvas.Accent` |
| everything else | the cell's fields, `label` and `titles`, as in a table |

`"$name"` and `"$description"` also live in the map: they are the canvas header, written by
the name/description operations. They are metadata like `layout_mode`, never cards — a
canvas that is renamed and then reloaded must still render its board.

`placement` and `accent` are reserved cell keys: they can never be added, removed or
rendered as editable fields.

## Constraints

- `bento_rows` is a floor: a card that reaches lower than the stored value grows the board,
  so shrinking the container can never hide a card.
- `x`, `y`, `w`, `h` are multiples of 0.5; `x`, `y` ≥ 0; `w`, `h` ≥ 0.5; `x + w ≤ bento_columns`.
  A card can be **moved and resized** in half-column steps, so the two gestures share one
  granularity and a card can be nudged without resizing it. The board renders two CSS
  tracks per column (`Structure.tracks_per_unit/0`) to make that possible; one row unit is
  72px including the 8px gap, so a half step is 40px.
- A template needs at least one card to save; a canvas may be empty (the empty state adds
  the first card).
- Unknown accents and columns outside 4–16 are rejected by the schema.
- Overlap is allowed after concurrent drags; the later sequence renders on top.

`Psc.Canvas.Structure` is the only module that knows these rules. The validators, the
reducer, the editor, the designer, the previews and the agent tools all call it.

## Operations

| Operation | Payload | Notes |
|---|---|---|
| `add_card` | `cell_key`, optional `placement`, `label`, `accent` | Idempotent; without a placement the board's first free slot is used |
| `remove_card` | `cell_key` | Removes the cell and its placement together |
| `move_card` | `cell_key`, `x`, `y` | Last-write-wins |
| `resize_card` | `cell_key`, `w`, `h` | The left edge stays put |
| `set_card_accent` | `cell_key`, `accent` | Validated against the token list |
| `set_bento_columns` | `columns` | Clamps every card into the new width |
| `set_bento_rows` | `rows` | Sets the container height; clamps up to the deepest card |

Cell content keeps the existing operations (`update_cell`, `update_cell_label`,
`add_cell_field`, `remove_cell_field`, `update_cell_field_title`).

A drag or resize sends one operation when the gesture ends. A gesture that ends where it
started sends nothing.

The board grows with its cards on both axes: a card dragged or resized past the right
edge widens `bento_columns` (up to 16), exactly like a card dragged down extends the rows.
An explicit narrower width from the toolbar still wins — that is the user asking for a
smaller board, so it clamps the cards instead.

## Editor

- `Edit layout` shows the drag grip, the resize corner, the accent swatch, the remove
  action and `Add card`. Without it a card behaves like a table cell.
- Dragging or resizing previews locally (`BentoBoard`) and pushes the final rectangle.
- Keyboard: focus the grip, arrow keys move half a unit; shift+arrows resize by the same
  step. The shift path
  lives in the hook because the LiveView keydown payload does not carry modifier flags.
- Removing a card with content opens the same confirmation as a row or column.
- The toolbar reports the board's real grid (`12 × 5`: columns × rows) and, while Edit
  layout is on, it is the control itself: two number inputs set the columns and the
  container height. The drag hook reads the grid from the DOM at the start of every
  gesture, so a board widened there is immediately usable for placing cards. Values outside the allowed ranges are ignored rather than clamped, so
  typing `1` on the way to `12` does not resize anything. Outside edit mode it is a
  read-only badge, because restructuring a canvas while reading it should not be one
  stray keystroke away.
- Every card carries its own `w × h` (`8 × 3`, or `6.5 × 2` after a half-step resize) in
  its control bar while Edit layout is on; outside edit mode the size is the card's
  `title` tooltip and its `data-bento-size` attribute.
- Cards carry `data-cell-nav` for the mobile fullscreen swipe (ADR-037).
- A card's body is in the flow, so the card grows with its Markdown and takes its grid
  rows along; `h` is a minimum, never a clip.

## Scrolling

The board is a document, not a dashboard: a board taller than the window grows and the
page scrolls, so there is one scrollbar rather than a nested one. The editor panel is
content-sized on `lg` for a bento (`lg:flex-none`) and the board's scroll wrapper becomes
`overflow-visible`; the table canvas keeps its fill-the-viewport behaviour. On a phone the
old behaviour stays — the board pans horizontally and scrolls vertically inside its own
area, because the page shell is a fixed-height app frame there.

## On a phone

The spatial arrangement is the point, so a phone does not collapse the board into one
column. Columns keep a minimum width (3rem below `sm`, 3.5rem up to `lg`) and the board
pans horizontally inside its scroll area; the card cut off at the edge is the affordance,
the same one the table grid uses. From `lg` the board fits the viewport again. Cards keep
the tap-to-fullscreen behaviour, and edit-mode controls grow to 32px touch targets.

## Designer

`/templates/new?mode=bento` starts a board with one card. The designer edits the
definition (label, fields, default values, section titles, colour, geometry) and keeps its
usual name/description/public/notes/save/share chrome. A shared template is editable by
anyone with access; a built-in one stays read-only.

## What a bento does not do

- It does not convert to or from a table. Duplicate the template instead.
- It has no row or column headers, so row/column accents and labels do not exist; each
  card carries its own label and colour.
- It does not introduce card content types (metric, image, checklist). A card is a cell
  with Markdown fields.
