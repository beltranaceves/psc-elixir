---
name: "crdt-dcollaboration"
description: "Automate and standardize creation of CRDT-based real-time collaboration features in Phoenix LiveView."
---

# Skill: Real-time Collaboration with CRDTs in Phoenix LiveView

## Purpose

This skill documents how to implement and operate real-time collaborative text editing in Phoenix LiveView using a CRDT-style event-log approach (as implemented in this repository). It covers architecture, schema design, LiveView wiring, client hooks, snapshotting, consistency checks, common pitfalls, and a migration path to stronger CRDTs.

## Goals

- Provide a reproducible pattern for collaborative editing using Ecto + PubSub + Presence.
- Explain the design trade-offs of a simple position-based delta CRDT.
- Give practical guidance for scaling, testing, and migrating to more robust CRDT implementations.

## Architecture Overview

- Clients send edited text to a LiveView (`phx-change`) which computes deltas and emits events.
- Each delta is persisted as a `DocumentEvent` in an append-only event log with a monotonic `seq` number.
- The server broadcasts operations over Phoenix.PubSub to all subscribers for the same document topic.
- Subscribers apply operations to their local state using `CRDT.apply_operation/2` and push `content_updated` events to the client hook.
- The client hook (`EditorHook`) updates the textarea while avoiding clobbering the active editor and preserving cursor position.
- Periodic idle/periodic saves persist full `content` to the `documents` table and record `snapshot_seq` indicating the event seq that the content covers.
- SnapshotManager replays only events after `snapshot_seq` for efficient loading.
- ConsistencyManager periodically verifies client state and enforces resyncs when divergence is detected.

## Key Files (implementation reference)

