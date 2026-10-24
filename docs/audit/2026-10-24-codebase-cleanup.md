# PSC codebase cleanup review

**Date:** 2026-10-24
**Scope:** `lib/`, `test/`, `assets/js/`, `assets/css/`, `priv/`, `scripts/`, `config/` (excluding `deps/`, `_build/`, `node_modules/`, `assets/vendor/`)
**Goal:** identify the largest files and the places where one file carries several responsibilities. No code was changed during the audit. A follow-up fixed the §3.1.1 editor findings; see the status note there.

## Method

- Total line counts use `(Get-Content file).Count` (blank lines included).
- Function counts use `Select-String` for `^  def ` / `^  defp `, plus `handle_event` / `handle_info` counts.
- The two editor LiveViews, `Psc.Canvas`, the agent modules, layouts, settings, catalog, and the largest tests were read directly.
- Line ranges below are current as of this review.

## 1. Where the code lives

| Area | Files | Lines |
|---|---:|---:|
| `lib/` (all `.ex`) | 121 | 22,334 |
| `lib/psc/` (contexts + schemas) | 39 | 4,758 |
| `lib/psc_web/live/` (LiveViews) | 14 | 6,485 |
| `lib/psc_web/components/` | 51 | 9,867 |
| `lib/psc_web/components/ui/` (SaladUI) | 41 | 7,786 |
| `test/` (ExUnit `.exs`) | 36 | 6,470 |
| `test/e2e/tests/` (Playwright) | 11 | 2,353 |
| `assets/js/` | 36 | 8,221 |
| `assets/css/` | 2 | 715 |

The two editor LiveViews alone are **4,175 lines — 64% of all LiveView code**. The `Psc.Canvas` context is **19% of `lib/psc`**. Most of `components/ui` and `assets/js/ui` is the SaladUI component library, not application code.

## 2. Largest application files

| # | File | Lines | Signals | Main responsibilities | Recommendation | Risk |
|---:|---|---:|---|---|---|---|
| 1 | `lib/psc_web/live/unstr_canvas_live/editor.ex` | 2,953 | 60 `def`, 65 `defp`, 43 `handle_event`, 14 `handle_info`, 7 `~H`, render ≈1,014 lines | access, header, grid, structure editing, presence, autosave, sharing, notes, agent chat, tabs | split by panel; extract notes and agent first | high |
| 2 | `lib/psc_web/live/canvas_layout_live/editor.ex` | 1,222 | 33 `def`, 28 `defp`, 31 `handle_event`, render ≈624 lines | draft layout state, grid structure, cell metadata, accents, notes, save/cancel, sharing, public | extract pure draft helpers, then render components | medium |
| 3 | `lib/psc/canvas.ex` | 898 | ≈45 public functions | built-in data, template CRUD, catalog, instantiation, canvas CRUD, event sourcing | split into sub-contexts behind a facade | medium-high |
| 4 | `lib/psc_web/components/layouts.ex` | 500 | 4 public components | app shell, admin shell, flash, theme toggle, nav helpers | split app/admin/flash/theme | low |
| 5 | `lib/psc/accounts.ex` | 470 | ≈30 public functions | auth, tokens, email/password, admin roles/bootstrap, agent key, sudo | extract admin/bootstrap and agent settings | medium |
| 6 | `lib/psc/agent/turn.ex` | 440 | 4 public, 21 private | turn lifecycle, event consumption, replay, prompt rendering, event mapping | extract event mapper and prompt builder | medium |
| 7 | `lib/psc_web/live/catalog_live/index.ex` | 398 | 6 events, render ≈225 lines | search, cards, modal, use/fork, preview helpers | extract card/modal components | low |
| 8 | `lib/psc_web/live/user_live/settings.ex` | 391 | 6 events, render ≈190 lines | email, password, agent key/model forms | extract form components; move model parsing | low |
| 9 | `lib/psc/agent.ex` | 343 | ≈30 public functions | config, sessions, messages, pruning | split config/sessions/messages/pruning | medium |
| 10 | `lib/psc_web/live/canvas_layout_live/index.ex` | 333 | render ≈215 lines | template library, share form, delete confirm, instantiate | extract `TemplateCard` | low |
| 11 | `lib/psc_web/live/unstr_canvas_live/index.ex` | 330 | render ≈190 lines | canvas creation picker + canvas cards | extract `CanvasCard` / `TemplatePicker` | low |
| 12 | `lib/psc/canvas/unstr_canvas_crdt.ex` | 303 | 1 public reducer + helpers | canvas operation reducer | cohesive; leave unless grid extraction needs it | low |
| 13 | `assets/js/hooks/cell_focus.js` | 362 | 1 hook | desktop click, mobile fullscreen, swipe, history/hash, keyboard | split mobile fullscreen/gestures | medium |

### Largest tests

