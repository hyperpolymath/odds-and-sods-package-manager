;; SPDX-License-Identifier: PMPL-1.0
;; META.scm - Meta-level information for odds-and-sods-package-manager
;; Media-Type: application/meta+scheme

(meta
  (architecture-decisions
    ("Federated hub with event-driven mirroring")
    ("Verification-first pipeline with proven/Idris2")
    ("Trust scoring via checky-monkey + oikos"))

  (development-practices
    (code-style ("Rust + AsciiDoc + Scheme metadata"))
    (security
      (principle "Defense in depth"))
    (testing ("CLI integration tests with mocked endpoints"))
    (versioning "SemVer")
    (documentation "AsciiDoc")
    (branching "main"))

  (design-rationale
    ("Maximize supply-chain integrity across language ecosystems")
    ("Enable decentralised distribution without single-fork dependence")))
