<!--
SPDX-License-Identifier: CC-BY-SA-4.0
Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
# OPSM CLI Feature Comparison: nala / aptitude / apt

## Executive Summary

**Current Status (v1.0.0):** OPSM has basic CLI functionality but lacks advanced features of nala/aptitude.

**Target (v1.5.0):** Feature parity with nala/aptitude for production workflows.

---

## Feature Matrix

| Feature | apt | nala | aptitude | OPSM v1.0 | OPSM v1.5 (planned) |
|---------|-----|------|----------|----------|-------------------|
| **Basic Operations** |
| Install packages | ✅ | ✅ | ✅ | ✅ | ✅ |
| Remove packages | ✅ | ✅ | ✅ | ❌ | ✅ |
| Search packages | ✅ | ✅ | ✅ | ✅ | ✅ |
| Update index | ✅ | ✅ | ✅ | ❌ | ✅ |
| Upgrade packages | ✅ | ✅ | ✅ | ❌ | ✅ |
| Show package info | ✅ | ✅ | ✅ | ❌ | ✅ |
| List installed | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Advanced Features** |
| Dependency resolution | ✅ | ✅ | ✅✅ | ✅✅ | ✅✅ |
| Conflict detection | Basic | ✅ | ✅✅ | ✅ | ✅✅ |
| Why-installed (rdepends) | ✅ | ✅ | ✅✅ | ✅ | ✅ |
| Reverse deps | ✅ | ✅ | ✅ | ✅ | ✅ |
| Dry-run/simulate | ✅ | ✅ | ✅ | ❌ | ✅ |
| Autoremove | ✅ | ✅ | ✅ | ❌ | ✅ |
| Hold/unhold packages | ✅ | ✅ | ✅ | ❌ | ✅ |
| **Performance** |
| Parallel downloads | ❌ | ✅✅ | ❌ | ❌ | ✅ |
| Download caching | ✅ | ✅ | ✅ | ⚠️ | ✅ |
| Resume downloads | ❌ | ✅ | ❌ | ❌ | ✅ |
| **UI/UX** |
| Interactive TUI | ❌ | ❌ | ✅✅ | ❌ | ✅ |
| Progress bars | Basic | ✅✅ | ✅ | ❌ | ✅ |
| Color output | ✅ | ✅✅ | ✅ | ⚠️ | ✅ |
| Summary before action | ❌ | ✅ | ✅ | ❌ | ✅ |
| **History** |
| Command history | ❌ | ✅✅ | ✅ | ❌ | ✅ |
| Undo/rollback | ❌ | ✅ | ✅ | ❌ | ✅ |
| History search | ❌ | ✅ | ✅ | ❌ | ✅ |
| **Scripting** |
| JSON output | ❌ | ❌ | ❌ | ⚠️ | ✅ |
| Exit codes | ✅ | ✅ | ✅ | ✅ | ✅ |
| --quiet mode | ✅ | ✅ | ✅ | ❌ | ✅ |
| --yes (no prompts) | ✅ | ✅ | ✅ | ⚠️ | ✅ |
| **Trust/Security** |
| GPG signatures | ✅ | ✅ | ✅ | ⚠️ | ✅✅ |
| Trust pipeline | ❌ | ❌ | ❌ | ✅✅ | ✅✅ |
| SLSA attestations | ❌ | ❌ | ❌ | ❌ | ✅✅ |
| Provenance tracking | ❌ | ❌ | ❌ | ❌ | ✅✅ |
| CVE scanning | ❌ | ❌ | ❌ | ❌ | ✅✅ |
| **Multi-Language** |
| Single ecosystem | ✅ | ✅ | ✅ | ❌ | ❌ |
| Multi-ecosystem | ❌ | ❌ | ❌ | ✅✅ | ✅✅ |
| Cross-registry deps | ❌ | ❌ | ❌ | ✅✅ | ✅✅ |

**Legend:**
- ✅✅ = Best-in-class
- ✅ = Implemented
- ⚠️ = Partial/basic
- ❌ = Not implemented

---

## Detailed Comparison

### 1. Basic Operations

#### apt (Standard)
```bash
apt install package
apt remove package
apt search keyword
apt update
apt upgrade
apt show package
apt list --installed
```

#### nala (Modern APT Frontend)
```bash
nala install package      # Parallel downloads, better UI
nala remove package       # Interactive confirmation
nala search keyword       # Clean output, relevance sorting
nala update               # Parallel repository updates
nala upgrade              # Summary before action
nala show package         # Formatted output
nala list --installed     # Table format
```

#### aptitude (TUI APT Frontend)
```bash
aptitude install package  # Interactive dependency resolution
aptitude remove package   # Suggests alternatives
aptitude search keyword   # Powerful search syntax
aptitude update           # TUI shows progress
aptitude safe-upgrade     # Conflict resolution
aptitude show package     # Detailed information
# Interactive TUI: aptitude (no args)
```