| File | Lines | Describe blocks | Notes |
|---|---:|---:|---|
| `test/e2e/tests/canvas.spec.ts` | 1,095 | 13 | mixes canvas editor, mobile, tabs, status pill, template designer, accents, library, flash placement |
| `test/psc/canvas_test.exs` | 961 | 9 | template CRUD, catalog, sharing, validation, instantiation, creation, structure ops, event pruning |
| `test/psc_web/live/unstr_canvas_live_test.exs` | 731 | 2 | index + editor |
| `test/psc_web/live/canvas_layout_live_test.exs` | 680 | 2 | library + designer |

### Large library/vendored files (not cleanup targets)

| File | Lines | Nature |
|---|---:|---|
| `assets/js/ui/components/toast.js` | 954 | SaladUI runtime |
| `lib/psc_web/components/ui/sidebar.ex` | 768 | SaladUI component (`@moduledoc false`) |
| `assets/js/ui/core/component.js` | 659 | SaladUI runtime |
| `assets/js/ui/components/select.js` | 583 | SaladUI runtime |
| `lib/psc_web/components/ui/dropdown_menu.ex` | 509 | SaladUI component |
| `lib/psc_web/components/core_components.ex` | 584 | Phoenix-generated core components, heavily used |
| `assets/css/app.css` | 676 | Tailwind entry: theme, base, animations, canvas styles |
| `lib/psc_web/components/ui/toast.ex` | 441 | SaladUI component |

## 3. Detailed findings

### 3.1 `PscWeb.UnstrCanvasLive.Editor` — the main god object

Current line map:

| Lines | Responsibility |
|---:|---|
| 1–50 | module setup, tab definitions, save intervals |
| 51–123 | `mount/3`: access check, load snapshot, ~40 assigns |
| 124–177 | PubSub subscribe, presence tracking, operation dispatch |
| 178–400 | agent chat events: new/send/refresh/menu/rename/duplicate/delete/select/stop |
| 401–616 | sharing, name/description updates, cell updates |
| 620–850 | structure editing events: toggle, add/remove row/column, labels, accents, cell label/fields |
| 851–976 | agent loading/subscription/helpers |
| 977–1180 | note list/load/select/create/delete/update/render, note presence |
| 1181–1318 | agent stream `handle_info`, canvas operation `handle_info` |
| 1319–1500 | idle/periodic save, note save, note operations, presence diff |
| 1501–1572 | structure/cell helper functions |
| 1573–2200 | `render/1`: app shell, header, share dialog, remove dialog, tabs, editor grid |
| 2201–2222 | notes panel |
| 2223–2548 | agent panel |
| 2549–2580 | Analysis placeholder |
| 2588–2953 | status source, notes view, header actions, active users, tab strip |

It mixes at least **nine** responsibilities:

1. Access control and mount/load.
2. Canvas header (name, description, presence, share, status).
3. Grid rendering and Markdown cell editing.
4. Structure editing (row/column/cell field operations).
5. Presence tracking and display.
6. Autosave, snapshot folding, status statistics.
7. Notes (list, editor, per-note presence, note autosave).
8. Agent chat (sessions, streaming, tool cards, menus).
9. Tab shell and placeholders.

Suggested seams:

- `PscWeb.UnstrCanvasLive.Notes` — a LiveComponent owning note state, note PubSub, note presence, note autosave, and `notes_view/1`. Roughly 350–450 lines leave the editor.
- `PscWeb.UnstrCanvasLive.Agent` — a LiveComponent/module owning sessions, streaming events, tool rendering, menus. Roughly 550–700 lines leave the editor.
- `PscWeb.UnstrCanvasLive.Grid` + shared grid components — grid rendering, structure controls, cell field editor. Roughly 450–550 lines.
- `PscWeb.UnstrCanvasLive.Header` — name/description/presence/status/share. Roughly 150–200 lines.
- `Psc.Canvas.Autosave` or `UnstrCanvasLive.SaveState` — idle/periodic timers, save stats, snapshot calls. Roughly 120–150 lines.
- The editor keeps mount/access, tab selection, and delegation: roughly 300–400 lines.

**Sequencing:** extract the Notes panel first (self-contained, already has dedicated tests), then Agent (also self-contained, with `canvas_agent_tab_test.exs`), then the grid/structure UI. Autosave and presence should be last because they touch the event log and every panel.

**Caveat:** a LiveComponent adds a process boundary and changes `handle_info`/PubSub ownership. If that is too risky, start with function components and pure helper modules while keeping events in the parent; convert Notes/Agent to LiveComponents only after the render is split.

### 3.1.1 Deep inspection — `PscWeb.UnstrCanvasLive.Editor`

