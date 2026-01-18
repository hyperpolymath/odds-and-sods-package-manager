;; SPDX-License-Identifier: PMPL-1.0
;; STATE.scm - Project state for odds-and-sods-package-manager

(state
  (metadata
    (version "0.1.0")
    (schema-version "1.0")
    (created "2025-01-17")
    (updated "2026-01-18")
    (project "odds-and-sods-package-manager")
    (repo "hyperpolymath/odds-and-sods-package-manager"))

  (project-context
    (name "OPM - Odds-and-sods Package Manager")
    (tagline "Federated multi-language package manager with trust pipeline")
    (tech-stack ("deno" "typescript" "proven/idris2")))

  (current-position
    (phase "scaffold")
    (overall-completion 15)
    (components
      (cli
        (status "scaffold")
        (completion 20)
        (notes "Deno CLI with subcommands: publish, audit, status"))
      (registry-hub
        (status "scaffold")
        (completion 10)
        (notes "Schema stubs and event handlers"))
      (trust-pipeline
        (status "planned")
        (completion 5)
        (notes "Client stubs for claim-forge, checky-monkey, oikos")))
    (working-features
      ("CLI argument parsing"
       "Config file search (OPM_CONFIG, ./opm.toml, ~/.config/opm/)"
       "HTTP client with retries and backoff"
       "Service client stubs")))

  (route-to-mvp
    (milestone "v0.1.0 - MVP wiring"
      (items
        ("opm publish pipeline: claim-forge → checky-monkey → cicd-hyper-a"
         "Manifest ingestion via nickel-config-reporter"
         "Registry read/write API via http-capability-gateway"
         "Property tests via echidnabot")))
    (milestone "v1.0.0 - Stable core"
      (items
        ("Full trust pipeline (8-dimension scoring)"
         "Dependency resolution with sustainability scoring"
         "Federation sync via git-private-farm + Radicle + IPFS"))))

  (blockers-and-issues
    (critical ())
    (high ())
    (medium
      ("Service contracts not yet defined"
       "Registry API schema incomplete"))
    (low ()))

  (critical-next-actions
    (immediate
      ("Wire real service contracts in clients/"))
    (this-week
      ("Define publish pipeline orchestration"
       "Add integration tests with mock services"))
    (this-month
      ("Connect to live trust pipeline services"))))