#### OPSM v1.0 (Current)
```bash
opsm install package                    # ✅ Works
opsm search keyword                     # ✅ Works
# Missing: remove, update, upgrade, show, list
```

**GAP:** OPSM v1.0 only has install and search. Missing basic operations.

---

### 2. Advanced Dependency Resolution

#### aptitude (Best)
```bash
# Interactive conflict resolution
aptitude install package
# Shows all solutions, lets you choose
# Can hold/unhold packages on the fly
# Why-installed tracking
```

#### OPSM v1.0
```bash
opsm install package
# PubGrub resolver (excellent)
# Shows conflicts with actionable messages
# Missing: interactive resolution, hold/unhold
```

**OPSM Advantage:** Cross-registry resolution (npm + Hex + Crates + ...).
**aptitude Advantage:** Interactive TUI for conflict resolution.

---

### 3. Performance

#### nala (Best)
- **Parallel downloads**: 3x faster than apt
- **Resume interrupted downloads**
- **CDN-aware mirror selection**
- **Progress bars for each package**

#### OPSM v1.0
- **No parallel downloads** (sequential)
- **No resume support**
- **Basic tarball caching** (/tmp)

**GAP:** OPSM needs parallel downloads for production use (v1.1 feature).

---

### 4. Interactive TUI

#### aptitude (Best)
```
┌───────────────────────────────────────┐
│ aptitude 0.8.13                       │
├───────────────────────────────────────┤
│ ► Installed Packages                  │
│   ► Upgradable Packages               │
│   ► New Packages                      │
│   ► Search Results                    │
│   ...                                 │
└───────────────────────────────────────┘
```

**Features:**
- Keyboard navigation (hjkl, arrows)
- Search within TUI (/)
- Mark/unmark packages (m)
- View dependencies (d)
- Why-installed (w)
- Apply changes (g)

#### OPSM v1.0
- **No TUI** (CLI only)

**GAP:** OPSM needs TUI for interactive workflows (v1.5 feature).

---

### 5. History and Rollback

#### nala (Best)
```bash
nala history           # Show all install/remove operations
nala history undo 3    # Rollback operation #3
nala history redo 3    # Reapply operation #3
nala history clear     # Clear history
```

#### OPSM v1.0
- **No history tracking**
- **No undo/rollback**

**GAP:** Critical for production use (v1.1 feature).

---

### 6. Scripting and Automation

#### Best Practices (All Tools)
```bash
# Non-interactive
apt install -y package

# Quiet output
apt -qq install package

# Exit codes
if apt install package; then
  echo "Success"
fi

# JSON output (OPSM v1.5)
opsm search --json keyword | jq '.packages[].name'
```

#### OPSM v1.0
- ✅ Exit codes work
- ❌ No --yes flag
- ❌ No --quiet flag
- ⚠️ Basic JSON (internal only)

**GAP:** Missing flags for CI/CD pipelines (v1.1 feature).

---

## What OPSM Adds Beyond nala/aptitude

### 1. Multi-Language Support ✅✅
```bash
# Install from any ecosystem
opsm install express --registry npm
opsm install phoenix --registry hex
opsm install tokio --registry crates
opsm install requests --registry pypi

# Cross-registry dependencies
# npm package depending on Rust crate
opsm install my-app  # Resolves across all registries
```

**Unique to OPSM:** No other tool does cross-language resolution.

### 2. Trust Pipeline ✅✅
```bash
opsm publish ./my-package
# Automatically:
# 1. palimpsest: Check licenses
# 2. oikos: Score sustainability (8 dimensions)
# 3. checky-monkey: Verify signatures
```

**Unique to OPSM:** multi-microservice verification before publish.

### 3. Formal Verification (v1.5) ✅✅
```elixir
# Mathematically proven security
Verified.Url.validate(url)  # Impossible to have SSRF
Verified.Json.parse(json)   # Impossible to have DoS
```

**Unique to OPSM:** Idris2 proven library with correctness proofs.

### 4. HAR Discovery ✅✅
```bash
# Find packages in obscure languages
opsm install idris2-json  # No registry? HAR agents search!
# - GitHub API search
# - Web scraping
# - Mirror finding
```

**Unique to OPSM:** Human-assisted discovery for unmaintained packages.

### 5. Federation ✅✅
```bash
# IPFS storage (v2.0)
# Radicle sync (v2.0)
# Event propagation to mirrors
# No single point of failure
```

**Unique to OPSM:** Decentralized, censorship-resistant.

---

## Roadmap: Achieving Parity

### v1.1.0 (Q1 2026) - Production Essentials

```bash
# NEW COMMANDS
opsm remove package          # Uninstall packages
opsm update                  # Update registry indexes
opsm upgrade                 # Upgrade all packages
opsm show package            # Detailed package info
opsm autoremove              # Remove unused dependencies

# NEW FLAGS
opsm install --yes package   # No prompts (CI/CD)
opsm install --quiet         # Minimal output
opsm install --dry-run       # Simulate, don't install
opsm install --parallel=5    # Parallel downloads
opsm search --json keyword   # JSON output

# HISTORY
opsm history                 # Show all operations
opsm history undo 3          # Rollback operation #3
opsm history list            # List all ops with IDs

# SCRIPTING
opsm list --json             # JSON output for scripting
opsm depends --format=tree   # ASCII tree visualization
opsm status                  # System health check
```