Second pass over the whole file, plus the contracts it depends on (`Psc.Canvas`, `UnstrCanvasCRDT`, `Psc.Notes`, `Psc.Agent.Turn`, `PscWeb.Presence`) and the three LiveView test files. Line numbers are current and refer to `lib/psc_web/live/unstr_canvas_live/editor.ex` unless stated otherwise.

**Shape.** 2,953 lines / 118 KB. 60 `def` — 43 `handle_event` clauses over 42 event names and 14 `handle_info` — 65 `defp`, 40 socket assigns, 19 `attr` blocks, 26 `@impl true`, 8 `Logger` calls. `render/1` is lines 1572–2589 (1,017 lines, 34% of the file) and contains six private function components (`cell_field_editor`, `notes_view`, `header_actions`, `active_users_list`, `tab_strip`, `tab_bar`) plus five imported/shared ones (`status_pill`, `share_button`, `share_dialog`, `markdown_editor`, `accent_bar`). There is no `terminate/2`.

The first line map (3.1) is directionally right but lumps the note events (405–529) into the share bucket and splits the render at panel boundaries that do not match where the components are defined. A corrected map:

| Lines | Responsibility |
|---:|---|
| 1–48 | module setup, save intervals, initial stats, tab table, `find_tab/1` |
| 50–122 | `mount/3`: access check, content load, 40 assigns |
| 124–175 | canvas PubSub subscribe, presence track, `process_operation/2` |
| 177–398 | agent chat events: new/send/refresh/menu/rename/duplicate/delete/select/stop (11) |
| 400–529 | share-open, tab selection, note select/create/delete/title/content/render (7) |
| 531–570 | share and remove access (3) |
| 571–625 | name, description, `update_cell` (4 clauses) |
| 626–788 | structure editing: toggle/add/remove/labels/accents/cell label/fields/titles (16) |
| 789–850 | `render_field`, structure id/remove/content helpers |
| 851–977 | agent helpers: scope refresh, load, subscribe, refs, dates, turn count |
| 979–1006 | `handle_params/3`: tab, focus cell, notes/agent load |
| 1008–1181 | notes state: list, scratchpad, open, note presence, resync, remote apply |
| 1182–1410 | `handle_info/2`: agent stream (6), canvas ops (2), presence, canvas/note idle save, note ops (2), periodic save |
| 1412–1479 | `save_cells`, `save_note_content`, presence refresh |
| 1481–1570 | grid width math, structure helpers, shared cell field component, presence labels |
| 1572–2589 | `render/1`: shell, header, dialogs, editor grid, notes panel, agent panel, placeholder, tab bar |
| 2591–2953 | status source, notes view, note snippets/editors, header actions, presence list, tab strip/bar |

**Findings.**

| # | Severity | Lines | Finding | Confidence |
|---:|---|---|---|---:|
| 1 | 🔴 High | 1319–1338, 1340–1363, 1387–1411, 1412–1473 | A failed save is immediately overwritten to `:saved`; the fingerprint also advances, so it is not retried until another edit | 10/10 |
| 2 | 🔴 High | 1219–1262 | The 4-tuple canvas operation handler gates on `user_id`, not `client_id`; a second tab of the same user ignores every remote edit | 9/10 |
| 3 | 🟠 Medium | 178–198, 312–351, 361–380, 382–398 | Starting/selecting/deleting a chat leaves a running turn alive; `agent_new` also leaves the composer permanently disabled | 9/10 |
| 4 | 🟠 Medium | 382–398, 2393–2401 | `agent_stop` does not clear `agent_phase`; the status line stays stuck | 10/10 |
| 5 | 🟠 Medium | 979–1006, 870–900, `turn.ex:136–142` | Switching to the Agent tab mid-turn replaces the in-memory transcript with the DB rows, dropping already-streamed deltas | 9/10 |
| 6 | 🟠 Medium | 1572–2589, 2765, 2680 | All panels render on every update; every canvas keystroke re-parses the note Markdown and every note snippet | 9/10 |
| 7 | 🟡 Medium-low | 142–175, 1324–1328, 1390–1394, 231–233, 298, 320, 476 | Persistence errors are ignored or pattern-matched; a DB hiccup crashes the LiveView or silently diverges clients | 9/10 |
| 8 | 🟡 Low | 147–153, 1225–1236, 1271–1276 | `Logger.debug` interpolates `inspect(operation)` and the whole cells map even when debug is off | 10/10 |
| 9 | 🟡 Low | 1105–1116, 1387–1411 | Switching notes cancels the idle save; that note's event tail stays unfolded until it is edited and saved again | 9/10 |
| 10 | 🟡 Low | 2075–2082, 2110–2117 | Cell-label and field-title inputs have no `phx-debounce` (row/column labels use 300 ms) | 9/10 |
| 11 | 🟡 Low | 2747–2755 | Deleting a note has no confirmation, unlike row/column removal | 10/10 |
| 12 | ⚪ Info | 1263–1306 | The legacy 3-tuple operation handler duplicates the 4-tuple one; only tests/context calls produce that shape | 9/10 |
| 13 | ⚪ Info | 51–122 | `mount/3` calls `Repo.get/2` with the raw URL id; a non-UUID path raises `Ecto.Query.CastError` instead of redirecting | 8/10 |

