# Development Workflow

This document defines **how** development happens in this repository. It is the operational
workflow for agentic development: a single workflow document that any coding agent reads and
follows. It is deliberately **not** a list of conventions — those live in `AGENTS.md`.

- `DEVELOPMENT.md` — **HOW**: the workflow (this file)
- `AGENTS.md` — **RULES**: conventions every agent must follow
- `docs/spec/` — **WHAT**: one structured spec per feature pillar
- `docs/plans/` — **PLAN**: implementation checklists derived from specs, one file per topic

---

## Philosophy: Agentic Test/Spec Driven Development

Development follows a **spec → plan → implement → verify** loop:

1. **Spec** — a structured document describing *what* to build, including machine-checkable
   acceptance criteria and the verification method for each criterion.
2. **Plan** — an implementation checklist derived from the spec (data model, context API,
   LiveView wiring, test plan). The test plan is derived *from* the acceptance criteria.
3. **Implement** — code written against the plan, with tests written alongside the code.
4. **Verify** — the implementation is proven to work through a fixed verification matrix
   (cheapest first). Evidence is reported **in the chat** for the user to review.

**No full autonomous loops.** Verification is a discrete step with evidence. The agent reports
what was checked, how, and the results. The user reviews the evidence and decides what happens
next. There is no silent auto-retry.

---

## Repository Layout (agentic infrastructure)

```
DEVELOPMENT.md                    # HOW — this workflow document
AGENTS.md                         # RULES — conventions (auth scopes, streams, forms, tests)
docs/spec/                        # WHAT — one structured spec per feature area
  creator.md                      #   canvas template creator/configurator  (stub — empty)
  editor.md                       #   canvas editor                        (stub — empty)
  deltas.md                       #   delta model & versioning             (stub — empty)
  telemetry.md                    #   analytics / interaction capture      (stub — empty)
  analytics.md                    #   analytics derived views              (stub — empty)
  insights.md                     #   insights & content analysis          (has content)
  scratchpad.md                   #   unstructured canvas                  (stub — empty)
  TODO.md                         #   loose follow-up ideas
docs/plans/                       # PLAN — implementation checklists, one file per topic
.github/skills/                   # pattern references (deep-dive how-tos)
  crdt-collaboration/             #   real-time editing pattern (event log, snapshots, consistency)
  architecture-diagram/           #   SVG architecture diagrams
scripts/
  export_chat.exs                 # chat session → markdown audit export
  verify_*.exs                    # backend stress/validity scripts (STUB — see below)
test/
  psc/                            # unit + context tests
  psc_web/                        # LiveView interaction tests
  e2e/                            # Playwright browser regression suite (own package.json)
docs/audit/                       # committed chat exports (full audit trail)
```

---

## The Workflow

### 1. Plan mode

**Input:** a spec from `docs/spec/` (or a feature request).

**Output:** an implementation checklist written to `docs/plans/<topic>.md`, following the
pattern of the existing `crdt_implementation_checklist.md` (see repo memory).
The checklist must include:

- data model (schemas, migrations)
- context module API
- LiveView wiring, JS hooks
- **test plan** — step-by-step, split into small isolated files, derived from the spec's
  acceptance criteria (each criterion maps to at least one test)
- design decisions + pitfalls
- pointers to relevant pattern references (e.g., `crdt-collaboration` if the feature needs
  real-time sync)
file lives in `docs/plans/` and is presented in the chat for review **before**

The plan is presented in the chat for review **before** implementation begins.

### 2. Implement mode

- Follow `AGENTS.md` conventions throughout.
- Implement in dependency order: **migrations → schemas → context → LiveView → templates →
  JS hooks → tests**.
- Write tests alongside the code, not after.
- End with the **verification phase** (below). Verification is part of implement mode — the
  agent does not declare a feature done until it has been verified.

### 3. Verify mode

Run the verification matrix, cheapest first. Report evidence for each step **in the chat**:

| Step | Tool | What it proves |
|---|---|---|
| 0 | `mix verify` | Zero warnings, tests pass — the fast gate |
| 1 | `mix test` (unit/context) | Business logic, changesets, CRDT ops |
| 2 | `mix test` (LiveView) | Component interaction, events, streams, forms |
| 3 | Ad-hoc browser (built-in Chromium tools) | The actual UI flow works — mount, edit, collaborate, version |
| 4 | `npx playwright test` (committed suite) | Regression protection for the future |

Evidence = test output, screenshots, and a short statement of what was checked. The user
reviews and decides next steps. No auto-retry loops.

