<!--
SPDX-License-Identifier: MPL-2.0
Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
# Paper Sketch — Zenodo / arXiv Submission

**Working Title:** *OPSM: Trust-First Package Management for the Ecosystem-of-Ecosystems Era*  
**Alt Title:** *Beyond Language Silos: Inclusive, Formally-Verified Cross-Ecosystem Dependency Management*  
**Venue target:** arXiv cs.SE or cs.PL; deposit to Zenodo for DOI  
**Audience:** PL/SE researchers, package manager implementors, security practitioners  
**Format:** ~8 000 words, conference-paper style; no IEEE/ACM overhead needed for arXiv/Zenodo  
**Status:** SKETCH — not yet written; route to CHATGPT for prose, CLAUDE for formal claims

---

## 1. The Core Argument (one paragraph)

Modern projects are not monolingual. A typical mid-2020s system combines a Rust core, a
Deno/ReScript frontend, Elixir coordination services, Julia batch scripts, and Zig
FFI bridges — and that is before counting the niche languages in embedded subsystems
(Ada safety core, Idris2 proof layer, Gleam actor network). Yet every package manager
available today is language-local: Cargo serves Rust, Hex serves Elixir, npm serves
JavaScript, each with its own trust model, its own resolver, its own vulnerability feed.
The result is *N* separate supply-chain attack surfaces, *N* separate pinning disciplines,
*N* separate audit processes — for one logical project. We call this the
**ecosystem-of-ecosystems problem**. OPSM is our answer: a single CLI with 101 registry
adapters, a unified trust pipeline from provenance generation to post-quantum attestation,
a formally-verified resolver, and a Human-Assisted Registry that enfranchises languages
whose communities are too small to operate a package index.

---

## 2. Structure / Section Map

### §1 Introduction
- The polyglot shift: data from GitHub Language Statistics, TIOBE polyglot monorepos
- Supply-chain incidents that crossed language boundaries (Log4Shell cascade,
  node-ipc, eslint-scope, PyPI typosquat → downstream Rust builds)
- Gap: no cross-ecosystem trust standard; SLSA is language-agnostic in principle but
  per-ecosystem in practice
- Contribution list (bullet form, verifiable against OPSM implementation)

### §2 Background and Related Work
- Language-local PMs: Cargo, npm/Deno, pip, Hex, pub (Dart), pub.dev, RubyGems,
  Hackage — what each does well and what it cannot see
- Cross-ecosystem tools that exist: Nix/Guix (good: reproducibility; gap: language
  semantics opaque to resolver), Renovate/Dependabot (good: multi-ecosystem awareness;
  gap: no trust pipeline, no verification, read-only)
- Supply-chain security standards: SLSA, SBOM (SPDX/CycloneDX), Sigstore, IANA
  package-metadata specs, OpenSSF Scorecard
- PubGrub resolver: what it guarantees vs what ad-hoc SAT/backtracking cannot

### §3 The Ecosystem-of-Ecosystems Problem (formalism + examples)

**Definition.** An *ecosystem* E is a tuple (R, V, M) where R is a registry,
V is a version scheme (Semver, PEP 440, Go MVS, etc.), and M is a manifest format
(Cargo.toml, package.json, mix.exs, etc.). An *ecosystem-of-ecosystems project* P
is a project whose dependency graph D spans ≥2 distinct ecosystems.

**Claim 1.** For any P with ecosystems {E₁, ..., Eₙ}, the union of attack surfaces
is at least Σᵢ|trust_assumptions(Eᵢ)| — there is no sub-additive interaction without
a shared trust root.

**Claim 2.** Resolver correctness across Eᵢ requires version-scheme translation
(e.g. Semver ↔ PEP 440) plus a monotonicity invariant that PubGrub can maintain
but greedy resolvers cannot.

**Examples:** real incidents (with CVEs) where a vulnerability in ecosystem Eᵢ
propagated through a cross-ecosystem build graph to Eⱼ.

### §4 OPSM Architecture

4.1 **Registry Layer** (101 adapters)
- 8 first-class adapters (Crates, npm, Hex, PyPI, RubyGems, Go, Hackage, pub)
- 93 plugin adapters (asdf plugins, language-specific custom registries)
- Uniform adapter interface: `fetch_versions/2`, `fetch_manifest/2`,
  `fetch_tarball/3`, `verify_checksum/2`
- ETS-based caching with TTL; federation propagation

4.2 **Unified Resolver** (PubGrub over V)
- Version scheme normalisation layer: `Semver`, `Pep440`, `GoMVS` → `ComparableVersion`
- Cross-ecosystem conflict detection: when Eᵢ and Eⱼ transitively share a native dep
  (e.g. OpenSSL), OPSM detects the diamond and applies the strictest version bound
- Property-based testing: ∀ inputs, PubGrub terminates and produces a minimal solution
  (QuickCheck / StreamData proofs)

4.3 **Trust Pipeline** (5 microservices)
- `claim-forge` (Rust): SLSA Level 3 provenance generation, ed25519+Dilithium5 signing
- `checky-monkey` (Rust): tarball integrity, SBOM extraction, CycloneDX validation
- `palimpsest-license` (Rust/Elixir): SPDX expression compatibility matrix, 
  PMPL/MPL/AGPL/MIT/Apache interactions verified
- `oikos` (Elixir): sustainability scoring — 8 dimensions (maintenance, bus factor,
  funding, responsiveness, test coverage, security posture, docs quality, governance)
- `cicd-hyper-a` (Rust): publication + federation, SLSA attestation anchoring

