# Insights — Content Analysis

## Status: Implemented (deterministic checks + optional AI review)

Insights is the **Analysis** tab of the canvas editor (`?tab=analysis`,
`#canvas-tab-analysis`). It is the first Research Extension from
[`docs/project_proposal.md`](../project_proposal.md); the interaction-level
telemetry extension is separate and is not a dependency.

The tab has two parts:

* **Overview** — eight simple facts rebuilt whenever the tab opens (and on
  **Refresh**). It is not stored.
* **Insights** — a list of collapsible findings. The four heuristics rerun
  when the tab opens and the canvas has changed since the stored report; they
  work with no provider configured. The optional AI review runs only when asked
  and adds attributed findings; when it fails the heuristic findings stay.

## Overview

`Psc.Insights.Overview.build/5` is a pure function of the editor's cells, its
in-memory `touch_map`, the canvas's edit statistics and the editors' names
(the part of the address before the `@`). `Psc.Insights.overview/5` gathers the
inputs and checks access.

| Tile | Source |
|---|---|
| Oldest cell | the earliest `touch_map` entry |
| Most changed | the highest per-cell edit count |
| Longest / shortest | word count of the cells that have text |
| Most / fewest edits | per-user edit counts (fewest needs two editors) |
| Net most added / removed | per-user added minus removed characters |

A tile without data shows "—" and says why. Cell tiles link to
`?tab=editor&cell=<key>`.

### Edit statistics

`unstr_canvases.edit_stats` holds per-cell edit counts and per-user
`edits` / `added` / `removed` totals, plus `since`, when counting started.
`Psc.Canvas.EditStats.fold/4` fills it during a save from the same events the
save prunes, in the same transaction as the snapshot and `touch_map`: one map
per canvas, no rows per edit. It replays every operation on a copy of the old
snapshot so each `update_cell` is compared with the value it replaced; the
characters counted are the edited span (common prefix and suffix excluded). An
edit that leaves the value unchanged is not counted.
`Psc.Canvas.unstr_canvas_edit_stats/1` adds the unsaved tail on the fly.

Counts start with the first save after the column was added. Earlier events
were already pruned, and neither the cells nor the pivots record who wrote what.

## Data model

One row per canvas in `canvas_insights` (`Psc.Insights.Report`, unique
`canvas_id`):

| Column | Meaning |
|---|---|
| `fingerprint` | stable hash of the `cells` map the run used |
| `snapshot_seq` | the canvas snapshot the run started from |
| `computed_at` | when the run finished |
| `mode` | `heuristic` or `assisted` |
| `provider`, `model` | set by an assisted run |
| `ai_fingerprint`, `ai_computed_at` | the cells hash and time of the last AI review |
| `findings` | JSONB array of normalised findings |
| `dismissed` | finding ids hidden for everyone with access |
| `stats` | coverage figures (`cells`, `fields`, `filled`, `empty_cells`, `coverage`) |

One row per canvas, not one row per finding: the deployed free tier caps every
table at 10k rows. Findings are JSON maps with a stable id, kind, severity,
confidence, `cell_keys`, optional `field`, title/detail/evidence, `source` and
attribution. `Psc.Insights.Finding` owns validation; ids are derived from the
kind, cells and field so a re-run preserves dismissals. Cell-level missing
content and canvas-level low coverage share the single `empty` kind.

Staleness uses `unstr_canvases.touch_map`: a per-cell map of the latest
`update_cell` timestamp, folded from the events a save is about to prune (in the
same transaction as the snapshot). It is not part of `cells`, so the CRDT,
templates and previews are unchanged. The editor also updates its in-memory copy
on local and remote operations, so a run immediately after an edit sees it.

## Detectors

`Psc.Insights.Analysis` runs the modules under `lib/psc/insights/detectors/`.
Every detector is a pure function of `Psc.Insights.Context` (`cells`, name,
description, `touch_map`, `now`).

| Detector | Finding | Severity |
|---|---|---|
| `Empty` | a cell with no content; a cell with some fields empty; canvas coverage below 30% (all `empty`) | warning / info |
| `Stale` | a filled cell older than `max(21 days, 2 × the youngest touched cell)` | warning |
| `Duplicate` | two fields with Jaccard similarity ≥ 0.6 over four-word shingles | warning |
| `Relevance` | a cell with ≥ 12 tokens that shares almost no vocabulary with its peers or the description (TF-IDF cosine < 0.08) | info, capped at 3 |