**Status (follow-up, 2026-10-24).** All 13 findings are fixed and covered by tests where the behavior is observable:

- Findings 1 and 7: `PscWeb.UnstrCanvasLive.Save.commit/3` owns the outcome; a failed write stays `:unsaved`, keeps the fingerprint and is retried. Context saves return `{:error, :not_found}` for a deleted row and `{:error, changeset}` for a stale update instead of raising.
- Finding 2 and 12: canvas broadcasts compare `client_id`; the legacy 3-tuple shape funnels through the same helper.
- Findings 3, 4 and 5: one `stop_running_turn/1` terminates the task, cancels the streaming message (unwrapping the context result) and clears the phase from new/select/delete/stop; `load_agent/1` keeps the in-memory transcript for the same session.
- Finding 6: `note_html` is cached in assigns and note snippets are derived in `reload_notes/1`, not during render.
- Finding 8: the per-operation debug logs are zero-arity functions.
- Finding 9: `leave_note/1` flushes the note before cancelling its timer; a failed note save retries while the note still exists.
- Findings 10, 11 and 13: cell label/title inputs debounce at 300 ms, note deletion asks for confirmation, and a malformed canvas id renders the "Canvas not found" redirect.
- Follow-up report (clicking a cell and out without typing dirtied the canvas): `markdown_field.js` sends `update_cell` only when the value differs from the last synced value, and `process_operation/2` ignores any operation whose CRDT result equals the current cells. No event row is written and the pill stays Saved.

Regression coverage lives in `test/psc_web/live/unstr_canvas_editor_regression_test.exs` and the four new cases in `test/psc_web/live/canvas_agent_tab_test.exs`. `mix verify` passes (402 tests), and the affected Playwright cases in `test/e2e/tests/notes.spec.ts` and `test/e2e/tests/canvas.spec.ts` pass (note-deletion confirmation and no-op cell blur).

**1. Save failures are reported as saved, and are not retried.** All three triggers run the save helper and then unconditionally assign `:saved` and the new fingerprint:

- `:idle_save` (1319–1338) — `save_cells/1` → `assign(:last_saved_cells, socket.assigns.cells)` → `assign(:save_state, :saved)`
- `:periodic_save` (1387–1411) — same pipeline
- `:note_idle_save` (1340–1363) — `save_note_content/2` → `assign(:note_last_saved_content, ...)` → `assign(:note_save_state, :saved)`

`save_cells/1` (1412–1444) and `save_note_content/2` (1445–1473) already assign `:unsaved` on `{:error, _}`, so the caller undoes the only signal. Because the fingerprint advances anyway, the next tick compares equal and does nothing: the comment "the next save will try again" is not what the code does. For notes this also means the event tail is not folded/pruned. `Canvas.update_unstr_canvas/2` at 1324 and 1390 is ignored for the same reason.

Small, testable fix: have the helpers return `{:ok, socket}` / `{:error, socket}`, advance the marker and set `:saved` only on `:ok`, and leave `:unsaved` (plus the next timer tick) on error.

**2. Same-user, second-tab canvas edits are dropped.** The broadcast carries `{user_id, client_id, operation, seq}` (`canvas.ex:812–830`), and the handler receives both, but the guard at 1221 is `user_id != socket.assigns.user_id`. Another tab of the same user has a different `client_id` and the same `user_id`, so it treats the operation as its own echo and skips it; the tab only catches up on reload. The note path (1365–1376) compares `client_id` and has a regression test (`note_collaboration_test.exs:119`); the canvas path has no equivalent test. Fix: compare `client_id` in the 4-tuple clause, and keep the user comparison only for the legacy 3-tuple shape.

**3. Agent turn lifecycle leaks.** `subscribe_agent/2` (902–914) unsubscribes the previous session topic. `agent_new/1` (178–198) creates a new session and subscribes it but does not clear `agent_turn_pid` or `agent_phase`; the old turn's `{:completed}`/`{:failed}` now goes nowhere, so the pid stays set and the composer stays disabled with "Wait for the current answer to finish" for the life of the socket. `agent_select` (361–380) and `agent_delete` (312–351) clear the pid without terminating the task, so the old turn keeps consuming tokens and writing to a topic nobody reads, and a second turn can be started concurrently. `agent_stop` (382–398) clears the pid but not the phase.

Fix: one `stop_turn/1` that terminates the `Task.Supervisor` child and clears `agent_turn_pid` + `agent_phase`, called by stop/new/select/delete (or intentionally keep the pid across chats and let completion clear it).

