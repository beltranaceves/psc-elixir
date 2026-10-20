# Catalog — implementation plan

> **Status:** not started.
> **Spec:** [catalog.md](../spec/catalog.md).
> **Decision to record:** ADR-031 — a template can be public, and its use is counted
> (written in Task 2, when the behaviour lands).
> **Companion docs:** [AGENTS.md](../../AGENTS.md) (how to work),
> [DEVELOPMENT.md](../../DEVELOPMENT.md) (workflow + environment),
> [design-decisions.md](../design-decisions.md) (ADRs).

The **Catalog** is the public face of the template library: a template marked public by
its owner appears at `/catalog`, ranked by how many times it has been used, searchable by
name and description, and inspectable in a modal that offers **Use template** and
**Fork**.

Work through the tasks in order. Each one is a commit. Every task ends with the
verification matrix from [AGENTS.md](../../AGENTS.md) green, and updates this document,
the spec and the matching ADR if the behaviour moved.

## The shape of the work

Five things have to happen, in this order, because each one depends on the one before it:

1. **The columns** — `public`, `use_count`, `fork_count`, `forked_from_id` on
   `canvas_layouts`. No new table: ADR-006 caps every table at 10 000 rows, and a row per
   use would grow without bound.
2. **The context** — the catalog query, the counter inside `instantiate_template/3`, and
   `fork_template/2`. Everything the UI does goes through here, so the counting rules
   exist in exactly one place.
3. **Publish** — the toggle in the designer, so there is something to put in the catalog.
4. **The catalog page** — route, nav, list, search, empty state, and the detail modal.
5. **Use and Fork** — the modal's two actions, which is what makes the catalog more than
   a list.

---

## Task 1 — The catalog columns

**Status: pending.**

- Migration `add_catalog_to_canvas_layouts`:
  - `add :public, :boolean, default: false, null: false`
  - `add :use_count, :integer, default: 0, null: false`
  - `add :fork_count, :integer, default: 0, null: false`
  - `add :forked_from_id, references(:canvas_layouts, type: :binary_id, on_delete: :nilify_all)`
- `Psc.Canvas.Layout` gains the four fields. **Only `:public` goes in the cast list** —
  `:use_count` and `:fork_count` are moved with `Repo.update_all(inc:)` and
  `:forked_from_id` is set on the struct in `fork_template/2`, so casting any of them
  would let a request set them (the same rule that keeps `author_id` out of the cast).
- `docs/data_model.md` gains the columns.

**Acceptance**

- A template created today has `public == false` and both counts at `0`; no backfill is
  needed and none is written.
- `Layout.changeset/2` accepts `:public` and ignores a `:use_count` /
  `:forked_from_id` in the params — a test asserts the cast list, not just the outcome.
- Deleting a source template nilifies its forks' `forked_from_id` and leaves the forks
  themselves standing.

**Verification** — `mix.bat verify`; `mix.bat test test/psc/canvas_test.exs`.

**Watch out** — `on_delete: :nilify_all` on a self-reference: the fork is a copy and
must survive its source being deleted, losing only the attribution line. `:nilify_all`
is the right value here because the only foreign key into `canvas_layouts` is this one;
`:nilify_child` is not an option Ecto accepts.

---

## Task 2 — The catalog context

**Status: done.**

In `Psc.Canvas`, beside the existing template functions:

- `list_public_templates(query \\ nil)` — `public = true`, ordered
  `[desc: use_count, desc: updated_at]`, `limit: 200`, preloading `:author`. A non-empty
  query narrows it with `ILIKE` over `name` and `description`.
- `get_public_template(id)` — the fetch behind the modal and both actions; a template
  that is not public is not found here.
- `publish_template/1` and `unpublish_template/1` — flip `:public` through the changeset.
- `fork_template(template, user_id)` — one `Repo.transaction`: insert the copy (name
  `"Name (fork)"`, the source's description and `layout_map`, `forked_from_id` set on the
  struct) and `inc` the source's `fork_count`.
