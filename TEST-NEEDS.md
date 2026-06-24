<!--
SPDX-License-Identifier: CC-BY-SA-4.0
Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
# SPDX-License-Identifier: CC-BY-SA-4.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

# TEST-NEEDS.md — odds-and-sods-package-manager (OPSM)

## Current State (Updated 2026-04-25, v1.5 additions same session)

**CRG Grade: B (Beta — Broad Trial)** — achieved 2026-04-25
_(Previous: C, achieved 2026-04-04)_

| Category            | Count | Status  | Notes                                                       |
|---------------------|-------|---------|-------------------------------------------------------------|
| Unit tests          | ~570  | ✓ PASS  | Core, crypto, git, network, federation, HAR, runtime, wiring |
| Integration         | 8+    | ✓ PASS  | Pipeline, trust pipeline, E2E, git pipeline, manifest roundtrip |
| E2E                 | 55+   | ✓ PASS  | Full install flows, error handling, workspace audit, multi-registry |
| Property-based      | 67    | ✓ PASS  | Lockfile, version constraints, manifest roundtrip, fuzz harness |
| Security aspect     | 18    | ✓ PASS  | Tampering, confusion, poisoning, MITM, path traversal, crypto |
| Concurrency aspect  | 12    | ✓ PASS  | Parallel ops, downloads, serialization, conflict, sync      |
| Audit wiring        | 12    | ✓ PASS  | Wiring.run_audit/2 + workspace TOML parsing                 |
| Registry dispatch   | 18    | ✓ PASS  | Registry.search/3 + exists?/2 for all 8 language adapters   |
| Live service E2E    | 23    | ✓ PASS  | Trust pipeline live HTTP contract (`:live_service` tag)     |
| CVE/OSV scanning    | 30    | ✓ PASS  | Typosquat Levenshtein + homoglyph, OSV client, Scanner      |
| Storage backends    | 18    | ✓ PASS  | Local/S3/IPFS backends + Manager round-trips                |
| Benchmarks          | 27    | ✓ READY | Baselines defined; formal Benchee run pending               |

**Source modules:** ~250 own source files (Elixir + Rust + Idris2).

**Test Summary (2026-04-25, including v1.5):**
- Total: 1 doctest + 67 properties + ~794 tests = **862 tests** (e2e + integration included)
- Passes: 860
- Pre-existing failures: 0
- Skipped (`:skip`): 20 (+1 OSV network test requires live API)
- Excluded from default run: 31
  - `:external_api` — live registry/API calls (included in `runtime-api` CI job)
  - `:requires_nif` — NIF compilation required (included in `nif-build` CI job)
  - `:live_download` — full install ~44MB (workflow_dispatch only)
  - `:live_service` — trust pipeline services must be running (included in `trust-pipeline-e2e` CI job)
- New tests added in 2026-04-25 session: **134**
- New tests added in v1.5 (same session): **48** (30 security + 18 storage)

---

## ✓ COMPLETED — CRG C Blitz (2026-04-04)

### Security Aspect Tests ✓
- [x] Package tampering detection: checksum mismatch rejected
- [x] Dependency confusion: registry source validation
- [x] Lockfile poisoning: integrity hash prevents tampering
- [x] Registry MITM: HTTPS validation, localhost/private IP blocking, file:// rejection
- [x] Path traversal: detection of ../ patterns, normalization
- [x] Cryptographic verification: SHA3-512 for lockfile, BLAKE2b for packages
- [x] Supply chain integrity: full dependency tree with integrity
- [x] Version substitution attack prevention

### Property-Based Tests ✓
- [x] Lockfile determinism: package list consistency
- [x] Version constraint intersection: constraint parsing and satisfaction
- [x] Manifest roundtrip: serialize/deserialize preserves data
- [x] Dependency tree consistency: forth filtering, package listing
- [x] Checksum consistency: mismatch detection, algorithm preservation
- [x] Integrity hash properties: stable computation, algorithm validation

### E2E Expansion ✓
- [x] Full install: resolve → verify → lockfile update
- [x] Full uninstall: remove → cleanup → verify
- [x] Version conflict detection: incompatible constraints, compatible resolution
- [x] Lockfile integrity: maintained through install cycle, write-read-verify
- [x] Multi-registry: simultaneous install from npm/cargo/hex

### Concurrency Aspect Tests ✓
- [x] Concurrent package additions: consistency check
- [x] Parallel reads: no state corruption
- [x] Integrity hash computation: idempotent under load
- [x] Download simulation: sequential download integrity
- [x] Large-scale operations: 50/100+ package handling
- [x] Conflict handling: same package from different forths
- [x] Sync checking under load: 50+ packages