**Implementation:**
- 2 weeks: Remove, update, upgrade, show, autoremove
- 1 week: Parallel downloads (Task.async_stream)
- 1 week: History tracking (SQLite database)
- 1 week: JSON output, flags

### v1.5.0 (Q2 2026) - Interactive TUI

```bash
# LAUNCH TUI
opsm tui                     # Interactive mode

# TUI FEATURES
# - Keyboard navigation (hjkl, arrows)
# - Search within TUI (/)
# - Mark packages for install/remove
# - View dependencies (tree view)
# - Why-installed tracking
# - Apply changes (batch operations)
# - Color-coded status (installed, upgradable, new)
```

**Implementation:**
- Library: ratatui (Rust TUI library)
- Language: Rust (better TUI support than Elixir)
- Integration: Call Elixir core via IPC
- 3 weeks: TUI skeleton + navigation
- 2 weeks: Package browser + search
- 1 week: Dependency visualization
- 1 week: Batch operations

**Alternative:** Use Elixir's Livebook for web-based TUI.

---

## Workflow Examples

### Scenario 1: CI/CD Pipeline
```bash
# apt/nala style
apt update -qq
apt install -y build-essential

# OPSM v1.1 equivalent
opsm update --quiet
opsm install --yes gcc make --registry system
opsm install --yes express --registry npm
opsm install --yes tokio --registry crates
```

### Scenario 2: Interactive Package Management
```bash
# aptitude style
aptitude                  # Launch TUI
# Navigate, mark packages, apply

# OPSM v1.5 equivalent
opsm tui                   # Launch TUI
# Same workflow
```

### Scenario 3: Dependency Investigation
```bash
# aptitude style
aptitude why package      # Why is this installed?
aptitude rdepends package # What depends on this?

# OPSM v1.0 (already works!)
opsm rdepends package      # ✅ Implemented
opsm depends package       # ✅ Implemented
```

### Scenario 4: History Rollback
```bash
# nala style
nala history
nala history undo 3

# OPSM v1.1 equivalent
opsm history
opsm history undo 3
```

---

## Summary

### Current Gaps (v1.0)

**Critical (v1.1):**
- ❌ Remove packages
- ❌ Update/upgrade
- ❌ Parallel downloads
- ❌ History/undo
- ❌ Flags (--yes, --quiet, --dry-run)
- ❌ JSON output

**Important (v1.5):**
- ❌ Interactive TUI
- ❌ Hold/unhold packages
- ❌ Autoremove
- ❌ Detailed show command

### OPSM Unique Strengths

✅✅ **Multi-language support** (8 ecosystems, 100+ planned)
✅✅ **Cross-registry resolution** (npm + Hex + Crates + ...)
✅✅ **Trust pipeline** (5-microservice verification)
✅✅ **Formal verification** (Idris2 proven library, v1.5)
✅✅ **HAR discovery** (obscure languages)
✅✅ **Federation** (IPFS, Radicle, distributed)

### Recommendation

**For v1.1:** Focus on production essentials (remove, update, parallel, history, flags)
**For v1.5:** Add TUI for interactive workflows
**For v2.0:** Maintain parity while scaling to 100+ languages

**Timeline:**
- v1.1 (6 weeks): nala-level usability
- v1.5 (8 weeks): aptitude-level interactivity
- v2.0 (12 weeks): Universal + intelligent

**Effort:**
- v1.1 features: 5 weeks
- v1.5 TUI: 7 weeks
- Total to parity: 12 weeks (3 months)

---

## Implementation Priority

### P0 (Must Have - v1.1)
1. Remove packages
2. Parallel downloads
3. History tracking
4. --yes, --quiet, --dry-run flags
5. JSON output

### P1 (Should Have - v1.1)
1. Update/upgrade commands
2. Show command (detailed info)
3. Autoremove
4. Progress bars

### P2 (Nice to Have - v1.5)
1. Interactive TUI
2. Hold/unhold packages
3. Conflict resolution UI
4. Why-installed visualization

### P3 (Future - v2.0)
1. CDN-aware mirror selection
2. Resume interrupted downloads
3. Advanced search syntax (aptitude-style)
4. Package recommendations

---

## Conclusion

**OPSM v1.0:** Strong foundation (resolver, trust, multi-language) but basic CLI.

**OPSM v1.1:** Achieve nala-level usability (3-5 weeks of work).

**OPSM v1.5:** Achieve aptitude-level interactivity (7-8 weeks of work).

**Total effort:** ~12 weeks to full feature parity with best-in-class tools (nala + aptitude).

**Unique value:** OPSM remains the **only** multi-language, trust-verified, federated package manager.
