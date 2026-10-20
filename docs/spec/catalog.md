# Catalog

## Overview

The **Catalog** is the public face of the template library. A template's owner can mark
it **public**, and it then appears at `/catalog` for every signed-in user, ranked by how
many times it has been used. From the catalog a template can be inspected in a modal and
either **used** (a canvas is created from it) or **forked** (a copy becomes the user's own
editable template).

The private library at `/templates` does not change: it stays the list of templates the
user owns or has been shared. The catalog is the discovery surface on top of it.

> **Terminology.** A **canvas** is one configurable workspace; a **template** is the
> reusable structure a canvas is created from (`canvas_layouts` / `Psc.Canvas.Layout`).
> To **publish** a template is to mark it public; to **use** a template is to create a
> canvas from it; to **fork** a template is to create a new template that copies it.

### Design principle

The catalog is a **ranking, not an index**. It answers "which templates are worth
starting from?", so it is ordered by evidence of use and capped in length. It is not a
complete listing of every public template, and it does not need pagination until the
ranking itself is too short.

## Decisions

These are the calls the spec makes; each is restated in the ADR that will record it
(ADR-031, written when the behaviour lands).

1. **Two counters, ranked by use.** `use_count` ranks the catalog; `fork_count` is
   reported alongside it in the modal. *Used* and *forked* are different signals — a use
   is a canvas someone wants to fill, a fork is a copy someone wants to edit — and the
   ranking the catalog is asked for is by use.
2. **Every use counts, including the author's.** The count is "how many times this
   template was used", a historical fact. Excluding the author would need a per-user
   ledger, which the row ceiling forbids (see below).
3. **Counts never decrease.** Deleting a canvas does not decrement `use_count`: the use
   happened. This keeps the counter a single `inc` with no read-modify-write.
4. **The catalog is behind login.** Every non-auth route in this app is an auth page, and
   the catalog is not one. It lives in the existing `live_session
   :require_authenticated_user`.
5. **Public is not shared.** `shared_with` still governs who may open a template in the
   designer. A public template is *usable* and *forkable* by anyone signed in, but not
   editable by them; `can_access_template?/2` is unchanged and a non-owner who navigates
   to `/templates/:id` is still turned away.
6. **A fork is a copy, not a link** — the same rule as ADR-009 for canvases. Editing the
   source never changes the fork. `forked_from_id` is attribution shown in the modal,
   nothing more.
7. **Unpublishing is safe.** Canvases and forks already made are independent copies; they
   keep working. The template just leaves the catalog.

## Data model

One migration, **no new tables**. Four columns on `canvas_layouts`:

| Column | Type | Purpose |
|--------|------|---------|
| `public` | `boolean`, default `false`, not null | Listed in the catalog |
| `use_count` | `integer`, default `0`, not null | Canvases created from this template |
| `fork_count` | `integer`, default `0`, not null | Templates forked from this template |
| `forked_from_id` | `binary_id`, FK → `canvas_layouts.id`, `on_delete: :nilify_all`, nullable | The template this was forked from |

**No usage event log.** ADR-006 caps every table at 10 000 rows on the free tier, and a
row per use would grow without bound while buying nothing the two counters do not
already say. The counters are columns, incremented with a single `inc` inside the same
transaction as the action that causes them — there is no read-modify-write and no second
round trip.

**Casting.** `:public` is user-settable and belongs in `Layout.changeset/2`.
`:use_count`, `:fork_count` and `:forked_from_id` are set programmatically (an `inc` and
a struct field) and must **not** be cast — the same rule that keeps `author_id` out of
the cast list.

Existing templates need no backfill: the column defaults make every template private and
uncounted, which is exactly what they were before the column existed.

## Context API

All of it lives in `Psc.Canvas` beside the existing template functions.

```elixir
list_public_templates(query \\ nil) :: [Layout]
# public = true, ordered by use_count desc then updated_at desc, limited to 200.
# A non-empty query narrows it with ILIKE over name and description.
# Preloads :author — the cards and the modal show who made it.

get_public_template(id) :: Layout | nil
# The fetch behind the modal and both actions: a template that is not public
# is not found here, so the catalog cannot be used to reach a private one.

publish_template(template) / unpublish_template(template) :: {:ok, Layout} | {:error, Changeset}
# Flips :public. The LiveView checks ownership before calling.

fork_template(template, user_id) :: {:ok, Layout} | {:error, Changeset}
# One Repo.transaction: inserts a Layout authored by user_id with the source's
# name ("Name (fork)"), description and layout_map, sets forked_from_id,
# and increments the source's fork_count.
```

