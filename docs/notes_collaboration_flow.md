# Collaborative text — event-sourced CRDT flow

Each keystroke batch is diffed into delta operations, persisted as an append-only
event row, broadcast over PubSub, and folded into a content snapshot on idle/periodic
ticks. Loading replays only the events after `snapshot_seq`.

This is the flow for a **note** — the collaborative Markdown inside a canvas. It used
to belong to the standalone documents feature, which was retired when notes landed
(ADR-027): the algorithm now lives in `Psc.TextStore` and serves the notes, and the
canvas editor's cells have their own, cruder equivalent (see
[canvas_collaboration_flow.md](canvas_collaboration_flow.md)).

```mermaid
sequenceDiagram
    autonumber
    actor U as User (browser)
    participant H as "MarkdownEditorHook (JS)"
    participant LW as "UnstrCanvasLive.Editor"
    participant N as "Psc.Notes"
    participant S as "Psc.TextStore"
    participant DB as "PostgreSQL"
    participant PS as "Psc.PubSub"
    participant O as "Other editors' LiveViews"

    Note over LW,PS: mount/3 — subscribe "note:id",<br/>load content via TextStore
    H->>H: preview mode until the editor receives focus
    U->>H: click preview
    H->>H: show raw Markdown textarea
    U->>H: keystroke (debounced 300 ms by phx-debounce)
    H->>LW: pushEvent "update_note_content" (full text)
    LW->>N: text_to_operations(old, new)
    N-->>LW: one coalesced op per contiguous run
    loop each op
        LW->>N: apply_operation(note_id, user_id, op)
        N->>S: append the event
        S->>DB: INSERT note_events (op, seq = max(event.seq, snapshot_seq) + 1)
        S->>PS: broadcast {:note_operation, user_id, op, seq}
        PS-->>O: {:note_operation, ...}
        O->>H: push_event "note_content_updated" → patch textarea
    end
    U->>H: blur textarea
    H->>LW: pushEvent "render_note" (current text)
    LW-->>H: push_event "note_rendered" (Earmark Markdown → HTML)
    H->>H: show inline preview
    Note over LW,DB: fold on idle (1.5 s) tick
    LW->>N: save_content_to_db(content)
    N->>S: fold
    S->>DB: UPDATE notes SET content, snapshot_seq = max(seq)<br/>DELETE note_events folded into the snapshot
    Note over S,DB: load = content + replay events after snapshot_seq
    Note over DB: Psc.EventsSweeper also deletes any stale<br/>rows with seq <= snapshot_seq (boot + every 6 h)
```

Two invariants worth remembering when changing this code:

- The next sequence number is floored at `snapshot_seq`, because events at or below
  the snapshot are pruned — `max(seq)` alone would restart at 1 and place new events
  where the loader never replays them.
- Pruning is load-bearing: free-tier Postgres is capped at 10k rows per table.
  Rows are sized so a note stays far below it — a delta op is *one row per
  contiguous edit run* (a 10k-character paste is a single row), not one row per
  character.

## Related diagrams

- [architecture.md](architecture.md) — system-wide layering
- [canvas_collaboration_flow.md](canvas_collaboration_flow.md) — the per-cell equivalent
- [data_model.md](data_model.md) — the `notes` / `note_events` tables