**4. Tab switch resets an in-flight transcript.** `select_tab` patches the URL (406–409); `handle_params/3` then calls `load_agent/1` (870–900), which replaces `agent_messages` with `Psc.Agent.list_messages/1`. `Psc.Agent.Turn` broadcasts `{:delta, ...}` but persists only the final message (`turn.ex:136–142`, `272–283`), so deltas already displayed are lost and the remaining ones append to an empty bubble until `{:completed}` replaces the content. Display-only, but a reconnect mid-turn has the same effect. Keep the in-memory list when the session is streaming, or persist deltas (with pruning) if resumability is wanted.

**5. Render cost is dominated by hidden panels.** Every panel is rendered and hidden (intentional, 1730–1733), so a canvas cell edit — which assigns `cells` — re-runs `Markdown.render(@note_content, ...)` at 2765 and `note_snippet/1` for every note at 2680, even on the Editor tab. A remote note operation re-renders too (1162–1177). On a long note/canvas every keystroke pays for a Markdown parse. Cache `note_html` in assigns when the content changes and precompute snippets when loading notes.

**6. Error handling.** `process_operation/2` (142–175) applies locally even if the event insert returns `{:error, changeset}`; name/description updates discard their result (1324, 1390); `agent_send` (231–233), `agent_duplicate` (298), `agent_delete` (320), and `update_note_title` (476) pattern-match `{:ok, _}`. A transient DB error on the free tier (2 connections) should flash and retry, not crash the LiveView.

**7. Smaller items.**

- The legacy 3-tuple canvas handler (1263–1306) is a line-for-line duplicate of 1219–1262; collapse both into one private `apply_remote_operation/4` with an optional client id.
- Eight `Logger.debug` calls build their message eagerly; two run per operation and include the whole cells map (147–153, 1225–1236, 1271–1276). Use a zero-arity function or log op type + seq.
- `leave_note/1` cancels `note_idle_timer_ref` (1105–1116) and `periodic_save` is canvas-only, so a note edited and abandoned within 1.5 s keeps its event tail. Content is replay-safe, but it counts against the ~10k-row ceiling. Fold on leave or include the open note in the periodic tick.
- Cell label (2075–2082) and field title (2110–2117) inputs have no debounce; row/column labels use 300 ms (1857, 1958), cell fields 150 ms (1543). One event row per keystroke is the current behavior.
- The note Delete button (2747–2755) has no confirmation. Row/column removal does (1692–1726).
- `mount/3` calls `Repo.get/2` with the raw URL id. Ecto raises `Ecto.Query.CastError` when the value cannot be cast, so `/canvas/not-a-uuid` is a 500 rather than the "Canvas not found" redirect at 114–121. Guard with `Ecto.UUID.cast/1`; no test covers it.

**Revised extraction sequence.** The 3.1 caveat stands; this ordering reduces risk while keeping the test hooks intact.

1. **Pure/function-component pass (no process change).** Move `status_source` and the save-stat bookkeeping into `PscWeb.UnstrCanvasLive.SaveStatus`; move `active_usernames/1`, `active_users_label/1`, `active_users_compact_label/1`, `active_user_count/1`, `note_editors/2`, `note_editors_label/1` into `PscWeb.UnstrCanvasLive.PresenceLabels`; move `turn_count/1`, `agent_date/1`, `agent_relative_time/1`, `agent_refs/1` and the cell/other split into `PscWeb.UnstrCanvasLive.AgentFormat`. Then move the six private function components into `UnstrCanvasLive.Components.*`. Events stay in the parent, IDs stay identical. Roughly 450 lines (components plus helpers) leave the file for little risk.
2. **Agent panel (function component, not a LiveComponent).** LiveComponents run in the parent LiveView process and have no `handle_info` callback, so they cannot own the session PubSub subscription or the turn timers. A nested LiveView would add routing/session/test plumbing. Move the render and formatting helpers to `UnstrCanvasLive.AgentPanel`; keep the 11 assigns, 11 events, 6 `handle_info` clauses and `phx-window-focus` in the parent.
3. **Notes.** Extract the render first. A full LiveComponent costs more because the header status pill reads `note_save_state`; it needs either a `send_update/2` to a small status LiveComponent or the pill moving into the notes panel. Only take that step if the note panel keeps growing.
4. **Grid/structure.** Extract row/column/cell header function components first (events remain `phx-click`/`phx-change` to the parent), then share the pure add/remove/label/accent semantics with `CanvasLayoutLive.Editor` as described in 3.4.
5. **Autosave.** Extract timers, fingerprint, save, stats and retry into one module; fixing finding 1 while moving the code is cheaper than fixing it twice. Add `terminate/2` for a best-effort flush, with the event log as the documented recovery path.

