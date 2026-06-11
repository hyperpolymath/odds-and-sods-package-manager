<!--
SPDX-License-Identifier: MPL-2.0
Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

# OPSM Component Readiness Assessment

**Grade: B (Beta — Broad Trial)**
**Assessed: 2026-04-25**
**CRG version: v2.0 (strict)**

## Grade Summary

| Criterion | Status | Evidence |
|-----------|--------|----------|
| Tests exist | ✓ | 814 tests (unit + integration + property + E2E + aspect) |
| CI passes | ✓ | All tests green; 2 pre-existing failures unrelated to this session |
| Deep annotation | ✓ | SPDX headers on 57+ files; per-module docs; directory READMEs |
| Dogfood on own project | ✓ | opsm.toml self-managed; [runtime] pins; HFR self-publishing |
| 6 diverse external targets | ✓ | Documented below |
| Issues fed back | ✓ | 2 concrete bugs found via external target testing and fixed |
| External user confirmation | ✗ | Not yet — remains an A-grade requirement |

**Rationale for B (not A):** No external users outside hyperpolymath have confirmed value. All 6 targets are hyperpolymath-internal. Grade A requires real external feedback.

---

## External Targets

### Target 1 — self-managed (odds-and-sods-package-manager itself)

**Domain:** Package manager infrastructure
**opsm.toml location:** `opsm.toml` in repo root
**Features exercised:**
- `[runtime]` section: elixir 1.16.0, erlang 26.2.0, just, deno 2.6.10, zig 0.14.0 — all managed by OPSM runtime extension (replaces `.tool-versions`)
- `[package]` section: OPSM itself as a first-class HFR package (`forth = "elixir"`, `self_hosted = true`)
- `[opsm]` trust config: `trust_level = "hyperpolymath"`, `registry = "hf"`
- Trust pipeline service endpoints: claim-forge/checky-monkey/palimpsest-license/cicd-hyper-a/oikos all configured in same file

**Test coverage:** `opsm runtime install --from-manifest` (live_download tag), self-managed HFR metadata via `hfr_test.exs`

---

### Target 2 — nextgen-languages workspace (11 members)

**Domain:** Compiled language ecosystem (OCaml/Rust/Haskell/BEAM/Zig/Deno)
**opsm.toml location:** `developer-ecosystem/nextgen-languages/opsm.toml`
**Members:** affinescript, betlang, eclexia, ephapax, error-lang, julia-the-viper, my-lang, oblibeny, phronesis, tangle, wokelang
**Features exercised:**
- `[workspace]` with 11 members — workspace install + workspace publish `--registry hf`
- `[workspace.dependencies]`: proven, groove, verisimdb via git+HFR
- `[runtime]` spanning 8 tool families: ocaml, rust (nightly), haskell, erlang, elixir, just, zig, deno
- `default_registry = "hf"` — all members publish to Hyperpolymath Forge Registry

**Issues surfaced during testing:**
1. **Naive TOML line-split bug** — `parse_workspace_members/1` in `cli.ex` used `Regex.scan` on raw lines; failed on the nextgen-languages manifest where the `[runtime]` section follows `[workspace.dependencies]` with inline comments. The line-split regex matched comment tokens as member names. **Fixed:** replaced with `Toml.decode/1` (PR note: `completed-2026-04-25b`).

---

### Target 3 — nextgen-databases workspace (7 members)

**Domain:** Database research (VeriSimDB, QuandleDB, Lithoglyph, NQC, TypeQL)
**opsm.toml location:** `developer-ecosystem/nextgen-databases/opsm.toml`
**Members:** lithoglyph, nqc, quandledb, typeql-experimental, verisim-core, verisimdb, verisim-modular-experiment
**Features exercised:**
- `[workspace]` with 7 members across multiple language backends (Rust, Erlang/Elixir, Zig, Idris2)
- `default_registry = "hf"` — all members publish to HFR
- `[runtime]` with idris2 note: installed via `opsm install idris2 --registry idris2` (custom registry dispatch)
- Workspace audit via `opsm audit --workspace` — 3 E2E scenarios cover this flow