`instantiate_template/3` gains the counter: the canvas insert, the note seeding and the
`use_count` increment happen in **one** `Repo.transaction`, so a canvas is never created
without its use being counted and a count is never bumped without a canvas. It counts
every instantiation — from the library as well as the catalog — because "how many times
it has been used" does not depend on where the button was.

## Routes

`live "/catalog", CatalogLive.Index, :index`, inside the existing
`live_session :require_authenticated_user` block. The header nav gains **Catalog** after
**Templates**, in both the desktop nav and the phone menu (`PscWeb.Layouts`).

## UI

### Catalog (`/catalog`)

The **app header** is the page's only title (`Catalog`), per ADR-025 — the body starts
with the content, not a repeated heading.

- **Search** — a single input at the top, `phx-change="search"` with a debounce,
  placeholder "Search templates…". An empty query is no filter. Filtering re-fetches and
  re-streams the list with `reset: true`; the sort does not change.
- **Cards** — a grid in the language of the library cards: name, description, author,
  grid dimensions, and the two counts ("Used 12 · Forked 3"). The whole card opens the
  modal. The list is a LiveView stream.
- **Empty state** — "No public templates yet", with a pointer at the designer's publish
  toggle for a user who owns templates but has published none.
- **Truncation** — when the ranking is cut at 200, a quiet line says so, so the cap reads
  as a ranking rather than as a missing page.

### Template modal

A SaladUI `UIDialog` (the house pattern used by Share and the discard confirmation),
opened by clicking a card and closed by Escape, an outside click, the × or Done.

It shows: name, description, author, grid dimensions, cell count, the two counts, the
last-updated date, and — when the template is a fork — "Forked from *source*".

It also shows a **read-only preview of the grid**: rows × columns with the cell labels,
built straight from `layout_map`. The designer's table is an editor; this is a picture of
what a canvas from this template will look like, and it is the detail a user needs before
choosing between two templates.

Two actions in the footer:

- **Use template** (primary) — instantiates a canvas owned by the current user and
  navigates to it, exactly as the library's *Use Template* does.
- **Fork** (outline) — forks the template and navigates to the new copy in the designer,
  with a "Template forked" flash. Forking your own template is allowed: it is how a
  variant gets made.

### Publish toggle (template designer)

Under **Description** in the name/description form: a checkbox, **"Public — list this
template in the catalog"**. Owner only; a read-only viewer does not see it. It is part of
the form's `save_template` params, so publishing is saved with the template like any
other field — there is no separate publish action and no second save button.

## Validation rules

- A template must already be valid to be published: the changeset that saves it validates
  the grid, so a template with no rows or columns cannot be saved and therefore cannot be
  published.
- Search is server-side `ILIKE` over `name` and `description`; there is no client-side
  filtering of the stream.
- The catalog's *Use* goes through `get_public_template/1`, so a private template cannot
  be instantiated from the catalog even by guessing an id.

## File plan

| File | Action | Purpose |
|------|--------|---------|
| `priv/repo/migrations/xxx_add_catalog_to_canvas_layouts.exs` | create | The four columns |
| `lib/psc/canvas/layout.ex` | modify | Fields; `:public` in the changeset |
| `lib/psc/canvas.ex` | modify | Catalog queries, the counter, `fork_template/2` |
| `lib/psc_web/live/catalog_live/index.ex` | create | The page, the modal, the grid preview |
| `lib/psc_web/router.ex` | modify | The `/catalog` route |
| `lib/psc_web/components/layouts.ex` | modify | The nav item, desktop and phone |
| `lib/psc_web/live/canvas_layout_live/editor.ex` | modify | The publish toggle |
| `docs/routing_map.md` | modify | The new route |
| `docs/data_model.md` | modify | The new columns |
| `test/psc/canvas_test.exs` | modify | Context tests |
| `test/psc_web/live/catalog_live_test.exs` | create | Page, search, modal, actions |
| `test/psc_web/live/canvas_layout_live_test.exs` | modify | The publish toggle |
| `test/e2e/tests/catalog.spec.ts` | create | Publish → catalog → use/fork |

## Acceptance criteria

- [ ] A template can be marked public in the designer, and appears in `/catalog`
- [ ] Unpublishing removes it from the catalog without breaking canvases or forks already made
- [ ] The catalog is ordered by use count, descending, and says so when it is truncated
- [ ] Search narrows the list by name and description without changing the order
- [ ] Clicking a card opens a modal with the details and a read-only grid preview
- [ ] *Use template* creates a canvas owned by me and increments the template's use count
- [ ] *Fork* creates a template owned by me, copies the definition, records the lineage and increments the source's fork count
- [ ] A fork is independent of its source, and a canvas is independent of its template (ADR-009)
- [ ] A private template cannot be reached through the catalog, and a non-owner still cannot open one in the designer
- [ ] No new table exists: the counts are columns, and nothing writes a row per use
