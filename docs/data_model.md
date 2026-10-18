# Data model

Ecto schemas as persisted today. Sharing is by email via the `shared_with` string
array on documents, canvases, and templates; the `*_events` tables are the append-only
operation logs used to rebuild state.

**Terminology.** The domain words and the code identifiers differ:

| Domain | Table | Schema | Surface |
|---|---|---|---|
| Canvas (configurable workspace) | `unstr_canvases` | `Psc.Canvas.UnstrCanvas` | `/canvases`, `PscWeb.UnstrCanvasLive` |
| Template (reusable structure) | `canvas_layouts` | `Psc.Canvas.Layout` | `/templates`, `PscWeb.CanvasLayoutLive` |
| Problem–Solution Canvas (fixed 12 cells) | `canvases` | `Psc.Canvas.Canvas` | `/psc-canvas`, `PscWeb.CanvasLive` |

The `unstr_` prefix and the `canvas_layouts` name are historical; the vocabulary above
is what docs and the UI use.

```mermaid
erDiagram
    users ||--o{ users_tokens : "token holder"
    users ||--o{ documents : "owns"
    users ||--o{ document_events : "authored"
    users ||--o{ canvases : "author"
    users ||--o{ unstr_canvases : "author"
    users ||--o{ unstr_canvas_events : "authored"
    users ||--o{ canvas_layouts : "author"
    documents ||--o{ document_events : "event log"
    unstr_canvases ||--o{ unstr_canvas_events : "event log"

    users {
        bigint id PK
        string email UK
        string hashed_password
        datetime confirmed_at
    }
    users_tokens {
        bigint id PK
        binary token UK
        string context
        string sent_to
        datetime authenticated_at
        bigint user_id FK
    }
    documents {
        bigint id PK
        string title
        text content
        string crdt_state
        int snapshot_seq
        string_array shared_with
        int user_id FK
    }
    document_events {
        bigint id PK
        map operation
        int seq
        int document_id FK
        int user_id FK
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
        int author_id FK
    }
```

Notes on the two canvas representations:

- `canvases` is the fixed 12-cell Problem–Solution Canvas; each cell is its own
  `embeds_one` schema (JSONB column) validated per cell.
- `unstr_canvases` is the configurable canvas: rows, columns, the 2D `layout`, and
  all cell data live inside the single `cells` map, validated against that layout.
- `canvas_layouts.layout_map` is the template definition (`rows`, `columns`,
  `layout`, `cells`) validated for grid completeness and unique field keys per
  cell.
- `snapshot_seq` on `documents`/`unstr_canvases` marks how far the saved
  `content`/`cells` has been folded; the `*_events` tables only ever hold rows
  above it, because folds delete what they covered and `Psc.EventsSweeper`
  reclaims any stale rows left behind.

## Related diagrams

- [architecture.md](architecture.md) — system-wide layering
- [documents_collaboration_flow.md](documents_collaboration_flow.md) — how the event tables are written and pruned
- [canvas_collaboration_flow.md](canvas_collaboration_flow.md) — how `cells` is updated
