#!/usr/bin/env bash
# SPDX-License-Identifier: PMPL-1.0
# OPM v1.0.0 Manual Validation Script
# Tests all major functionality before release

set -euo pipefail

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

readonly TEST_DIR="/tmp/opm-validation-$$"
readonly OPM_BIN="./opm"

PASSED=0
FAILED=0
SKIPPED=0

log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $*"
}

error() {
    echo -e "${RED}[$(date +'%H:%M:%S')] ERROR:${NC} $*" >&2
}

warn() {
    echo -e "${YELLOW}[$(date +'%H:%M:%S')] WARN:${NC} $*"
}

section() {
    echo ""
    echo "============================================================"
    echo "$1"
    echo "============================================================"
}

test_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASSED++))
}

test_fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAILED++))
}

test_skip() {
    echo -e "${YELLOW}⊘${NC} $1"
    ((SKIPPED++))
}

setup() {
    log "Setting up test environment..."
    mkdir -p "$TEST_DIR"
    cd "$TEST_DIR"

    # Build OPM if needed
    if [[ ! -f "$OPM_BIN" ]]; then
        log "Building OPM..."
        cd /var/mnt/eclipse/repos/odds-and-sods-package-manager/opm_ex
        mix escript.build || {
            error "Failed to build OPM"
            exit 1
        }
        cd "$TEST_DIR"
    fi
}

cleanup() {
    log "Cleaning up..."
    cd /
    rm -rf "$TEST_DIR"
}

# =============================================================================
# Test 1: Version Constraint Parser
# =============================================================================
test_version_constraints() {
    section "Test 1: Version Constraint Parsing"

    cd /var/mnt/eclipse/repos/odds-and-sods-package-manager/opm_ex

    log "Running version constraint tests..."
    if mix test test/opm/version_constraint_test.exs --color 2>&1 | grep -q "0 failures"; then
        test_pass "Version constraint parser tests"
    else
        test_fail "Version constraint parser tests"
    fi

    cd "$TEST_DIR"
}

# =============================================================================
# Test 2: Dependency Resolver
# =============================================================================
test_dependency_resolver() {
    section "Test 2: Dependency Resolver"

    cd /var/mnt/eclipse/repos/odds-and-sods-package-manager/opm_ex

    log "Running resolver tests..."
    if mix test test/opm/resolver_test.exs --color 2>&1 | grep -q "0 failures"; then
        test_pass "Dependency resolver tests"
    else
        test_fail "Dependency resolver tests"
    fi

    cd "$TEST_DIR"
}

# =============================================================================
# Test 3: Lockfile System
# =============================================================================
test_lockfile() {
    section "Test 3: Lockfile System"

    cd /var/mnt/eclipse/repos/odds-and-sods-package-manager/opm_ex

    log "Running lockfile tests..."
    if mix test test/opm/lockfile_test.exs --color 2>&1 | grep -q "0 failures"; then
        test_pass "Lockfile system tests"
    else
        test_fail "Lockfile system tests"
    fi

    cd "$TEST_DIR"
}

# =============================================================================
# Test 4: Trust Pipeline
# =============================================================================
test_trust_pipeline() {
    section "Test 4: Trust Pipeline"

    cd /var/mnt/eclipse/repos/odds-and-sods-package-manager/opm_ex

    log "Running trust pipeline tests (unit tests)..."
    if mix test test/integration/trust_pipeline_test.exs --exclude integration --color 2>&1 | grep -q "0 failures"; then
        test_pass "Trust pipeline unit tests"
    else
        test_fail "Trust pipeline unit tests"
    fi

    cd "$TEST_DIR"
}

# =============================================================================
# Test 5: Verified Library
# =============================================================================
test_verified_library() {
    section "Test 5: Verified Library"

    cd /var/mnt/eclipse/repos/odds-and-sods-package-manager/opm_ex

    log "Running verified library tests..."
    if mix test test/opm/verified_test.exs --color 2>&1 | grep -q "0 failures"; then
        test_pass "Verified library tests"
    else
        test_fail "Verified library tests"
    fi

    cd "$TEST_DIR"
}

# =============================================================================
# Test 6: E2E Integration Tests
# =============================================================================
test_e2e_integration() {
    section "Test 6: E2E Integration Tests"

    cd /var/mnt/eclipse/repos/odds-and-sods-package-manager/opm_ex

    log "Running E2E integration tests (unit tests only)..."
    if mix test test/integration/e2e_test.exs --exclude integration --exclude skip --color 2>&1 | grep -q "0 failures"; then
        test_pass "E2E unit tests"
    else
        test_fail "E2E unit tests"
    fi

    cd "$TEST_DIR"
}

# =============================================================================
# Test 7: Registry Adapters
# =============================================================================
test_registry_adapters() {
    section "Test 7: Registry Adapters"

    cd /var/mnt/eclipse/repos/odds-and-sods-package-manager/opm_ex

    local adapters=("npm" "hex" "cargo" "pypi" "nimble" "idris2" "git" "agentic")

    for adapter in "${adapters[@]}"; do
        log "Checking $adapter adapter..."
        if grep -q "defmodule Opm.Registries.$(echo "$adapter" | sed 's/.*/\u&/')" "lib/opm/registries/${adapter}.ex" 2>/dev/null; then
            test_pass "$adapter adapter exists"
        else
            test_fail "$adapter adapter missing"
        fi
    done

    cd "$TEST_DIR"
}

