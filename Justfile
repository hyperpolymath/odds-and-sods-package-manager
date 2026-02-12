# SPDX-License-Identifier: PMPL-1.0-or-later
# OPSM - Odds and Sods Package Manager
# https://just.systems/man/en/

set shell := ["bash", "-uc"]
set dotenv-load := true
set positional-arguments := true

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

# Build ReScript CLI
build-cli:
    deno task build

# Build ReScript CLI in watch mode
build-cli-watch:
    deno task build:watch

# Build Elixir escript (standalone binary)
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
build: build-cli build-escript

# Clean all build artifacts
clean:
    deno task clean
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

# Run Deno tests
test-cli:
    deno task test

# Run all tests
test-all: test test-cli

# ═══════════════════════════════════════════════════════════════════════════════
# LINT & FORMAT
# ═══════════════════════════════════════════════════════════════════════════════

# Format Elixir code
fmt-ex:
    cd opsm_ex && mix format

# Format with Deno
fmt-deno:
    deno fmt

# Lint ReScript output with Deno
lint:
    deno lint cli/*.res.js cli/clients/*.res.js

# Check Elixir format
fmt-check:
    cd opsm_ex && mix format --check-formatted

# Format all code
fmt: fmt-ex fmt-deno

# ═══════════════════════════════════════════════════════════════════════════════
# RUN
# ═══════════════════════════════════════════════════════════════════════════════

# Run OPSM via escript (primary CLI)
opsm *args:
    cd opsm_ex && ./opsm {{args}}

# Run OPSM via Deno (ReScript CLI — trust pipeline)
opsm-cli *args:
    deno task opsm -- {{args}}

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
    @echo "Deno deps auto-resolved via import maps"

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

# Run full CI pipeline locally
ci: deps build test lint fmt-check
    @echo "CI pipeline complete!"

# ═══════════════════════════════════════════════════════════════════════════════
# UTILITIES
# ═══════════════════════════════════════════════════════════════════════════════

# Count lines of code
loc:
    @echo "=== OPSM Lines of Code ==="
    @echo -n "Elixir: " && find opsm_ex/lib -name "*.ex" | xargs wc -l 2>/dev/null | tail -1
    @echo -n "ReScript: " && find cli -name "*.res" | xargs wc -l 2>/dev/null | tail -1
    @echo -n "Rust (services): " && find services -name "*.rs" | xargs wc -l 2>/dev/null | tail -1
    @echo -n "Rust (mobile): " && find opsm_mobile -name "*.rs" | xargs wc -l 2>/dev/null | tail -1

# Show TODO comments
todos:
    @grep -rn "TODO\|FIXME" --include="*.ex" --include="*.res" --include="*.rs" . 2>/dev/null | grep -v node_modules | grep -v _build | grep -v target || echo "No TODOs"

# Show git status
status:
    @git status --short

# Show recent commits
log count="20":
    @git log --oneline -{{count}}