**Tests missing around the above:** same-user second canvas tab (mirror `note_collaboration_test.exs:119`), failed save keeps `:unsaved` and retries, `agent_stop`/`agent_new` during a turn, note switch inside the idle window, and a malformed canvas id.

**Refactor status (2026-10-25).** Slices 1–3 and the agent render split are implemented:

| Module | Kind | Lines |
|---|---|---:|
| `editor.ex` | LiveView coordinator | 1,717 (from 3,044) |
| `header.ex` | function components | 214 |
| `tabs.ex` | function components + tab table | 89 |
| `grid.ex` | function components | 536 |
| `notes_panel.ex` | function components + note formatting | 226 |
| `agent_panel.ex` | function component (render + formatting) | 382 |
| `save.ex` | plain module | 62 |

The parent keeps canvas state, operations, save timers, presence, notes state and the agent state/subscription. All test IDs and `phx-hook` bindings are unchanged. `mix verify` passes (403 tests) and the full Playwright suite passes (60 tests). The Notes LiveComponent remains deferred: the header status pill would need `send_update/2` or a third status component, which is the complexity this refactor was meant to avoid.

**Bento follow-up (2026-10-25).** The bento layout mode (ADR-035 to ADR-038, `docs/spec/bento.md`) landed on top of the split:

- `Psc.Canvas.Structure` is the one module that knows a structure's shape; it also owns clamping, `next_slot/1`, `neighbours/2` and the reserved cell keys (the CRDT now delegates to it).
- The shared cell body moved to `UnstrCanvasLive.Cell`, so the table grid and the bento board cannot drift.
- New modules: `UnstrCanvasLive.Bento` (board), `CanvasLayoutLive.BentoEditor` (designer) and the `BentoBoard` JS hook.
- The window was 20 lines longer after the split (`editor.ex` 1,717), and the render dispatch is a two-line `Structure.bento?/1` branch.

### 3.2 `PscWeb.CanvasLayoutLive.Editor`

Current line map:

| Lines | Responsibility |
|---:|---|
| 1–80 | mount/access, new-vs-existing draft |
| 81–170 | grid structure events |
| 171–198 | accent events |
| 199–284 | cell metadata events (label, fields, titles, defaults) |
| 285–402 | save, share, dirty/cancel/leave |
| 403–597 | layout-map helpers: normalize, add/remove, labels, accents, notes |
| 598–1221 | one `render/1` (~624 lines) |

The render contains the whole page: share dialog, page actions, name/description/public form, Notes section, Grid section, Analysis/Agent placeholders, and the discard dialog.

Suggested seams:

- `Psc.Canvas.LayoutDraft` — pure functions for `normalize_layout_map`, add/remove row/column, labels, accents, notes mode, template notes. This is the highest-value extraction: it is pure, testable, and removes ~200 lines from the LiveView.
- `PscWeb.CanvasLayoutLive.TemplateForm` — name/description/public/save/cancel.
- `PscWeb.CanvasLayoutLive.NotesSection` — notes mode, note list, Markdown editors.
- `PscWeb.CanvasLayoutLive.GridEditor` — the grid table and cell editors.
- The LiveView keeps mount/access, save/share, and dirty tracking: roughly 250 lines.

Risk is lower than the canvas editor because there is no CRDT, PubSub, or presence.

### 3.3 `Psc.Canvas` — a context with six jobs

| Lines | Responsibility |
|---:|---|
| 18–138 | built-in PSC cell data, `psc_cells`, `blank_cells`, `field_title` |
| 139–176 | legacy template CRUD (`list/get/create/update/delete_canvas_layout`) |
| 177–407 | template CRUD, listing, sharing, access |
| 408–570 | catalog queries, publish/unpublish, fork |
| 571–638 | instantiation and template-to-canvas copy |
| 639–766 | canvas CRUD, sharing, access |
| 767–898 | canvas event sourcing: replay, append, save, prune, sweep |

Suggested split, keeping `Psc.Canvas` as a facade:

- `Psc.Canvas.Builtins` — PSC/scratchpad layout maps, seed, `psc_cells`, `blank_cells`.
- `Psc.Canvas.Templates` — template CRUD, sharing, access.
- `Psc.Canvas.Catalog` — public queries, publish/unpublish, fork.
- `Psc.Canvas.Instantiation` — `instantiate_template/3`, cell transformation, use count.
- `Psc.Canvas.Canvases` — canvas CRUD, sharing, access.
- `Psc.Canvas.Events` — `get_unstr_canvas_content`, `apply_unstr_canvas_operation`, `save_unstr_canvas_content_to_db`, `sweep_folded_events`, sequence helper.

Start with `Builtins` and `Events`: both are self-contained and have clear tests. Keep the facade so call sites do not change.

**Dead/duplicate API found in `Psc.Canvas`:**