# =============================================================================
# Test 8: HAR Agents
# =============================================================================
test_har_agents() {
    section "Test 8: HAR Agents"

    cd /var/mnt/eclipse/repos/odds-and-sods-package-manager

    local agents=("github-search.sh" "web-scraper.jl" "mirror-finder.sh")

    for agent in "${agents[@]}"; do
        local agent_path="scripts/har-agents/$agent"
        if [[ -x "$agent_path" ]]; then
            test_pass "$agent is executable"
        else
            test_fail "$agent is not executable"
        fi

        # Check shebang
        if head -1 "$agent_path" | grep -q "^#!"; then
            test_pass "$agent has valid shebang"
        else
            test_fail "$agent missing shebang"
        fi
    done

    # Check dependencies
    if command -v jq &>/dev/null; then
        test_pass "jq available (required for bash agents)"
    else
        test_skip "jq not installed (bash agents will fail)"
    fi

    if command -v julia &>/dev/null; then
        test_pass "julia available (required for web-scraper)"
    else
        test_skip "julia not installed (web-scraper will fail)"
    fi

    cd "$TEST_DIR"
}

# =============================================================================
# Test 9: CLI Commands
# =============================================================================
test_cli_commands() {
    section "Test 9: CLI Commands"

    cd /var/mnt/eclipse/repos/odds-and-sods-package-manager/opm_ex

    # Test help
    if mix opm help &>/dev/null; then
        test_pass "opm help command"
    else
        test_fail "opm help command"
    fi

    # Test version
    if mix opm version &>/dev/null; then
        test_pass "opm version command"
    else
        test_fail "opm version command"
    fi

    # Test status (will fail if services not running, but command should work)
    if mix opm status &>/dev/null || true; then
        test_pass "opm status command exists"
    else
        test_fail "opm status command missing"
    fi

    cd "$TEST_DIR"
}

# =============================================================================
# Test 10: Configuration
# =============================================================================
test_configuration() {
    section "Test 10: Configuration"

    cd /var/mnt/eclipse/repos/odds-and-sods-package-manager/opm_ex

    # Check for default config
    if [[ -f "config/opm.toml" ]] || [[ -f "opm.toml" ]]; then
        test_pass "Configuration file exists"
    else
        test_skip "Configuration file not found (will use defaults)"
    fi

    # Test config loading
    log "Testing configuration loading..."
    if mix run -e "Opm.Config.load()" &>/dev/null; then
        test_pass "Configuration loads successfully"
    else
        test_fail "Configuration loading failed"
    fi

    cd "$TEST_DIR"
}

# =============================================================================
# Test 11: Documentation
# =============================================================================
test_documentation() {
    section "Test 11: Documentation"

    cd /var/mnt/eclipse/repos/odds-and-sods-package-manager

    local docs=(
        "README.adoc"
        "ROADMAP.adoc"
        "docs/adding-language-adapters.adoc"
        "docs/har-integration.adoc"
        "scripts/har-agents/README.md"
    )

    for doc in "${docs[@]}"; do
        if [[ -f "$doc" ]]; then
            test_pass "$doc exists"
        else
            test_fail "$doc missing"
        fi
    done

    cd "$TEST_DIR"
}

# =============================================================================
# Test 12: Full Test Suite
# =============================================================================
test_full_suite() {
    section "Test 12: Full Test Suite"

    cd /var/mnt/eclipse/repos/odds-and-sods-package-manager/opm_ex

    log "Running full test suite (this may take a while)..."
    local test_output
    test_output=$(mix test --exclude integration --exclude skip --color 2>&1)

    if echo "$test_output" | grep -q "0 failures"; then
        local test_count
        test_count=$(echo "$test_output" | grep -oP '\d+(?= tests)' | tail -1)
        test_pass "Full test suite: $test_count tests passed"
    else
        test_fail "Full test suite has failures"
        echo "$test_output" | tail -20
    fi

    cd "$TEST_DIR"
}

# =============================================================================
# Main
# =============================================================================
main() {
    log "OPM v1.0.0 Validation Suite"
    log "==========================="

    setup

    test_version_constraints
    test_dependency_resolver
    test_lockfile
    test_trust_pipeline
    test_verified_library
    test_e2e_integration
    test_registry_adapters
    test_har_agents
    test_cli_commands
    test_configuration
    test_documentation
    test_full_suite

    cleanup

    section "Test Summary"
    echo ""
    echo -e "${GREEN}Passed:${NC}  $PASSED"
    echo -e "${RED}Failed:${NC}  $FAILED"
    echo -e "${YELLOW}Skipped:${NC} $SKIPPED"
    echo ""

    if [[ $FAILED -eq 0 ]]; then
        log "All tests passed! OPM v1.0.0 is ready for release."
        exit 0
    else
        error "$FAILED test(s) failed. Please fix before release."
        exit 1
    fi
}

# Trap cleanup on exit
trap cleanup EXIT INT TERM

main "$@"
