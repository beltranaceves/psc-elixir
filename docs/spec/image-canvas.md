# Image boards

An image board is the third layout mode: floating cells over a backdrop picture.

The table arranges cells in a matrix; the bento arranges cards on a column grid. An
image board arranges cells **where they belong on a picture** — a floor plan, a
diagram, a screenshot, a map, an SVG. A cell is either a card (a titled Markdown box)
or a bare text label. The mode is chosen when the template is created and is copied to
every canvas made from it
([ADR-039](../design-decisions.md#adr-039--an-image-board-pins-cells-to-percentages-of-a-picture)).

## Shape

An image canvas and an image template share the same flat shape: one entry per cell,
plus `"layout_mode"` and a `"backdrop"`.

```json
{
  "layout_mode": "image",
  "backdrop": {
    "url": "/images/image-board-blueprint.svg",
    "fit": "contain",
    "alt": "Blueprint grid with three marked zones",
    "aspect": 1.6
  },
  "brief": {
    "label": "Brief",
    "kind": "card",
    "placement": {"x": 4, "y": 8, "w": 28, "h": 18},
    "accent": "sky",
    "content": ""
  },
  "next_step": {
    "label": "Next step",
    "kind": "text",
    "placement": {"x": 34, "y": 78, "w": 32, "h": 8},
    "content": "Book the review"
  }
}
```

| Key | Meaning |
|---|---|
| `layout_mode` | `"image"`. Absent means a table. |
| `backdrop.url` | The picture: `https(s)://…`, a root-relative path (`/images/…`), or a `data:image/*` URI |
| `backdrop.fit` | `contain`, `cover` or `stretch`; used when `aspect` pins the board |
| `backdrop.alt` | Optional description, copied to the picture's `alt` |
| `backdrop.aspect` | Optional width ÷ height. Absent means the picture's own shape sets the board |
| `placement` | `x`, `y`, `w`, `h` in **percent of the backdrop**, 0–100 |
| `kind` | `"card"` (default) or `"text"` |
| `accent` | optional outline token, drawn as a ring around the card or the text label |
| `background` | optional cell surface tint from the accent token list |
| everything else | the cell's fields, `label` and `titles`, exactly as in a table cell |

`"$name"` and `"$description"` are the canvas header, written by the name/description
operations. They are metadata, never cells.

`placement`, `accent`, `background` and `kind` are reserved cell keys: they can never be
added, removed or rendered as editable fields.

## Geometry

- Percentages, not pixels or grid tracks. The picture can be any size, and the same
  stored placement keeps its spot at every viewport width. This is the reason the mode
  exists: a cell is *about a place in the picture*.
- `w` and `h` are at least **2%**; `x + w ≤ 100` and `y + h ≤ 100`, so a cell can never
  sit outside the picture. Moves and resizes snap to the same **half-percent** step as
  the bento's half-unit step, so a cell can be nudged without being resized first.
- A drag or resize sends one operation when the gesture ends. Arrow keys on the move
  grip send one operation per press; shift+arrows resize by the same step.
- Geometry is clamped in one place, `Psc.Canvas.Structure.clamp_placement/2`, called by
  the reducer. Clamping anywhere else would let two clients disagree about the same
  event.

## The backdrop

- The picture is a URL, not an upload: the app has no object store, and a URL keeps the
  row small and the template portable. Static assets under `priv/static` are served at
  their path (`/images/image-board-blueprint.svg`), and a percent-encoded `data:image`
  URI works for a self-contained picture.
- Only image sources are accepted (`http(s)`, `/…`, `data:image/…`). Quotes,
  whitespace and control characters are rejected, and a `javascript:` URI never reaches
  the `src` attribute. The picture is rendered with `<img>`, so an SVG cannot run
  script even if its URL is a data URI.
- **The picture's own shape is the default.** Without `aspect`, the `<img>` is in the
  flow, gives the board its height, and the cells are percentages of that height.
  Setting `aspect` pins the board to a stable frame and fits the picture inside it with
  `fit` (`contain` letterboxes, `cover` crops, `stretch` distorts). A pinned frame is
  useful when a template should keep its shape while the picture loads or when several
  pictures with different ratios are swapped in.
- A canvas may have no backdrop (an empty frame with a prompt). A **template may not**:
  its cell coordinates only mean something relative to a picture, so saving one without
  a backdrop is refused.

## Cell kinds

- **Card** — the same body as a table cell: a label, fields with section titles, and
  the Markdown editors. It is drawn as a floating card with a shadow. The card's
  content scrolls inside its box; the box itself stays the size the user placed, so it
  keeps covering the place on the picture it was put over.
- **Text** — a one-line input placed directly on the picture: no card frame, no
  title row, no fields. It edits the cell's `content` field with the ordinary
  `update_cell` operation, so autosave, collaboration and the event log need no special
  case. It is the annotation you would otherwise draw on the picture with a marker.

A cell can switch kind without losing its content: the fields stay in the cell, they
are simply not shown while it is text.

## Operations

| Operation | Payload | Notes |
|---|---|---|
| `add_card` | `cell_key`, optional `placement`, `label`, `accent`, `kind` | Idempotent; without a placement the first free 2%-step slot is used |
| `remove_card` | `cell_key` | Removes the cell and its placement together |
| `move_card` | `cell_key`, `x`, `y` | Percent, last-write-wins |
| `resize_card` | `cell_key`, `w`, `h` | The left edge stays put |
| `set_cell_kind` | `cell_key`, `kind` | `"card"` or `"text"` |
| `set_card_accent` | `cell_key`, `accent` | Validated against the accent tokens |
| `set_cell_background` | `cell_key`, `background` | Surface tint for a card or a text cell |
| `set_backdrop` | `backdrop` (`url`, `fit`, `alt`, `aspect`) | Missing fields keep their value; an empty URL clears the picture |

Cell content keeps the existing operations (`update_cell`, `update_cell_label`,
`add_cell_field`, `remove_cell_field`, `update_cell_field_title`). Bento-only
operations (`set_bento_columns`, `set_bento_rows`) are no-ops on an image board.

A backdrop change is a canvas operation like any other: everyone sees the new picture,
and the event log replays it.

## Editor

- The toolbar carries **Edit layout**, a cell count, **Add cell** and **Add text**.
- While Edit layout is on, a second row edits the backdrop: URL, shape, fit and
  description. The values are stored through `set_backdrop`; an invalid URL is ignored
  and the current picture stays.
- Every cell carries its size in percent, a drag grip, a **Text/Card** toggle, its
  a **Colors** control, a remove action and a resize corner. The Colors panel labels the
  two independent colours: **Outline** rings the card (or the text label) and **Background**
  tints the surface; either row can be cleared with None.
- A remove asks first when the cell has content, the same dialog the table and bento
  use. An empty cell goes immediately.
- Dragging or resizing previews locally; the final rectangle is pushed on release.
  Keyboard: focus the grip and use the arrow keys, shift+arrows to resize.
- The picture is the board, and it scales to the available width: because the cells are
  percentages, the whole board stays visible on a phone rather than panning. On a
  desktop the page scrolls; a phone keeps the board in its own vertical scroll area. A
  card tapped on a phone still opens fullscreen.

## Designer

`/templates` has one **New Template** card; its type picker offers **Table grid**,
**Bento board** and **Image board**, and the image option opens the designer at
`/templates/new?mode=image` with the sample blueprint picture and two cells (a card and
a text label), so the template is valid immediately and demonstrates both kinds. The
designer edits the definition — label, kind, fields, default values, section titles,
accent and geometry — and keeps its usual name/description/public/notes/save/share
chrome.

A designer cell grows with its definition box, while a dashed outline marks the real
footprint: a small placement must not make the fields uneditable. The canvas renders the
placement exactly.

The built-in **Image Board** (`slug: "image"`) is seeded create-if-missing like the
others, so a new user can start from a working example.

## Previews

- The canvas picker draws the picture's thumbnail with one box per cell at its
  percentage placement.
- The catalog's detail modal draws the picture and each cell's label over it.
- The caption under a template reads `N cells`, and the structure section is titled
  **Picture** rather than **Grid**.

## Validation

`Psc.Canvas.Structure` owns the rules:

- backdrop: a present map needs an allowed URL, a known `fit`, and an `aspect` between
  0.1 and 10; a canvas may have no backdrop, a template may not;
- every cell: a map with a placement, half-percent coordinates, at least 2% in each
  dimension, entirely inside 0–100, a valid label and a known kind;
- a template needs at least one cell;
- accents and notes modes are validated as in the other modes.

## What an image board does not do

- It does not upload files: the picture is a URL. An upload would need an object store,
  which the free tier does not have.
- It has no z-order, rotation or per-cell opacity. The later sequence renders on top,
  like a bento; overlap is allowed because two people can drag at once.
- It does not convert to or from a table or a bento. Duplicate the template instead.
- It does not crop or annotate the picture itself; the cells are the annotations.
