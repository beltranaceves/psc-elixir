# Collaborative text documents — event-sourced CRDT flow

Each keystroke batch is diffed into delta operations, persisted as an append-only
event row, broadcast over PubSub, and folded into a content snapshot on idle/periodic
ticks. Loading replays only the events after `snapshot_seq`.

```mermaid
sequenceDiagram
    autonumber
    actor U as User (browser)
    participant H as "DocumentEditorHook (JS)"
    participant LW as "DocumentLive.Editor"
    participant D as "Psc.Documents"
    participant DB as "PostgreSQL"
    participant PS as "Psc.PubSub"
    participant O as "Other editors' LiveViews"

    Note over LW,PS: mount/3 — subscribe "document:id" + "presence:id",<br/>Presence.track/4, load content via SnapshotManager
    H->>H: preview mode until the editor receives focus
    U->>H: click preview
    H->>H: show raw Markdown textarea
    U->>H: keystroke (debounced 300 ms by phx-debounce)
    H->>LW: pushEvent "update_content" (full text)
    LW->>D: CRDT.text_to_deltas(old, new)
    D-->>LW: one coalesced op per contiguous run
    loop each op
        LW->>D: apply_operation(doc_id, user_id, op)
        D->>DB: INSERT document_events (op, seq = max(event.seq, snapshot_seq) + 1)
        D->>PS: broadcast {:operation, user_id, op, seq}
        PS-->>O: {:operation, ...}
        O->>H: push_event "content_updated" → patch textarea
    end
    LW->>PS: Presence.update(cursor_pos)
    PS-->>O: presence_diff → peer list / cursors
    U->>H: blur textarea
    H->>LW: pushEvent "render_document" (current text)
    LW-->>H: push_event "document_rendered" (Earmark Markdown → HTML)
    H->>H: show inline preview
    Note over LW,DB: fold when pending ops reach 500,<br/>else on idle (1.5 s) or periodic (10 s) tick
    LW->>D: save_content_to_db(content)
    D->>DB: UPDATE documents SET content, snapshot_seq = max(seq)<br/>DELETE document_events folded into the snapshot
    Note over D,DB: load = content + replay events after snapshot_seq
    Note over DB: Psc.EventsSweeper also deletes any stale<br/>rows with seq <= snapshot_seq (boot + every 6 h)
```

Two invariants worth remembering when changing this code:

- `next_sequence/1` is floored at `snapshot_seq`, because events at or below the
  snapshot are pruned — `max(seq)` alone would restart at 1 and place new events
  where `SnapshotManager.load_with_snapshot/1` never replays them.
- Pruning is load-bearing: free-tier Postgres is capped at 10k rows per table.
  Rows are sized so a document stays far below it — a delta op is *one row per
  contiguous edit run* (a 10k-character paste is a single row), not one row per
  character, and a fold happens at 500 pending ops at the latest.

## Related diagrams

- [architecture.md](architecture.md) — system-wide layering
- [canvas_collaboration_flow.md](canvas_collaboration_flow.md) — the per-cell equivalent
- [data_model.md](data_model.md) — `documents` / `document_events` tables
