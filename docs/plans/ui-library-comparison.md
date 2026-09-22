# UI Component Library Comparison: SaladUI vs Mishka Chelekom

Status: researched 2026-09-23, NOT yet executed. Decision aid only — no code changes.
Context: project is now on Elixir 1.20.4 / OTP 29.1 / Phoenix 1.8.14 / LiveView 1.2.12.
`mishka_chelekom ~> 0.0.8, only: :dev` is already a dependency but **zero components
have ever been generated** (no `Mishka`/`mishka` references in `lib/` or `assets/`).

## 1. Head-to-head (all facts verified 2026-09-23)

| | SaladUI | Mishka Chelekom |
|---|---|---|
| Hex version | **1.0.0** (Aug 2026) | **0.0.9** (Jul 2026) |
| Design language | shadcn/ui | own system (Flowbite-like: colors × variants × sizes) |
| Component count | ~40 | **80+** (goal: 200), incl. chat, carousel, drawer, combobox, rating, stepper, timeline, gallery, device_mockup — gaps SaladUI has |
| Headless (unstyled, ARIA + hooks) | no | **yes** (Base-UI-for-Phoenix ports, `mix mishka.ui.gen.headless`) |
| Restyle-without-forking | no (edit copied files) | **yes, `MishkaChelekom.Kit`** (Spark DSL `customize`/`from`) |
| LiveView requirement | `~> 1.2` ✅ satisfied | `~> 1.2` **optional** ✅ satisfied |
| Elixir floor | `~> 1.14` ✅ | 1.18+ ✅ |
| Tailwind | v4 ✅ | v4 (migrated in 0.0.8/0.0.9) ✅ |
| Elixir 1.20 + OTP 29 CI | unknown | **yes** (1.20.2/OTP 29 in CI matrix) |
| JS approach | own framework (`core/` state-machine, portal, positioner + `SaladUIHook`) | per-component hooks, pure JS |
| Dark mode | shadcn `:root`/`.dark` vars | **built into every component** (dark variants since 0.0.2) |
| Unit tests | partial (author asks for help) | yes, incl. e2e per mix command |
| AI integration | none | **built-in MCP server** (11 tools, 9 resources; stdio/HTTP/Phoenix-router) + `usage-rules/` + `MCP.md` |
| Popularity | ~1.1k ★, 153k downloads | ~750 ★, 70k downloads |
| License | MIT | Apache-2.0 |
| Prod footprint | `tw_merge` runtime (setup) or none (install) | **zero** — dev-only generator, components vendored |

## 2. Project-specific fit

**daisyUI coexistence.** Both coexist at CSS level (separate namespaces), but neither
follows our `data-theme` toggle. Mishka's per-component dark variants are closer to
mappable than SaladUI's `:root`/`.dark` scheme — still a manual step either way.

**Name collisions.** Both collide with globally-imported `CoreComponents`
(`button`, `input`, `table`, `modal`…). Same remedy both ways: import per-LiveView,
migrate one template at a time. Mishka's `--global` flag (replace CoreComponents
imports project-wide) is powerful but too blunt for now — prefer gradual.

**AGENTS.md.** Either choice supersedes the "hand-write components, no daisyUI" rule;
update the JS/CSS section on adoption.

**Sunk cost: none.** Mishka 0.0.8 sits in `mix.exs` unused. Its transitive deps
(`igniter`, `sourceror`, `owl`, …) are dev-only. Choosing SaladUI means removing it
(`mix deps.unlock --unused` cleans up); choosing Mishka means bumping `~> 0.0.8` →
`~> 0.0.9` (0.0.9 needs `igniter >= 0.8.2`, `guarded_struct ~> 0.1.1` — resolver handles it).

## 3. Recommendation: Mishka Chelekom

1. **You already own it** — dep present, zero generated code, so evaluation is free.
2. **More of what a canvas product needs**: chat, carousel, drawer, combobox, rating,
   stepper, timeline — SaladUI's gaps are exactly our widget surface.
3. **Headless + Kit** is the better long-term architecture: semantic ARIA components
   restyled via Spark DSL beats forking 40 copied files when the design evolves.
