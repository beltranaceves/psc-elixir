# Elixir / OTP / Phoenix Upgrade — Pre-Flight Plan

Status: researched 2026-09-21, NOT yet executed.
Supersedes the same content previously held in repo memory.

Current: Elixir 1.19.5, OTP 27 (nif_version 2.17, erts 15.2.7.1), Phoenix 1.8.5, LiveView 1.1.26.
Latest: Elixir **1.20.4**, OTP **29.1**, Phoenix **1.8.14** (no 1.9 exists), LiveView **1.2.12**.

## 1. DECIDE OTP FIRST

Windows Elixir installers are OTP-specific (`elixir-otp-27.exe` / `-28` / `-29`). Choosing
OTP late = installing Elixir twice + rebuilding deps twice.

Official compatibility table (`elixir.hexdocs.pm/compatibility-and-deprecations.html`):

- **1.20 → OTP 27–29**
- **1.19 (current) → OTP 26–28**

So: **OTP 29 requires Elixir 1.20+**; Elixir 1.20 runs fine on current OTP 27.
"Only the next minor release effectively leverages the new features of the latest OTP" →
**OTP 29 gives no Elixir-level benefit today** (that'd need 1.21).

**Recommended target: Elixir 1.20.4 + OTP 28.4.** Rationale: OTP 28 keeps Elixir 1.19 as a
rollback path (1.19 supports 26–28); OTP 29 is a one-way door (can't roll Elixir back to 1.19).
Most conservative alt: stay on OTP 27 (`elixir-otp-27.exe`), zero OTP risk.
Note OTP 29: no 32-bit Windows build; cwd now LAST in code path; `array` repr changed
(serialized arrays unreadable); ssl prefers post-quantum KEX.

## 2. SEQUENCING IS CRITICAL — upgrade deps BEFORE installing Elixir

Gate is `compile --warnings-as-errors`. These releases carry explicit *Elixir 1.20 warning* fixes:

- Phoenix 1.8.6 "Fix more deprecation and type checker warnings on Elixir 1.20"
- LV 1.1.26 "Fix type warnings on Elixir 1.20"; LV 1.1.21 "Mark LiveView template code as
  generated to prevent warnings on Elixir 1.20"

Installing 1.20 first → checker analyzes old lib-generated code → build fails on unfixable warnings.
Order: `mix deps.update` → `mix verify` green on 1.19 → THEN install 1.20.

## 3. REPO AUDIT — clean on every v1.20 hard deprecation

Verified absent: `Logger.enable/disable`, `Logger.*_backend`, `Kernel.ParallelCompiler.async/1`,
`<<x::size(y)>>` w/o pin, 3-arg `File.stream!`, CLI config in `def project` (already `def cli`),
`mix do` commas, `xref: [exclude:]`, struct-update w/o pattern match (v1.19). **No code changes
needed for Elixir 1.20 itself.**

## 4. PRE-FLIGHT EDITS

- `mix.exs`: `elixir: "~> 1.15"` → `"~> 1.20"` (intent; `~> 1.15` already permits 1.20).
- `Dockerfile`: `ARG ELIXIR_VERSION=1.19.5`→`1.20.4`, `ARG OTP_VERSION=27.3.4.2`→`28.4`;
  ⚠️ verify `hexpm/elixir:<elixir>-erlang-<otp>-debian-trixie-*-slim` tag exists (NOT verified).
- Only if taking LiveView 1.2:
  - `config/config.exs:41` `:colocated_js` → `:colocated_assets` (deprecated in 1.2)
  - **3 forms with `phx-change` but no `id`** — 1.2 warns on these (form recovery needs id):
    `lib/psc_web/live/unstr_canvas_live/editor.ex` lines 368 (`update_name`), 444
    (`update_description`), 515 (`update_cell`).
  - Only `phoenix_live_dashboard` (`~> 0.19 or ~> 1.0`) constrains LV → nothing blocks 1.2.

## 5. NATIVE CODE (cost of the OTP bump)

- `bcrypt_elixir`: C via `elixir_make` — **NOT cc_precompiler** → always compiles from source →
  needs MSYS2 PATH. All envs.
- `lazy_html`: C via `cc_precompiler` (test only).
- `igniter_js`: Rust via `rustler_precompiled` (dev only) → **OK, no action**: 0.8.4 knows NIF
  versions only up to 2.17, but `find_compatible_nif_version/2` deliberately clamps to the highest
  same-major minor ("In case one is using this lib in a newer OTP version..."). 2.17 artifact loads
  on newer ERTS. 0.9.0 adds no new NIF versions.

An **Elixir-only** upgrade touches none of this (NIF ABI follows ERTS, not Elixir).

## 6. INSTALL SEQUENCE

1. Dep upgrades + `mix verify` green (on 1.19)
2. Pre-flight edits
3. Record `elixir --version` + HEAD for rollback
4. Install OTP (`otp_win64_28.x.exe`)
5. Install matching `elixir-otp-28.exe`
6. **Delete `_build/`** (BEAM not portable across OTP majors) + MSYS2 on PATH + `mix nif.fix`
7. `mix deps.get`
8. `mix verify`

## 7. EXPECT + ROLLBACK

Expect **new** warnings in `lib/` from the stronger 1.20 checker — that's the feature working;
budget for it. (1.19+ `mix test` distinguishes exit codes for warnings-as-errors vs test failures.)
Rollback: reinstall 1.19.5/`elixir-otp-27.exe`, revert floor, wipe `_build`. OTP 28 allows Elixir
1.19; OTP 29 does not.