### Benchmarks ✓
- [x] Version constraint solving (parse, satisfies)
- [x] Lockfile operations (10, 50, 100, 500 package scales)
- [x] Integrity hash computation
- [x] Trust pipeline mockup
- [x] Large-scale package operations

---

## ✓ COMPLETED — 2026-04-25 Session (+134 tests)

### Audit Wiring Tests ✓ (`test/opsm/wiring/audit_test.exs`)
- [x] Wiring.run_audit/2: 12 tests covering single-package and workspace TOML parsing

### Registry Dispatch Tests ✓ (`test/opsm/registries/language_adapters_test.exs`)
- [x] Registry.search/3 dispatch to all 8 language adapters (betlang, ephapax, phronesis,
  tangle, wokelang, lithoglyph, quandledb, nqc) — returns empty list offline, no crash
- [x] Registry.exists?/2 dispatch to all 8 adapters
- [x] Unknown registry atom returns `{:error, _}` not a crash (18 tests total)

### Error Handling E2E ✓ (`test/integration/e2e_test.exs`)
- [x] Registry degradation: fallback behaviour when primary registry returns 404/500
- [x] Manifest robustness: malformed opsm.toml fields do not crash resolver
- [x] 13 new tests across registry degradation + manifest robustness describes

### Workspace Audit E2E ✓ (`test/integration/e2e_test.exs`)
- [x] Multi-member workspace audit: reads `[workspace]` members, audits each
- [x] Empty workspace: graceful handling (no crash)
- [x] Degraded workspace: one member unreachable; others succeed (3 tests)

### Trust Pipeline Live-Service E2E ✓ (`test/integration/trust_pipeline_live_e2e_test.exs`)
- [x] Health checks: all 5 services (claim-forge, checky-monkey, palimpsest, cicd-hyper-a, oikos)
- [x] Attestation generation + verification via claim-forge
- [x] Package verification via checky-monkey (async polling)
- [x] Licence analysis via palimpsest-license
- [x] CI/CD gate via cicd-hyper-a
- [x] Sustainability scoring via oikos
- [x] Full pipeline: coordinated call across all 5 services
- [x] 23 tests total; `@moduletag :live_service`; included in `trust-pipeline-e2e.yml`

### Property-Based Fuzz Harness ✓ (`test/opsm/fuzz_harness_test.exs`)
- [x] 14 properties covering 6 OPSM boundary surfaces: lockfile JSON, version constraint
  strings, package manifest fields, registry adapter dispatch, crypto hashing, URL validation

### VersionConstraint Alias Fix ✓
- [x] VersionConstraint module aliased in e2e_test.exs — Version Conflict Detection tests
  (lines 762, 788) now pass: 0 failures (`06b9e9f`)

---

## ✓ COMPLETED — v1.5 CLI + Infrastructure (+48 tests, same session)

### TUI Skeleton ✓ (`opsm_ex/lib/opsm/cli.ex`, `opsm-ui/tui/`)
- [x] `opsm tui` dispatch clause in cli.ex
- [x] `run({:tui, _opts})` launches `opsm-tui` via `Port.open` with `:nouse_stdio`
  (preserves fd 0/1/2 for crossterm raw-mode)
- [x] Graceful error when `opsm-tui` binary not found (build instructions printed)
- [x] `OPSM_TUI_BIN` env var override for dev/testing
- [x] `opsm-tui` Cargo build verified clean (ratatui 0.30, crossterm 0.28)

### CVE/OSV Scanning + Typosquat Detection ✓ (`lib/opsm/security/`)
- [x] `Opsm.Security.Osv` — api.osv.dev/v1/query client; forth→OSV ecosystem mapping;
  severity extraction from database_specific/CVSS_V3/V2/ecosystem_specific; fixed_in extraction
- [x] `Opsm.Security.Typosquat` — two-row Levenshtein DP (O(m·n)); homoglyph normalisation
  (l↔1, o↔0, rn↔m, strip -_.); popular-package allowlists for npm/cargo/pypi/hex/gem/go
- [x] `Opsm.Security.Scanner` — Report struct (clean?/critical_count/high_count/has_critical_or_high?);
  scan/3 + scan_resolved/3; print_report/1
- [x] `opsm scan <package>` CLI command; exits 1 on critical/high findings
- [x] Passive warn-only scan in Installer.install_with_rollback (never blocks)
- [x] 30 tests, 0 failures (1 skipped: network-dependent OSV test)

### S3/IPFS Tarball Storage ✓ (`lib/opsm/storage/`)
- [x] `Opsm.Storage.Backend` behaviour (put/get/exists?/url)
- [x] `Opsm.Storage.Local` — wraps `~/.cache/opsm/packages`; always active
- [x] `Opsm.Storage.S3` — inline AWS SigV4 (PUT/GET/HEAD); no ExAws dependency;
  supports AWS/MinIO/Garage/Tigris/R2 via OPSM_S3_ENDPOINT override
