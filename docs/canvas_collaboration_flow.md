# Canvas — per-cell CRDT flow

The configurable canvas (`/canvas`) stores all cell content in a single
`cells` map. Edits are structured operations (`update_cell`, `update_name`,
`update_description`) that are event-sourced, broadcast, and folded into the map —
with a per-tab `client_id` so a client skips the echo of its own operations.

```mermaid
sequenceDiagram
    autonumber
    actor U as User (browser)
    participant CH as "CellHook (JS)"
    participant LV as "UnstrCanvasLive.Editor"
    participant C as "Psc.Canvas"
    participant R as "UnstrCanvasCRDT"
    participant DB as "PostgreSQL"
    participant PS as "Psc.PubSub"
    participant O as "Other clients' LiveViews"

    Note over LV,PS: mount/3 — subscribe "unstr_canvas:id" + "presence_unstr:id",<br/>per-tab client_id for echo suppression
    U->>CH: edit a markdown cell field
    CH->>LV: pushEvent "update_cell" {cell_key, field, value}
    LV->>C: apply_unstr_canvas_operation(id, user_id, client_id, op)
    C->>DB: INSERT unstr_canvas_events (op, seq)
    C->>PS: broadcast {:operation, user_id, client_id, op, seq}
    PS-->>O: {:operation, ..., client_id}
    O->>R: rebuild cells (apply_operation/2)
    O->>CH: push_event "cell_updated" {cell_key, field, new_value}
    LV->>CH: push_event "field_rendered" (Earmark markdown → HTML)
    Note over LV,DB: :idle_save / :periodic_save
    LV->>C: save_unstr_canvas_content_to_db(cells)
    C->>DB: UPDATE unstr_canvases SET cells, snapshot_seq<br/>DELETE unstr_canvas_events folded into the snapshot
```

State-shape rules that must stay consistent across the editor, templates, and replay:

- Cell data lives at flat top-level keys (`cells[cell_key][field]`).
- The canvas title/description edited in the UI live under the reserved
  `"$name"` / `"$description"` keys.

## Related diagrams

- [architecture.md](architecture.md) — system-wide layering
- [documents_collaboration_flow.md](documents_collaboration_flow.md) — the text-document equivalent
- [data_model.md](data_model.md) — `unstr_canvases` / `unstr_canvas_events` tables
