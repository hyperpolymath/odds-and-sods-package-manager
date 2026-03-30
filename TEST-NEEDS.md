# TEST-NEEDS.md — odds-and-sods-package-manager

> Generated 2026-03-29 by punishing audit.

## Current State

| Category     | Count | Notes |
|-------------|-------|-------|
| Unit tests   | ~25   | opsm_test, package/transaction, progress, maintenance, validation, config, lockfile, imp_property, registry_gateway, version_constraint, verified, verified/url_property, verified/json_property, verified/result_property |
| Integration  | 5     | pipeline, trust_pipeline, e2e, git_pipeline, manifest_roundtrip |
| E2E          | 1     | integration/e2e_test.exs |
| Benchmarks   | 0     | Bench files exist but are in deps/proven (not own benchmarks) |

**Source modules:** ~238 own source files (Elixir + ReScript + Rust). Covers: package management, trust pipeline, registry gateway, version constraints, lockfiles, config, validation, manifest handling, Nickel plugins.

## What's Missing

### P2P (Property-Based) Tests
- [ ] Version constraint: already has imp_property_test but needs more: arbitrary version range intersection/union
- [ ] Lockfile: property tests for lockfile determinism (same inputs = same lockfile)
- [ ] Manifest: arbitrary manifest structure validation
- [ ] Registry gateway: response format property tests

### E2E Tests
- [ ] Full install: search -> resolve -> download -> verify -> install -> lockfile update
- [ ] Full update: check -> resolve conflicts -> download -> verify -> swap -> lockfile update
- [ ] Trust pipeline: untrusted package -> verification -> trust decision -> install/reject
- [ ] Uninstall: remove -> cleanup -> lockfile update -> verify no orphans

### Aspect Tests
- **Security:** No tests for package tampering detection, registry MITM, dependency confusion, lockfile poisoning — CRITICAL for a package manager
- **Performance:** ZERO own benchmarks. Resolution speed, download throughput, verification time all unmeasured
- **Concurrency:** No tests for parallel package downloads, concurrent installs, lockfile contention
- **Error handling:** No tests for network failure during download, corrupted package, version conflict deadlock, registry unavailability

### Build & Execution
- [ ] `mix test` for Elixir
- [ ] ReScript build
- [ ] Rust crate tests

### Benchmarks Needed
- [ ] Dependency resolution time vs dependency graph size
- [ ] Package download + verification throughput
- [ ] Lockfile generation time
- [ ] Trust pipeline evaluation speed
- [ ] Version constraint solving time

### Self-Tests
- [ ] Registry connectivity health check
- [ ] Lockfile integrity self-validation
- [ ] Package cache consistency check
- [ ] Trust chain verification

## Priority

**CRITICAL.** A package manager with ZERO security tests is a supply chain risk. 238 source files with 30 test files is 12.6% file coverage. The property tests and integration tests are a decent start but security testing is completely absent. No own benchmarks despite the deps/proven benchmarks being present (those test the wrong thing). Lockfile and trust pipeline need immediate hardening.

## FAKE-FUZZ ALERT

- `tests/fuzz/placeholder.txt` is a scorecard placeholder inherited from rsr-template-repo — it does NOT provide real fuzz testing
- Replace with an actual fuzz harness (see rsr-template-repo/tests/fuzz/README.adoc) or remove the file
- Priority: P2 — creates false impression of fuzz coverage