- [x] `Opsm.Storage.Ipfs` — Kubo HTTP RPC (/api/v0/add, /api/v0/cat, /api/v0/pin/ls);
  local CID index (~/.cache/opsm/ipfs-index.json)
- [x] `Opsm.Storage.Manager` — read-order Local→S3→IPFS; write-through on fresh download;
  store failures logged as warnings, never propagated
- [x] Downloader.download/2 integrated: checks Manager.fetch before registry; calls Manager.store after
- [x] Backwards compatible: no env vars = local-only (existing behaviour)
- [x] 18 tests, 0 failures

---

## Remaining Work

### P1 — Formal Proofs (HIGH priority — see PROOF-NEEDS.md)

These are HIGH priority; OPSM is a high-value attack target. The Idris2 ABI
layer (`src/abi/`) is already scaffolded — extend from there.

- [ ] **Package installation integrity** (Idris2) — install operations don't corrupt existing packages
- [ ] **Dependency resolution termination** (Idris2) — PubGrub terminates and produces consistent solution
- [ ] **Verified HTTP security policy** (Idris2) — `Opsm.Verified` HTTP formally sound (not just tested)
- [ ] **Safe exec sandboxing invariants** (Idris2) — package scripts cannot escape sandbox
- [ ] **Validation completeness** (Idris2) — no bypass path through input validation
- [ ] **PQ crypto NIF correctness** (Coq/EasyCrypt) — `opsm_pq_nif` signing operations are correct

### P1 — Component Tests (deferred from CRG-C blitz)

- [ ] **ReScript component tests** — `opsm_mobile` UI, `opsm-ui` components (Deno test harness)
- [ ] **Rust crate tests** — `opsm_pq_nif` NIF; other Rust crates in `services/`
  (currently only integration-tested via Elixir; no `cargo test` suite)

### P1 — Benchee Baselines

- [ ] Run `bench/opsm_bench.exs` with Benchee; record official baseline numbers
- [ ] Establish CI regression gate (fail if operation degrades >20% vs baseline)
- [ ] Target latencies: <5s resolver for 100 packages, <30s for 1000

### P2 — Fuzz Harness Expansion

The `fuzz_harness_test.exs` property harness covers 6 surfaces but is not a true
libFuzzer/AFL++ harness. For production-grade fuzzing:
- [ ] Structured fuzz corpus: lockfile JSON edge cases (deeply nested, giant arrays, NUL bytes)
- [ ] Version constraint fuzz: Unicode, overlapping ranges, malformed semver
- [ ] Package manifest fuzz: missing required fields, type coercions
- [ ] libFuzzer integration via `cargo fuzz` (Rust boundary functions) or `afl.cr`

### P2 — Performance Optimization

- [ ] Profile resolver with large dependency graphs (1000+ packages)
- [ ] Cache version constraint parse results (hot path)
- [ ] Parallel registry fetches: `Task.async_stream` for multi-registry resolution
- [x] Tarball download caching (S3/IPFS) — **DONE** (`a9d353a`): Local/S3/IPFS
  backends with inline SigV4 signing; Manager write-through; backwards-compatible
- [ ] Benchmark against cargo/pip on equivalent graphs

### P3 — Mobile Device Testing

- [ ] iOS simulator testing
- [ ] Android emulator testing (Gossamer IPC; Tauri eliminated per ADR-002)
- [ ] App Store submission preparation

---

## Test Coverage Summary

**By Category (current):**
| Category | Count | CI tag |
|----------|-------|--------|
| Unit/integration | ~570 | default |
| E2E + integration | 55+ | `--include e2e --include integration` |
| Property-based | 67 | default |
| Security aspect | 18 | default |
| Concurrency aspect | 12 | default |
| Audit wiring | 12 | default |
| Registry dispatch | 18 | default |
| Live service E2E | 23 | `:live_service` → trust-pipeline-e2e.yml |
| External API | 15 | `:external_api` → runtime-api job |
| Live download | 6 | `:live_download` → workflow_dispatch |
| Requires NIF | varies | `:requires_nif` → nif-build.yml |
| Benchmarks | 27 | Benchee (not yet run officially) |

**CRG Grade Evidence:**
- Grade C: achieved 2026-04-04 (544 tests, all aspects)
- Grade B: achieved 2026-04-25 (814 tests, 6 external targets, 2 issues fed back)
- Grade A: requires external user confirmation outside hyperpolymath — **not yet achieved**
