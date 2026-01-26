;; SPDX-License-Identifier: PMPL-1.0-or-later
;; AGENTIC.scm - AI agent interaction patterns for odds-and-sods-package-manager

(define agentic-config
  `((version . "1.0.0")
    (codex
      ((model . "gpt-5")
       (tools . ("read" "edit" "bash" "rg"))
       (permissions . "workspace-write")))
    (patterns
      ((code-review . "thorough")
       (refactoring . "conservative")
       (testing . "integration")))
    (constraints
      ((languages . ("Rust" "Idris2" "Nickel" "Haskell" "Elixir"))
       (banned . ("typescript" "go" "python" "makefile"))))))
