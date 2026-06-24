<!--
SPDX-License-Identifier: CC-BY-SA-4.0
Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
<!-- TOPOLOGY.md — Project architecture map and completion dashboard -->
<!-- Last updated: 2026-03-08 -->

# OPSM (Odds and Sods Package Manager) — Project Topology

## System Architecture

```
                        ┌─────────────────────────────────────────┐
                        │              OPERATOR / DEVELOPER       │
                        │        (CLI, UI, Agentic Discovery)     │
                        └───────────────────┬─────────────────────┘
                                            │
                                            ▼
                        ┌─────────────────────────────────────────┐
                        │           OPSM CORE (ELIXIR)            │
                        │    (PubGrub Resolver, Wiring, Lockfile) │
                        └──────────┬───────────────────┬──────────┘
                                   │                   │
                                   ▼                   ▼
                        ┌───────────────────────┐  ┌────────────────────────────────┐
                        │ REGISTRY ADAPTERS(101)│  │ TRUST PIPELINE (5 SVCS)        │
                        │ - npm, Hex, Crates    │  │ - claim-forge (Attest)         │
                        │ - PyPI, RubyGems, Go  │  │ - checky-monkey (Verify)       │
                        │ - Agentic (HAR)       │  │ - oikos (Sustainability)       │
                        └──────────┬────────────┘  └──────────┬─────────────────────┘
                                   │                          │
                                   └────────────┬─────────────┘
                                                ▼
                        ┌─────────────────────────────────────────┐
                        │           SECURITY & PROOFS             │
                        │  ┌───────────┐  ┌───────────────────┐  │
                        │  │ Rust NIF  │  │  Container Sec    │  │
                        │  │ (PQ Crypto)│ │  (4 Microservices)│  │
                        │  └─────┬─────┘  └────────┬──────────┘  │
                        └────────│─────────────────│──────────────┘
                                 │                 │
                                 ▼                 ▼
                        ┌─────────────────────────────────────────┐
                        │          EXTERNAL ECOSYSTEMS            │
                        │      (Language APIs, System PMs)        │
                        └─────────────────────────────────────────┘

                        ┌─────────────────────────────────────────┐
                        │          REPO INFRASTRUCTURE            │
                        │  Justfile Automation  .machine_readable/  │
                        │  SLSA Level 3 Compliance  0-AI-MANIFEST.a2ml  │
                        └─────────────────────────────────────────┘
```

## Completion Dashboard

```
COMPONENT                          STATUS              NOTES
─────────────────────────────────  ──────────────────  ─────────────────────────────────
CORE MANAGER (v2.0.0)
  PubGrub Resolver                  ██████████ 100%    Cross-registry resolution stable
  101 Registry Adapters             ██████████ 100%    All major ecosystems active
  Manifest Conversion               ██████████ 100%    10 formats supported
  Agentic Discovery (HAR)           ██████████ 100%    3 agents verified

TRUST & SECURITY
  Trust Pipeline (5 Svcs)           ██████████ 100%    Integrity/License/Eco checks
  Container Sec (4 Svcs)            ██████████ 100%    Scan/Sign/Verify/Monitor stable
  PQ Crypto (Rust NIF)              ██████████ 100%    Dilithium5/Kyber hybrid active
  Verified.Library                  ██████████ 100%    SSRF/DoS prevention proven

REPO INFRASTRUCTURE
  Justfile Automation               ██████████ 100%    Standard build/test tasks
  .machine_readable/                ██████████ 100%    STATE tracking active
  Test Suite                        ██████████ 100%    547 core + 40 property tests
  Dependabot Vulnerabilities        ██████████ 100%    30 vulns fixed (2026-03-08)
  3-Forge Mirroring                 ██████████ 100%    GitHub + GitLab + Bitbucket

UPCOMING (this week)
  E2E Integration Tests             ░░░░░░░░░░   0%    Real registry calls
  Mobile Wrapper Polish             ░░░░░░░░░░   0%    Tauri 2.x
  PQ NIF Verify Match               ░░░░░░░░░░   0%    Opened message validation
  Interactive TUI                   ░░░░░░░░░░   0%    ratatui-based, aptitude-style

─────────────────────────────────────────────────────────────────────────────
OVERALL:                            █████████░  90%    v2.0.0 — core done, 4 items remaining
```

## Key Dependencies

```
Registry Adapter ──► PubGrub Resolver ──► Trust Pipeline ──► Lockfile
     │                   │                   │                 │
     ▼                   ▼                   ▼                 ▼
  PQ Crypto ────────► Build Pipeline ─────► Container Sec ──► Install
```

## Update Protocol

This file is maintained by both humans and AI agents. When updating:

1. **After completing a component**: Change its bar and percentage
2. **After adding a component**: Add a new row in the appropriate section
3. **After architectural changes**: Update the ASCII diagram
4. **Date**: Update the `Last updated` comment at the top of this file

Progress bars use: `█` (filled) and `░` (empty), 10 characters wide.
Percentages: 0%, 10%, 20%, ... 100% (in 10% increments).