4. **Dark mode is built in**, not a mapping project.
5. **MCP server + usage-rules** compound the agentic workflow this repo is built around
   (Tidewave was removed for cost; this is free and local).
6. **Proven on our exact toolchain** (1.20/OTP 29 CI); SaladUI's status there is unknown.

SaladUI wins only on shadcn familiarity and a larger community. If the team already
knows shadcn class names by heart, say so — otherwise Mishka.

## 4. If Mishka: onboarding checklist (mirrors salad-ui-onboarding.md §6)

- [ ] `mix.exs`: `{:mishka_chelekom, "~> 0.0.8", only: :dev}` → `"~> 0.0.9"`; `mix deps.get`
- [ ] Generate ONE component first to learn the workflow, e.g.
      `mix mishka.ui.gen.component button --import --helpers --yes`
      (never `gen.components` all 80+ on day one)
- [ ] Review generated diff: `lib/psc_web/components/`, CSS config, `app.js` hooks
- [ ] `mix verify` green (format + warnings-as-errors + 179 tests)
- [ ] Dev boot + screenshot a page with the component, light AND dark
- [ ] Evaluate headless (`mix mishka.ui.gen.headless dialog`) vs styled for canvas widgets
- [ ] Optionally wire the MCP server (`mix mishka.mcp.setup --stdio`) for agent use
- [ ] Update AGENTS.md JS/CSS guidelines; `mix precommit`; commit as its own commit

## 5. If SaladUI: plan stands

`docs/plans/salad-ui-onboarding.md` remains valid (LV 1.2 prerequisite now satisfied).
Only change: remove `mishka_chelekom` from `mix.exs` + `mix deps.unlock --unused`.

## 6. Out of scope (either choice)

- Migrating auth templates; removing daisyUI; `data-theme` toggle integration —
  decided after screenshots, same as before.

## 7. Styling gap assessment (2026-09-23, user feedback: "Mishka isn't beautiful")

Verified by reading both button implementations, not just screenshots.

**SaladUI default button** (`SaladUI.Helpers.button_variant/1`):
`inline-flex items-center justify-center whitespace-nowrap rounded-md text-sm
font-medium transition-colors focus-visible:ring-ring … disabled:opacity-50`,
variant `bg-primary text-primary-foreground shadow-sm hover:bg-primary/90`.
The polish is in micro-detail: medium font weight, `rounded-md`, subtle
`shadow-xs/sm`, color transitions, focus-visible rings, disabled opacity.

**Mishka default button** (`priv/components/button.eex`, `color_variant/2`):
`bg-primary-light text-white hover:bg-primary-hover-light …` with defaults
`variant="base"`, `font_weight="font-normal"`, `rounded="large"`, `size="large"`.
Flat fills, normal font weight, no transitions/rings/disabled-opacity in the base.
Palette is hand-rolled hex (`--primary-light: #007f8c` teal, `--secondary-light:
#266ef1`, …) — serviceable admin-template colors, not a curated system.

**Verdict: the gap is real but shallow.** It lives in design tokens (palette,
radius, shadows, font weights) and micro-interactions — not component structure.
Both map variant/color/size attrs to class lists; both theme via CSS vars.
Mishka documents the override path in the CSS file itself ("if you want to
override it, call `:root` inside your app.css"), plus the Kit DSL and headless
components for deeper reskins. A palette + base-style pass (~10 hex values,
font-medium defaults, transitions) closes most of the distance.

Options: (A) SaladUI for looks — accept missing chat/carousel/drawer/combobox;
(B) Mishka + re-skin — keep 80+ components, restyle tokens; (C) Mishka headless +
own shadcn-style tokens — most work, most "yours"; (D) hybrid — SaladUI primitives
+ Mishka exotic widgets, but two design languages to reconcile.
Recommendation stands (B, with C for canvas-specific widgets): structural gaps
can't be themed away, but tokens can. Neither default survives contact with a real
product identity anyway (per AGENTS.md world-class-UI rule, the team restyles regardless).
