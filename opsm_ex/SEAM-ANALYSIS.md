<!--
SPDX-License-Identifier: MPL-2.0
Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
# OPSM Seam Analysis Report

## Executive Summary

Analysis of 21 Elixir modules (~5,200 lines) across five quality dimensions.

---

## 1. DEPENDABILITY (Reliability, Error Handling, Fault Tolerance)

### Critical Seams Identified

| ID | Location | Issue | Severity |
|----|----------|-------|----------|
| D1 | `installer.ex:101` | Unsafe pattern match `{:ok, trust_result} = Pipeline.verify(package)` crashes on error | HIGH |
| D2 | `registry.ex:75,98,117` | `Task.await_many` with no error handling - crashes if any task fails | HIGH |
| D3 | `downloader.ex:117` | File stream can leave partial files on network error | MEDIUM |
| D4 | `cli.ex` | `System.halt()` called directly - no cleanup | MEDIUM |
| D5 | `native.ex:161` | `System.cmd` with streaming can hang indefinitely | MEDIUM |
| D6 | `installer.ex:165` | `File.mkdir_p!` crashes instead of returning error | LOW |
| D7 | `config.ex:96` | TOML parse errors not user-friendly | LOW |

### Recommendations

- D1: Use `case` instead of unsafe `=` pattern match
- D2: Wrap tasks in `Task.Supervisor` with timeout handling
- D3: Download to temp file, rename on success
- D4: Use proper shutdown with cleanup hooks
- D5: Add configurable timeout to native commands
- D6: Use `File.mkdir_p` and handle errors gracefully
- D7: Wrap TOML errors with context

---

## 2. SECURITY (Input Validation, Safe Operations, Trust Verification)

### Critical Seams Identified

| ID | Location | Issue | Severity |
|----|----------|-------|----------|
| S1 | `installer.ex:178-232` | Shell commands built with user input (path injection) | HIGH |
| S2 | `native.ex` | Package names passed directly to shell commands | HIGH |
| S3 | `npm.ex:17-19` | URL constructed with `URI.encode` only - incomplete sanitization | MEDIUM |
| S4 | `downloader.ex` | No HTTPS certificate validation options | MEDIUM |
| S5 | `installer.ex` | Symlink creation without checking for existing files (symlink attacks) | MEDIUM |
| S6 | `config.ex` | Token stored in config file (plaintext) | LOW |
| S7 | `registry.ex:151` | `String.to_existing_atom` prevents atom table exhaustion (GOOD) | OK |

### Recommendations

- S1/S2: Validate package names against allowlist pattern `^[a-zA-Z0-9_@/-]+$`
- S3: Add additional URL validation, reject file:// and other dangerous schemes
- S4: Add option for CA certificate pinning
- S5: Check target doesn't exist, use `File.ln_s` with care
- S6: Support keyring/secret-store integration

---

## 3. USABILITY (CLI UX, Error Messages, Documentation)

### Critical Seams Identified

| ID | Location | Issue | Severity |
|----|----------|-------|----------|
| U1 | `cli.ex` | Error messages inconsistent - some have context, some don't | MEDIUM |
| U2 | `cli.ex:770` | Generic "Error: reason" without actionable guidance | MEDIUM |
| U3 | All modules | No progress indicators for long operations | MEDIUM |
| U4 | `installer.ex` | Silent failures in bin linking (user doesn't know why) | MEDIUM |
| U5 | `native.ex:83-89` | Hex install shows instructions but doesn't execute | LOW |
| U6 | Help text | Missing examples for common workflows | LOW |
| U7 | `downloader.ex:122` | File size shown but no ETA or progress bar | LOW |

### Recommendations

- U1/U2: Standardize error format: `Error: {what} - {why} - {how to fix}`
- U3: Add `IO.write` based progress for downloads
- U4: Log verbose output when `--verbose` flag set
- U5: Add `--execute` flag for hex to actually run mix deps.get
- U6: Add common workflow examples to help
- U7: Add download progress bar

---

## 4. FUNCTIONALITY (Feature Completeness, Edge Cases)

### Critical Seams Identified

| ID | Location | Issue | Severity |
|----|----------|-------|----------|
| F1 | `installer.ex` | No rollback on partial install failure | HIGH |
| F2 | `registry.ex` | No caching - every request hits network | MEDIUM |
| F3 | `downloader.ex:147` | `nil` checksum silently skipped - should warn | MEDIUM |
| F4 | `cli.ex` | `reinstall`, `pin`, `unpin`, `history`, `clean` not implemented | MEDIUM |
| F5 | `installer.ex` | No lock file support for reproducible installs | MEDIUM |
| F6 | `native.ex` | No support for gem, nuget, maven, pub, go native install | LOW |
| F7 | `federation.ex` | `discover` function returns empty alternatives | LOW |

### Recommendations

- F1: Implement transaction-based install with rollback
- F2: Add in-memory cache with TTL for registry responses
- F3: Warn when checksum missing, add `--require-checksum` flag
- F4: Implement remaining commands
- F5: Add opsm.lock file generation and reading
- F6: Add remaining native toolchain support
- F7: Implement alternative package discovery

---

## 5. PERFORMANCE (Efficiency, Parallelism, Caching)

### Critical Seams Identified

| ID | Location | Issue | Severity |
|----|----------|-------|----------|
| P1 | `registry.ex` | No response caching - duplicate requests | HIGH |
| P2 | `downloader.ex` | Downloads entire file before checksum verification | MEDIUM |
| P3 | `installer.ex` | Sequential unpack operations, could parallelize | MEDIUM |
| P4 | `trust/pipeline.ex:58` | 30 second timeout too long for health checks | LOW |
| P5 | `http.ex` | Connection pooling not configured | LOW |
| P6 | `npm.ex:75-86` | Fetches all versions when only checking existence | LOW |

### Recommendations

- P1: Add ETS-based cache with configurable TTL
- P2: Stream checksum calculation during download
- P3: Parallelize independent unpack operations
- P4: Reduce health check timeout to 5 seconds
- P5: Configure Req connection pooling
- P6: Use HEAD request for existence check (already done for npm.exists?)

---

## Priority Matrix

| Priority | Items | Impact |
|----------|-------|--------|
| P0 (Critical) | D1, D2, S1, S2 | Crashes, security vulnerabilities |
| P1 (High) | F1, P1, U1, U2 | Major UX/functionality gaps |
| P2 (Medium) | D3, S3, S5, F2, F3, U3, U4 | Quality improvements |
| P3 (Low) | Everything else | Polish |

---

## Implementation Plan

### Phase 1: Critical Fixes (D1, D2, S1, S2)
1. Fix unsafe pattern match in installer
2. Add Task.Supervisor for parallel registry calls
3. Add package name validation
4. Sanitize shell command inputs

### Phase 2: High Priority (F1, P1, U1, U2)
1. Add transaction rollback for installs
2. Implement ETS cache for registry
3. Standardize error messages
4. Add actionable error guidance

### Phase 3: Medium Priority
1. Download to temp file
2. Add progress indicators
3. Warn on missing checksums
4. Fix symlink attack vector

### Phase 4: Polish
1. Implement remaining commands
2. Add lock file support
3. Connection pooling
4. Documentation improvements
