# OPM v1.0.0 Testing Guide

This guide provides manual testing procedures to validate OPM functionality before release.

## Prerequisites

```bash
# Install OPM
cd opm_ex
mix deps.get
mix compile
mix escript.build

# Make OPM available globally (optional)
sudo ln -s $(pwd)/opm /usr/local/bin/opm

# Verify installation
opm version
```

## Test Categories

- [Automated Tests](#automated-tests)
- [Manual Tests](#manual-tests)
- [Integration Tests](#integration-tests)
- [Performance Tests](#performance-tests)

---

## Automated Tests

### Run All Tests

```bash
cd opm_ex

# Run all unit tests (fast)
mix test --exclude integration --exclude skip

# Run specific test suite
mix test test/opm/version_constraint_test.exs
mix test test/opm/resolver_test.exs
mix test test/opm/lockfile_test.exs
mix test test/opm/verified_test.exs

# Run validation script
../scripts/validate-v1.0.sh
```

**Expected:** All tests pass (164+ tests, 0 failures)

---

## Manual Tests

### Test 1: Version Constraint Parser

Test semver constraint parsing:

```bash
# In iex
iex -S mix

alias Opm.VersionConstraint

# Caret range
{:ok, c} = VersionConstraint.parse("^1.2.3", :semver)
VersionConstraint.satisfies?("1.2.3", c)  # true
VersionConstraint.satisfies?("1.3.0", c)  # true
VersionConstraint.satisfies?("2.0.0", c)  # false

# Tilde range
{:ok, c} = VersionConstraint.parse("~1.2.3", :semver)
VersionConstraint.satisfies?("1.2.3", c)  # true
VersionConstraint.satisfies?("1.2.9", c)  # true
VersionConstraint.satisfies?("1.3.0", c)  # false

# Python constraints
{:ok, c} = VersionConstraint.parse(">=1.0,<2.0", :python)
VersionConstraint.satisfies?("1.5.0", c)  # true
VersionConstraint.satisfies?("2.0.0", c)  # false
```

**Expected:** All constraint checks return expected boolean values.

---

### Test 2: Dependency Resolver

Test simple dependency resolution:

```bash
iex -S mix

alias Opm.Resolver

# Simple resolution
deps = [%{name: "lodash", constraint: "^4.17.0", forth: :npm}]
{:ok, resolution} = Resolver.resolve(deps, forth: :npm)

# Check result
Map.keys(resolution)  # Should include "lodash"
resolution["lodash"].version  # Should be 4.17.x
```

**Expected:** Resolution succeeds, returns package metadata.

---

### Test 3: Install Package (npm)

Test installation of a simple npm package:

```bash
cd /tmp
mkdir opm-test-install
cd opm-test-install

# Initialize
opm init

# Install small package
opm install lodash --forth npm

# Verify installation
ls node_modules/lodash
cat opm.lock  # Should contain lodash entry
```

**Expected:**
- Package downloaded to `node_modules/lodash`
- Lockfile created with package metadata
- Checksums verified

---

### Test 4: Install Package with Dependencies (npm)

Test transitive dependency resolution:

```bash
cd /tmp
mkdir opm-test-deps
cd opm-test-deps

# Install package with dependencies
opm install express --forth npm

# Verify dependencies installed
ls node_modules/  # Should include accepts, mime-types, etc.
cat opm.lock | jq '.packages | keys'  # Show all installed packages
```

**Expected:**
- Express and all dependencies installed
- Lockfile contains full dependency tree
- No conflicts

---

### Test 5: Dependency Conflict Detection

Test that resolver detects conflicts:

```bash
iex -S mix

alias Opm.Resolver

# Create impossible constraints (for demonstration)
deps = [
  %{name: "package-a", constraint: "^1.0.0", forth: :npm},
  %{name: "package-a", constraint: "^2.0.0", forth: :npm}
]

# Should fail with conflict
{:error, {:conflict, _}} = Resolver.resolve(deps)
```

**Expected:** Resolver returns conflict error with explanation.

---

### Test 6: Lockfile Integrity

Test lockfile creation and reading:

```bash
cd /tmp/opm-test-install

# Create lockfile
opm install lodash

# Verify lockfile structure
cat opm.lock | jq '.'
cat opm.lock | jq '.version'  # Should be "1.0"
cat opm.lock | jq '.packages | keys'  # Should include "lodash"

# Test lockfile roundtrip
cp opm.lock opm.lock.backup
opm install  # Should use existing lockfile
diff opm.lock opm.lock.backup  # Should be identical (except timestamps)
```

**Expected:**
- Lockfile valid JSON
- Contains version, packages, metadata
- Roundtrip preserves structure

---

### Test 7: Registry Adapters

Test each registry adapter:

```bash
# npm
opm search lodash --forth npm
opm info lodash --forth npm

# Hex (Elixir)
opm search poison --forth hex
opm info poison --forth hex

# Crates (Rust)
opm search serde --forth cargo
opm info serde --forth cargo

# PyPI (Python)
opm search requests --forth pypi
opm info requests --forth pypi

# Nimble (Nim)
opm search nimble --forth nimble
opm info nimble --forth nimble

# Idris2
opm search idris2-json --forth idris2
opm info idris2-json --forth idris2

# Git (generic)
opm info https://github.com/idris-community/idris2-json --forth git

# Agentic (HAR-based discovery)
# Requires HAR agents running
opm info obscure-package --forth agentic
```

**Expected:** Each adapter returns package information or appropriate error.

---

### Test 8: HAR Agents

Test HAR agent discovery:

```bash
# Start HAR agents (in separate terminals)
cd /var/mnt/eclipse/repos/odds-and-sods-package-manager/scripts/har-agents
./github-search.sh &
./web-scraper.jl &
./mirror-finder.sh &

# Submit test task
mkdir -p /tmp/opm-har-ingest
cat > /tmp/opm-har-ingest/test-task.imp.json <<EOF
{
  "imp": {
    "package": "idris2-json",
    "forth": "idris2"
  }
}
EOF

# Wait for agents to process
sleep 10

# Check results
ls /tmp/opm-har-ingest/results/
cat /tmp/opm-har-ingest/results/test-task.result.json | jq '.'

# Cleanup
rm /tmp/opm-har-ingest/test-task.imp.json
```

**Expected:**
- Agents process task file
- Result file created with package discovery
- Agents continue watching queue

---

### Test 9: Trust Pipeline Services

Test trust service health checks:

```bash
opm status

# Should show status of:
# - claim-forge
# - checky-monkey
# - palimpsest-license
# - cicd-hyper-a
# - oikos
```

**Expected:**
- Services reachable: shows "healthy" or "degraded"
- Services unreachable: shows "unreachable" (this is OK for v1.0)

---

### Test 10: Publish Package (requires services)

Test publishing a package:

```bash
cd /tmp
mkdir my-test-package
cd my-test-package

# Create package.json
cat > package.json <<EOF
{
  "name": "my-test-package",
  "version": "1.0.0",
  "description": "Test package for OPM validation",
  "license": "MIT",
  "main": "index.js"
}
EOF

# Create simple module
echo "module.exports = { test: true };" > index.js

# Initialize git (required for checky-monkey)
git init
git add .
git commit -m "Initial commit"
git remote add origin https://github.com/test/my-test-package.git

# Publish (requires trust services running)
opm publish .

# Expected output:
# ✓ Manifest ingested
# ✓ Attestation generated (claim-forge)
# ✓ License compatibility (palimpsest)
# ✓ Published to registry (cicd-hyper-a)
# ⏳ Checky-monkey verification queued
```

**Expected:**
- Manifest validated
- Tarball created
- Trust services contacted (may timeout if not running)
- Package metadata prepared for publication

---

### Test 11: Audit Package

Test sustainability audit:

```bash
# Audit a GitHub repository
opm audit https://github.com/some/popular-repo

# Expected output:
# Sustainability Analysis (oikos)
# --------------------------------
#   overall score: 75/100
#   scores:
#     maintainability: 80
#     documentation: 70
#     testCoverage: 75
#     ...
#
# License Analysis (palimpsest)
# -----------------------------
#   ✓ Detected 1 licenses
#   ✓ Compatibility: compatible
```

**Expected:**
- Oikos contacted (may timeout if not running)
- Palimpsest contacted (may timeout if not running)
- Graceful degradation if services unavailable

---

### Test 12: Verified Library

Test URL and JSON validation:

```bash
iex -S mix

alias Opm.Verified.{Url, Json}

# URL validation
{:ok, url} = Url.validate("https://registry.npmjs.org/package")
url.host  # "registry.npmjs.org"

# Should block localhost
{:error, :blocked_host} = Url.validate("https://localhost/api")

# Should block private IPs
{:error, :blocked_host} = Url.validate("http://192.168.1.1/api")

# JSON parsing
{:ok, data} = Json.decode(~s({"name":"test"}))
data["name"]  # "test"

# Should reject deeply nested JSON
nested = Enum.reduce(1..25, "1", fn _, acc -> ~s({"a":#{acc}}) end)
{:error, :nesting_too_deep} = Json.decode(nested)
```

**Expected:** All validations work as expected, malicious inputs rejected.

---

### Test 13: Event Dispatcher

Test federation event creation:

```bash
iex -S mix

alias Opm.Events
alias Opm.Config

{:ok, config} = Config.load()

# Create security advisory event
event_data = %{
  package: "test-package",
  version: "1.0.0",
  severity: "high",
  description: "Test vulnerability",
  cve_id: "CVE-2024-TEST"
}

{:ok, response} = Events.publish_event(config, :security_advisory, event_data)

response.event_id  # "evt_..."
response.status  # "queued"
```

**Expected:** Event created with unique ID, queued for propagation.

---

## Integration Tests

### Test 14: Full Workflow (Install → Publish → Audit)

Complete end-to-end workflow:

```bash
# 1. Install dependencies
cd /tmp
mkdir full-workflow-test
cd full-workflow-test
opm init

opm install lodash express --forth npm
ls node_modules/
cat opm.lock | jq '.packages | keys'

# 2. Create your package
cat > package.json <<EOF
{
  "name": "workflow-test",
  "version": "1.0.0",
  "dependencies": {
    "lodash": "^4.17.0",
    "express": "^4.18.0"
  }
}
EOF

# 3. Publish (requires services)
git init && git add . && git commit -m "init"
opm publish .

# 4. Audit
opm audit .
```

**Expected:** Complete workflow executes without errors.

---

## Performance Tests

### Test 15: Large Dependency Graph

Test resolver performance with complex dependencies:

```bash
cd /tmp
mkdir perf-test
cd perf-test

# Install package with large dependency tree
time opm install webpack --forth npm

# Check lockfile size
wc -l opm.lock
jq '.packages | length' opm.lock
```

**Expected:**
- Resolution completes in <30 seconds
- Lockfile contains 50+ packages
- No memory issues

---

### Test 16: Concurrent Installs

Test that multiple installs don't interfere:

```bash
cd /tmp
mkdir -p test-{1,2,3}

# Run installs in parallel
(cd test-1 && opm install lodash) &
(cd test-2 && opm install express) &
(cd test-3 && opm install axios) &

wait

# Verify all succeeded
ls test-1/node_modules/lodash
ls test-2/node_modules/express
ls test-3/node_modules/axios
```

**Expected:** All installs succeed without conflicts.

---

## Troubleshooting

### Services Unavailable

If trust services are not running, many tests will show warnings but should not fail:

```
⚠ Checky-monkey submission failed: connection refused
⚠ License analysis unavailable: service timeout
```

This is expected behavior - OPM degrades gracefully.

### HAR Agents Not Running

If HAR agents are not running, agentic adapter will timeout:

```
⚠ HAR task timed out: task-abc123 after 30000ms
```

Start agents with:
```bash
cd scripts/har-agents
./github-search.sh &
./web-scraper.jl &
./mirror-finder.sh &
```

### Package Download Failures

If package downloads fail:
- Check internet connection
- Verify registry is accessible
- Check if package name is correct
- Try with different registry (`--forth` flag)

### Lockfile Corruption

If lockfile becomes corrupted:
```bash
rm opm.lock
opm install  # Recreates from package.json
```

---

## CI/CD Integration

For automated testing in CI:

```yaml
# .github/workflows/test.yml
name: Test
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.15'
          otp-version: '26'

      - name: Install dependencies
        run: cd opm_ex && mix deps.get

      - name: Run tests
        run: cd opm_ex && mix test --exclude integration

      - name: Run validation
        run: ./scripts/validate-v1.0.sh
```

---

## Test Summary

| Category | Tests | Expected Result |
|----------|-------|-----------------|
| Unit Tests | 164+ | All pass |
| Version Constraints | 20+ | Parsers work correctly |
| Dependency Resolution | 15+ | Resolves transitive deps |
| Lockfile | 10+ | Roundtrip integrity |
| Registry Adapters | 8 | All available |
| HAR Agents | 3 | Process tasks correctly |
| Trust Pipeline | 5 services | Graceful degradation |
| Verified Library | 28 | Validates safely |
| E2E Workflows | 3+ | Complete flows work |

---

## Release Checklist

Before releasing v1.0.0, ensure:

- [ ] All 164+ unit tests pass
- [ ] Version constraint parser handles semver, Python, Cargo
- [ ] Dependency resolver handles transitive dependencies
- [ ] Lockfile roundtrip preserves data
- [ ] All 8 registry adapters functional
- [ ] HAR agents executable and documented
- [ ] Verified library blocks malicious inputs
- [ ] Trust pipeline degrades gracefully
- [ ] E2E workflows complete successfully
- [ ] Documentation complete (README, ROADMAP, guides)
- [ ] Manual tests pass on fresh system
- [ ] Performance acceptable (<30s for complex graphs)
- [ ] No compilation warnings (except deprecations)

---

## Getting Help

- **Issues:** https://github.com/hyperpolymath/opm/issues
- **Documentation:** docs/
- **Examples:** examples/
- **State file:** STATE.scm (project status)
