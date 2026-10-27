# AGENTS.md — project context for coding agents

**This file is context, not a work order.** If you are reading it because the user referenced
it, that reference is not a request to start, plan, resume, or schedule any task. Do exactly
what was asked, and nothing more.

## How to behave

- **Answer the request that was made.** A question wants an answer; a bug report wants a
  diagnosis or a fix; naming a file may mean nothing more than reading it.
- **Resolve scope before acting.** If it is unclear what should change, ask one short
  question. Do not infer a larger workstream from a mention.
- **Do not invent work.** No picking tasks out of documents, no "while I am here" refactors,
  no unrequested plans or roadmaps. Ignore TODOs and historical notes unless they block the
  request.
- **Change as little as the request allows.** Prefer surgical edits. Do not restyle, rename,
  or reformat code you were not asked to touch.
- **Say what you did and what you verified.** Report the commands you ran and their real
  output. Never claim a check passed without running it. If something fails, surface it
  instead of retrying silently or working around it.
- **Never guess an API.** The exact dependency sources are vendored in `deps/`; read them or
  the docs instead of relying on memory. Guessed names fail at compile time or, worse,
  silently at runtime.
- **Keep output small.** Read line ranges instead of whole files, run one test file while
  iterating, and filter noisy logs.

## What the project is

A Phoenix 1.8 / LiveView application for collaborative structured canvases. Users author
reusable **templates**, instantiate them as **canvases**, edit them together in real time, and
attach Markdown **notes**. Deployed to Gigalixir (free tier), with Postgres.

Stack: Elixir 1.20, Phoenix 1.8.5, LiveView 1.2, Ecto, Bandit, Tailwind v4 + esbuild,
SaladUI components (`lib/psc_web/components/ui/`), `Req` for HTTP.

## The domain model

| Concept | Table | Module | Where |
|---|---|---|---|
| Template | `canvas_layouts` | `Psc.Canvas.Layout` | designed at `/templates/:id` |
| Canvas | `unstr_canvases` | `Psc.Canvas.UnstrCanvas` | edited at `/canvas/:id` |
| Canvas event | `unstr_canvas_events` | `Psc.Canvas.UnstrCanvasEvent` | append-only edit log |
| Note | `notes` | `Psc.Notes.Note` | Markdown child of a canvas |
| Note event | `note_events` | `Psc.Notes.NoteEvent` | append-only edit log |

- A **template** holds `layout_map`: rows, columns, a cell matrix, per-cell fields and optional
  section titles, row/column accents, and a `notes_mode`. It can be `public` and is then listed
  in `/catalog`.
- A template or canvas has a **layout mode**: `table` (the rows × columns matrix above),
  `bento` (free-form cards with a `placement` on a 4–16 column grid), or `image`
  (floating cards and text labels with a `placement` in percent of a backdrop picture's
  `url`). `Psc.Canvas.Structure` is the only module that knows the shapes; see
  `docs/spec/bento.md` and `docs/spec/image-canvas.md`.
- A **canvas** is created from a template (or blank, or the built-in PSC). Creation goes
  through `Psc.Canvas.instantiate_template/3`; the cells and notes are a copy, never a link.
- A **note** inherits its canvas's access rules. There is no per-note sharing.
- All aggregate writes go through the context modules (`Psc.Canvas`, `Psc.Notes`); LiveViews do
  not touch the repo directly.

## Administration

- Authorization is `users.role` (`:member | :admin`). Roles change only through
  `Psc.Accounts` (`promote_admin/1`, `demote_admin/1`); the last admin cannot be demoted, and
  a role is never cast from a registration or profile form.
- `/admin` is guarded by the `:require_admin` plug and `on_mount`. It hosts a Backpex 0.22
  panel (`PscWeb.Admin.*Live`) plus two plain LiveViews: the dashboard and `/admin/api-keys`.
  Backpex owns CRUD chrome; canvases and notes are read-only there because their content
  belongs to the event log.