- `instantiate_template/3` wraps the canvas insert, the note seeding and a
  `use_count` `inc` in **one** `Repo.transaction`. It counts every instantiation, from
  the library as well as the catalog.
- ADR-031 added to `docs/design-decisions.md` (index row + section).

**Acceptance**

- The catalog query returns public templates ordered by `use_count`, then by
  `updated_at`; a private template is never in the result, and `get_public_template/1`
  returns `nil` for one.
- Search matches a fragment of a name and a fragment of a description, and an empty query
  is no filter.
- Instantiating a template bumps exactly its `use_count` by exactly one, and a failed
  instantiation bumps nothing (the transaction rolls back).
- Forking copies the definition, sets the lineage, bumps the source's `fork_count`, and
  leaves the source untouched by later edits to the fork (and vice versa).
- Counts never decrease when a canvas or a fork is deleted.

**Verification** — `mix.bat verify`; `mix.bat test test/psc/canvas_test.exs`.

**Watch out** — the counter must be `Repo.update_all(inc:)`, never a changeset
read-modify-write: two simultaneous uses would otherwise lose one. And `ILIKE` treats
`%` and `_` as wildcards, so escape them out of the user's query before interpolating it.

**Found while building it** — the fork's name retry cannot live inside one
transaction. Template names are unique, so the second fork of a source needs a
different name, but a unique violation aborts the Postgres transaction it happened
in and every later statement in it fails with `25P02 in_failed_sql_transaction`.
Each attempt is therefore its own transaction (`fork_once/3`), and only a
name-taken error is retried.

---

## Task 3 — Publish in the designer

**Status: done.**

- Under **Description** in the name/description form: a checkbox, **"Public — list this
  template in the catalog"**, owner only. The Phoenix checkbox pair (a hidden `false`
  input and the checkbox) so an unticked box still submits `"public" => "false"`.
- `handle_event("save_template", …)` stops destructuring exactly two keys and reads
  `public` with a default, then passes it to `update_template` / `create_template`.
- A read-only viewer sees no toggle and no save controls, so nothing else changes.

**Acceptance**

- The toggle renders for the owner and not for a shared non-owner.
- Saving with it ticked persists `public: true`; unticked persists `false`; reopening the
  template shows the saved state.
- A template that is public and then unpublished keeps its canvases working.

**Verification** — `mix.bat verify`;
`mix.bat test test/psc_web/live/canvas_layout_live_test.exs`; a browser pass on the
toggle.

**Watch out** — the handler currently pattern-matches `%{"name" => …, "description" => …}`;
a third required key would crash on any form that omits it. Read it with a default.

---

## Task 4 — The catalog page

**Status: done.**

- Route `live "/catalog", CatalogLive.Index, :index` inside the **existing**
  `live_session :require_authenticated_user` block — a `live_session` name may only be
  defined once.
- `PscWeb.Layouts` gains the **Catalog** nav item after **Templates**, in the desktop nav
  and in the phone menu.
- `PscWeb.CatalogLive.Index`:
  - the list as a **LiveView stream** of cards (name, description, author, dimensions,
    "Used N · Forked N");
  - `handle_event("search", …)` re-fetches and re-streams with `reset: true`;
  - the empty state, and the truncation line when the ranking is cut at 200;
  - the **detail modal** — a `UIDialog` opened by clicking a card, showing the details,
    the two counts, the "Forked from …" line and a **read-only grid preview** built from
    `layout_map`, closed by Escape / outside / × / Done via `on-close`.
- `docs/routing_map.md` gains the route.

**Acceptance**

- `/catalog` lists published templates in use-count order and nothing else; the header
  reads *Catalog* and the nav marks it current (ADR-025: no repeated page title in the
  body).
- Typing in the search narrows the list without changing the order, and clearing it
  restores the full ranking.
- A card opens the modal; Escape and the × close it; the grid preview shows the template's
  rows, columns and cell labels.
