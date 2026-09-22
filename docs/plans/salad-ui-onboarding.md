# SaladUI Onboarding Plan

Status: researched 2026-09-23, NOT yet executed.
Topic: adopt [SaladUI](https://github.com/bluzky/salad_ui) (shadcn-inspired LiveView
component library) as the project's component library.

## 1. What SaladUI is (verified facts)

- Hex package `salad_ui` **1.0.0** (published Aug 11, 2026), MIT, ~1.1k GitHub stars,
  actively maintained (latest commit ~Aug 2026). Demo/storybook at
  `https://salad-storybook.fly.dev/`, docs at `https://salad-ui.hexdocs.pm/`.
- ~40 function-component modules (`button`, `dialog`, `table`, `form`, `input`, `toast`,
  `sidebar`, `chart`, …). Missing vs shadcn: carousel, combobox, drawer, input-otp,
  context-menu. Elixir unit tests exist for most components (`test/salad_ui/`); the
  author notes v1 components are not fully covered.
- Runtime deps (from Hex): `igniter ~> 0.6`, **`phoenix_live_view ~> 1.2`**,
  `sourceror ~> 1.9`, `tw_merge ~> 0.1`. Own requirement: `elixir ~> 1.14`.
- Tailwind v4 compatible (repo upgraded to v4 ~2 months ago). Ships its own
  `salad_ui.css`, shadcn-style color-scheme CSS vars (`priv/static/assets/colors/*.css`),
  `tailwind.colors.json`, vendored `tw-animate.css`, and a JS framework
  (`assets/salad_ui/`: `core/` state-machine/portal/positioner utils + per-component
  `components/*.js`, all wired through one `SaladUIHook`).
- Both install tasks are **Igniter-based** (`use Igniter.Mix.Task`).

## 2. Prerequisite: LiveView 1.1 → 1.2 (BLOCKER, do first)

`salad_ui` hard-requires `phoenix_live_view ~> 1.2`; we are on **1.1.33** with a
`~> 1.1.0` constraint. Nothing else blocks 1.2 (only `phoenix_live_dashboard`
constrains LV, with `~> 0.19 or ~> 1.0`, which permits 1.2).

Steps (already audited in `docs/plans/elixir-otp-phoenix-upgrade-preflight.md` §4):

1. `mix.exs`: `{:phoenix_live_view, "~> 1.1.0"}` → `"~> 1.2.0"`.
2. `config/config.exs:41`: `:colocated_js` → `:colocated_assets` (renamed in 1.2;
   current key becomes a deprecation warning, which fails our `--warnings-as-errors` gate).
3. Add missing `id` to **3 forms with `phx-change` but no `id`** (LV 1.2 warns; form
   recovery needs an id) — all in `lib/psc_web/live/unstr_canvas_live/editor.ex`:
   line 368 (`update_name`), 444 (`update_description`), 515 (`update_cell`).
4. `mix deps.get && mix verify` green before touching SaladUI.

## 3. Decision: `salad.setup` vs `salad.install` → use `install`

| | `mix salad.setup` (library) | `mix salad.install` (local, RECOMMENDED) |
|---|---|---|
| Components | imported from `SaladUI.*`, not customizable | ~40 `.ex` files copied to `lib/psc_web/components/ui/`, fully editable |
| JS | references package JS | copied to `assets/js/ui/` |
| Runtime dep on `salad_ui` | yes, forever | only needed for `tw_merge` (see §5) |
| Prefix | none (`SaladUI.Button`) | `--prefix` rewrites module names |

For this project (custom canvas UI, will restyle components): **local install**.

Recommended invocation:

```bash
mix salad.install --prefix PscWeb.Components.UI --color-scheme slate
```

- `--prefix PscWeb.Components.UI` (not the default `PscUi`): modules land at
  `lib/psc_web/components/ui/*.ex` as `PscWeb.Components.UI.Button`, matching path
  convention and the existing `PscWeb.*` namespace. (Default prefix is
  `Phoenix.Naming.camelize("psc_ui")` = `PscUi`, which would not match the file paths.)
- `--color-scheme slate`: neutral gray-blue that fits a canvas/productivity tool.
  Any of gray/slate/stone/neutral/red/orange/amber/yellow/lime/green/emerald/teal/cyan/
  sky/blue/indigo/violet/purple/fuchsia/pink/rose. Re-runnable choice; only affects
  the appended `@layer base` vars.

## 4. What the installer will change (so the diff is no surprise)

From the installer source (`lib/mix/tasks/salad.install.ex`, `salad.setup.ex`):

1. `lib/psc/application.ex` — adds `TwMerge.Cache` to the supervision tree
   (via `Igniter.Project.Application.add_new_child`).
2. `assets/css/app.css` — appends `@layer base { <color-scheme vars>, border-color … }`,
   inserts `@import "./salad_ui.css";` after the last `@import`, and patches Tailwind v4
   sources/plugins/theme tokens (TailwindPatcher).
3. `assets/css/salad_ui.css` — created (copied from package).
4. `assets/tailwind.colors.json` — created (design tokens, compat).
5. `assets/vendor/tw-animate.css` — downloaded (**needs network at install time**).
6. `assets/js/ui/` — ~30 JS files copied (`index.js`, `core/*`, `components/*`).
7. `assets/js/app.js` — patched via JSPatcher: adds the `import SaladUI from "./ui/index.js"`
   block + per-component imports, registers `SaladUI: SaladUI.SaladUIHook` in the
   `LiveSocket` hooks map alongside our `EditorHook`, `CellHook`, `MarkdownField`.