- LiveView editor: [lib/psc_web/live/document_live/editor.ex](lib/psc_web/live/document_live/editor.ex#L1-L1)
- Context & orchestration: [lib/psc/documents.ex](lib/psc/documents.ex#L1-L1)
- CRDT logic (delta compute/apply): [lib/psc/documents/crdt.ex](lib/psc/documents/crdt.ex#L1-L1)
- Consistency checks: [lib/psc/documents/consistency_manager.ex](lib/psc/documents/consistency_manager.ex#L1-L1)
- Snapshots: [lib/psc/documents/snapshot_manager.ex](lib/psc/documents/snapshot_manager.ex#L1-L1)
- Ecto: `Document` schema: [lib/psc/documents/document.ex](lib/psc/documents/document.ex#L1-L1)
- Ecto: `DocumentEvent` schema: [lib/psc/documents/document_event.ex](lib/psc/documents/document_event.ex#L1-L1)
- Presence wrapper: [lib/psc_web/presence.ex](lib/psc_web/presence.ex#L1-L1)
- Client hook: [assets/js/hooks/editor_hook.js](assets/js/hooks/editor_hook.js#L1-L1)

## Data Model

- `documents` table (Ecto `Psc.Documents.Document`)
  - `title`, `content`, `crdt_state` (future), `shared_with`, `snapshot_content`, `snapshot_seq`
  - `content` stores last saved full text; `snapshot_seq` is max event seq included in that content
  - `shared_with` is an array of emails for simple share-list-based authorization

- `document_events` table (Ecto `Psc.Documents.DocumentEvent`)
  - `operation` (map), `seq` (integer), `document_id`, `user_id`
  - Append-only event log; `seq` provides deterministic replay order

## CRDT Design in this repo

- Format: positional deltas per character
  - Insert: `%{"type" => "insert", "pos" => pos, "char" => char}`
  - Delete: `%{"type" => "delete", "pos" => pos}`
- `CRDT.text_to_deltas/2` computes a minimal set of per-character ops by finding the first divergence point and emitting one op per inserted/deleted char.
- `CRDT.apply_operation/2` applies a single op to a server-side string via slicing.
- Concurrency model: server-assigned `seq` numbers serialize operations; event order determines final state.

## LiveView Behavior

- On mount: authorize access using `Documents.can_access_document?/2`, load content from `SnapshotManager.load_with_snapshot/1`, subscribe to PubSub and presence topics, track presence.
- On `phx-change` (`update_content`): compute deltas via `Documents.text_to_operations/2`, call `Documents.apply_operation/3` for each op to persist and broadcast, update presence and schedule idle save.
- On PubSub `{:operation, user_id, op, seq}`: apply op using `CRDT.apply_operation/2`, push `content_updated` event to clients, update assigns.
- Timers:
  - Idle save (`@idle_save_interval`) — persist full content to `documents.content` + update `snapshot_seq` to current max event seq.
  - Periodic save (`@periodic_save_interval`) — fallback save.
  - Consistency check (`@consistency_check_interval`) — call `ConsistencyManager.verify_consistency/2` to detect divergence and force resyncs.
  - Snapshot check (`@snapshot_check_interval`) — call `Documents.should_snapshot?/1` and `Documents.create_snapshot/1`.

## Client Hook (`EditorHook`)

- Mounted: set textarea value from server `value` attribute (because `phx-update=\"ignore\"`).
- Listens for `content_updated` pushes. If `fromUserId == -1`, it's a server resync — always apply. If `fromUserId` matches current user and the textarea is focused, skip to avoid clobbering.
- Restores cursor position when possible.

## Operational Concerns & Recommendations

- Performance:
  - Avoid writing one DB row per keystroke at scale. Consider batching multiple character ops into a single event payload (e.g., arrays of ops) or perform client-side delta detection to emit only logical operations.
  - Add DB indexes on `(document_id, seq)` and on `document_id` for event queries.
  - Consider sharding events or archiving old events after snapshots are taken (retain for audit if needed).

- Storage:
  - Events can grow large; implement retention or compaction strategy. After snapshotting, events prior to `snapshot_seq` can be archived or deleted if full audit not required.

- Correctness & Conflict Handling:
  - The current position-based approach relies on server sequencing. Concurrent edits are serialized by seq but this can lead to unintuitive results for users. For better intent preservation, migrate to identifier-based CRDTs (RGA, LSEQ) or use a mature library like Yjs on the client and mirror operations server-side.

- Bandwidth:
  - Current LiveView sends full textarea on each `phx-change`. For large docs and frequent edits, this is expensive. Alternatives:
    - Send deltas from client (compute on JS) and call a dedicated phx-target or channel event.
    - Use WebSocket channels with a compact delta protocol.

- Security:
  - Ensure `Documents.can_access_document?/2` is always used where appropriate and that `get_document` preloads the user to avoid nil errors.
  - Sanitize pasted content where necessary.

- Testing:
  - Add unit tests for `CRDT.text_to_deltas/2` and `CRDT.apply_operation/2` for varied edit patterns (prefix, suffix, middle, replacements, multi-byte characters).
  - Add integration tests that replay random sequences of operations from multiple simulated users and assert final text matches replay under the same ordering.
  - Use `start_supervised!/1` to spin up processes in tests and `Phoenix.PubSub` to assert broadcasts.

## Limitations of the current approach (be explicit in SKILL teaching)

- Not a full CRDT: lacks unique element identifiers, tombstones, and commutative/associative conflict resolution.
- Per-character events are heavy; no batching by default.
- No vector clocks or causal metadata; relies on central sequencing.
- `text_to_deltas/2` only detects first divergence and may fail to create minimal deltas for complex edits.

## Migration Path to Robust CRDTs

1. Evaluate requirements: real-time collaborative richness, offline edits, merge semantics.
2. Consider libraries:
   - Yjs (client): excellent performance, rich features, can be integrated with a server adapter (y-websocket) and mirrored events stored on server.
   - Automerge (JS/Rust): offline-first but can be heavy in size without compression.
   - Implement an identifier-based CRDT in Elixir (RGA/LSEQ) for server-side authoritative merging.
3. Integration strategies:
   - Bridge: Let clients run Yjs and sync a canonical text to the server periodically (server stores snapshots and serialized Yjs state). Use `DocumentEvent` to persist Yjs update messages instead of per-char ops.
   - Replace: Implement server-side RGA and change operation format to include element IDs; update client hook to emit identifier-based ops.
4. Migration tools:
   - Store a mapping version in `documents` (e.g., `crdt_state` JSON) and support replaying old positional events into the new CRDT during migration, or provide a migration job to rebuild state.

## Example Checklist for Implementation

- [ ] Add `document_events` table and index
- [ ] Add `snapshot_seq` and `content` fields to `documents` table
- [ ] Implement `CRDT` module (apply, diff)
- [ ] Implement `Documents.apply_operation/3` (persist + broadcast)
- [ ] Implement `SnapshotManager` (create/load snapshots)
- [ ] Implement `ConsistencyManager` (verify/sync)
- [ ] Wire LiveView: mount subscriptions, `update_content`, `handle_info` for operations and presence
- [ ] Add `EditorHook` in `assets/js/hooks` with `phx-update=\"ignore\"`
- [ ] Add tests for CRDT and integration
- [ ] Add DB indexes and monitoring for event growth

## Recommended Next Tasks

- Add batching of operations at the LiveView level (group per 200ms or per logical change) to reduce DB writes.
- Implement event compaction after snapshots (archive or delete preceding events if auditing is not required).
- Replace positional CRDT with an identifier-based CRDT if user experience during concurrency is critical.
- Add monitoring/telemetry for events/sec, snapshot frequency, and divergence occurrences.

## References

- Implementation in repo: see the files listed in "Key Files" above.
- For advanced CRDTs: Yjs (https://yjs.dev), Automerge (https://automerge.org)

---

This SKILL.md documents the pattern used in this repository and the recommended improvements and testing strategies to make collaborative editing production-ready.
