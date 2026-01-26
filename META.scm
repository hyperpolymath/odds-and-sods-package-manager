;;; META.scm — OPSM Meta-Level Information
;;; SPDX-License-Identifier: PMPL-1.0-or-later
;;; Media Type: application/meta+scheme

(define meta
  '((metadata
      (version . "1.0.0")
      (schema-version . "2025-12-08")
      (created . "2025-01-17")
      (last-updated . "2026-01-23")
      (project . "OPSM (Odds and Sods Package Manager)")
      (repository . "https://github.com/hyperpolymath/odds-and-sods-package-manager"))

    (architecture-decisions
      ((adr-001
         (title . "Choose Elixir for Core Implementation")
         (status . "accepted")
         (date . "2025-01-17")
         (context
           "Need robust, concurrent package manager capable of handling:"
           "- Parallel registry fetches"
           "- Async trust pipeline verification"
           "- Federation event propagation"
           "- Multi-registry resolution")
         (decision
           "Use Elixir/BEAM for core implementation"
           "Reasons:"
           "1. Fault-tolerant (OTP supervision trees)"
           "2. Concurrent (lightweight processes)"
           "3. Functional (pure functions, pattern matching)"
           "4. Hot code reloading (zero-downtime updates)"
           "5. Distributed (federation-ready)")
         (consequences
           "POSITIVE:"
           "- Excellent parallelism (registry fetches, trust pipeline)"
           "- Battle-tested reliability (WhatsApp, Discord scale)"
           "- Phoenix for mobile API reuses all logic"
           "NEGATIVE:"
           "- Not suitable for iOS/Android native (requires Tauri wrapper)"
           "- Smaller talent pool than Node.js/Python"
           "- Deployment requires BEAM VM"))

       (adr-002
         (title . "Adopt PubGrub for Dependency Resolution")
         (status . "accepted")
         (date . "2025-01-20")
         (context
           "Need dependency resolver that:"
           "- Handles version constraints (semver, Python, Cargo)"
           "- Detects conflicts early"
           "- Provides actionable error messages"
           "- Scales to 1000+ package graphs")
         (decision
           "Implement PubGrub algorithm (used by Dart, pip, Poetry)"
           "Key features:"
           "- Version range splitting"
           "- Conflict-driven backtracking"
           "- Human-readable error messages")
         (consequences
           "POSITIVE:"
           "- Best-in-class error messages"
           "- Proven at scale (Flutter ecosystem)"
           "- Handles complex constraints elegantly"
           "NEGATIVE:"
           "- More complex than naive backtracking"
           "- Requires careful testing"))

       (adr-003
         (title . "Use Tauri 2.0 for Mobile Wrapper")
         (status . "accepted")
         (date . "2026-01-23")
         (context
           "Need iOS/Android support but BEAM VM not available on mobile"
           "Evaluated:"
           "1. Tauri 2.0 (Rust + web UI)"
           "2. Dioxus (pure Rust UI)"
           "3. Gleam → JS → React Native"
           "4. Zig FFI")
         (decision
           "Use Tauri 2.0 hybrid architecture:"
           "- ReScript UI with TEA (rescript-tea)"
           "- Rust Tauri commands (rescript-tauri bindings)"
           "- Phoenix Elixir backend (100% code reuse)"
           "- Type-safe routing (cadre-router + cadre-tea-router)")
         (consequences
           "POSITIVE:"
           "- 100% backend code reuse (no rewrite)"
           "- Native iOS/Android compilation"
           "- Type-safe across all layers (ReScript → Rust → Elixir)"
           "- Leverages existing cadre-router, rescript-tea projects"
           "NEGATIVE:"
           "- Requires Phoenix API layer"
           "- HTTP latency between Tauri and Phoenix"
           "- More complex than pure Rust solution"))

       (adr-004
         (title . "Integrate Proven Library for Security")
         (status . "accepted")
         (date . "2026-01-23")
         (context
           "Need formal guarantees for:"
           "- SSRF prevention (URL validation)"
           "- DoS prevention (JSON parsing limits)"
           "- Correct error handling (Result monad)")
         (decision
           "Create Verified library in Elixir (v1.0)"
           "Then bind to Idris2 proven functions (v1.5 NIFs)"
           "Modules:"
           "- Verified.Url: URL validation with private IP blocking"
           "- Verified.Json: JSON parsing with depth/size limits"
           "- Verified.Result: Railway-oriented programming")
         (consequences
           "POSITIVE:"
           "- Mathematical proofs of security properties (v1.5)"
           "- No SSRF/DoS vulnerabilities possible"
           "- Compiler-verified correctness"
           "NEGATIVE:"
           "- Idris2 NIFs complex to implement"
           "- Learning curve for proven programming"))

       (adr-005
         (title . "Adopt HAR for Obscure Package Discovery")
         (status . "accepted")
         (date . "2025-01-22")
         (context
           "Problem: Obscure languages (Idris2, Nimble, ATS, etc.) lack:"
           "- Centralized registries"
           "- Package indexes"
           "- Discovery mechanisms"
           "Pure automation fails for unmaintained packages")
         (decision
           "Human-Assisted Registry (HAR) approach:"
           "- Queue system (/tmp/opsm-har-ingest/)"
           "- Three agents:"
           "  1. github-search.sh (GitHub API)"
           "  2. web-scraper.jl (Julia, DuckDuckGo)"
           "  3. mirror-finder.sh (SWH, Wayback, Debian/Fedora)"
           "- Timeout-based fallback to user assistance")
         (consequences
           "POSITIVE:"
           "- Solves unsolvable problem (no registry = no discovery)"
           "- Human judgment for edge cases"
           "- Scales with crowdsourcing (v2.0)"
           "NEGATIVE:"
           "- Not instant (HAR queue processing)"
           "- Requires agent maintenance"))

       (adr-006
         (title . "Zero npm/Node - Use Deno for Mobile")
         (status . "accepted")
         (date . "2026-01-23")
         (context
           "User's technology standards prohibit:"
           "- npm/Node.js"
           "- package.json + node_modules"
           "- TypeScript"
           "Must use: ReScript, Rust, Elixir, Deno")
         (decision
           "Use Deno for mobile wrapper developsment:"
           "- Import maps (deno.json) instead of package.json"
           "- npm: URLs for ReScript dependencies"
           "- Zero node_modules (Deno caches automatically)"
           "- ReScript compiles to ES6 modules")
         (consequences
           "POSITIVE:"
           "- Meets user's tech standards"
           "- Cleaner than npm (no node_modules)"
           "- Fast (Deno caching)"
           "NEGATIVE:"
           "- Less common than npm/Node"
           "- Some tooling assumes Node")))

    (developsment-practices
      (code-style
        (languages
          (elixir . "Follow Elixir core style (mix format, Credo)")
          (rescript . "2-space indent, ES6 modules, explicit types")
          (rust . "rustfmt + clippy, prefer Result over panic")
          (julia . "Follow official style guide")
          (bash . "ShellCheck compliant, POSIX where possible"))
        (naming
          (modules . "PascalCase (Opsm.VersionConstraint)")
          (functions . "snake_case (parse_version, fetch_package)")
          (types . "snake_case (package_t, result<ok, error>)")
          (constants . "SCREAMING_SNAKE_CASE (MAX_RETRIES)"))
        (comments
          "SPDX headers in all files"
          "Module docstrings (@moduledoc)"
          "Function docstrings (@doc) for public functions"
          "Inline comments for non-obvious logic only"))

      (security
        (input-validation . "All external input validated via Verified library")
        (url-handling . "Verified.Url blocks localhost and private IPs")
        (json-parsing . "Verified.Json enforces depth (20) and size (10MB) limits")
        (error-handling . "Result monad for explicit error propagation")
        (trust-pipeline . "All 5 microservices must verify before publish")
        (secrets . "Never commit secrets (use env vars + .gitignore)")
        (dependencies . "Audit all dependencies (mix audit, cargo audit)"))

      (testing
        (unit-tests . "ExUnit for Elixir, 80%+ coverage target")
        (property-tests . "StreamData for security properties (40 tests)")
        (integration-tests . "E2E tests for full workflows (33 tests)")
        (performance-tests . "Resolver benchmarks (<5s for 100 packages)")
        (manual-testing . "TESTING.md checklist (16 scenarios)")
        (ci . "GitHub Actions on every PR"))

      (versioning
        (scheme . "Semantic versioning (MAJOR.MINOR.PATCH)")
        (git-tags . "v1.0.0, v1.1.0, etc.")
        (changelog . "Keep CHANGELOG.md updated")
        (breaking-changes . "Major version bump, migration guide"))

      (documentation
        (adoc . "Architecture and design docs (AsciiDoc)")
        (md . "User-facing docs (Markdown)")
        (inline . "@moduledoc, @doc for code")
        (examples . "examples/ directory with working code")
        (readme . "README.adoc as entry point"))

      (branching
        (main . "Always deployable, protected")
        (feature-branches . "feature/*, delete after merge")
        (releases . "Tag on main, no release branches")
        (hotfixes . "hotfix/* merged to main")))

    (design-rationale
      (why-multi-language
        "Problem: Modern projects use polyglot stacks (Elixir + Rust + ReScript + Julia)"
        "Solution: OPSM as universal package manager"
        "Benefit: One tool for all dependencies, cross-language resolution")

      (why-federation
        "Problem: Centralized registries are single points of failure (npm outage 2016, left-pad incident)"
        "Solution: Federation via IPFS, Radicle, git-private-farm, opsm-registry-hub"
        "Benefit: Censorship resistance, high availability, community sovereignty")

      (why-trust-pipeline
        "Problem: Package registries trust community moderation (malware, typosquatting, supply chain attacks)"
        "Solution: 5-microservice verification before publish"
        "Benefit: Proactive security, attestations, provenance, sustainability scoring")

      (why-har
        "Problem: Obscure languages lack registries (Idris2, Nimble, ATS, Agda, etc.)"
        "Solution: Human-Assisted Registry with agentic discovery"
        "Benefit: Universal support without requiring centralized registries")

      (why-proven-library
        "Problem: Traditional validation is bug-prone (SSRF, DoS, injection)"
        "Solution: Idris2 proven library with mathematical correctness proofs"
        "Benefit: Impossible to bypass security (compiler-verified)")

      (why-mobile
        "Problem: Developers work on mobile devices, need package management"
        "Solution: Native iOS/Android app via Tauri 2.0"
        "Benefit: OPSM everywhere (laptop, phone, tablet)")

      (why-tea-architecture
        "Problem: Complex state management in mobile UI (race conditions, stale state)"
        "Solution: The Elm Architecture (Model-View-Update)"
        "Benefit: Predictable state, no race conditions, easy testing")

      (why-rescript-not-typescript
        "Problem: TypeScript has unsound type system (any, type assertions)"
        "Solution: ReScript with sound type system"
        "Benefit: 100% type safety, faster compilation, no runtime errors"))

    (governance
      (maintainer . "Jonathan D.A. Jewell (@hyperpolymath)")
      (license . "PMPL-1.0 (Polymath Public Meta-License)")
      (contributions . "See CONTRIBUTING.md")
      (code-of-conduct . "Contributor Covenant 2.1")
      (decision-making . "Benevolent dictator (BDFL model) until v2.0, then community governance (v10.0 DAO)"))

    (future-vision
      (v1.1 . "Production hardening (real-world testing, performance, mobile completion)")
      (v1.5 . "Enhanced trust (Idris2 NIFs, SLSA attestations, supply chain provenance)")
      (v2.0 . "Scale and intelligence (100+ languages, ML discovery, distributed resolver)")
      (v10.0 . "Federated ecosystem (cross-forge governance, global registry hubs, automated health monitoring)")
      (ultimate-goal . "Universal, self-governing package ecosystem with mathematical correctness guarantees"))))