- `list_canvas_layouts/0` — no callers in `lib/` or `test/`; only docs/history mention it. It is also unscoped. Remove.
- `update_canvas_layout/2`, `delete_canvas_layout/1` — no callers; superseded by `update_template/2`, `delete_template/1`. Remove.
- `create_canvas_layout/1` — only used by the test fixture's authorless path. `create_template(nil, attrs)` is equivalent; update the fixture and remove.
- `get_canvas_layout/1` — duplicates `get_template_with_author/1` minus the author preload. Unify on the preloaded version to avoid `NotLoaded` surprises.
- Two naming generations (`canvas_layout` vs `template`) run through the context, the fixture, the library LiveView, and the catalog. Pick `template` consistently.

### 3.4 Duplicated grid/structure UI

The designer grid (≈334 lines) and the canvas structure editing UI (≈454 lines) render the same concepts twice:

- row/column header with label input, accent swatch, inline accent palette, remove ×
- cell label input
- per-field section-title input, default/value input, remove ×
- add-field form
- fixed row-label column

The data sources differ: the designer mutates a local `layout_map`; the canvas dispatches CRDT operations. A shared function component can take the cell data plus event names/attrs:

- `PscWeb.Components.CanvasGrid` — table, header, row header, cell shell.
- `PscWeb.Components.AccentPicker` — swatch + palette.
- `PscWeb.Components.CellFieldEditor` — title/value/remove row.

This is a medium-risk refactor because the test hooks (`#cell-card-<key>`, `#accent-bar-*`, `#cell-<key>-label`, `#md-<key>-<field>`) are a contract. Keep the IDs identical.

There is also a domain-level duplication: `Psc.Canvas.UnstrCanvasCRDT` and the designer's private helpers implement the same row/column add/remove/label/accent semantics on the same `rows/columns/layout` shape. A shared `Psc.Canvas.Grid` module (pure, with a cell-factory callback) could back both.

### 3.5 Markdown editing duplication and a dead hook

- `assets/js/hooks/markdown_editor_hook.js` (190 lines) is the rich editor: configurable events, preview/textarea switch, patch-based remote updates with caret preservation, auto-grow.
- `assets/js/hooks/markdown_field.js` (83 lines) is a simpler duplicate for canvas cells: hardcoded `render_field`/`field_rendered`/`cell_updated`, 500 ms debounce, no patch/caret logic.
- `assets/js/hooks/cell_hook.js` (46 lines) is imported and registered in `app.js`, but no element uses `phx-hook="CellHook"`. It is dead.

Recommendation: delete `CellHook`; unify `MarkdownField` on the `MarkdownEditorHook` contract (or extract the shared preview/debounce/remote-update helpers) so the two editors cannot drift further.

### 3.6 Other multi-responsibility files

- **`Psc.Agent` (343)** — configuration (`enabled?`, `model_for`, `api_key`), session CRUD, message CRUD, and retention/pruning. Split `Psc.Agent.Config`, `Psc.Agent.Sessions`, `Psc.Agent.Messages`, `Psc.Agent.Pruning`; keep `Psc.Agent` as a facade.
- **`Psc.Agent.Turn` (440)** — turn lifecycle, Jido event consumption, replay for tests, prompt rendering, event-field mapping, `safe`/`unwrap` helpers. Extract `Psc.Agent.EventMapper` and `Psc.Agent.Prompt`.
- **`PscWeb.Components.Layouts` (500)** — `app/1` (app shell/header/nav/mobile menu), `admin/1` (Backpex shell), `flash_group/1`, `theme_toggle/1`, nav helpers. Split into `Layouts.App`, `Layouts.Admin`, `Layouts.Flash`, `Layouts.ThemeToggle`.
- **`CatalogLive.Index` (398)** — search state, card grid, template modal, use/fork actions, preview/notes helpers. Extract `CatalogCard`, `TemplateModal`, and `PreviewSection`.
- **`UserLive.Settings` (391)** — three independent forms (email, password, agent key/model) plus token-confirmation mount and model parsing helpers. Extract `EmailForm`, `PasswordForm`, `AgentKeyForm`; move `build_agent_model/agent_provider/agent_model_id/default_agent_model` to `Psc.Agent` (the deployment-model lookup already exists there).
- **`Psc.Accounts` (470)** — registration/login/tokens/email/password, admin roles, admin bootstrap, agent key, sudo. Extract `Psc.Accounts.Admin` / `Bootstrap`; this is lower priority because it follows the standard Phoenix auth shape.
- **`assets/js/hooks/cell_focus.js` (362)** — desktop click-to-edit, mobile fullscreen, swipe navigation, URL hash/history, Escape handling. Split the mobile fullscreen/gesture state machine into a helper module; keep the hook as the event binder.
- **`assets/css/app.css` (676)** — theme tokens, base layer, animations, canvas-specific layout, tab styles. It is still manageable; if it grows, split with `@import` files (`theme.css`, `animations.css`, `canvas.css`).