The detectors are explainable and offline: no NLP dependency, no network.
`Relevance` is the noisy one by nature and stays silent unless at least four
cells have enough text.

## AI review

`Psc.Insights.LLM` performs one non-streaming completion through the user's own
provider connection (`Psc.Agent.Connections`), not the ReAct loop of the Agent
tab. It asks for one JSON object, validates every finding (`contradiction`,
`relevance`, `empty`, `duplicate` only; a legacy `coverage` answer is folded
into `empty`), drops unknown cell keys, caps the output at eight findings and
labels every result with provider and model. The
prompt carries the canvas title, description and cell text; the **Include
notes** toggle adds the canvas's Markdown notes as supplemental context (at
most ten notes, truncated).

**Run AI review** and the toggle are shown only to a user with a connection.
The toggle is off by default and is read per run. A new review replaces the
previous AI findings; a heuristic re-run keeps them, so a paid answer is not
thrown away when the tab reopens. Tests replace the call
with `config :psc, :insights_llm` (a function or `{module, function}` pair); no
test reaches the network.

## Interface

* **Overview** (`#canvas-analysis-overview`): the tiles
  (`#canvas-analysis-tiles`, `#overview-<id>` with ids `oldest`,
  `most_changed`, `longest`, `shortest`, `most_edits`, `fewest_edits`,
  `net_added`, `net_removed`), when counting started
  (`#canvas-analysis-since`) and the coverage line (`#canvas-analysis-coverage`).
  **Refresh** (`#canvas-analysis-refresh`) recounts and reruns the heuristics;
  a "Canvas changed" chip (`#canvas-analysis-changed`) appears after an edit.
* **Insights** (`#canvas-analysis-insights`): the summary
  (`#canvas-analysis-summary`), **Run AI review** (`#canvas-analysis-ai-run`),
  filter chips (`#canvas-analysis-filter-<kind>`,
  `#canvas-analysis-filter-dismissed`) and the findings
  (`#canvas-analysis-findings`). Each finding (`#insight-<sanitised-id>`) is a
  `<details>` row: the summary shows severity, title and source; the body has
  the detail, cell chips and Dismiss/Restore. The row's `open` state is kept on
  the client (`JS.ignore_attributes`), so a re-render does not collapse it.
* A cell chip (`#insight-cell-<finding>-<key>`) navigates to
  `?tab=editor&cell=<key>`, the existing focus contract used by the editor,
  which scrolls to the cell and rings it (`#cell-card-<key>`).
* A stale banner (`#canvas-analysis-stale`) appears when the live `cells`
  fingerprint differs from the last AI review's; the review never reruns on
  its own.
* Dismiss/restore are shared with everyone who can open the canvas; the
  Dismissed filter reviews them.
* **Include notes** (`#canvas-analysis-notes`) appears with a connection and
  adds the canvas's notes to the AI prompt. Without a connection a settings
  hint (`#canvas-analysis-ai-hint`) takes the buttons' place.
* **Copy** (`#canvas-analysis-copy`) copies the overview and the visible
  findings as Markdown from the hidden `#canvas-analysis-report-text`;
  dismissed findings are left out.
* AI progress is announced in `#canvas-analysis-progress`; a failure flashes an
  error and keeps the heuristic findings.

Presence, the save pill and Share already come from the shared canvas header on
non-editor tabs; the panel does not duplicate them. Report changes are not
broadcast: another open tab sees a new run or a dismissal when it next loads
the report.

## Access

Every `Psc.Insights` function takes `current_scope`. The canvas's own rule is
the gate: the author or an account in `shared_with`. The Analysis tab is not a
separate sharing surface.

## Tests

* `test/psc/insights/detectors_test.exs` — detector behaviour on table fixtures.
* `test/psc/insights/overview_test.exs` — the tiles, including missing data.
* `test/psc/canvas/edit_stats_test.exs` — the edited-span count and the fold.
* `test/psc/insights_test.exs` — caching, authorization, dismiss/restore,
  fingerprint/staleness, touch-map and edit-stats fold, overview access.
* `test/psc/insights/llm_test.exs` — prompt, parsing, attribution, provider
  failure, AI findings kept across heuristic re-runs, injected provider call
  (no network).
* `test/psc_web/live/canvas_analysis_test.exs` — overview, heuristics on open,
  cell links, Refresh, AI review on demand, stale banner,
  dismiss/restore/filter, AI gating.
