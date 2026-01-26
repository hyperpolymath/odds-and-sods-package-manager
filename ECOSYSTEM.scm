;;; ECOSYSTEM.scm — OPSM Ecosystem Position
;;; SPDX-License-Identifier: PMPL-1.0-or-later
;;; Media Type: application/vnd.ecosystem+scm

(ecosystem
  (metadata
    (version . "1.0.0")
    (name . "OPSM (Odds and Sods Package Manager)")
    (type . "federated-package-manager")
    (purpose . "Universal, trust-verified package management with formal guarantees")
    (created . "2025-01-17")
    (updated . "2026-01-26"))

  (position-in-ecosystem
    (layer . "infrastructure")
    (scope . "multi-language-package-management")
    (niche . "federated-trust-verification")
    (differentiators
      "First package manager with formal verification (proven library)"
      "Human-Assisted Registry (HAR) for obscure language discovery"
      "8-dimensional sustainability scoring (Oikos integration)"
      "Cross-registry dependency resolution (npm + Hex + Crates + PyPI + ...)"
      "Native mobile support (iOS/Android via Tauri 2.0)"
      "Federation-first architecture (IPFS, Radicle, git-private-farm)"
      "Zero-trust security model (SLSA attestations, provenance tracking)"))

  (related-projects
    ((name . "npm")
     (relationship . "sibling-standard")
     (url . "https://npmjs.com")
     (description . "JavaScript package registry")
     (comparison . "OPSM: multi-language, federated, trust-verified. npm: JS-only, centralized, minimal verification"))

    ((name . "Cargo")
     (relationship . "sibling-standard")
     (url . "https://crates.io")
     (description . "Rust package registry")
     (comparison . "OPSM: multi-language, HAR discovery. Cargo: Rust-only, excellent resolver"))

    ((name . "pip/PyPI")
     (relationship . "sibling-standard")
     (url . "https://pypi.org")
     (description . "Python package registry")
     (comparison . "OPSM: trust pipeline, formal verification. PyPI: Python-only, community trust"))

    ((name . "Hex")
     (relationship . "sibling-standard")
     (url . "https://hex.pm")
     (description . "Erlang/Elixir package registry")
     (comparison . "OPSM: multi-language. Hex: BEAM-only, excellent API"))

    ((name . "Nix")
     (relationship . "inspiration")
     (url . "https://nixos.org")
     (description . "Reproducible package manager")
     (comparison . "OPSM: language-agnostic packages. Nix: OS-level, full reproducibility"))

    ((name . "Guix")
     (relationship . "inspiration")
     (url . "https://guix.gnu.org")
     (description . "Functional package manager")
     (comparison . "OPSM: trust verification focus. Guix: Scheme-based, GNU philosophy"))

    ((name . "IPFS")
     (relationship . "potential-integration")
     (url . "https://ipfs.io")
     (description . "Distributed file system")
     (integration . "OPSM v2.0 will use IPFS for artifact storage"))

    ((name . "Radicle")
     (relationship . "potential-integration")
     (url . "https://radicle.xyz")
     (description . "Decentralized code collaboration")
     (integration . "OPSM federation sync via Radicle network"))

    ((name . "Sigstore")
     (relationship . "potential-integration")
     (url . "https://sigstore.dev")
     (description . "Software signing service")
     (integration . "OPSM v1.5 SLSA attestations via Sigstore"))

    ((name . "Idris2")
     (relationship . "dependency")
     (url . "https://idris-lang.org")
     (description . "Dependently-typed functional language")
     (integration . "OPSM proven library written in Idris2 (v1.5 NIFs)"))

    ((name . "Phoenix Framework")
     (relationship . "dependency")
     (url . "https://phoenixframework.org")
     (description . "Elixir web framework")
     (integration . "OPSM mobile API built with Phoenix"))

    ((name . "Tauri")
     (relationship . "dependency")
     (url . "https://tauri.app")
     (description . "Cross-platform app framework")
     (integration . "OPSM mobile wrapper uses Tauri 2.0"))

    ((name . "opsm-ui")
     (relationship . "sibling-ui")
     (url . "https://github.com/hyperpolymath/opsm-ui")
     (description . "Cross-platform UI spec and shell for OPSM")
     (integration . "UI uses OPSM CLI for discovery, dry-run plans, and apply actions"))

    ((name . "gitbot-fleet")
     (relationship . "quality-enforcement")
     (url . "https://github.com/hyperpolymath/gitbot-fleet")
     (description . "Bot fleet for RSR, verification, sustainability, presentation, release readiness")
     (integration . "Continuous repo quality enforcement for OPSM")))

    ((name . "cadre-router")
     (relationship . "dependency")
     (url . "https://github.com/hyperpolymath/cadre-router")
     (description . "Type-safe URL routing for ReScript")
     (integration . "OPSM mobile routing layer"))

    ((name . "rescript-tea")
     (relationship . "dependency")
     (url . "https://github.com/hyperpolymath/rescript-tea")
     (description . "The Elm Architecture for ReScript")
     (integration . "OPSM mobile UI architecture"))

    ((name . "claim-forge")
     (relationship . "sibling-microservice")
     (url . "https://github.com/hyperpolymath/claim-forge")
     (description . "Attestation generation service")
     (integration . "OPSM trust pipeline component #1"))

    ((name . "checky-monkey")
     (relationship . "sibling-microservice")
     (url . "https://github.com/hyperpolymath/checky-monkey")
     (description . "Package verification service")
     (integration . "OPSM trust pipeline component #2"))

    ((name . "palimpsest-license")
     (relationship . "sibling-microservice")
     (url . "https://github.com/hyperpolymath/palimpsest-license")
     (description . "License analysis service")
     (integration . "OPSM trust pipeline component #3"))

    ((name . "oikos")
     (relationship . "sibling-microservice")
     (url . "https://github.com/hyperpolymath/oikos")
     (description . "Sustainability scoring service")
     (integration . "OPSM trust pipeline component #4 (8-dimension scoring)"))

    ((name . "cicd-hyper-a")
     (relationship . "sibling-microservice")
     (url . "https://github.com/hyperpolymath/cicd-hyper-a")
     (description . "Registry publication service")
     (integration . "OPSM trust pipeline component #5 (publish + federation)"))

    ((name . "opsm-registry-hub")
     (relationship . "sibling-infrastructure")
     (url . "https://github.com/hyperpolymath/opsm-registry-hub")
     (description . "Federated registry hub")
     (integration . "OPSM federation target for event propagation"))

    ((name . "rhodium-standard-repositories")
     (relationship . "potential-consumer")
     (url . "https://github.com/hyperpolymath/rhodium-standard-repositories")
     (description . "Repository standards specification")
     (integration . "OPSM follows RSR conventions")))

  (what-this-is
    "OPSM is a federated, multi-language package manager with formal verification guarantees. It combines:"
    ""
    "1. UNIVERSAL LANGUAGE SUPPORT: 8 registries today (npm, Hex, Crates, PyPI, Nimble, Idris2, Git, Agentic), 100+ in v2.0"
    "2. TRUST PIPELINE: 5-microservice verification (attestations, signatures, licenses, sustainability, provenance)"
    "3. FORMAL VERIFICATION: Proven library (Idris2) with mathematical correctness proofs (v1.5)"
    "4. HUMAN-ASSISTED DISCOVERY: HAR agents for obscure/unmaintained packages (GitHub search, web scraping, mirror finding)"
    "5. FEDERATION-FIRST: Event propagation, IPFS storage, Radicle sync, git-private-farm mirroring"
    "6. NATIVE MOBILE: iOS/Android apps via Tauri 2.0 with ReScript TEA architecture"
    "7. INTELLIGENT SEARCH: ML-based semantic search and recommendations (v2.0)"
    "8. SUPPLY CHAIN SECURITY: SLSA attestations, provenance tracking, CVE integration (v1.5)"
    ""
    "OPSM answers the question: 'What if package management prioritized trust and universality over convenience?'")

  (what-this-is-not
    "OPSM is NOT:"
    ""
    "- A replacement for language-specific tools (use Cargo for Rust, npm for JS, etc. for single-language projects)"
    "- A build system (use Make, Bazel, etc. OPSM only manages dependencies)"
    "- A version control system (use Git, etc. OPSM federates via VCS but doesn't replace it)"
    "- A container orchestrator (use Docker, K8s. OPSM manages packages inside containers)"
    "- A CI/CD platform (OPSM integrates with CI/CD but doesn't orchestrate builds)"
    "- A security scanner (OPSM integrates with scanners but delegates deep analysis)"
    "- Centralized infrastructure (OPSM is federation-first, avoid single points of failure)"
    "- Production-ready for all languages yet (v1.0 focuses on 8 ecosystems, v2.0 expands to 100+)")

  (architectural-philosophy
    (principles
      "Trust over convenience (verification adds latency but ensures safety)"
      "Federation over centralization (avoid npm-style single points of failure)"
      "Formal over informal (mathematical proofs > community trust)"
      "Universal over specialized (one tool for all languages)"
      "Human-assisted over fully automated (HAR for edge cases)"
      "Transparent over opaque (audit logs, provenance, open source)"
      "Composable over monolithic (microservices for trust pipeline)"
      "Type-safe over dynamic (ReScript, Rust, Elixir, Idris2 stack)")))
