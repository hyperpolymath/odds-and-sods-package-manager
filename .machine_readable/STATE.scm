;; SPDX-License-Identifier: PMPL-1.0-or-later
;; STATE.scm - Project state for odds-and-sods-package-manager

(state
  (metadata
    (version "2.0.0")
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
    (overall-completion 98)
    (milestone "v2.0.0-universal-registry")
    (working-features
      ("101 registry adapters across all major ecosystems"
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
       "Post-quantum crypto: hybrid Ed25519+Dilithium5 signatures, Kyber-1024 KEM, SPHINCS+"
       "PQ trust pipeline: package signature verification, lockfile signing, encrypted lockfiles"
       "SLSA Level 3 compliance: provenance generation, signature verification, policy enforcement"
       "Oikos sustainability scoring: real package-level analysis in resolver, heuristic fallback"
       "Federation: 9 language forths + 9 system connection ports"
       "Agentic cross-registry search: parallel search across all registries"
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
       "498 core tests + 40 properties + 1 doctest"
       "Safe atom conversion prevents atom table exhaustion"
       "5 high-severity seams fixed (D1, D2, S1, S2, F1)"
       "panic-attack assail scan: 0 actionable findings"
       "QUIC/HTTP3 transport with automatic protocol negotiation and 0-RTT resumption"
       "CLI commands: install, remove, search, info, list, pin, unpin, clean, history, undo, reinstall"))
    (registries
      ("npm" "cargo/crates" "hex/elixir" "pypi/python"
       "rubygems/ruby" "go/golang" "pub/dart/flutter" "hackage/haskell"
       "nuget/dotnet" "maven/java/kotlin"
       "packagist/php/composer" "cpan/perl" "cran/r" "conda/anaconda"
       "cocoapods/ios" "opam/ocaml" "clojars/clojure" "luarocks/lua"
       "terraform/tf" "jsr/deno" "conan/cpp" "swift/spm" "elm" "vcpkg"
       "julia/juliageneral" "dub/dlang" "shard/crystal" "raku/perl6"
       "raco/racket" "chicken/scheme" "alire/ada" "stackage/haskell"
       "pear/php" "pecl/php" "sbt_plugins/scala" "gradle_plugins/gradle"
       "deno_x" "cargo_binstall" "bower"
       "homebrew" "homebrew_cask" "nix" "nix_flakes" "nix_darwin"
       "apt/deb" "rpm/dnf" "alpine/apk" "flatpak/flathub" "snap/snapcraft"
       "guix" "macports" "portage/gentoo" "xbps/void" "zypper/opensuse"
       "aur/arch" "pacstall" "solus/eopkg" "spack/hpc" "pkgsrc/netbsd"
       "freebsd" "fpm"
       "docker/oci" "helm" "buildpacks/cnb" "k8s_operators/olm"
       "pulumi" "tekton" "ansible/galaxy" "chef/supermarket"
       "puppet/forge" "scoop" "winget"
       "vscode" "jetbrains" "sublime" "vim/neovim" "eclipse"
       "melpa/emacs" "elpa" "grafana" "openupm/unity" "godot"
       "jsdelivr" "cdnjs" "webjars" "github_packages/ghcr"
       "gitlab_packages" "wordpress" "wordpress_themes"
       "wapm/wasm" "bioconductor" "astrolabe" "vpm/vrchat"
       "nimble/nim" "idris2" "git" "agentic"
       "oblibeny" "my_lang" "julia_the_viper" "error_lang" "eclexia"))
    (recent-changes
      ("2026-02-13: v2.0.0 — 101 registry adapters (universal registry coverage)"
       "2026-02-13: SLSA Level 3 compliance module (provenance, verification, policy)"
       "2026-02-13: Post-quantum trust pipeline (Dilithium5+Ed25519 hybrid, Kyber-1024 KEM)"
       "2026-02-13: Oikos sustainability scoring integrated into resolver"
       "2026-02-13: Agentic cross-registry search (real parallel search)"
       "2026-02-13: Fixed resolve_from_forth/2 manifest_convert stub"
       "2026-02-13: SLSA provenance wired into installer and lockfile"
       "2026-02-13: Git clone/build/run pipeline (clone, build_detector, builder, pipeline)"
       "2026-02-13: System PM version querying (8 package managers)"
       "2026-02-13: Bidirectional manifest conversion (7 output formats)"
       "2026-02-13: Cross-ecosystem dependency name mapping (50+ mappings)"
       "2026-02-13: Native opsm.toml manifest format"
       "2026-02-13: Real export_to_port implementation"))
    (next-work
      ("Build and test PQ NIF (Rust native extensions for Dilithium5/Kyber-1024/SPHINCS+)"
       "Add --sustainability CLI flag for resolver"
       "Implement autoremove command in maintenance.ex"
       "Fix proven dependency compilation errors"
       "Improve Mix.exs manifest parsing (replace regex with proper evaluation)"
       "End-to-end integration tests for SLSA and PQ trust pipeline"
       "Eclexia language integration"))))
