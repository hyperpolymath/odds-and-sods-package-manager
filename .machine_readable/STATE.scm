;; SPDX-License-Identifier: PMPL-1.0
;; STATE.scm - Project state for odds-and-sods-package-manager

(state
  (metadata
    (version "0.0.1")
    (schema-version "1.0")
    (created "2026-01-18")
    (updated "2026-01-18")
    (project "odds-and-sods-package-manager")
    (repo "hyperpolymath/odds-and-sods-package-manager"))

  (project-context
    (name "Odds-and-sods Package Manager")
    (tagline "Federated package manager with formal verification")
    (tech-stack ("Rust" "Idris2" "Nickel" "Haskell" "Elixir")))

  (current-position
    (phase "scaffold")
    (overall-completion 10)
    (working-features
      ("Repo scaffold"
       "CLI stubs + HTTP wiring"
       "Registry schemas + examples"
       "IMP docs draft"))
    (next-work
      ("Define real service contracts"
       "Implement publish/audit orchestration"
       "Stabilize IMP schema"))))
