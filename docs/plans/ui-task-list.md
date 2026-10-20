# UI polish task list — checkpoint (2026-10-19)

**Status:** descriptions only — **no implementation yet**. Each item was reproduced in the
running dev app (`localhost:4000`, signed in, dark theme unless noted) at commit `a56d820`.
Measurements below come from the live DOM, not from reading code alone.

**Supersedes** [agent-task-list.md](agent-task-list.md) for the current UI pass (that document
remains the longer-term MVP backlog).

Each task is written to be picked up independently. Every task ends with *Acceptance* (what
"done" means) and, where the ask was ambiguous, *Decision needed*.

---

## Checkpoint

| # | Task | Scope | Type | Blocked? | Status |
|---|---|---|---|---|---|
| 1 | Tighten top padding on most routes | layout/theme, 6 LiveViews | cosmetic | — | done |
| 2 | Zoom in the auth pages on mobile | login/register markup | cosmetic + a11y | — | done |
| 3 | Rename routes to `/canvas` and `/canvas/:id` | router, links, tests | refactor | — | done (+ redirects) |
| 4 | Remove the duplicate "Create Template" | templates index | cleanup | — | done |
| 5 | Mobile layout for the templates list | templates index | responsive | 4 (same file) | done |
| 6 | Make the template card actions consistent | templates index | cosmetic | 5 | done |
| 7 | Mobile layout for the designer | designer editor | responsive | — | done (pan) |
| 8 | "Template saved" alert should be green | flash component + 4 call sites | cosmetic | — | done |
| 9 | Canvas list: "Templates" instead of "Canvases"? | copy/naming | **decision needed** | needs decision | done (copy-only default) |
| 10 | Fix the active-users tooltip | tooltip JS + usage | bug | — | done |
| 11 | Prune the "canvas" naming sprawl | contexts/LiveViews/routes | refactor | 3, and legacy removal | partial — legacy deleted, renames open |

Suggested order: **10 → 8 → 4 → 6 → 1 → 2 → 5 → 7 → 3 → 11**, with **9** decided before any of
the naming work.

---

## 1 — Tighten top padding on most routes

**Observed.** Every page except the canvas editor starts 64–80 px below the header:

| Route | First heading top | Composition |
|---|---|---|
| `/canvases` | 120 px | `main` py-8 (32) + inner `py-8` (32) |
| `/templates` | 122 px | same double padding |
| `/documents` | 138 px | `main` 32 + inner `py-12` (48) |
| `/templates/:id` (designer) | ~112 px | `main` 32 + inner `py-6` (24) |
| `/canvases/:id` (canvas editor) | 106 px grid top | `main_class="py-2"` — **the target feel** |

**Cause.** `Layouts.app` applies `py-8` and most pages *also* wrap their content in `px-4 py-8`
(or `py-12`), doubling the offset.

**Proposal.** Set the app-shell default to a smaller vertical padding (`py-4`/`py-3`) and strip
the inner `py-*` from the page wrappers, keeping horizontal padding in one place. Leave the
canvas editor's `fill_height`/`py-2` behaviour as-is.

**Acceptance.** First heading sits ~72–80 px from the viewport top on all routes; no page loses
its horizontal gutters; canvas editor unchanged; checked at 390 px and 1192 px.

---

## 2 — Zoom in the auth pages on mobile

**Observed (390 px).** Login/register render a 323 px form (83 % of the viewport) with inputs at
`font-size: 14px` / 40 px tall. The viewport meta is `width=device-width, initial-scale=1`.

**Cause / effect.** On iOS Safari, focusing an input below 16 px zooms the whole page, so the
layout jumps and then never quite resets — this reads as "zoomed out page, punches in on focus".
At the same time the form is narrower than it could be (`max-w-sm` + `px-4`), so text is small
even before the zoom.

**Proposal.** On `< sm`: input font-size 16 px and height 44 px; widen the form container
(~`max-w-md`, `px-4`); bump the heading one step; keep the desktop sizing unchanged.

**Acceptance.** No iOS focus zoom (all auth inputs ≥ 16 px at mobile widths); form ≥ 90 % of a
390 px viewport; error chips and labels still align; verified in the browser at 390 px.