4.4 **Post-Quantum Hardening**
- Motivation: harvest-now-decrypt-later against package signatures
- Dilithium5 + Ed25519 hybrid; Kyber-1024 KEM for key exchange; SPHINCS+ for
  time-stamp commitments
- Implemented as Rust NIF called from Elixir; benchmarks show < 2ms overhead
  for typical package verification

4.5 **Human-Assisted Registry (HAR)**
- Problem: minority-language ecosystems (Pony, Lobster, Pharo, GDScript, Idol, etc.)
  have no centralised registry; they distribute via git + manual instructions
- HAR: three agentic discovery agents (GitHub scraper, web crawler, mirror finder)
  that build a registry record with human curation step before acceptance
- Inclusion claim: any language that has ≥1 public package can participate without
  infrastructure investment; HAR provides the indexing layer
- Governance: curation committee model; RFC process for new language onboarding

4.6 **Manifest Interoperability**
- 10 input formats → unified internal representation → 7 output formats
- Round-trip fidelity: what is preserved vs what is lossy (documented per format)
- Lock-file generation: deterministic across OPSM versions

### §5 Formal Guarantees and Verification
- PubGrub properties: completeness, minimality, termination — proven via StreamData
- License compatibility: SPDX expression decision procedure proven correct for
  a subset of SPDX (excluding GPL linking edge cases; explicitly out of scope)
- SSRF and DoS prevention: verified block at the resolver boundary
- What we do NOT prove (honesty): we cannot verify upstream registry honesty;
  trust pipeline mitigates but does not eliminate

### §6 Evaluation

6.1 **Correctness** (547 core + 40 property + 49 integration tests)
- Resolver correctness vs npm/pip on their own test suites (cross-ecosystem cases)
- Trust pipeline false positive/negative rates on known-good and known-bad packages

6.2 **Performance**
- Resolver: compared to `npm install`, `cargo build`, `mix deps.get` on equivalent
  dependency graphs; OPSM overhead breakdown
- Trust pipeline: per-package latency distribution; cache hit rates

6.3 **Inclusion**
- Languages onboarded via HAR: how many, time-to-first-package
- Comparison: how many of those languages have any tooling in Nix/Guix/Renovate

6.4 **Security**
- Supply chain simulation: inject a known-malicious package; OPSM detects via
  claim-forge provenance mismatch in N% of cases

### §7 Limitations and Future Work
- Resolver completeness for circular cross-ecosystem deps (currently rejected)
- HAR governance scalability (human curation bottleneck)
- Plugin system sandboxing (subprocess boundary for untrusted registry adapters)
- Integration with Guix/Nix channel infrastructure (OPSM as frontend)
- Formal SLSA Level 4 upgrade (requires hermetic build environment)

### §8 Conclusion
- The ecosystem-of-ecosystems problem is structural, not incidental
- OPSM demonstrates it is solvable at acceptable overhead
- Open source (MPL-2.0 / MPL-2.0 fallback); HAR governance model documented

---

## 3. Key Claims (must be backed by evidence before submission)

| Claim | Evidence needed | Status |
|-------|-----------------|--------|
| PubGrub correctly resolves cross-ecosystem deps where greedy fails | Failing test case + OPSM resolution | Needs construction |
| Trust pipeline catches N% of SLSA-violating packages | Simulation or real-world corpus | Needs benchmark |
| HAR reduces time-to-first-package for minority languages to < 1 day | Case studies (Pony? Lobster?) | Needs documentation |
| Post-quantum signing overhead < 2ms at p99 | Benchmark in claim-forge | Claimed; needs formal measurement |
| License compatibility matrix is sound for SPDX core | Formal proof or exhaustive case analysis | Needs proof or scope statement |

---

## 4. Assignment

| Task | Assigned to |
|------|-------------|
| Full prose draft (§1, §2, §8) | CHATGPT |
| Formalism (§3, §5) | CLAUDE |
| Architecture section (§4) | CLAUDE (from EXPLAINME.adoc) |
| Evaluation data collection | Jonathan + CLAUDE (run benchmarks) |
| Figures (architecture diagram, trust pipeline flow) | VIBE |
| Bibliography | CHATGPT |
| arXiv/Zenodo submission | Jonathan (manual) |

---

## 5. Notes from Past Discussions

The following design choices emerged from the long discussions that preceded OPSM v2:

- **"Package manager as CI gate, not just CLI tool"** — the trust pipeline must run
  in CI, not just locally, so OPSM ships as a GitHub Actions step as well as a CLI
- **"Registry adapters must be hot-reloadable"** — this is why the adapter interface
  is a clean function triple; new registries do not require recompile
- **"Version schemes are not comparable"** — the normalisation layer is non-trivial;
  PEP 440 post/dev releases have no Semver equivalent and must be handled as
  out-of-band metadata
- **"Minority languages matter"** — the explicit decision that OPSM will never say
  "your language is too small to matter"; HAR is the institutional commitment to that
- **"Trust is not binary"** — oikos sustainability score is NOT a block/allow gate;
  it is advisory metadata surfaced to the developer; paternalistic blocking would
  reduce adoption
- **"Post-quantum NOW, not later"** — harvest-now-decrypt-later means today's signed
  packages will be forgeable in ~10 years if only classical signatures are used;
  Dilithium5 hybrid is the hedge

---

*Route to CHATGPT for §1/§2/§8 prose. Route to CLAUDE for §3/§5 formalism and §4 draft.*  
*Zenodo: create new deposit under hyperpolymath community, select CC-BY-4.0 for paper text.*
*arXiv: cs.SE primary, cs.CR secondary (supply-chain security angle).*