**Step 0 first, always.** `mix verify` is the gate: it runs `nif.fix`, compiles with
`--warnings-as-errors`, and runs the test suite stopping at the *first* failure. Do not proceed
to the browser steps until it is green.

### Command reference

| Command | Purpose |
|---|---|
| `mix verify` | **Fast gate** — warnings + tests, stops at first failure |
| `mix precommit` | Strict full check (same as verify, plus `deps.unlock --unused`) |
| `mix test` | Full test suite |
| `mix test test/path/to/file_test.exs` | One test file (prefer this while iterating) |
| `mix test test/path/to/file_test.exs:42` | One test at a line |
| `mix nif.fix` | Re-create Windows NIF `.dll` files (runs automatically in the aliases) |
| `mix compile --warnings-as-errors` | Compile only, warnings are errors |
| `mix ecto.gen.migration name` | Generate a migration |

---

## Line endings & formatting

Tracked text files are normalized to **LF** by `.gitattributes` (`* text=auto eol=lf`), matching
the Elixir formatter. `format` is part of both the `verify` and `precommit` aliases.

- `mix verify` runs `format` (rewrites files in place — self-healing).
- `mix precommit` runs `format --check-formatted` (strict, no side effects).
- Check a file's endings with `git ls-files --eol <file>` (`i/lf` = LF in git).
- `rel/overlays/bin/*.bat` are deliberately `eol=crlf` — Windows scripts need CRLF to execute.

**History:** the repository previously had mixed CRLF/LF endings committed with no
`.gitattributes`, so `mix format` rewrote every CRLF file (~6,500 lines of noise per run) and
`--check-formatted` could never pass. It was normalized in a single commit; add that commit's
SHA to `.git-blame-ignore-revs` if you want to preserve blame history. Do not reintroduce CRLF
into tracked text files.

---

## Environment & tooling guide (Windows)

Practical notes on working in this environment. Most were learned the hard way — each entry
records a failure mode and the technique that gets around it.

### Running commands

- **PowerShell blocks the `.ps1` shims** (`mix.ps1`, `npm.ps1`) via execution policy. Use
  `mix.bat`, `npm.cmd`, `npx.cmd`, or wrap in `cmd /c "…"`.
- **PATH is not always consistent between terminal calls.** A command that resolved a moment ago
  can come back *"is not recognized"*. Verify before relying on it: `Get-Command mix.bat`.
  MSYS2 binaries in particular are **not** on PATH by default (see "Toolchain" below).
- **Long git output is paginated** and will hang a command. Always use `git --no-pager log …`,
  `git --no-pager diff …`, `git --no-pager show …`.
- **`sc` is an alias for `Set-Content` in PowerShell.** It does *not* call `sc.exe`, so
  `sc query postgresql-x64-16` silently **creates a file named `query`**. Use `Get-Service` or
  `sc.exe` explicitly.