- **Agent keys can be issued by an admin.** `/admin/api-keys` creates, rotates, defaults and
  deletes `agent_connections` rows for any account, so an admin can hand someone a provider
  key instead of requiring them to bring their own. The row stays owned by that account and
  the key stays write-only: the page renders only `key_hint`. Accounts must already exist —
  an admin cannot create one.
- **Built-in templates are rows** (`canvas_layouts.built_in` + unique `slug`), seeded
  create-if-missing by `Psc.Release.setup/0`. Everyone can use them; they cannot be deleted;
  admins can rename or unpublish them in `/admin/templates`.
- Boot order is migrate → `ADMIN_EMAILS` bootstrap → built-in seed. `ADMIN_PASSWORD` is only
  needed for addresses that do not have an account yet; creating the account is what stops
  someone else from registering the address first. `mix phx.server` does not run that
  sequence locally: `mix run priv/repo/bootstrap_admins.exs` runs the admin step on its own.

## Invariants that must not break

- **Event sourcing with pruning.** Edits are rows in the event table; a save folds them into
  the snapshot (`cells` / `content`), advances `snapshot_seq`, then deletes rows covered by
  it. Never move `snapshot_seq` backwards and never delete unfolded events.
- **Free-tier ceiling.** Postgres is limited to ~10k rows per table, so any per-edit row must
  be pruned or aggregated.
- **Per-field last-write-wins.** A canvas operation carries a whole field value; there is no
  character-level merge on canvases.
- **Template → canvas is a copy.** Editing a template never mutates existing canvases.
- **Auth is `current_scope`-based.** Pass `current_scope` into contexts and read
  `current_scope.user`; there is no `current_user` assign.
- **Test hooks are a contract.** `#canvas-header`, `#canvas-grid`, `#cell-card-<key>`,
  `#md-<key>-<field>`, `#active-users-tooltip`, `#cell-r1_c1` are used by LiveView and
  Playwright tests. Grep before renaming one. The free-form modes add `#canvas-bento` /
  `#bento-card-<key>` and `#canvas-image` / `#image-board` / `#image-cell-<key>` /
  `#text-cell-<key>`; the designer's are `#designer-bento*` and `#designer-image*`.

## Code conventions (the essentials)

- Use the app layout: `<Layouts.app flash={@flash} current_scope={@current_scope}>`.
- LiveView streams for collections: `stream/3`, `phx-update="stream"`, `@streams.name`.
  Re-stream with `reset: true` to filter; use `stream_insert/3` when an item changes.
- Never use `live_redirect` / `live_patch`; use `<.link navigate>` / `push_navigate`.
- Forms: build with `to_form/2` in the LiveView, render with `<.form for={@form} id="...">`,
  and read fields as `@form[:field]`. Never pass a changeset to `<.form>` and never use
  `let={f}`.
- Use the imported `<.input>` and `<.icon>` components rather than hand-rolled markup.
- HEEx: `{...}` for values inside tags and bodies, `<%= %>` for block constructs; class lists
  need `[...]`; comments are `<%!-- --%>`.
- Colocated hooks must be written as a **literal** string starting with a dot:
  `phx-hook=".MyHook"`. A conditional expression is not rewritten and fails at runtime.
- Tailwind v4: keep the `@import "tailwindcss" source(none);` + `@source` block in `app.css`.
  Do not `@apply`; do not add a `tailwind.config.js`.
- Ecto: preload associations used in templates; use `Ecto.Changeset.get_field/2`; keep
  programmatically-set fields (`user_id`, counters) out of `cast/3`.
- Elixir: no index access on lists (`Enum.at/2` instead); no `else if` (use `cond`); no nested
  modules in one file; use `start_supervised!/1` in tests and avoid `Process.sleep/1`.

## Environment (Windows)

- Run `mix.bat`, `npm.cmd`, `npx.cmd` (or wrap in `cmd /c "..."`); PowerShell blocks the
  `.ps1` shims.
