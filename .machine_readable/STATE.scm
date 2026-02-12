;; SPDX-License-Identifier: PMPL-1.0-or-later
;; STATE.scm - Project state for odds-and-sods-package-manager

(state
  (metadata
    (version "1.2.0")
    (schema-version "1.0")
    (created "2026-01-18")
    (updated "2026-02-12")
    (project "odds-and-sods-package-manager")
    (repo "hyperpolymath/odds-and-sods-package-manager"))

  (project-context
    (name "OPSM - Odds-and-sods Package Manager")
    (tagline "Federated multi-language package manager with cryptographic security and formal verification")
    (tech-stack ("Elixir" "Rust" "ReScript" "Deno" "Idris2" "Julia" "Bash")))

  (current-position
    (phase "production")
    (overall-completion 88)
    (milestone "v1.2.0-registry-overhaul")
    (working-features
      ("10 registry adapters (npm, Hex, Crates, PyPI, RubyGems, Go, Pub, Hackage, NuGet, Maven)"
       "Real dependency resolution across all 10 registries"
       "Real package download, extraction, and installation with rollback"
       "Package removal and installed package tracking (installed.json)"
       "Lockfile generation and integrity verification"
       "PubGrub-based dependency resolver with semver, Python PEP 440, and Go MVS support"
       "Version constraint engine: caret, tilde, wildcard, comparison, AND/OR combinators"
       "Trust pipeline (5 microservices: claim-forge, checky-monkey, palimpsest-license, oikos, cicd-hyper-a)"
       "Container security pipeline (4 Rust services: svalinn, selur, vordr, cerro-torre)"
       "HAR integration (3 agents: github-search, web-scraper, mirror-finder)"
       "Cryptographic security (Argon2id, ChaCha20-Poly1305, BLAKE2b, SHA3-512)"
       "Federation: 9 language forths + 9 system connection ports"
       "Manifest conversion (package.json, Cargo.toml, mix.exs, pyproject.toml, .ipkg, .ncl)"
       "Verified library (SSRF prevention, JSON DoS prevention, Result monad)"
       "Federation events (security advisories, package updates)"
       "Native toolchain delegation (npm, cargo, mix, pip, gem, go, dart)"
       "Deno-based CLI build (zero npm dependency)"
       "335 core tests + 40 properties + 1 doctest, 0 failures"))
    (recent-changes
      ("2026-02-12: Added 6 new registry adapters (RubyGems, Go, Pub, Hackage, NuGet, Maven)"
       "2026-02-12: Real package download and installation (not just dry-run)"
       "2026-02-12: Go MVS semantics, pseudo-version support, quoted module names"
       "2026-02-12: RubyGems v2 API (v1 dependencies endpoint dead)"
       "2026-02-12: Maven POM XML dependency parsing"
       "2026-02-12: Hackage cabal file parsing with GHC builtin filtering"
       "2026-02-12: NuGet nuspec XML parsing"
       "2026-02-12: Pub.dev dependency fetching"
       "2026-02-12: Version constraint engine: Go v-prefix, 4-part Hackage versions"
       "2026-02-12: All 4 OPSM microservices implemented (checky-monkey, palimpsest-license, oikos, cicd-hyper-a)"
       "2026-02-12: Migrated CLI build from npm/npx to pure Deno"
       "2026-02-12: Fixed ReScript shadowing warnings"
       "2026-02-12: Implemented 7 CLI stub commands (remove, reinstall, etc.)"
       "2026-02-11: URL validation fixes, phantom registry removal"
       "2026-02-11: Real npm/hex/cargo/pypi dependency resolution"))
    (next-work
      ("Complete mobile wrapper (Tauri 2.0 + ReScript TEA)"
       "Real-world package testing (100+ packages across all registries)"
       "Performance optimization for large dependency graphs"
       "Topological sort for installation order"
       "Checksum verification for all registries"
       "Enroll in gitbot-fleet, echidna proofing"
       "Run panic-attack assail for weak point scanning"
       "v2.0: 100+ language adapters"))))