### 3.7 Tests

- **`test/e2e/tests/canvas.spec.ts` (1,095 / 13 describes)** — split by feature: `canvas-editor.spec.ts`, `canvas-mobile.spec.ts`, `template-designer.spec.ts`, `canvas-layout.spec.ts` (or similar). Move shared login/setup helpers to a fixture.
- **`test/psc/canvas_test.exs` (961 / 9 describes)** — split into `template_test.exs`, `catalog_test.exs`, `instantiation_test.exs`, `canvas_structure_test.exs`, `canvas_events_test.exs`.
- **`test/psc_web/live/unstr_canvas_live_test.exs` (731)** — split index vs editor.
- **`test/psc_web/live/canvas_layout_live_test.exs` (680)** — split library vs designer.

These are mechanical moves; do them after the production code is split so test files track the new modules.

## 4. What not to split

- `lib/psc_web/components/ui/*` (41 files, 7,786 lines) is the SaladUI component library (`@moduledoc false`). `sidebar.ex` (768) and `dropdown_menu.ex` (509) are large but cohesive components, not god objects.
- `assets/js/ui/*` (~8,221 lines) is the SaladUI runtime; `toast.js` (954) and `component.js` (659) are library code.
- `assets/vendor/*` (`daisyui.js` 885, `tw-animate.css` 529) is vendored.
- `lib/psc_web/components/core_components.ex` (584) is Phoenix-generated and heavily used (`<.icon>` alone has 61 call sites). Do not split it; only prune genuinely unused helpers after checking call sites (e.g., `show/2` and `hide/2` currently have none).

## 5. Suggested cleanup sequence

### Phase 0 — dead code (low risk, quick wins)

1. Remove `Psc.Canvas.list_canvas_layouts/0`, `update_canvas_layout/2`, `delete_canvas_layout/1`.
2. Update the template fixture to call `create_template(nil, attrs)` and remove `create_canvas_layout/1`.
3. Unify `get_canvas_layout/1` on `get_template_with_author/1`.
4. Remove the unused `CellHook` import/registration and file.

### Phase 1 — pure helpers (low risk)

5. Extract `Psc.Canvas.LayoutDraft` from the designer's private helpers.
6. Extract `Psc.Agent.EventMapper` and `Psc.Agent.Prompt` from `Turn`.
7. Extract `Psc.Canvas.Builtins` from `Psc.Canvas`.
8. Extract `Psc.Canvas.Events` from `Psc.Canvas`.

### Phase 2 — render components (low-medium risk)

9. Split the designer `render/1` into `TemplateForm`, `NotesSection`, `GridEditor`, and placeholders.
10. Split the canvas editor `render/1` into `Header`, `Grid`, `NotesPanel`, and `AgentPanel` function components, keeping events in the parent.
11. Extract shared `CanvasGrid`, `AccentPicker`, and `CellFieldEditor` components.
12. Split `Layouts`, `CatalogLive.Index`, and `UserLive.Settings` render code.

### Phase 3 — stateful panels (medium risk)

13. Convert the Notes panel to a LiveComponent (or a delegated module) with its own PubSub/presence/autosave.
14. Convert the Agent panel similarly.
15. Extract autosave/status into `Psc.Canvas.Autosave` or `UnstrCanvasLive.SaveState`.

### Phase 4 — contexts and tests (medium-high risk)

16. Split `Psc.Canvas` into `Templates`, `Catalog`, `Instantiation`, `Canvases`, `Events`, `Builtins`, with a facade.
17. Split `Psc.Agent`, `Psc.Accounts`, and `Layouts`.
18. Split the large ExUnit and Playwright files to match.

## 6. Guardrails

- **Test hooks are a contract:** `#canvas-header`, `#canvas-grid`, `#cell-card-<key>`, `#md-<key>-<field>`, `#active-users-tooltip`, `#cell-r1_c1`. Preserve them through any render extraction.
- **Event sourcing:** never move `snapshot_seq` backwards; never delete unfolded events; save first, then prune. `Psc.Canvas.Events` must keep the current transaction/ordering semantics.
- **PubSub:** preserve topics (`unstr_canvas:<id>`, `presence_unstr:<id>`, note topics) and the per-client echo suppression (`client_id`).
- **Agent prompt caching:** the system prompt is constant, tools are listed in a fixed order, and history is replayed append-only. Do not re-serialize `jsonb` when extracting the prompt builder.
- **Canvas semantics:** per-field last-write-wins, template → canvas is a copy, structure edits are available to anyone with access.
- **Verify per phase:** `mix.bat verify` (format, compile with warnings as errors, full tests). Run Playwright for visual/interaction changes.
