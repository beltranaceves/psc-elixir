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
| `placement` | `x`, `y` (0-based grid units), `w`, `h` (units). `h` is a **minimum** |
| `accent` | optional token from `Psc.Canvas.Accent` |
| everything else | the cell's fields, `label` and `titles`, as in a table |

`placement` and `accent` are reserved cell keys: they can never be added, removed or
rendered as editable fields.

## Constraints

- `w`, `h` ≥ 1; `x` ≥ 0, `y` ≥ 0; `x + w ≤ bento_columns`.
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

Cell content keeps the existing operations (`update_cell`, `update_cell_label`,
`add_cell_field`, `remove_cell_field`, `update_cell_field_title`).

A drag or resize sends one operation when the gesture ends. A gesture that ends where it
started sends nothing.

## Editor

- `Edit layout` shows the drag grip, the resize corner, the accent swatch, the remove
  action and `Add card`. Without it a card behaves like a table cell.
- Dragging or resizing previews locally (`BentoBoard`) and pushes the final rectangle.
- Keyboard: focus the grip, arrow keys move one unit; shift+arrows resize. The shift path
  lives in the hook because the LiveView keydown payload does not carry modifier flags.
- Removing a card with content opens the same confirmation as a row or column.
- Cards carry `data-cell-nav` for the mobile fullscreen swipe (ADR-037).

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
