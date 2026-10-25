# Data model

Ecto schemas as persisted today. Sharing is by email via the `shared_with` string
array on canvases and templates; the `*_events` tables are the append-only
operation logs used to rebuild state.

**Terminology.** The domain words and the code identifiers differ:

| Domain | Table | Schema | Surface |
|---|---|---|---|
| Canvas (configurable workspace) | `unstr_canvases` | `Psc.Canvas.UnstrCanvas` | `/canvas`, `PscWeb.UnstrCanvasLive` |
| Template (reusable structure) | `canvas_layouts` | `Psc.Canvas.Layout` | `/templates`, `PscWeb.CanvasLayoutLive` |
| Note (collaborative Markdown in a canvas) | `notes` | `Psc.Notes.Note` | `/canvas/:id?tab=notes`, `PscWeb.UnstrCanvasLive` |
| Problem–Solution Canvas (fixed 12 cells) | `canvases` | `Psc.Canvas.Canvas` | `/psc-canvas`, `PscWeb.CanvasLive` |

The `unstr_` prefix and the `canvas_layouts` name are historical; the vocabulary above
is what docs and the UI use.

```mermaid
erDiagram
    users ||--o{ users_tokens : "token holder"
    users ||--o{ notes : "authored"
    users ||--o{ note_events : "authored"
    users ||--o{ canvases : "author"
    users ||--o{ unstr_canvases : "author"
    users ||--o{ unstr_canvas_events : "authored"
    users ||--o{ canvas_layouts : "author"
    canvas_layouts ||--o{ canvas_layouts : "forked from"
    unstr_canvases ||--o{ notes : "owns"
    notes ||--o{ note_events : "event log"
    unstr_canvases ||--o{ unstr_canvas_events : "event log"

    users {
        bigint id PK
        string email UK
        string hashed_password
        datetime confirmed_at
        string role "member | admin"
    }
    users_tokens {
        bigint id PK
        binary token UK
        string context
        string sent_to
        datetime authenticated_at
        bigint user_id FK
    }
    notes {
        binary_id id PK
        string title
        text content
        int snapshot_seq
        binary_id canvas_id FK
        bigint created_by_id FK
    }
    note_events {
        binary_id id PK
        map operation
        int seq
        binary_id note_id FK
        bigint user_id FK
    }
    canvases {
        uuid id PK
        string name
        text description
        string_array shared_with
        map problem
        map leverage
        map solution_cluster
        map horizon
        map outer_environment
        map inner_environment
        map evolvability_cluster
        map potential
        map manifestations
        map capabilities
        map merit_cluster
        map mission
        int author_id FK
    }
    unstr_canvases {
        uuid id PK
        string name
        string description
        string_array shared_with
        string notes_mode
        map cells
        int snapshot_seq
        int author_id FK
    }
    unstr_canvas_events {
        uuid id PK
        map operation
        int seq
        uuid unstr_canvas_id FK
        int user_id FK
    }
    canvas_layouts {
        uuid id PK
        string name UK
        string description
        map layout_map
        string_array shared_with
        boolean public
        int use_count
        int fork_count
        uuid forked_from_id FK
        boolean built_in
        string slug UK "unique when present"
        int author_id FK
    }
```

Notes on the two canvas representations:

- The `unstr_canvases.cells` map holds the canvas's structure and content flat: `rows`,
  `columns` and `layout` (the matrix of cell keys) beside every cell's data at its own
  key. Its default is the **empty structure** — a canvas with no rows and no columns,
  built in place with structure editing (ADR-033); the built-in 12-cell PSC grid is a
  seeded built-in template (`slug: "psc"`, ADR-034), not a schema default.

- `canvases` is the fixed 12-cell Problem–Solution Canvas; each cell is its own
  `embeds_one` schema (JSONB column) validated per cell.
- `unstr_canvases` is the configurable canvas: rows, columns, the 2D `layout`, and
  all cell data live inside the single `cells` map, validated against that layout.
- A structure map also carries a `"layout_mode"`: absent or `"table"` is the matrix
  above, `"bento"` is flat cards with a `placement` in grid units and `bento_columns`,
  and `"image"` is flat cells with a `placement` in percent of a `backdrop` picture.
  See [spec/bento.md](spec/bento.md) and [spec/image-canvas.md](spec/image-canvas.md).
- `canvas_layouts.layout_map` is the template definition (`rows`, `columns`,
  `layout`, `cells`) validated for grid completeness and unique field keys per
  cell. A bento or image template is flat instead, with the same mode key.
- `snapshot_seq` on `notes`/`unstr_canvases` marks how far the saved
  `content`/`cells` has been folded; the `*_events` tables only ever hold rows
  above it, because folds delete what they covered and `Psc.EventsSweeper`
  reclaims any stale rows left behind.

## Related diagrams

- [architecture.md](architecture.md) — system-wide layering
- [notes_collaboration_flow.md](notes_collaboration_flow.md) — how the event tables are written and pruned
- [canvas_collaboration_flow.md](canvas_collaboration_flow.md) — how `cells` is updated
