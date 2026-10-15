# UI Design Handoff — Fix the Three-Theme Mess

Status: brief written 2026-09-23, NOT yet executed. Hand this file to the design agent.
Context: SaladUI migration waves 1–3 done (buttons, forms, badges, auth pages).
Stack: Elixir 1.20.4 / OTP 29.1 / Phoenix 1.8.14 / LiveView 1.2.12 / Tailwind v4 /
daisyUI (vendored) + SaladUI 1.0.0 (local, `PscWeb.Components.UI.*`).

## 1. The problem (verified by screenshots + source audit, 2026-09-23)

Three design systems render on the same page, uncoordinated:

| System | Owns | Theme mechanism |
|---|---|---|
| daisyUI + custom `daisyui-theme` light/dark | page chrome: `navbar`, `menu`, `btn btn-ghost`, `body bg-base-100`, theme toggle (`data-theme` + localStorage in `root.html.heex`) | `data-theme="dark"` on `<html>` |
| Hand-rolled Tailwind (`bg-white text-gray-900`, `bg-blue-600`, …) | ALL page content: cards, headings, inputs, grid cells (~211 hardcoded occurrences in 17 files) | **none — always light**, invisible on dark page bg |
| SaladUI (`:root`/`.dark` CSS vars) | migrated buttons, inputs, badges, alerts | `.dark` class on `<html>` — **never set** |

Visible symptoms (screenshots): white content cards floating on a dark page; SaladUI
inputs render near-black fill with unreadable placeholder text; form labels
(`text-gray-900` on white card) wash out; headings (`text-3xl text-gray-900`) are
near-invisible against the dark background; auth pages are the worst (white
pill inputs on dark bg, no visible labels since SaladUI inputs are bare).

Root cause: the page background went dark (daisyUI theme) while content was written
for a light page. SaladUI migration made it worse by adding a third, also-unthemed
system. No single decision — accretion.

## 2. The decision the owner must make first

**Option A — commit to dark-first product UI (recommended).**
The chrome (navbar, body, theme toggle) is already dark. Make content follow:
SaladUI `.dark` vars become the default, hand-rolled `bg-white text-gray-900` cards
become dark surfaces. Light mode becomes the fallback, not the default.

**Option B — commit to light-first.**
Revert page chrome to light (`data-theme="light"` default), keep content as-is,
map SaladUI `:root` vars (already light). Less work now, fights the existing
dark chrome + toggle.

**Option C — true dual-theme.**
Map all three systems onto both `data-theme` values. Most work; only if the
product needs a light mode on day one.

Default to A unless the owner says otherwise. Everything below assumes A.

## 3. Scope of work

1. **Token mapping (the core fix).** In `assets/css/app.css`: define SaladUI's
   shadcn vars under BOTH `:root` (light values, already shipped) AND
   `[data-theme="dark"]` (copy the `.dark` block SaladUI shipped, re-scoped).
   Same for any hand-rolled surfaces that survive step 2. Verify: toggle theme,
   SaladUI buttons/inputs/badges must flip. Screenshot both.
2. **Content cards → dark surfaces.** Replace `bg-white text-gray-900` page
   scaffolding with theme-aware tokens (`bg-card text-card-foreground` where
   SaladUI exists; `bg-base-100 text-base-content` elsewhere). Files: all 5 index
   pages + 4 editors + auth pages (~17 files, ~211 hardcoded classes — grep
   `bg-white|text-gray-900|border-gray` to enumerate; many are inside canvas grid
   cells that may legitimately stay light as "paper" — decide per surface).
3. **Headings + labels.** `text-3xl text-gray-900` headings → theme-aware
   (`text-foreground` or keep explicit but visible on both). SaladUI `form_label`
   already handles error color; check its default color on dark.
4. **Inputs audit.** SaladUI `input`/`textarea` on dark: confirm placeholder +
   fill + focus ring contrast after step 1. The near-black fill seen in screenshots
   is the `:root` bg on a dark page — step 1 fixes it.
5. **Keep working:** `<.link>`, `<.form>`, `<.icon>`, flash, editors' grid cells,
   canvas hooks. Don't restyle what isn't broken.
6. **AGENTS.md update.** The JS/CSS section still says "hand-write components, no
   daisyUI" — superseded twice over (SaladUI adopted, daisyUI retained for chrome).
   Rewrite to: SaladUI for components, daisyUI for page chrome, theme tokens in
   `app.css`, `data-theme` is the toggle mechanism.

## 4. Verification (DEVELOPMENT.md matrix, mandatory)

- `mix verify` after every coherent chunk (format + warnings-as-errors + 179 tests).
- **Screenshots are the acceptance test:** every migrated surface captured in
  light AND dark (`data-theme` toggle in navbar). Contrast-check inputs,
  placeholders, labels, buttons, badges in both.
- LiveView tests: extend element assertions (`has_element?`) to the restyled
  markup where selectors changed.
- `npx playwright test` stays green throughout.
- Commit per surface (index pages / editors / auth), not one giant commit.

## 5. Out of scope

- New components (dialog/dropdown/toast adoption) — finish theming first.
- Removing daisyUI or CoreComponents — shrink gradually.
- Product identity / brand palette — this brief is coherence (one theme system),
  not beauty. Palette pass comes after.
- `docs/plans/salad-ui-migration.md` waves are done; this supersedes its §5a
  "decide after screenshots" — the screenshots now exist (see §1).

## 6. Pointers for the agent

- Theme toggle: `lib/psc_web/components/layouts/root.html.heex` (inline script,
  `phx:set-theme`, localStorage `phx:theme`).
- Tokens: `assets/css/app.css` (daisyUI themes + SaladUI `@layer base` appended
  by installer), `assets/css/salad_ui.css`.
- SaladUI usage pattern: qualified aliases (`UIButton`/`UIInput`/`UIForm`/
  `UIAlert`/`UIBadge`) — CoreComponents is global via `html_helpers`, never
  import both unqualified (see `docs/plans/salad-ui-migration.md` §2).
- Error translation: `config :salad_ui, error_translator_function,
  {PscWeb.CoreComponents, :translate_error}` (already set — fallback crashes).
- Server: `set MIX_ENV=dev && set PSC_DB_NAME=psc_e2e && set PSC_PORT=4001 &&
  mix phx.server`; login `e2e@example.com` / `e2e-password-123` (seeded).
  Wait for `.phx-connected` before typing (else LiveView wipes inputs).
