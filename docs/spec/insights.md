# Insights — Content Analysis

## Status: Implemented (deterministic checks + optional AI review)

Insights is the **Analysis** tab of the canvas editor (`?tab=analysis`,
`#canvas-tab-analysis`). It is the first Research Extension from
[`docs/project_proposal.md`](../project_proposal.md); the interaction-level
telemetry extension is separate and is not a dependency.

The design is deterministic-first. Four heuristics run on the canvas snapshot
and work with no provider configured. The optional AI pass is a second,
explicitly requested phase that appends attributed findings; when it fails the
heuristic report stays.

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
| `findings` | JSONB array of normalised findings |
| `dismissed` | finding ids hidden for everyone with access |
| `stats` | coverage figures (`cells`, `fields`, `filled`, `empty_cells`, `coverage`) |

One row per canvas, not one row per finding: the deployed free tier caps every
table at 10k rows. Findings are JSON maps with a stable id, kind, severity,
confidence, `cell_keys`, optional `field`, title/detail/evidence, `source` and
attribution. `Psc.Insights.Finding` owns validation; ids are derived from the
kind, cells and field so a re-run preserves dismissals.

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
| `Empty` | a cell with no content; a cell with some fields empty; canvas coverage below 30% | warning / info |
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
`relevance`, `coverage`, `duplicate` only), drops unknown cell keys, caps the
output at eight findings and labels every result with provider and model. The
prompt carries the canvas title, description and cell text; the **Include
notes** toggle adds the canvas's Markdown notes as supplemental context (at
most ten notes, truncated).

The toggle is shown only to a user with a connection. It is off by default and
is read per run: turning it on does not silently re-run. Tests replace the call
with `config :psc, :insights_llm` (a function or `{module, function}` pair); no
test reaches the network.

## Interface

* Empty state (`#canvas-analysis-empty`): icon, explanation, **Run analysis**
  (`#canvas-analysis-run`), and a settings link when AI is unavailable.
* Results (`#canvas-analysis-results`): coverage/empty/findings tiles, filter
  chips (`#canvas-analysis-filter-<kind>`, `#canvas-analysis-filter-dismissed`),
  and finding cards (`#insight-<sanitised-id>`).
* A cell chip (`#insight-cell-<key>`) navigates to
  `?tab=editor&cell=<key>`, the existing focus contract used by the editor,
  which scrolls to the cell and rings it (`#cell-card-<key>`).
* A stale banner (`#canvas-analysis-stale`) appears when the live `cells`
  fingerprint differs from the report's; the report is never re-run
  automatically.
* Dismiss/restore are shared with everyone who can open the canvas; the
  Dismissed filter reviews them.
* **Include notes** (`#canvas-analysis-notes`) appears once AI is on and adds
  the canvas's notes to the AI prompt.
* **Copy** (`#canvas-analysis-copy`) copies the visible report as Markdown from
  the hidden `#canvas-analysis-report-text`; dismissed findings are left out.
* AI progress is announced in `#canvas-analysis-progress`; a failure flashes an
  error and keeps the heuristic findings.

Presence, the save pill and Share already come from the shared canvas header on
non-editor tabs; the panel does not duplicate them.

## Access

Every `Psc.Insights` function takes `current_scope`. The canvas's own rule is
the gate: the author or an account in `shared_with`. The Analysis tab is not a
separate sharing surface.

## Tests

* `test/psc/insights/detectors_test.exs` — detector behaviour on table fixtures.
* `test/psc/insights_test.exs` — caching, authorization, dismiss/restore,
  fingerprint/staleness, touch-map fold.
* `test/psc/insights/llm_test.exs` — prompt, parsing, attribution, provider
  failure, injected provider call (no network).
* `test/psc_web/live/canvas_analysis_test.exs` — empty state, run, cell link,
  stale banner, dismiss/restore/filter, AI gating.
