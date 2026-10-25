# SPDX-License-Identifier: MPL-2.0
// Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
# OPSM - Odds and Sods Package Manager
# https://just.systems/man/en/

set shell := ["bash", "-uc"]
set dotenv-load := true
set positional-arguments := true

import? "contractile.just"

project := "opsm"
version := "1.2.0"

# ═══════════════════════════════════════════════════════════════════════════════
# DEFAULT & HELP
# ═══════════════════════════════════════════════════════════════════════════════

default:
    @just --list --unsorted

# ═══════════════════════════════════════════════════════════════════════════════
# BUILD
# ═══════════════════════════════════════════════════════════════════════════════

# Build Elixir escript (standalone binary) — the OPSM CLI
build-escript:
    cd opsm_ex && mix deps.get && mix escript.build

# Build Tauri mobile app (debug)
build-mobile:
    cd opsm_mobile/src-tauri && cargo build

# Build Tauri mobile app (release)
build-mobile-release:
    cd opsm_mobile/src-tauri && cargo build --release

# Build a specific Rust microservice
build-service name:
    cd services/{{name}} && cargo build

# Build all Rust microservices
build-services:
    #!/usr/bin/env bash
    for svc in services/*/; do
        svc_name=$(basename "$svc")
        echo "Building $svc_name..."
        (cd "$svc" && cargo build) || exit 1
    done

# Build everything
build: build-escript

# Clean all build artifacts
clean:
    cd opsm_ex && mix clean
    rm -rf opsm_ex/opsm

# ═══════════════════════════════════════════════════════════════════════════════
# TEST
# ═══════════════════════════════════════════════════════════════════════════════

# Run Elixir tests
test *args:
    cd opsm_ex && mix test {{args}}

# Run Elixir tests with verbose output
test-verbose:
    cd opsm_ex && mix test --trace

# Run all tests
test-all: test

# ═══════════════════════════════════════════════════════════════════════════════
# LINT & FORMAT
# ═══════════════════════════════════════════════════════════════════════════════

# Format Elixir code
fmt-ex:
    cd opsm_ex && mix format

# Lint Elixir code (strict compile — warnings are errors)
lint:
    cd opsm_ex && mix deps.get && mix compile --warnings-as-errors

# Check Elixir format
fmt-check:
    cd opsm_ex && mix format --check-formatted

# Format all code
fmt: fmt-ex

# ═══════════════════════════════════════════════════════════════════════════════
# TOOLCHAIN (single source of truth: opsm.toml [runtime] — docs/TOOLCHAIN.adoc)
# ═══════════════════════════════════════════════════════════════════════════════

# Regenerate .tool-versions from opsm.toml [runtime]
toolchain-sync:
    sh scripts/toolchain.sh sync

# Verify .tool-versions and CI image pins match opsm.toml [runtime]
toolchain-check:
    sh scripts/toolchain.sh check

# ═══════════════════════════════════════════════════════════════════════════════
# RUN
# ═══════════════════════════════════════════════════════════════════════════════

# Run OPSM via escript (the CLI)
opsm *args:
    cd opsm_ex && ./opsm {{args}}

# Run OPSM Elixir in dev mode with IEx
repl:
    cd opsm_ex && iex -S mix

# ═══════════════════════════════════════════════════════════════════════════════
# PACKAGE OPERATIONS (shortcuts)
# ═══════════════════════════════════════════════════════════════════════════════

# Install a package (dry-run)
install-dry forth pkg:
    cd opsm_ex && ./opsm install @{{forth}} {{pkg}} --dry-run

# Search across all registries
search query:
    cd opsm_ex && ./opsm search {{query}}

# Show package info
info forth pkg:
    cd opsm_ex && ./opsm info @{{forth}} {{pkg}}

# Check for updates
check-updates:
    cd opsm_ex && ./opsm check-update

# Verify lockfile integrity
verify:
    cd opsm_ex && ./opsm check

# ═══════════════════════════════════════════════════════════════════════════════
# DEPENDENCIES
# ═══════════════════════════════════════════════════════════════════════════════

# Install Elixir dependencies
deps-ex:
    cd opsm_ex && mix deps.get

# Install all dependencies
deps: deps-ex

# Audit Elixir dependencies
deps-audit:
    cd opsm_ex && mix hex.audit

# ═══════════════════════════════════════════════════════════════════════════════
# CONTAINERS
# ═══════════════════════════════════════════════════════════════════════════════

# Build a service container image
container-build service tag="latest":
    podman build -t {{project}}-{{service}}:{{tag}} -f services/{{service}}/Containerfile services/{{service}}/

# Start all OPSM services
compose-up *args:
    #!/usr/bin/env bash
    if command -v selur-compose >/dev/null 2>&1; then
        selur-compose -f selur-compose.yml up {{args}}
    elif command -v podman-compose >/dev/null 2>&1; then
        podman-compose -f selur-compose.yml up {{args}}
    else
        echo "Install selur-compose or podman-compose"
        exit 1
    fi

# Stop all OPSM services
compose-down:
    #!/usr/bin/env bash
    if command -v selur-compose >/dev/null 2>&1; then
        selur-compose -f selur-compose.yml down
    elif command -v podman-compose >/dev/null 2>&1; then
        podman-compose -f selur-compose.yml down
    fi

# ═══════════════════════════════════════════════════════════════════════════════
# CI & QUALITY
# ═══════════════════════════════════════════════════════════════════════════════
# The CI entry points live in the CI section at the end of this file, so that
# `just ci` is one definition with one meaning (docs/CI-CD.adoc).

# ═══════════════════════════════════════════════════════════════════════════════
# UTILITIES
# ═══════════════════════════════════════════════════════════════════════════════

# Count lines of code
loc:
    @echo "=== OPSM Lines of Code ==="
    @echo -n "Elixir: " && find opsm_ex/lib -name "*.ex" | xargs wc -l 2>/dev/null | tail -1
    @echo -n "Rust (services): " && find services -name "*.rs" | xargs wc -l 2>/dev/null | tail -1

# Show TODO comments
todos:
    @grep -rn "TODO\|FIXME" --include="*.ex" --include="*.rs" . 2>/dev/null | grep -v node_modules | grep -v _build | grep -v target || echo "No TODOs"

# Show git status
status:
    @git status --short

# Show recent commits
log count="20":
    @git log --oneline -{{count}}

# Run panic-attacker pre-commit scan
assail:
    @command -v panic-attack >/dev/null 2>&1 && panic-attack assail . || echo "panic-attack not found — install from https://github.com/hyperpolymath/panic-attacker"

# Self-diagnostic — checks dependencies, permissions, paths
doctor:
    @echo "Running diagnostics for odds-and-sods-package-manager..."
    @echo "Checking required tools..."
    @command -v just >/dev/null 2>&1 && echo "  [OK] just" || echo "  [FAIL] just not found"
    @command -v git >/dev/null 2>&1 && echo "  [OK] git" || echo "  [FAIL] git not found"
    @echo "Checking for hardcoded paths..."
    @grep -rn '$HOME\|$ECLIPSE_DIR' --include='*.rs' --include='*.ex' --include='*.gleam' --include='*.sh' . 2>/dev/null | head -5 || echo "  [OK] No hardcoded paths"
    @echo "Diagnostics complete."

# Auto-repair common issues
heal:
    @echo "Attempting auto-repair for odds-and-sods-package-manager..."
    @echo "Fixing permissions..."
    @find . -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
    @echo "Cleaning stale caches..."
    @rm -rf .cache/stale 2>/dev/null || true
    @echo "Repair complete."

# Guided tour of key features
tour:
    @echo "=== odds-and-sods-package-manager Tour ==="
    @echo ""
    @echo "1. Project structure:"
    @ls -la
    @echo ""
    @echo "2. Available commands: just --list"
    @echo ""
    @echo "3. Read README.adoc for full overview"
    @echo "4. Read EXPLAINME.adoc for architecture decisions"
    @echo "5. Run 'just doctor' to check your setup"
    @echo ""
    @echo "Tour complete! Try 'just --list' to see all available commands."

# Open feedback channel with diagnostic context
help-me:
    @echo "=== odds-and-sods-package-manager Help ==="
    @echo "Platform: $(uname -s) $(uname -m)"
    @echo "Shell: $SHELL"
    @echo ""
    @echo "To report an issue:"
    @echo "  https://github.com/hyperpolymath/odds-and-sods-package-manager/issues/new"
    @echo ""
    @echo "Include the output of 'just doctor' in your report."


# Print the current CRG grade (reads from READINESS.md '**Current Grade:** X' line)
crg-grade:
    @grade=$$(grep -oP '(?<=\*\*Current Grade:\*\* )[A-FX]' READINESS.md 2>/dev/null | head -1); \
    [ -z "$$grade" ] && grade="X"; \
    echo "$$grade"

# Generate a shields.io badge markdown for the current CRG grade
# Looks for '**Current Grade:** X' in READINESS.md; falls back to X
crg-badge:
    @grade=$$(grep -oP '(?<=\*\*Current Grade:\*\* )[A-FX]' READINESS.md 2>/dev/null | head -1); \
    [ -z "$$grade" ] && grade="X"; \
    case "$$grade" in \
      A) color="brightgreen" ;; B) color="green" ;; C) color="yellow" ;; \
      D) color="orange" ;; E) color="red" ;; F) color="critical" ;; \
      *) color="lightgrey" ;; esac; \
    echo "[![CRG $$grade](https://img.shields.io/badge/CRG-$$grade-$$color?style=flat-square)](https://github.com/hyperpolymath/standards/tree/main/component-readiness-grades)"

secret-scan-trufflehog:
    @command -v trufflehog >/dev/null && trufflehog filesystem . --only-verified || true

# ═══════════════════════════════════════════════════════════════════════════════
# CI — the same gates CI runs, runnable on a laptop (docs/CI-CD.adoc)
# ═══════════════════════════════════════════════════════════════════════════════

# Everything CI will check. Run this before you open a pull request.
ci: toolchain-check fmt-check lint json-check yaml-check test proven-check

# Fast subset: nothing that compiles or fetches.
ci-fast: toolchain-check fmt-check json-check yaml-check

# JSON conformance, report-only (J-1/J-2). Needs ijson-jcs on PATH.
json-check:
    bash scripts/ci/check-json.sh .

# JSON conformance, blocking.
json-enforce:
    bash scripts/ci/check-json.sh --enforce .

# YAML parse (blocking) + KYAML drift (report-only). Needs yq v4.45+.
yaml-check:
    bash scripts/ci/check-yaml.sh .

# Rewrite every JSON file into JCS form (needs ijson-jcs).
json-fix:
    @for f in $$(git ls-files '*.json'); do ijson-jcs fix "$$f" >/dev/null || exit 1; echo "fixed $$f"; done

# Validate test/proven_manifest.toml against the suite on disk.
proven-check:
    cd opsm_ex && mix run --no-start scripts/validate_proven.exs

# Run the suite with the Proven-Tests reporter and print the coverage summary.
proven-report:
    cd opsm_ex && OPSM_PROVEN_REPORT=1 mix test
    cd opsm_ex && mix run --no-start scripts/proven_summary.exs
    @cat opsm_ex/proven-summary.md

# Cross-repo CI dependency chains (read-only). Needs squabble on PATH:
#   cargo install --git https://github.com/hyperpolymath/cicd-squabbler --locked squabble-cli
squabble-chains:
    squabble chains . --follow 1

# The gate state of a pull request, with the moves open to it.
#   just squabble-fetch 122
squabble-fetch pr:
    squabble fetch hyperpolymath/odds-and-sods-package-manager {{pr}}

# Full tool-install soak against ten registries (network, slow). Not part of CI.
stress:
    cd opsm_ex && mix run scripts/stress_test.exs

# Benchmarks (not part of the blocking gate).
bench:
    cd opsm_ex && mix run bench/opsm_bench.exs