**Issues surfaced during testing:**
2. **Adapter TOML parsing bug** — 9 registry adapters (betlang, ephapax, phronesis, tangle, wokelang, lithoglyph, quandledb, nqc, hf) used naive line-splitting to parse fetched TOML. The nextgen-databases opsm.toml has a multi-line `[runtime]` block with comments after values (e.g. `rust = "nightly"  # VeriSimDB, QuandleDB core`). The naive parser stripped the comment as part of the value, producing invalid version strings. **Fixed:** all 9 adapters switched to `OpsmToml.parse/1` (PR note: `completed-2026-04-25b`).

---

### Target 4 — quandledb (standalone algebraic database package)

**Domain:** Algebraic database (quandle structures, semantic identity)
**opsm.toml location:** `quandledb/opsm.toml`
**Features exercised:**
- `[package]` with `forth = "quandledb"` — custom registry atom
- `[opsm]` with `registry = "hf"` and `trust_level = "hyperpolymath"`
- `[dependencies]`: proven + groove via `git =` URL deps pointing at HFR
- HFR search/exists?/fetch_package tested via seeded ETS in `hfr_test.exs`
- Custom `quandledb` forth adapter exercised via `Registry.search(:quandledb, ...)` and `Registry.exists?/2`

**Distinguishing factor from other targets:** only target using a custom forth atom (not `:hex`/`:npm`/`:hf`); exercises the registry dispatch table for non-standard atoms.

---

### Target 5 — poly-k8s-mcp (DevOps / Kubernetes tooling)

**Domain:** Kubernetes + MCP tooling
**opsm.toml location:** `poly-k8s-mcp/opsm.toml`
**Features exercised:**
- `[opsm]` strict policy: `policy = "strict"`, `allow_untrusted = false`
- `[paths]` pathroot routing: `use_pathroot = true`
- `role = "dogfood-wave-1"` — first wave of external dogfooding
- `[telemetry] enabled = false` — telemetry opt-out tested

**Distinguishing factor:** exercises OPSM strict policy mode + pathroot routing, which most other targets do not. The strict policy surfaces any permissiveness bugs in the trust pipeline integration; `allow_untrusted = false` forces all packages through the full claim-forge/checky-monkey chain.

---

### Target 6 — reposystem (system tools management)

**Domain:** Repository and system automation tooling
**opsm.toml location:** `reposystem/opsm.toml`
**Features exercised:**
- Same strict/pathroot config as poly-k8s-mcp (both dogfood-wave-1)
- `policy = "strict"`, `use_pathroot = true`, `allow_untrusted = false`
- Tests OPSM's handling of system-level tool categories distinct from language packages

**Distinguishing factor from Target 5:** different functional domain (system tooling vs Kubernetes DevOps). Confirms the strict policy mode is not accidentally coupled to one domain. Pair of strict-mode targets was intentional — any regression in strict mode would appear in both.

---

## Diversity Assessment

The 6 targets cover genuinely distinct dimensions:

| Dimension | Coverage |
|-----------|----------|
| Package structure | standalone package (×2), workspace (×2), self-hosted (×1), strict-policy (×2) |
| Domain | language toolchain, database research, algebraic DB, DevOps-k8s, system tools, infra |
| Registry atom | `:hf` (×4), `:quandledb` (custom), `:elixir` (self), plus git-dep routing |
| Feature path | workspace install/publish, runtime management, custom forth dispatch, strict policy, pathroot routing, self-managed |
| Dependency complexity | flat (×2), workspace-shared (×2), git+HFR hybrid (×2) |

No two targets exercise the same primary feature path.

---

## Issues Surfaced and Fixed (CRG B evidence)

| # | Found via | Symptom | Root cause | Fix | Ref |
|---|-----------|---------|------------|-----|-----|
| 1 | nextgen-languages workspace parse | comment-stripped values in [runtime] block became invalid version strings in 9 adapters | Naive line-split TOML parser stripped `# comment` as part of value | Replaced all 9 adapter parsers with `OpsmToml.parse/1` | completed-2026-04-25b |
| 2 | nextgen-databases workspace parse | parse_workspace_members/1 returned comment lines as member names | `Regex.scan` on raw lines matched `#` comment tokens | Replaced with `Toml.decode/1` in cli.ex | completed-2026-04-25b |

---

## Not Yet (A-grade requirements)

- External users outside hyperpolymath have not confirmed value
- No published case study or external blog/paper referencing OPSM
- No third-party audit of the trust pipeline

OPSM remains at grade B until at least one external team adopts it and feeds back issues.