- **`Set-Content -Encoding utf8` writes a byte-order mark on PowerShell 5.1**, which breaks
  strict JSON parsers (VS Code's task runner, `jq`, Node). To write clean UTF-8:
  ```powershell
  [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))
  ```
  Recovery for an already-BOM'd file: any editor save through `replace_string_in_file` rewrites
  it without the BOM.

### When the terminal stops cooperating

The integrated terminal can degrade: commands appear to succeed but produce no output, and
nothing actually executes. **This is recoverable — switch to a VS Code task with redirected
output:**

```
cmd /c "cd /d C:\software\psc-elixir && <command> > C:\software\psc-elixir\tmp\agent-logs\run.log 2>&1"
```

then read `tmp/agent-logs/run.log` with `read_file`. Redirecting to a file is the important part:
it removes the dependency on capturing terminal output at all. `tmp/agent-logs/` is gitignored
(see `.gitignore`), so these logs never pollute `git status` — no cleanup step needed. Always
redirect there, never to the repo root.

⚠️ **`create_and_run_task` appends every task it is given to `.vscode/tasks.json`.** Diagnostic
one-offs accumulate as junk entries. After using it, restore the committed task list:

```
git checkout -- .vscode/tasks.json
```

The committed `.vscode/tasks.json` holds the four tasks worth keeping: `mix verify`, `mix test`,
`e2e (playwright)`, `phx.server`.

### The browser is a research tool, not just a UI checker

The built-in browser tools reach the **public internet**, not only localhost. This makes them a
first-class documentation and research tool:

- Navigate to docs, blog posts, release notes, RFCs — then extract the text:
  ```js
  await page.evaluate(() => {
    const t = document.body.innerText;
    const i = t.indexOf('to_form');
    return t.slice(Math.max(0, i - 100), i + 300);
  });
  ```
  Verified working against `hexdocs.pm` (which redirects to `phoenix-live-view.hexdocs.pm`).
- `screenshot_page` accepts a `ref`/`selector`, so you can capture just one element (a chart, a
  rendered component) rather than the whole viewport.
- `fetch_webpage` is the lighter option and returns text directly into context, but it **can
  return only a redirect notice instead of content**. If it does, follow the redirect URL or
  fall back to the browser.

**But prefer the local source for API truth.** `deps/` contains the exact source of the exact
versions in use — no network, no redirects, no version drift. Reach for the web when the answer
is *not* in `deps/`: ecosystem conventions, migration guides, error messages, design discussion.

### Reading the UI: screenshots are authoritative

**Accessibility snapshots can lag behind the page.** After an action, an a11y snapshot has been
observed still showing the *previous* state — e.g. after successfully creating a document it
still reported "No documents yet", and after creating a canvas it still showed the create button
as disabled. In both cases the screenshot showed the correct, updated state.

Rules:
- When a screenshot and an a11y snapshot disagree, **trust the screenshot**.
- Take a screenshot after any action whose result matters, not just a snapshot read.
- A fresh full `goto`/reload produces a trustworthy snapshot; a snapshot read immediately after
  a click may not.

### Driving LiveView from the browser or Playwright

- **Wait for `.phx-connected` before typing into a form.** LiveView wipes input values that were
  typed before the view connected, because the first server diff re-renders the inputs. Symptom:
  the form submits *empty* fields. (`PHX_CONNECTED_CLASS` is applied to the `data-phx-main`
  element by `hideLoader()` — see `deps/phoenix_live_view/priv/static/phoenix_live_view.esm.js`.)
- **Scope to a form id, then address inputs by `name`.** Pages can contain several forms with the
  same labels — `/users/log-in` has both a magic-link and a password form, each with an "Email"
  field. Use `#login_form_password` + `input[name="user[email]"]`, not a bare label lookup.

### Playwright failure artifacts

Every failure writes a folder under `test/e2e/test-results/` containing:

| File | Use |
|---|---|
| `test-failed-1.png` | Screenshot of the failure — view it (`view_image`) to *see* what broke |
| `error-context.md` | A11y snapshot of the failed state **plus the test source** |

`error-context.md` is often enough to diagnose without re-running: it shows both the assertion
and the DOM state at failure.

### Isolated environments for experiments

The same build can be run against a different database and port, so ad-hoc work never touches
`psc_dev` (see `config/runtime.exs` and `config/dev.exs`):

```
set MIX_ENV=dev && set PSC_DB_NAME=psc_e2e && set PSC_PORT=4001 && mix phx.server
```

- `PSC_DB_NAME` — database name (default `psc_dev`)
- `PSC_PORT` — HTTP port, takes precedence over `PORT` (default `4000`)

For ad-hoc inspection of business logic or the database, write a script and run it with
`mix run` — **do not pass `--no-start`**, which leaves the repo unstarted and produces
`could not lookup Ecto repo Psc.Repo`:

```
set MIX_ENV=dev && set PSC_DB_NAME=psc_e2e && mix run scripts/my_check.exs
```

See also "Backend Stress/Validity Scripts" below.

### Toolchain

- **NIF extension (`nif.fix`).** Erlang on Windows resolves NIFs as `.dll`, but `elixir_make`
  builds `bcrypt_elixir` from the Unix `Makefile`, which hardcodes `bcrypt_nif.so`. Without the
  `.dll`, `Bcrypt.Base` fails to load and every password operation raises — 12 test failures with
  a misleading *"make sure you have a C compiler"* message. The `nif.fix` alias copies `priv/*.so`
  to `.dll` in the current `_build` environment and is wired into `test`, `verify`, and
  `precommit`. No-op on non-Windows.
- **A C toolchain is available but off PATH.** MSYS2 lives at `C:\msys64`; `gcc` is at
  `C:\msys64\mingw64\bin\gcc.exe` and `make` at `C:\msys64\usr\bin\make.exe`. Prepend both to
  PATH when compiling a NIF from source:
  ```powershell
  $env:PATH = "C:\msys64\mingw64\bin;C:\msys64\usr\bin;" + $env:PATH
  $env:CC = "gcc"
  mix.bat deps.compile bcrypt_elixir --force
  ```
  A fresh `_build` (or a new `MIX_ENV`) is therefore buildable — it just needs this PATH,
  followed by `mix nif.fix`.

### Git

- **Check a file's line endings:** `git ls-files --eol <file>` → `i/lf` / `i/crlf`.
- **`git add --renormalize .` only touches *tracked* files.** A newly created `.gitattributes`
  must be staged separately.
- **Refreshing the working tree after a `.gitattributes` change:** git normalizes on *compare*,
  so the tree looks clean while the bytes on disk are still CRLF. Refresh with:
  ```
  git rm --cached -r -q . && git reset --hard
  ```
  (`git checkout-index -a -f` is not sufficient.)
- **A file isn't showing up as untracked?** It is probably ignored:
  `git check-ignore -v <file>` names the matching rule.
- **Discarding everything unstaged** (including deletions) is `git reset --hard`; to keep it
  scoped, `git checkout -- <paths>`.

### Context economy

- **Delegate exploration to a subagent** (`runSubagent`) when a question needs broad searching —
  many file reads and greps. The subagent works in its own context and returns only a summary,
  so the main conversation doesn't pay for the exploration.
- Run **one test file** while iterating; filter long output; read specific line ranges
  (see `AGENTS.md`, "Output discipline").

---

## Verification Matrix Details

### Step 1–2: `mix test`

- Unit/context tests live in `test/psc/`, LiveView tests in `test/psc_web/`.
- Follow the test conventions in `AGENTS.md` (element-based assertions, `start_supervised!`,
  no `Process.sleep`, etc.).
- Run the full suite with `mix test`; run a single file with `mix test test/path/to/file.exs`.

### Step 3: Ad-hoc browser verification

The agent uses its **built-in browser tools** (Playwright under the hood) to open the running
app and interact with it:

- `open_browser_page` — launch Chromium at `http://localhost:4000`
- `click_element`, `type_in_page`, `hover_element`, `drag_element` — interact with the UI
- `read_page` — accessibility snapshot of the DOM
- `screenshot_page` — **captures the page; the image goes directly into the LLM context**
  (multimodal). This is how the agent *sees* the UI.
- `run_playwright_code` — arbitrary Playwright JS for complex flows

This is the immediate feedback loop during implement mode. No files, no setup, no committed
code. Requires the dev server to be running (`mix phx.server`).

### Step 4: Playwright regression suite

The committed E2E suite lives in `test/e2e/` with its **own `package.json`** — completely
separate from the Phoenix esbuild/tailwind tooling.

**Setup (one-time):**

```bash
cd test/e2e
npm install
npx playwright install chromium
```

The database, migrations, seed user, and assets are handled automatically by the Playwright
`globalSetup` on every run. For a manual fallback (e.g., to inspect the DB before a run):

```bash
set MIX_ENV=dev && set PSC_DB_NAME=psc_e2e && set PSC_PORT=4001 && mix e2e.setup
```

**Running:**

```bash
cd test/e2e
npx playwright test
```

**`webServer` config** (auto-start + detect):

```js
// test/e2e/playwright.config.ts
export default defineConfig({
  webServer: {
    command: 'mix phx.server',
    cwd: '../..',                  // run from the project root (where mix.exs lives)
    url: 'http://localhost:4001',
    reuseExistingServer: true,     // if 4001 is already up, reuse it — no second server
    timeout: 120_000,
    env: { MIX_ENV: 'dev', PSC_DB_NAME: 'psc_e2e', PSC_PORT: '4001' },
  },
  // ...
});
```

Behavior:
- **Nothing running** → Playwright runs `mix phx.server` and waits for `http://localhost:4001`.
- **Already running** → `reuseExistingServer: true` detects the live port and reuses it.
- **Server fails to start** → the run fails with server output in the report.

**Why `MIX_ENV=dev` + env overrides:** the E2E server runs the **already-compiled dev build**
against a separate database (`psc_e2e`) and port (`4001`) via `PSC_DB_NAME` / `PSC_PORT`
(see `config/dev.exs`). This avoids recompiling dependencies for a new environment — important
because `bcrypt_elixir` compiles C code via `make`, which requires a C toolchain that may not
be present. `config/test.exs` uses the Ecto Sandbox (`server: false`) and cannot serve a real
running server, and the dev database (`psc_dev`) is never touched.

**Auth in tests:** use Playwright `storageState` — a global setup logs in once via the UI with
the seeded confirmed user, saves the session cookie to `test/e2e/.auth/user.json`, and every
test reuses it. (The app uses `phx.gen.auth` with email confirmation; the seed user is
pre-confirmed to bypass that flow.)

**Screenshots on failure:** `@playwright/test` auto-saves a PNG + trace for every failed test
to `test-results/`. The agent reads these with `view_image` to *see* exactly what broke — the
image enters the LLM context.

---

## Spec Format (structured)

Every spec in `docs/spec/` follows this structure so agents can consume it mechanically:

```markdown
# <Feature> Spec

## Overview
<2–3 sentences: what and why>

## Data Model
<schemas, fields, types, associations, migrations — with exact field names and types>

## File Plan
Exact paths to create or modify, with module names and function signatures.
Ambiguity here is what causes retries, so be concrete:
- `lib/psc/<context>.ex` — module `Psc.<Context>`, functions `list_thing/1`, `create_thing/2`
- `lib/psc_web/live/<x>_live/index.ex` — module `PscWeb.<X>Live.Index`, `mount/3`, `render/1`
- `lib/psc_web/router.ex` — add route inside an existing `live_session` (name it and say why)
- `test/psc/<context>_test.exs` — context tests

## API / Context Module
<function signatures, return shapes, side effects>

## UI Behavior
<routes, LiveViews, key element IDs, interactions>

## Acceptance Criteria
- AC-1: <verifiable behavior>
  Verify: <test file(s) + verification method>
- AC-2: ...

## Out of Scope
<explicitly not in this spec>

## Verification Methods
<per-criterion: which layer of the matrix applies — unit, LiveView, browser, E2E>
```

The acceptance criteria are the contract: plan mode derives the test plan from them, and
verify mode checks against them. Specs, tests, and verification stay in lockstep.

---

## Canonical Exemplars

Prefer copying a known-good file over inventing structure. For each task, start from the
exemplar and adapt it. These are the files the project already treats as idiomatic:

| Task | Copy the structure of |
|---|---|
| Ecto schema + changeset | `lib/psc/documents/document.ex` |
| Context module (CRUD + authorization) | `lib/psc/documents.ex` |
| Pure domain logic / algorithms | `lib/psc/documents/crdt.ex` |
| List LiveView (index) | `lib/psc_web/live/document_live/index.ex` |
| Editor LiveView (events, forms) | `lib/psc_web/live/canvas_layout_live/editor.ex` |
| LiveView with CRDT + presence + timers | `lib/psc_web/live/document_live/editor.ex` |
| Context test | `test/psc/documents_test.exs` |
| Pure-function test | `test/psc/documents/crdt_test.exs` |
| LiveView test | `test/psc_web/live/document_live_test.exs` |
| Test fixtures | `test/support/fixtures/document_fixtures.ex` |
| Playwright E2E test | `test/e2e/tests/smoke.spec.ts` |

**Vision-first verification.** When a change affects the UI, a screenshot is **mandatory
evidence**. Reasoning about markup is expensive and unreliable; *looking* at the rendered page is
cheap and reliable. Use the built-in browser tools to open the running app and capture a
screenshot rather than inferring correctness from the template source.

---

## Chat Audit

Every agent session is stored by VS Code as a JSONL transcript. To keep a full audit trail in
the repository:

1. **Locate the transcript:**
   `%APPDATA%\Code\User\workspaceStorage\<workspace-hash>\GitHub.copilot-chat\transcripts\<session-id>.jsonl`
   (the newest file is the current session).
2. **Export to markdown:**
   `mix run --no-start scripts/export_chat.exs --session-id <id> -o docs/audit/<date>-<topic>.md`
   (omit `--session-id` to auto-detect the newest session; omit `-o` to use the default
   `docs/audit/<date>-<session-short>.md`).
3. **Commit it** alongside the code it produced.

The export script reads the JSONL (structured events: `user.message`, `assistant.message` with
content + reasoning, `tool.execution_*`) and renders clean markdown: user/assistant turns, tool
calls, timestamps.

Manual fallback: VS Code's built-in "Copy All" in the chat view.

---

## Backend Stress/Validity Scripts (STUB)

This section is reserved for `scripts/verify_*.exs` — `mix run` scripts that exercise context
modules / business logic directly for stress and validity testing (e.g., CRDT operation
sequences, version-tree invariants, analytics event integrity). Not yet implemented; the
folder and this section exist so the pattern is established. When writing one, follow the
pattern: `mix run scripts/verify_<topic>.exs`, deterministic output, exit non-zero on failure.

---

## First Specs

The stubs in `docs/spec/` are empty and ready to be filled in. The first two to write are
**`docs/spec/creator.md`** (the canvas template creator/configurator) and
**`docs/spec/editor.md`** (the canvas editor). Together they are foundational: every other area
(versioning, analytics, insights) operates on canvases instantiated from templates.

- `creator.md` — defining canvas structure (cells, relations, semantics) and templates;
  template persistence and instantiation of canvases
- `editor.md` — the editor UI and components for creating and editing cells, on an
  instantiated canvas

Write them in the structured format above, with acceptance criteria and verification methods
for each.