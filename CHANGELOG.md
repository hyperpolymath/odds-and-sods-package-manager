<!--
SPDX-License-Identifier: MPL-2.0
SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)
-->

# Changelog

All notable changes to `odds-and-sods-package-manager` will be documented in this file.

This file is generated from conventional commits by the
[`changelog-reusable.yml`](https://github.com/hyperpolymath/standards/blob/main/.github/workflows/changelog-reusable.yml)
workflow (`hyperpolymath/standards#206`). Adopt the workflow in this repo's CI to keep this file in sync automatically — see
[`templates/cliff.toml`](https://github.com/hyperpolymath/standards/blob/main/templates/cliff.toml)
for the canonical config.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
this project aims to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- feat(storage): S3/IPFS tarball cache backends replacing /tmp-only caching
- feat(security): CVE/OSV scanning + typosquat detection
- feat(tui): wire opsm tui dispatch to ratatui binary
- feat(cli): history undo <n> by position/ID + pin-aware update
- feat(bots): scaffold .bot_directives/ for gitbot-fleet targeting
- feat(e2e): enterprise trust pipeline live-service E2E tests + CI workflow
- feat(crg): achieve grade B — 6 diverse external targets documented
- feat(fuzz): property-based fuzz harness covering 6 OPSM boundary surfaces
- feat(gossamer): complete Tauri elimination; Gossamer-native IPC
- feat(e2e): add error-handling + workspace audit E2E scenarios; wire into CI

### Fixed

- fix(affine): migrate record literals to #{ } (affinescript#218) (#29)
- fix(ci): pin upload-artifact to valid SHA (Refs standards#48) (#27)
- fix(ci): bump a2ml/k9-validate-action pins to canonical (standards#85) (#25)
- fix(ci): sync hypatia-scan.yml to canonical (kill cd-scanner build drift) (#24)
- fix(ci): build Hypatia escript from repo root (estate dogfood drift)
- fix(ci): Phase-2 fleet submission must not fail the security gate (#23)
- fix(security): bump rand 0.9.2 → 0.9.3 in opsm-tui (GHSA-cq8v-f236-94qc) (#17)
- fix(ci): root-cause three pre-existing infra failures (#18)
- fix(ci): rsr-antipattern.yml duplicate heredoc (#19)
- fix(ci): repair YAML block-scalar in workflow-linter Check Permissions step (#20)

### Changed

- refactor(contractiles): complete layout migration to .machine_readable/contractiles/
- refactor(arch): architectural reconciliation — compose profiles, TOML parsers, SPDX, pipeline fix

### Documentation

- docs(test-needs): update for v1.5 deliverables (TUI, CVE/OSV, S3/IPFS)
- docs(roadmap+tests): bring ROADMAP and TEST-NEEDS fully current
- docs(6a2): populate META ADRs and ECOSYSTEM relationships
- docs(rsr): add RSR_COMPLIANCE.adoc — filled compliance record
- docs: add paper sketch for Zenodo/arXiv submission on cross-ecosystem package management
- docs: substantive CRG C annotation (EXPLAINME.adoc)
- docs: add TEST-NEEDS.md and/or PROOF-NEEDS.md from audit

### CI

- ci: redistribute concurrency-cancel guard to read-only check workflows (#28)
- ci: bump actions/upload-artifact SHA to current v4 (#16)
- ci(secret-scanner): drop duplicate --fail from trufflehog extra_args (#15)
- ci: SHA-pin hyperpolymath validate-actions in dogfood-gate
- ci(antipattern): fix top-level dir matching + benchmarks/lsp/bench filename allowlists (#14)

## Pre-history

Prior commits to this file's introduction are recorded in git history but not formally classified into Keep-a-Changelog sections. To backfill, run `git cliff -o CHANGELOG.md` locally using the canonical [`cliff.toml`](https://github.com/hyperpolymath/standards/blob/main/templates/cliff.toml) — this is one-shot mechanical work.

---

<!-- This file was seeded by the 2026-05-26 estate tech-debt audit follow-up (Row-2 Phase 3); see [`hyperpolymath/standards/docs/audits/2026-05-26-estate-documentation-debt.md`](https://github.com/hyperpolymath/standards/blob/main/docs/audits/2026-05-26-estate-documentation-debt.md). -->
