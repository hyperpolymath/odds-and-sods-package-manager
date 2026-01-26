;; SPDX-License-Identifier: PMPL-1.0-or-later
;; ECOSYSTEM.scm - Ecosystem position for odds-and-sods-package-manager
;; Media-Type: application/vnd.ecosystem+scm

(ecosystem
  (version "1.0")
  (name "odds-and-sods-package-manager")
  (type "federated-package-manager")
  (purpose "Verified, federated package distribution across ecosystems")

  (position-in-ecosystem
    (category "package-management")
    (subcategory "federation")
    (unique-value ("formal-verification" "trust-pipeline" "multi-forge-sync")))

  (related-projects
    ("proven" "checky-monkey" "claim-forge" "palimpsest-license"
     "nickel-config-reporter" "hybrid-automation-router" "protocol-squisher"
     "scaffoldia" "cicd-hyper-a" "http-capability-gateway" "git-private-farm"
     "oikos" "rhodibot" "seambot" "echidnabot" "robot-repo-automaton"
     "opsm-ui" "gitbot-fleet"))

  (what-this-is
    ("Federated package manager"
     "Verification-first distribution pipeline"
     "Registry hub and CLI orchestration"))

  (what-this-is-not
    ("Single-ecosystem package manager"
     "Centralized registry without federation")))