8. `lib/psc_web/components/ui/` — ~40 component modules + `ui.ex` index, all rewritten
   to the `--prefix`.

## 5. Integration points & pitfalls (project-specific)

### 5a. daisyUI coexistence (biggest open question)

We ship daisyUI (`@plugin "../vendor/daisyui" { themes: false }`) plus two custom
`daisyui-theme` light/dark themes driven by `data-theme` + `localStorage`
(`root.html.heex`), with `bg-base-100 text-base-content` on `<body>`.

- SaladUI does **not** use daisyUI classes; it uses its own shadcn-style CSS vars
  (`--background`, `--primary`, … in the appended `@layer base`). The two systems
  coexist at the CSS level (different class/var namespaces), so nothing breaks on install.
- But our `data-theme` light/dark toggle will **not** recolor SaladUI components.
  shadcn-style schemes define `:root` + `.dark` vars; our dark mode is
  `[data-theme=dark]`. Decide during implementation: (a) leave SaladUI light-only
  initially, (b) map the scheme vars onto both `:root` and `[data-theme="dark"]`,
  or (c) drop daisyUI themes later. **Verify visually with a screenshot** (per
  DEVELOPMENT.md vision-first rule) before calling this done.
- AGENTS.md currently says *"Always manually write your own tailwind-based components
  instead of using daisyUI"*. Adopting SaladUI supersedes that rule — update AGENTS.md
  (JS/CSS guidelines section) as part of this work so future sessions don't get
  contradictory instructions.

### 5b. Component name collisions with CoreComponents (will break compile)

`PscWeb.CoreComponents` is imported **globally** via `html_helpers()` in `lib/psc_web.ex`,
and it defines `button`, `input`, `table`, `modal`, etc. — the same names SaladUI uses.
Importing both unqualified in one module is a **compile error** (ambiguous import).

Strategy (do not globally import SaladUI):

- Keep `import PscWeb.CoreComponents` as-is; import SaladUI modules **per LiveView**
  (`import PscWeb.Components.UI.Button`) only where used.
- Where a collision occurs, prefer the SaladUI component and migrate that template off
  the CoreComponents one; do not import both names in the same module.
- Long-term: shrink `core_components.ex` as SaladUI coverage grows (it stays for
  `translate_error`, flash, and auth-generated templates until migrated).
- SaladUI form components + our `to_form/2` convention: SaladUI has its own `form.ex`;
  check its `field`/`for` API against AGENTS.md form rules during the first form
  migration (auth templates are the last to migrate, not the first).

### 5c. Keep `{:salad_ui, "~> 1.0"}` in mix.exs even after local install

The installer copies sources, but `TwMerge.Cache` (supervised in application.ex) comes
from `tw_merge`, which we only get transitively via `salad_ui`. Keep the dep; removing
it means adding `tw_merge` directly. Also keep it for re-running the installer.

### 5d. `mix verify` / `precommit` impact

- ~40 new files must compile under `--warnings-as-errors` on Elixir 1.20's type checker.
  Upstream runs credo+styler on them, so expect clean — but `verify` is the proof.
- `precommit` runs `deps.unlock --unused`: `igniter`/`sourceror` stay used (installer
  tasks + `mishka_chelekom`); `tw_merge` stays used via the supervised cache. No action
  expected, but watch the output.
- `.formatter.exs`: add the new `lib/psc_web/components/ui/` path check — inputs already
  cover `{config,lib,test}/**/*.{heex,ex,exs}`, so no change needed. Confirm `mix format`
  doesn't reformat upstream files noisily on first run; if it does, format once and commit.

## 6. Implementation checklist

- [ ] LV 1.2 upgrade (§2): constraint, `:colocated_assets`, 3 form ids, `mix verify` green
- [ ] `mix.exs`: add `{:salad_ui, "~> 1.0"}` (plain dep; installer runs via igniter already present)
- [ ] `mix deps.get`
- [ ] Run `mix salad.install --prefix PscWeb.Components.UI --color-scheme slate` (needs network)
- [ ] Review installer diff (§4): application.ex, app.css, app.js, new `ui/` dirs, vendor css
- [ ] `mix verify` green (format + warnings-as-errors + 179 tests)
- [ ] Dev boot + screenshot a page rendering 2–3 SaladUI components (button, card, dialog)
      incl. light AND dark (`data-theme`) state — decides §5a follow-up
- [ ] Migrate ONE low-risk template to SaladUI components (e.g. document index buttons)
      as the pattern reference; keep CoreComponents for the rest
- [ ] Update AGENTS.md JS/CSS guidelines (SaladUI replaces the no-daisyUI rule)
- [ ] `mix precommit`, commit as its own revertable commit

## 7. Verification (per DEVELOPMENT.md matrix)

- Step 0 `mix verify` — gate: new files warning-free, 179 tests pass
- Step 1–2 `mix test` — covered by step 0; add a LiveView test asserting a migrated
  template renders the SaladUI markup (element-based, `has_element?`)
- Step 3 ad-hoc browser — **mandatory**: screenshot light + dark rendering
- Step 4 `npx playwright test` — existing suite must stay green (no visual assertions on
  migrated pages yet, so this is regression-only)

## 8. Out of scope

- Migrating auth-generated templates (`user_live/*`, CoreComponents flash/modal) — later.
- Removing daisyUI — later, if ever; coexistence is the plan.
- Dark-mode var mapping for SaladUI (§5a options b/c) — decided after seeing screenshots.
