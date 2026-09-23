# UI Migration Plan: Current UI → SaladUI Components

Status: researched 2026-09-23, NOT yet executed.
Basis: runtime exploration of the running app (screenshots of `/`, `/documents`,
`/canvas-designer`, `/canvas-layouts`, `/users/settings`, all as `e2e@example.com`),
SaladUI storybook (`button`, `dialog`, `table`, `form`, `tooltip` playgrounds),
and source audit of `core_components.ex` vs `lib/psc_web/components/ui/*`.

Prerequisite (done, commit `139bac8`): LiveView 1.2.12. SaladUI 1.0.0 installed
locally as `PscWeb.Components.UI.*` (~40 modules in `lib/psc_web/components/ui/`,
JS in `assets/js/ui/`, `TwMerge.Cache` supervised). **Not imported anywhere yet** —
zero usage in templates, so the app renders exactly as before.

## 1. What the app actually looks like (runtime evidence)

Every authenticated page follows one pattern: dark page background (`bg-base-300`-ish),
white rounded card (`bg-white rounded-lg shadow p-8`) holding the content, daisyUI
buttons (`btn btn-primary`), CoreComponents `input` (dark-styled), heroicons.
Pages: `/documents` (list + new-doc form), `/canvases`, `/canvas-designer`
(name/desc/layout create form), `/canvas-layouts` (+ `/new` editor), document/canvas
editors (textarea + presence + share sidebars), auth pages (`login`, `registration`,
`settings`, `confirmation`).

## 2. Collision map: CoreComponents (global) vs SaladUI (local, unused)

`import PscWeb.CoreComponents` is global via `html_helpers()` in `lib/psc_web.ex`.
Same-name components in both — **never import both unqualified in one module**:

| CoreComponents | SaladUI (`UI.*`) | Notes |
|---|---|---|
| `button` (daisyUI `btn`, `variant="primary"`) | `button` (`default/secondary/destructive/outline/ghost/link`, `sm/lg/icon`) | closest swap; SaladUI has no `navigate` support — keep `<.link>` for navigation |
| `input` (label+errors, all types, select/checkbox/textarea) | `input` (bare input only) + `form/form_item/form_label` | NOT 1:1 — CoreComponents `input` bundles label+errors; SaladUI splits them |
| `table` (rows + `row_click`) | `table` (plain table, caption) | CoreComponents richer; migrate simple tables first |
| `modal` | `dialog` / `alert_dialog` / `sheet` | different API (trigger/content slots + JS hook); needs JS verification |
| `flash` (daisyUI toast+alert) | `toast` (+ `toast-flash.js` hook) | toast needs the JS hook path verified in browser |
| `header` | none | keep |
| `list` | none | keep |
| `icon` (heroicons) | `icon` | keep CoreComponents (heroicons wired); do not import SaladUI icon |
| `show/hide`, `translate_error` | — (helpers has own error translator) | keep CoreComponents; optionally set `config :salad_ui, :error_translator_function, {PscWeb.CoreComponents, :translate_error}` |

Rule: import SaladUI **per LiveView** (`import PscWeb.Components.UI.Button`), never
globally. Where names collide, migrate the template fully off the CoreComponents one.

## 3. Migration order (simplest → hardest, each its own commit)

**Wave 1 — drop-in, no JS, no form semantics.** Buttons and badges/cards:
- `document_live/index.ex`: hand-rolled `<button class="...bg-blue-600...">` (New
  Document, Create, Cancel) → `<.button>` variants. Proves the pattern; screenshot.
- `canvas_live/index.ex`, `unstr_canvas_live/index.ex`, `canvas_layout_live/index.ex`:
  same button swap.
- `badge`/`card`/`avatar`/`skeleton` where used (mostly static markup).

**Wave 2 — forms (needs care).** SaladUI `input` is a bare input; label+error
composition moves to `form_item`/`form_label` + `field_errors`. Migrate:
- `canvas_layout_live/editor.ex` (name/desc form, simplest `for={%{}}` form)
- `unstr_canvas_live/index.ex` create form, then `editor.ex` name/desc/cell forms
- Auth pages (`login`, `registration`, `settings`) **last** — they use real changesets
  + `validate_*` events; keep CoreComponents `input` until the SaladUI form pattern
  is proven on a `for={%{}}` form first.

**Wave 3 — JS-driven overlays.** `dialog` (share dialogs?), `dropdown_menu`,
`tooltip`, `popover`, `toast` (replace `flash`). Each needs: hook registered
(`SaladUI.SaladUIHook` already in `app.js` hooks map — verify it loads), interaction
tested in browser (open/close, focus trap), screenshot. One component per commit.

**Never migrate:** `<.link>`, `<.form>`, `<.icon>`, `<.header>`, `<.list>`,
`show/hide`, `translate_error` — no SaladUI equivalent or CoreComponents is better.

## 4. Per-wave verification (DEVELOPMENT.md matrix)

- `mix verify` (format + warnings-as-errors + tests) after every wave.
- LiveView test per migrated template: `has_element?` on the SaladUI markup
  (e.g. `assert has_element?(view, "button.bg-primary")`), not raw HTML.
- **Browser screenshot mandatory per wave**, light AND dark (`data-theme` toggle):
  SaladUI uses `:root`/`.dark` vars, our toggle sets `data-theme="dark"` — expect
  SaladUI components to stay light in dark mode until vars are mapped (known gap
  from `ui-library-comparison.md` §5a; decide fix after seeing it).
- `npx playwright test` stays green throughout (regression-only, no visual asserts yet).

## 5. Out of scope

- Restyling SaladUI tokens to product identity (separate design pass).
- Mapping shadcn vars onto `data-theme="dark"` (deferred until screenshots show it).
- Removing daisyUI / CoreComponents (shrink gradually as coverage grows).
- Auth template migration (Wave 2 last, may stay on CoreComponents indefinitely).