- Long git output paginates and hangs: always `git --no-pager log/diff/show`.
- `sc` is an alias for `Set-Content`; use `Get-Service` or `sc.exe`.
- `Set-Content -Encoding utf8` writes a BOM; write JSON with
  `[System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))`.
- Tracked text files are LF (`.gitattributes`); the exception is `rel/overlays/bin/*.bat`.
- Two servers, two databases: dev is port 4000 / `psc_dev`; Playwright uses 4001 / `psc_e2e`.
  Never point E2E at the dev database. An isolated manual run:
  `set MIX_ENV=dev && set PSC_DB_NAME=psc_e2e && set PSC_PORT=4001 && mix.bat phx.server`.
- Ad-hoc scripts: `mix.bat run scripts/x.exs`, not `--no-start`.

## Verification

Run the narrowest check that covers your change, then widen only if needed:

1. `mix.bat test path/to/file_test.exs` while iterating.
2. `mix.bat verify` — format, compile with warnings as errors, tests.
3. Browser check for anything visual or interactive.
4. `npx.cmd playwright test` (from `test/e2e`) for end-to-end flows; it reuses a running
   server.

`mix.bat precommit` is the strict full check (formatting must already be applied). Report the
results, not a summary of intentions.

## Deployment (Gigalixir)

- Live at `psc.gigalixirapp.com` (app `psc`, free tier, `gigalixir-26`).
- Deploy with `git push gigalixir main`, or `scripts\deploy.ps1` (refuses a dirty tree or a
  non-`main` branch, streams the build log, probes the login page).
- The `Procfile` runs `Psc.Release.setup()` before starting the server: migrate, bootstrap
  the admins listed in `ADMIN_EMAILS` (creating accounts with `ADMIN_PASSWORD` when needed),
  and seed the built-in templates. All three steps are idempotent.
- Required files: `elixir_buildpack.config` (do **not** add `release=true`), `Procfile`
  (start `bin/psc`, never `bin/server`), and `def release` in `mix.exs`.
- Only numeric `PSC_PORT`/`PORT` values are honored; otherwise listen on 4000. SSL for the
  database follows its host; `PSC_DB_SSL=true|false` overrides.
- Root-level `priv/static` files (`manifest.webmanifest`, `sw.js`, `offline.html`,
  `favicon.ico`) are in `PscWeb.static_paths/0`. Verified routes rewrite their `~p` links
  to digested names in production (`manifest-<hash>.webmanifest`), so `Plug.Static` allows
  those digested prefixes with `only_matching`. Without it the manifest 404s in production
  while dev keeps working, and the app stops being installable as a PWA.
- The free tier allows 1 app, 1 database, ~10k rows per table, 2 connections.

## Agent tab and MCP

- The canvas editor's **Agent** tab is a chat over that canvas. **Sessions persist,
  agents do not**: every turn starts a throwaway `Jido.AgentServer`
  (`Psc.Agent.Turn`), streams events over `Psc.PubSub` on
  `agent_session:<id>`, writes the result and exits. Sessions hang off
  `agent_sessions.canvas_id`, so a canvas owns its own transcript.
- **Agent customization is copied from the template.** `canvas_layouts.agent_config`
  and `unstr_canvases.agent_config` hold `{prompt, roles, default_role, tools}`;
  `agent_files` rows hold the text reference documents. Instantiation and forking
  copy both, and editing a template never changes an existing canvas. The
  designer's Agent section and the canvas Info tab share
  `PscWeb.Components.AgentConfigEditor`.
- **A chat pins its profile.** The first user message stores `agent_sessions.role` and
  `.profile` (composed system prompt, tool allowlist, file manifest). Canvas edits apply
  to new chats. `Psc.Agent.Profile` layers the immutable
  `CanvasAgent.base_prompt/0`, the configured prompt, the selected role and the file
  manifest. `Psc.Agent.Turn` applies it through the ReAct
  `ai.react.set_system_prompt` command and passes `allowed_tools` per request.