---

## 3 — Rename the canvas routes to `/canvas` and `/canvas/:id`

**Observed.** Routes are `/canvases` and `/canvases/:id` (`lib/psc_web/router.ex`), with 44
references across `lib/`, `test/` and `test/e2e/` (16 in one LiveView test file, 7 in
`canvas.spec.ts`, 6 in the session-controller test, the rest in layouts, pages and controllers).

**Proposal.**
1. Add `live "/canvas"` and `live "/canvas/:id"`; keep the old paths as permanent redirects
   (`/canvases` → `/canvas`, `/canvases/:id` → `/canvas/:id`) so bookmarks and the deployed E2E
   links survive one release.
2. Replace `~p"/canvases"` with `~p"/canvas"` everywhere (navigation, page controller redirect,
   tests, E2E).
3. Update `docs/routing_map.md`.

**Acceptance.** No `"/canvases"` path literal remains except the redirect rules; all tests and
the Playwright suite green; old URLs redirect with 301/308 to the new ones; the nav item still
highlights on `/canvas`.

**Notes.** Keep the *label* "Canvases" (it names the collection) unless #9 decides otherwise.

---

## 4 — Remove the duplicate "Create Template"

**Observed** on `/templates` (both desktop and mobile):
- A **New Template** link top-right → `/templates/new` (the designer).
- A **Create New Template** card with a **Create Template** submit that instantly creates a
  2×2 template and stays on the page.

