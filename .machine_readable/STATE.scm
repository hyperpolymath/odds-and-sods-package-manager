;; SPDX-License-Identifier: PMPL-1.0-or-later
;; STATE.scm - Project state for odds-and-sods-package-manager

(state
  (metadata
    (version "1.3.0")
    (schema-version "1.0")
    (created "2026-01-18")
    (updated "2026-02-13")
    (project "odds-and-sods-package-manager")
    (repo "hyperpolymath/odds-and-sods-package-manager"))

  (project-context
    (name "OPSM - Odds-and-sods Package Manager")
    (tagline "Federated multi-language package manager with cryptographic security and formal verification")
    (tech-stack ("Elixir" "Rust" "ReScript" "Deno" "Idris2" "Julia" "Bash")))

  (current-position
    (phase "production")
    (overall-completion 95)
    (milestone "v1.3.1-interconnection-pipeline")
    (working-features
      ("34 registry adapters across all major ecosystems"
       "Real dependency resolution across all registries"
       "Topological sort for install order (Kahn's algorithm)"
       "Real package download, extraction, and installation with batch rollback"
       "Package removal and installed package tracking (installed.json)"
       "Lockfile generation and integrity verification with checksum verification"
       "PubGrub-based dependency resolver with semver, Python PEP 440, and Go MVS support"
       "ETS-based registry cache with TTL for resolver performance"
       "Version constraint engine: caret, tilde, wildcard, comparison, AND/OR combinators"
       "Trust pipeline (5 microservices: claim-forge, checky-monkey, palimpsest-license, oikos, cicd-hyper-a)"
       "Container security pipeline (4 Rust services: svalinn, selur, vordr, cerro-torre)"
       "HAR integration (3 hardened agents: github-search, web-scraper, mirror-finder)"
       "Cryptographic security (Argon2id, ChaCha20-Poly1305, BLAKE2b, SHA3-512)"
       "Federation: 9 language forths + 9 system connection ports"
       "Manifest conversion (package.json, Cargo.toml, mix.exs, pyproject.toml, pubspec.yaml, go.mod, Gemfile, opsm.toml, .ipkg, .ncl)"
       "Git clone/build/run pipeline (15 build systems, SSRF-safe, ref pinning)"
       "System PM querying (dpkg, rpm, pacman, brew, nix, flatpak, snap, guix)"
       "Cross-ecosystem dependency name mapping (50+ known mappings)"
       "Bidirectional manifest writer (7 output formats)"
       "Native opsm.toml manifest format with build/run config"
       "Verified library (SSRF prevention, JSON DoS prevention, Result monad)"
       "Federation events (security advisories, package updates)"
       "Native toolchain delegation (npm, cargo, mix, pip, gem, go, dart)"
       "Mobile wrapper (Tauri 2.x + ReScript TEA) with CSP and configurable API"
       "Deno-based CLI build (zero npm dependency)"
       "413 core tests + 40 properties + 1 doctest (84 new in v1.3.1)"
       "Safe atom conversion prevents atom table exhaustion"
       "5 high-severity seams fixed (D1, D2, S1, S2, F1)"
       "panic-attack assail scan: 0 actionable findings"))
    (registries
      ("npm" "cargo/crates" "hex/elixir" "pypi/python"
       "rubygems/ruby" "go/golang" "pub/dart/flutter" "hackage/haskell"
       "nuget/dotnet" "maven/java/kotlin"
       "packagist/php/composer" "cpan/perl" "cran/r" "conda/anaconda"
       "cocoapods/ios" "opam/ocaml" "clojars/clojure" "luarocks/lua"
       "terraform/tf" "jsr/deno" "conan/cpp" "swift/spm" "elm" "vcpkg"
       "julia/juliageneral"
       "nimble/nim" "idris2" "git" "agentic"
       "oblibeny" "my_lang" "julia_the_viper" "error_lang" "eclexia"))
    (recent-changes
      ("2026-02-13: Git clone/build/run pipeline (clone, build_detector, builder, pipeline)"
       "2026-02-13: System PM version querying (8 package managers)"
       "2026-02-13: Bidirectional manifest conversion (7 output formats)"
       "2026-02-13: Cross-ecosystem dependency name mapping (50+ mappings)"
       "2026-02-13: Native opsm.toml manifest format"
       "2026-02-13: Real export_to_port implementation"
       "2026-02-13: 84 new tests (all passing)"
       "2026-02-12: Fixed 5 high-severity seams (D1, D2, S1, S2, F1)"
       "2026-02-12: panic-attack assail scan — 0 actionable findings"
       "2026-02-12: Added 15 new registry adapters (34 total)"
       "2026-02-12: ETS-based registry cache with TTL"
       "2026-02-12: Topological sort wired into installer correctly"))
    (next-work
      ("Implement stubbed CLI commands (reinstall, pin, unpin, history, clean)"
       "Oikos sustainability scores integration in resolver"
       "v2.0: Push toward 100+ registry adapters"
       "Security Phase 2: Post-quantum crypto (Dilithium5, Kyber-1024)"
       "SLSA Level 3 compliance"
       "QUIC/HTTP3 client"))))