- **Reference files are text rows with nested paths.** `agent_files.path` is the
  identity (`docs/spec/bento.md`); `name` is the basename. `Psc.Agent.Files` accepts
  directory uploads through `PscWeb.AgentUploads`, preserves the relative paths, and
  skips hidden/build folders and binary files. Uploads are staged: two pickers (files
  and a folder) feed a README-style preview where files/directories can be removed
  before "Add to references" merges them into the draft. Caps: 24 files, 128 KiB each,
  768 KiB total. The designer and Info tab can also create and edit files by path.
- `read_agent_file` takes a `path`; it is in the shared registry, so `/mcp` exposes it
  too; canvas access is the gate. Files are sent to the viewer's own model provider and
  are visible to everyone who can open the canvas.
- Tools live in `Psc.Agent.Tools.*` as `Jido.Action` modules and call
  `Psc.Canvas` / `Psc.Notes` with the caller's `current_scope`. They are
  read-only by construction; the same modules back `/mcp`
  (`PscWeb.MCP.Plug`, JSON-RPC, bearer token) for external agents.
- `Psc.Agent.Turn.run/4` takes `script: [...]` so tests replay a turn without a
  model. No test may hit a network.
- The tab is gated per user: it needs a **connection** saved in settings
  (`agent_connections`: a provider, a write-only API key and a `model_id`,
  optionally a `base_url`). Connections are personal; `users.default_agent_connection_id`
  picks one for new chats and `agent_sessions.connection_id` pins the chat.
  Legacy `users.agent_api_key` / `users.agent_model` pairs still resolve when the
  user has no connection, but the settings page no longer writes them.
- `Psc.Agent.ModelCatalog` supplies model suggestions: offline from the packaged
  `LLMDB` catalog, and live from each provider's model-listing endpoint, which is
  also what the "Test connection" button runs (no token cost). Providers do not
  share one endpoint: most are OpenAI-shaped (`GET {base_url}/models` with a
  bearer token), Anthropic uses `x-api-key` + `anthropic-version`, Google uses
  `/v1beta/models` with the key as a query parameter.
- Tests must not go online: turns started from a LiveView cannot receive
  `Turn.run/4`'s `:script` option, so `config :psc, :agent_turn_script` is read
  when no option is given.
- `/mcp` 404s unless `PSC_MCP_TOKEN` and `PSC_MCP_USER` are set.
- Prompt caching depends on a byte-stable prefix: the system prompt is constant,
  tools are listed in a fixed order, and history is replayed append-only (never
  re-serialise `jsonb` into the prompt).

## Where things live

- `lib/psc/` — contexts and schemas (`canvas.ex`, `notes.ex`, `text_store.ex`, `admin.ex`).
- `lib/psc/agent/` — the agent runtime (`turn.ex`, `canvas_agent.ex`), configuration and
  profiles (`config.ex`, `profile.ex`, `files.ex`) and the tool registry under `tools/`.
- `lib/psc_web/live/` — LiveViews: `unstr_canvas_live/` (canvas), `canvas_layout_live/`
  (designer), `catalog_live/`, `user_live/`, `admin/` (Backpex resources + dashboard).
- `lib/psc_web/components/` — shared components, including SaladUI under `ui/`.
- `assets/js/hooks/` — client hooks; `assets/css/app.css` — Tailwind entry.
- `priv/repo/migrations/`, `priv/repo/seeds.exs`, `priv/repo/e2e_seeds.exs`.
- `test/` — ExUnit; `test/e2e/` — Playwright.

## Documents are reference, not a queue

`docs/spec/`, `docs/design-decisions.md` (ADRs), `docs/data_model.md`,
`docs/routing_map.md`, and `docs/plans/` record how the product works and what was decided.
They are background reading. Nothing in them is scheduled, assigned, or awaiting an agent;
do not treat any of it as work to start unless the user asks for it.