- A template with no `layout_map` keys (an old row) renders an empty preview rather than
  crashing.

**Verification** — `mix.bat verify`; `mix.bat test test/psc_web/live/catalog_live_test.exs`;
a browser pass on search, the modal and the empty state.

**Watch out** — the modal's `open` is an assign, so a patch that re-renders the page must
not close it: keep the open template's id in the socket and render the dialog from it.
And the preview reads `layout_map` with `Map.get(…, [])` defaults — stored maps from
before a field existed are the normal case, not the edge case.

---

## Task 5 — Use and Fork

**Status: done.**

- **Use template** (primary) — `Canvas.instantiate_template(get_public_template(id),
  user.id)`, then redirect to the new canvas with a flash, exactly as the library's
  *Use Template* does.
- **Fork** (outline) — `Canvas.fork_template(template, user.id)`, then redirect to the new
  template in the designer with a "Template forked" flash. Forking your own template is
  allowed.
- Both buttons `phx-disable-with` while the event is in flight, so a double click cannot
  create two canvases or two forks.
- A failure stays on the page with an error flash; the modal stays open.

**Acceptance**

- Using a template creates a canvas owned by me and lands me in its editor; the
  template's `use_count` is one higher afterwards.
- Forking creates a template owned by me, named "*Name* (fork)", with the same grid, and
  lands me in its designer; the source's `fork_count` is one higher.
- Using a template I do not own and am not shared with works — that is the point of the
  catalog — while `/templates/:id` for it still turns me away.
- A private template cannot be used or forked from the catalog, even with a guessed id.

**Verification** — `mix.bat verify`; `mix.bat test test/psc_web/live/catalog_live_test.exs`;
a browser pass on both actions.

**Watch out** — the *Use* path must go through `get_public_template/1`, not
`get_canvas_layout/1`, or the catalog becomes a way to instantiate a private template by
id. The library's own `instantiate` event has that hole today; do not copy it.

---

## Task 6 — E2E regression

**Status: done.**

- `test/e2e/tests/catalog.spec.ts`:
  - publish a template in the designer, find it in `/catalog`, open its modal;
  - search for it and for something that does not exist;
  - use it, and assert the canvas opens and the count went up on reopening the modal;
  - fork it, and assert the designer opens on a copy owned by the second user;
  - unpublish it, and assert it leaves the catalog while its canvas still opens.
- Reuse the harness helpers (`uniqueName`, the auth storage state) the other specs use.

**Acceptance**

- The spec passes alongside the existing 41, and the whole suite stays green.

**Verification** — `npx.cmd playwright test` from `test/e2e`; `mix.bat precommit`.

**Watch out** — the E2E database is reset between runs (`priv/repo/e2e_reset.exs`), so the
spec must create everything it asserts on and must not depend on templates left by
another spec.

**Found while building it** — the publish toggle could not be toggled. LiveView
re-derives a checkbox's `checked` from the server's render on every patch
(`DOM.syncAttrsToProps`), and `mark_dirty` ignored its params, so the server never
learned about the toggle and undid it the moment it fired a change event. The fix
is in Task 3: the draft's publish state is an assign, updated by `mark_dirty`
like the name and description.

---

## Definition of done (applies to every task)

- [ ] Behaviour matches the task's acceptance criteria, verified in a running app where visual.
- [ ] `mix.bat verify` green (format, zero warnings, all tests).
- [ ] New behaviour covered by tests at the right level (context → `test/psc/…`,
      LiveView → `test/psc_web/live/…`, flow → `test/e2e/tests/…`).
- [ ] No new `100vh`/hardcoded light-dark colours; use theme tokens (ADR-015) and the
      existing flex layout (ADR-020/021).
- [ ] Docs updated when behaviour or data shape changed (`data_model.md`, `routing_map.md`,
      the spec, the ADR).
- [ ] Deployed? Only when the user asks — then `scripts\deploy.ps1`.
