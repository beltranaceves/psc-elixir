# Project Overview — Psc

## Summary
Psc is a Phoenix (v1.8) web application written in Elixir (>= 1.15). It is a LiveView-first app (uses `phoenix_live_view`) with Ecto-backed persistence (`ecto_sql`, `postgrex`) and a Bandit HTTP adapter. The codebase is structured like a standard Phoenix app with an OTP application module `Psc.Application`, web entrypoint `PscWeb`, and contexts under `lib/`.

Key project traits:
- LiveView-driven UI with colocated hooks (`phoenix-colocated`) and custom client hooks (see `assets/js/hooks`).
- Tailwind-based CSS (Tailwind v4 import syntax in `assets/css/app.css`) and daisyUI plugins for theming.
- JS bundling via esbuild and CSS via Tailwind (aliases: `assets.setup`, `assets.build`).
- Uses `:req` as the preferred HTTP client for external requests.
- Includes clustering/CRDT dependencies (`:delta_crdt`, `:dns_cluster`) suggesting distributed state or realtime CRDT-backed features.
- Adapter/Runtime: `bandit` is configured as the Phoenix adapter in `config/config.exs`.
- Local mailer for dev via `Swoosh.Adapters.Local` (dev mailbox at `/dev/mailbox`).

Notable dependencies (non-exhaustive): `phoenix`, `phoenix_live_view`, `ecto_sql`, `postgrex`, `esbuild`, `tailwind`, `bandit`, `delta_crdt`, `dns_cluster`, `req`, `swoosh`.

## Project layout highlights
- `lib/` — application and web modules (`Psc`, `PscWeb`, contexts, LiveViews, templates).
- `config/` — app and env-specific configuration (`Bandit` adapter, LiveView salt, repo, tailwind/esbuild config).
- `assets/` — frontend JS and CSS (`assets/js/app.js`, `assets/css/app.css`), vendor scripts (daisyUI, heroicons), colocated hooks.
- `deps/` — many dependencies vendored via mix (useful for offline or embedded dev setups in this workspace).
- `test/` — tests and helpers; `mix test` is configured to create and migrate the test DB before running.

## Conventions and project-specific guidelines
(Extracted from `AGENTS.md` and repo config)
- Use `mix precommit` to run the project's lint/format/tests before finishing changes.
- Always use `:req` for HTTP calls; avoid `:httpoison`, `:tesla`, or `:httpc`.
- LiveView templates must be wrapped with `<Layouts.app flash={@flash} ...>` and must receive `@current_scope` as required by auth rules.
- Auth-related routes must use the provided `live_session` blocks and plugs. The project uses a `current_scope` pattern (see `config/config.exs` for scope config).
- Use `to_form/2` + `<.form for={@form}>` and the `<.input>` core component for forms; avoid passing raw changesets directly to templates.
- LiveView streams are preferred for lists; follow `stream/3` conventions (parent element `phx-update="stream"`, id usage, re-streaming on updates).
- Use Tailwind classes and the provided import syntax in `assets/css/app.css`; do not use `@apply` or inline scripts in templates.

## Developer quick start
1. Install and set up deps + DB + assets:

```bash
mix setup
```

This runs `deps.get`, `ecto.setup` (create/migrate/seeds), and `assets.setup` (tailwind + esbuild install if missing).

2. Start the server:

```bash
mix phx.server
# or in IEx with hot access
iex -S mix phx.server
```

3. Visit the app: open `http://localhost:4000`.

4. Run tests:

```bash
mix test
```

5. Precommit checks (use before finalizing a change):

```bash
mix precommit
```

## Notes & pointers for contributors
- Check `mix.exs` for aliases (`assets.build`, `assets.deploy`, `precommit`) and dependency versions.
- `config/config.exs` contains the `:scopes` configuration used for multi-scope auth; when adding features that require `current_scope`, ensure the route is placed in the correct `live_session` with appropriate plugs.
- The app exposes dev conveniences: local Swoosh mailbox at `/dev/mailbox`, LiveReload features, and rich dev live-reloader hooks configured in `assets/js/app.js`.
- For cluster/CRDT work, `:delta_crdt` and `:dns_cluster` are present — review those dependencies' docs and existing modules in `lib/` for integration patterns.

## Where to look next
- Application entry: `lib/psc/application.ex` and `lib/psc.ex`.
- Web entrypoint and helpers: `lib/psc_web.ex` and `lib/psc_web/router.ex`.
- Frontend bundle: `assets/js/app.js` and `assets/css/app.css`.
- Project guidelines and scaffolding notes: `AGENTS.md` (this file).

---
Created by automation: summary + quick-start for this repository.