Two entry points with different outcomes for the same intent; the inline one is also the reason
the template list sits below the fold on mobile (#5).

**Proposal.** Keep **New Template → designer** (the canonical path per ADR-013/014) and delete
the inline create card, redirecting its handler/tests accordingly. If the quick-create shortcut
is wanted, it should be a secondary action inside the designer's "blank template" flow, not a
third form on the list.

**Also fix while in this file (found during the pass).** The inline form's labels point at
non-existent ids (`for="new-template-name"` vs input `id="name"`, same for description), and the
generic ids `name`/`description` are shared with the new-canvas form's convention.

**Acceptance.** One create-template affordance; no inline create form; list moves up
accordingly; the designer is reachable from the header action; LiveView tests updated.

---

## 5 — Mobile layout for the templates list (to resemble the canvas editor)

**Observed (390 px).** The page is a vertical stack of boxed panels: `Templates` heading at
122 px, the create panel from 188 px, and **"Available Templates" only starts at 550 px** —
below the fold, with the first card at 594 px. Double padding plus nested `rounded-xl` panels
make it feel unlike the tight canvas editor.

**Proposal (pattern to match the canvas editor).**
- One compact header row: title + primary action, like `#canvas-header` (this also removes the
  separate create panel, see #4).
- Full-width content, no nested card-in-page padding; keep the grid `grid-cols-1` on mobile and
  `md:grid-cols-2 lg:grid-cols-3`.
- Keep card padding but align the action row (#6) and let meta text truncate.

**Acceptance.** At 390 px the first template card is visible without scrolling (or within one
short scroll); header uses a single row; no horizontal overflow; desktop layout unchanged.

---

## 6 — Make the template card actions consistent

**Observed** (computed styles, dark theme):

| Action | Height | Font | Radius | Border | Variant |
|---|---|---|---|---|---|
| Use Template | 32 px | 12 px | 6.4 px | none | filled primary |
| Edit | 34 px | 14 px | 8 px | 1 px `base-content/10` | raw link |
| Share | 32 px | 12 px | 6.4 px | none | ghost |
| Delete | 32 px | 12 px | 6.4 px | none | ghost (red text) |

Only "Edit" has an outline, and that outline is 10 % opacity — invisible in light mode. Mixed
heights and font sizes make the row look accidental.

**Proposal.** One family: primary **Use Template**; `outline`-style **Edit**, **Share**,
**Delete** all at `size="sm"` with the same height/radius/font and a `border-base-content/20`
outline (theme token, so light mode shows it). Replace the raw `<a class="...">` Edit with the
same `UIButton` component so all four share padding and focus rings.

**Acceptance.** All four buttons share height, radius, font size and outline colour; the row
wraps cleanly at 390 px; visible outline in light and dark; `Delete` still reads as destructive.

---

## 7 — Mobile layout for the designer (`/templates/:id`)

**Observed (390 px).** The grid table is 261 px wide and **overflows internally**; every cell
input collapses to 14–18 px wide (`column-c1-label` 18 px, `cell-r1_c1-label` 17 px,
`cell-r1_c1-field-content` 14 px, `cell-r1_c1-new-field` 14 px). The structure is unusable on a
phone even though the page itself does not scroll horizontally.

**Proposal.** Pick one and document it:
- **(a) Scrollable grid (fast).** Give the table the canvas-editor treatment: `table-fixed`,
  a computed `min-width` (row-label column sized from the longest label + 12 rem per column),
  an `overflow-auto` wrapper, and the outer rounded frame. Cells stay editable, the user pans.
- **(b) Stacked cards (better UX).** Below `sm`, render one card per **row** with each cell as a
  block (label input, field rows, add-field form); the desktop keeps the table. More markup but
  no horizontal panning.

Recommendation: ship (a) now (shares the canvas grid utilities), then (b) if phones matter.

**Acceptance.** At 390 px every input is ≥ 120 px wide or reachable by panning; no clipped
controls; add/remove row/column reachable; save/cancel visible; desktop unchanged.

---

## 8 — "Template saved" alert should be green

**Observed.** Saving the designer triggers `put_flash(:info, "Template saved")`; the card renders
with `data-flash-kind="info"`, the indigo primary border (`oklab(0.58 0.0288 -0.2312 / 0.4)`),
the information icon and primary badge. Success reads as neutral information.

**Cause.** The flash component only supports `:info` and `:error` kinds
(`lib/psc_web/components/core_components.ex`; `Layouts.flash_group/1` renders those two).

**Proposal.** Add a `:success` kind (green border/badge/icon `hero-check-circle`, auto-dismiss
like info) and use it for positive outcomes: template saved/created/shared, canvas
created/deleted, access removed, password updated. Keep `:info` for neutral messages ("Welcome
back!") and `:error` unchanged.

**Acceptance.** "Template saved" renders green with a check icon; light-mode contrast ≥ 4.5:1
against the card background; no regression to error/info cards; unit/browser check in both
themes.

---

## 9 — Canvas list: "Templates" instead of "Canvases"? (decision needed)

**Observed labels.**
- Nav: **Canvases**, **Templates**.
- `/canvases`: h1 **Canvases**; section **Create New Canvas** with a **Template** select
  (default "Blank canvas"); section **My Canvases**; empty state "No canvases yet."
- `/templates`: h1 **Templates**; **Create New Template**; **Available Templates**; card action
  **Use Template** (creates a canvas).

**Ambiguity.** Two readings of the ask:
- **(i)** The canvas list page should be titled **Templates** — that contradicts its content
  (it lists canvases) unless the product model changes to "a canvas is an instantiated template".
- **(ii)** The *entry point* should be template-first: the nav/landing experience leads with
  templates, and the canvas list is a secondary "My canvases" view.

**Decision needed.** Pick (i), (ii), or "keep as-is, only clarify the create section copy".
Default if nobody decides: keep the noun "Canvases" for the list, but rename the create section
to **"Start a canvas"** and make the template picker the first field with an explicit
"Blank canvas" option (copy-only change).

**Acceptance.** All user-facing labels use the ADR-010 vocabulary consistently; nav, page title
and empty states agree; screenshots at desktop and mobile.

---

## 10 — Fix the active-users tooltip

**Observed** (`#active-users-tooltip` in the canvas editor, 390 px):
- Hovering the trigger opens it (`data-state="open"`); moving the pointer away leaves the content
  visible for a while — one measurement still showed `open: true` with `state: "closed"` ~900 ms
  after leaving, then it finally hid. There is no fade: the content is hidden by `hidden=""`
  (display none).
- With `side="bottom"`, `align="end"` and a 243 px content box, the position is computed from the
  trigger with **only a flip** when space runs out; there is no horizontal clamping, so a trigger
  near an edge can push it off-screen.
- On touch there is no hover-out and the tooltip configures **no outside-click dismissal**
  (`onOutsideClick` is not passed), so a tap-opened tooltip stays until something else steals it.

**Root causes in the vendor code.**
- `assets/js/ui/core/positioner.js`: `getFlippedPlacement/3` flips the side but never shifts
  `x`/`y` into the viewport (no `Math.min/Math.max` clamp).
- `assets/js/ui/components/tooltip.js`: triggers are `mouseover`/`focusin` only; content closing
  depends on `mouseout`/`focusout`; no `pointerdown`/scroll dismissal.
- Timing mismatch: the tooltip's animation config runs a 130 ms JS timer and then applies
  `hidden`, while the CSS exit animation (`tw-animate.css`) is 150 ms — so the exit is cut
  before it fades.

**Proposal.** (1) Clamp the computed position into
`{top: 8, right: viewport-8, bottom: viewport-8, left: 8}` after flip. (2) Add a
`clickOutside`/`pointerdown` + `scroll` close for tooltips. (3) On touch, make the trigger
toggle on `click` and close on the next outside tap. (4) Align the JS duration with the CSS one
(or let CSS own the timing). Prefer fixing the shared components over special-casing the canvas.

**Acceptance.** Tooltip never leaves the viewport at 320/390/768/1192 px for triggers at left,
centre and right; closes within ~150 ms of the pointer leaving; closes on outside tap/click;
fades out instead of blinking; no memory/listener leaks after LiveView patches.

---

## 11 — Why does "canvas" appear so much, and what can be pruned?

**Observed counts** (`lib/` only): **559** occurrences of "canvas" (case-insensitive); **21**
modules under `lib/psc/canvas/`; **28** `…Canvas…` modules in total; **44** references to the
`/canvases` path.

There are **three generations** of the same noun in the tree:

| Generation | Modules | Status |
|---|---|---|
| Legacy fixed PSC canvas | `Psc.Canvas.Canvas`, `CanvasLive.Index/Editor`, and 15 fixed-cell schemas (`Problem`, `Leverage`, `Solution`, `SolutionCluster`, `Horizon`, `OuterEnvironment`, `InnerEnvironment`, `Evolvability`, `EvolvabilityCluster`, `Potential`, `Manifestations`, `Capabilities`, `Merit`, `MeritCluster`, `Mission`) | reachable only via `/psc-canvas`, not linked anywhere |
| Templates | `Psc.Canvas.Layout`, `CanvasLayoutLive.Index/Editor` | live feature, named "Layout" while the product says **Template** |
| Configurable canvas | `Psc.Canvas.UnstrCanvas`, `UnstrCanvasEvent`, `UnstrCanvasCRDT`, `UnstrCanvasLive.*` | live feature, `Unstr` prefix is historical |

**Proposal (in this order).**
1. **Delete the legacy generation** (matches the earlier P0-2 idea): remove `/psc-canvas` routes,
   `CanvasLive.*`, the 15 fixed-cell schemas and `Psc.Canvas.Canvas`, plus their tests — the
   single biggest reduction (~18 modules) and it removes the `/canvases` vs `/psc-canvas`
   confusion.
2. **Rename to product vocabulary**: `Layout` → `Template`, `CanvasLayoutLive` → `TemplateLive`,
   `UnstrCanvas` → `Instance` (or `CanvasInstance`), `UnstrCanvasLive` → `CanvasLive`,
   `UnstrCanvasEvent`/`CRDT` accordingly. Do it as mechanical commits after #3 so the route
   rename and the module rename do not collide.
3. Leave the `Psc.Canvas` context name (it is the aggregate root) and the `canvases` DB table
   alias alone unless a migration is already planned.

**Acceptance.** No module named for an implementation detail (`Unstr`, `Layout`) or for a
deleted feature (`CanvasLive` legacy); `grep -ri unstr lib test` empty; test count unchanged
apart from deleted legacy tests; routes and docs consistent; one commit per rename step.

---

## Outcome — implemented 2026-10-19 (ADR-022)

All items except the module renames in #11 are in the code and verified in the running app.

| # | What shipped |
|---|---|
| 1 | Shell `main` padding 32 → 24 px and inner `py-*` removed from the canvas list, templates list, documents list and designer. First heading now at **80 px** on every measured route (was 120–138). The default container is `w-full` (auto margins on a flex item otherwise shrink it to fit-content, which had been narrowing auth forms). Editor pages use **8 px** horizontal gutters on phones, and the designer's grid card is full-bleed below `sm` (header keeps its own padding) — the table starts at **9 px** from the viewport edge in both editors (was 41 px in the designer, 17 px in the canvas editor). |
| 2 | Auth inputs **16 px / 44 px** below `sm`, containers `max-w-md`: the register form is now **358 px (92 %)** of a 390 px viewport, so iOS no longer zooms on focus. |
| 3 | Routes are `/canvas` and `/canvas/:id`; `GET /canvases` and `/canvases/:id` redirect via `PscWeb.RedirectController`. Router, layouts, pages, tests and E2E updated. |
| 4 | Inline create card, its handler, default layout map and test removed; **New Template** (→ designer) is the only creation path. |
| 5 | Templates list: compact header row, `max-w-6xl` content, no nested create panel, and an explanatory empty state. At 390 px the first card starts at **160 px** and the page fits one screen. |
| 6 | All four card actions now share height 32 px, font 12 px, radius 6.4 px; Edit/Share/Delete use the `outline` variant (theme-token border, visible in light mode); Delete keeps destructive text. |
| 7 | Designer grid keeps a computed `min-width` (`10rem + 14rem × columns`) inside an `overflow-auto` wrapper: inputs went from **14–18 px** to **54–190 px** at 390 px, panning horizontally instead of collapsing. |
| 8 | `:success` flash kind added (green border/wash/badge, check icon, auto-dismiss, progress bar). "Template saved", template created/deleted/shared, access removed, canvas created/deleted/shared, document created/shared and "Email changed" now use it. Verified: `data-flash-kind="success"`, green border, check icon. |
| 9 | Copy-only default applied: the list keeps its "Canvases" noun; the create section is **"Start a canvas"** with **"Start from"** (template picker) first, then name and description. |
| 10 | Positioner clamps into the viewport (8 px edge); tooltips close on outside press (mouse/touch) and toggle on tap; JS hide timer aligned to the 150 ms CSS exit. Verified open-on-hover inside the viewport at 300 px and closed on an outside click. |
| 11 | Legacy fixed canvas **deleted**: `/psc-canvas` routes, `PscWeb.CanvasLive.{Index,Editor}`, `Psc.Canvas.Canvas` + 15 embedded cell schemas, 11 legacy context functions, the `canvas_fixture` and their test file (≈18 modules). **Not done:** renaming `UnstrCanvas*` → `Canvas*`, `Layout` → `Template`, `CanvasLayoutLive` → `TemplateLive` — mechanical but wide; tracked below. |

**Still open from #11.** The module renames are the remaining half. Suggested order: (a)
`CanvasLayoutLive` → `TemplateLive` (2 modules, router, tests), (b) `Psc.Canvas.Layout` →
`Template` (context + fixtures + tests), (c) `UnstrCanvas*` → `Canvas*`/`Instance` (context,
CRDT, events, LiveViews, tests, logger strings). Table names stay unchanged.

**Follow-up (2026-10-19): fullscreen cells on phones.** Below `sm`, the first tap on a canvas
cell expands it to the viewport (`is-expanded`, body scroll locked, floating close button in the
bottom-right) with a short scale/fade animation (skipped under `prefers-reduced-motion`); a
second tap enters editing, and the button/Escape returns to the grid (with an exit fade).
Swiping horizontally moves between columns and vertically between rows, handing the fullscreen
state to the neighbour; vertical swipes scroll instead when the cell content is taller than the
screen. The transition is directional: the cell slides out with the finger and the next one
arrives from the opposite edge (`is-swipe-out-*` / `is-swipe-in-*`). The first tap is captured
before the markdown display's own click listener, so a tap never drops straight into edit mode
(the bug found on a real phone). Desktop still opens the field on the first click. Covered by
the E2E tests `canvas editor mobile fullscreen cells` (mouse and real touch events).

**Follow-up (2026-10-20): visible mobile feedback and view state.** Share dialogs now cap
their height, scroll internally, and follow the visual viewport while the mobile keyboard is
open. Feedback cards move above the bottom app bar below `lg`, while desktop keeps the
top-right placement. Canvas tab patches replace the current history entry, so Back leaves the
editor for the canvas library. Rendered Markdown cells use tighter line height and block
margins. Template accent coverage now saves, reloads, and renders the persisted row/column
tokens; no data-model change was needed because accents already belong in `layout_map`.

**Follow-up (2026-10-20): header-owned index titles.** The shared route title is now the
single semantic page heading and uses larger typography. The Canvases and Templates index
pages no longer repeat that title in the main body, leaving the available space for their
forms, actions, and library sections. The **New Template** action is the first tile of the
library grid — the same size as a template card, with a dashed border marking it as the
create action — so the header keeps only the route title.

**Follow-up (2026-10-20): card text stays inside its card.** A canvas description with a
long unbreakable token used to paint past the card's border (measured: 596 px of overflow
on a 373 px card). Card names now break on word boundaries and descriptions both break
long tokens and clamp to two lines, in the canvas list and the template library.

**Follow-up (2026-10-20): the page no longer scrolls on a phone.** The body was
`min-h-screen` (100vh) while the app is sized in `dvh` (100dvh). On a phone 100vh is the
*large* viewport — taller than the app by the height of the browser toolbar — so the page
scrolled vertically and left an empty strip under the app. On a desktop, where `vh` and
`dvh` are identical, this was invisible, which is why it only showed on the phone. The
body now uses `min-h-dvh`, and the document editor's `h-screen` frame became `h-dvh`.

**Follow-up (2026-10-20): instant tab switching.** Clicking a tab used to wait for the
server: the click pushed a patch and the server re-rendered the whole view, grid and
Markdown included — a network round trip on the critical path, which read as a lag on a
phone. Every view is now rendered and the inactive ones hidden, and a `CanvasTabs` hook
swaps the panel synchronously with the click (0.4 ms). The server still owns the state and
the URL, and confirms a moment later. The selected tab is styled from `aria-selected` in
CSS so the client can move the highlight without duplicating utility classes.

**Follow-up (2026-10-20): tighter editor header.** The gap between the canvas description and
the table dropped from 30 px to 14 px. Two causes: the share dialog's root was a zero-height
flex item between the header and the grid, so it opened a gap of its own on each side (it is
now rendered out of the flow), and the workspace gap went from 12 px to 8 px.

**Follow-up (2026-10-20): view state in the URL.** The phone fullscreen cell is now a URL
state (`#cell-<key>`): entering it pushes a history entry, so Back collapses the cell and
returns to the canvas grid instead of leaving the canvas, and the view can be linked and
reloaded. Swiping to a neighbour replaces the fragment rather than stacking entries. The
share dialog no longer scrolls the page — it is kept inside the visible viewport by moving
it with `top` when the keyboard opens, so the grid behind it no longer jumps. The bottom
app bar's height is now a known value (3.75 rem plus the safe-area inset) and the editor
reserves exactly that below the grid, so the table ends just above the bar — a 6 px sliver
of breathing room rather than a dead band or a welded-on edge. The panel is never nudged with a transform: Tailwind v4 centres it
with the `translate` property, so a transform on top of it shifted half the dialog off the
screen.

---

## Notes / incidental findings

- ~~The inline "Create New Template" form's labels are not associated with their inputs.~~
  Fixed by removing the form (#4); the canvas form's `<.input>` labels are associated.
- ~~The canvas card renders an empty `<p>` for a blank description.~~ Fixed: the description
  paragraph is only rendered when non-empty (canvas and template cards).
- Automated clicking in Playwright occasionally times out on this app ("visible, enabled and
  stable") even though the element is on screen; `element.click()` via `evaluate` (or
  `force: true`) works. The hidden reconnect flash cards contain infinite `animate-spin`
  spinners, which is the likeliest culprit — worth a look if E2E gets flaky.
