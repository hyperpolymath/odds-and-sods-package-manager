<!--
SPDX-License-Identifier: CC-BY-SA-4.0
Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
# SPDX-License-Identifier: CC-BY-SA-4.0
# Registry API Changelog and Monitoring

Tracks API version targets, upcoming deprecations, and monitoring priorities
for OPSM's 103 registry adapters.

Author: Jonathan D.A. Jewell
Last updated: 2026-03-10

## Registry Adapter Count

OPSM has **103 registry adapters** in `opsm_ex/lib/opsm/registries/`.

## Major Registry API Versions

| Registry | Adapter File | API Version / Endpoint | Notes |
|----------|-------------|----------------------|-------|
| **npm** | `npm.ex` | `registry.npmjs.org` (v1 packument + v1 search) | Uses `/-/v1/search` endpoint |
| **PyPI** | `pypi.ex` | `pypi.org/pypi/{name}/json` (JSON API) | XML-RPC search deprecated; search is non-functional |
| **crates.io** | `crates.ex` | `crates.io/api/v1` | Requires User-Agent header |
| **Hex.pm** | `hex.ex` | `hex.pm/api` (v1) + `repo.hex.pm` (tarballs) | Fetches release-specific deps |
| **RubyGems** | `rubygems.ex` | `rubygems.org/api/v1` | Stable |
| **Docker Hub** | `docker_hub.ex` | `registry.hub.docker.com/v2` | Token auth required |
| **NuGet** | `nuget.ex` | `api.nuget.org/v3` | Service index discovery |
| **Maven Central** | `maven.ex` | `search.maven.org/solrsearch` | Solr-based |
| **Go Modules** | `go_modules.ex` | `proxy.golang.org` | Module proxy protocol |
| **Packagist** | `packagist.ex` | `packagist.org/p2` | v2 metadata endpoint |
| **pub.dev** | `pub_dev.ex` | `pub.dev/api` | Dart/Flutter |
| **CocoaPods** | `cocoapods.ex` | `cdn.cocoapods.org` | CDN-based |
| **JSR** | `jsr.ex` | `jsr.io/api` | Deno/JS registry |
| **Homebrew** | `homebrew.ex` | `formulae.brew.sh/api` | JSON API |

## Known API Deprecations and Changes

### CRITICAL (action required)

| Registry | Deprecation | Impact | Deadline |
|----------|-------------|--------|----------|
| **PyPI** | XML-RPC search (`search()`) fully removed | `Opsm.Registries.Pypi.search/2` already returns placeholder; no functional search | Already deprecated |
| **Docker Hub** | Rate limiting tightened (100 pulls/6h anonymous) | May need authenticated pulls for high-volume resolution | Ongoing |

### WARNING (monitor closely)

| Registry | Change | Impact | Timeline |
|----------|--------|--------|----------|
| **npm** | Registry v2 discussions | Packument format may change; OPSM uses v1 packument | No firm date |
| **crates.io** | Sparse index as default | `crates.ex` uses HTTP API (not git index), so minimal impact | Already default in cargo |
| **NuGet** | v3 service index evolution | New resource types may be added | Rolling |
| **Maven Central** | Central Portal replacing OSSRH | Publishing changes; read API stable | 2025+ rollout |
| **Homebrew** | API versioning | `formulae.brew.sh` may version endpoints | No firm date |
| **Go Modules** | GONOSUMCHECK patterns | Checksum database changes | Ongoing |

### LOW RISK (stable)

- **Hex.pm**: Stable API, well-documented
- **RubyGems**: v1 API stable for years
- **CPAN**: MetaCPAN API stable
- **Hackage**: Stable API
- **Elm packages**: Simple Git-based registry, unlikely to change
- **pub.dev**: Google-maintained, stable

## Rate Limiting Summary

| Registry | Limit | Auth Helps? |
|----------|-------|-------------|
| npm | No published limit (fair use) | N/A |
| PyPI | ~100 req/min (JSON API) | No |
| crates.io | 1 req/sec (requires User-Agent) | No |
| Hex.pm | No published limit | N/A |
| Docker Hub | 100 pulls/6h (anon), 200 (auth) | Yes |
| RubyGems | 10 req/sec | API key for higher |
| NuGet | No published limit | N/A |
| Go Modules | No published limit | N/A |
| GitHub Packages | 5000 req/hr (auth) | Required |
| GitLab Packages | Varies by instance | Required |

## Monitoring Checklist

### Tier 1 — Monitor Weekly (high traffic, critical)

These are the most-used registries and the ones most likely to have API changes:

- [ ] npm (`npm.ex`) — Check for registry v2 announcements
- [ ] PyPI (`pypi.ex`) — Monitor for new search API replacement
- [ ] crates.io (`crates.ex`) — Rate limit / sparse index changes
- [ ] Hex.pm (`hex.ex`) — API changes
- [ ] Docker Hub (`docker_hub.ex`) — Rate limiting changes
- [ ] RubyGems (`rubygems.ex`) — API deprecations
- [ ] NuGet (`nuget.ex`) — v3 resource changes
- [ ] Maven Central (`maven.ex`) — Central Portal migration
- [ ] Go Modules (`go_modules.ex`) — Proxy protocol changes
- [ ] JSR (`jsr.ex`) — New registry, API may evolve rapidly

### Tier 2 — Monitor Monthly (moderate traffic)

- [ ] Packagist, pub.dev, CocoaPods, Homebrew, Homebrew Cask
- [ ] Conda, CRAN, Hackage, Stackage
- [ ] Helm, Terraform, Pulumi
- [ ] VS Code Marketplace, JetBrains

### Tier 3 — Monitor Quarterly (low traffic, stable)

- [ ] All Linux distribution registries (apt, rpm, alpine, AUR, etc.)
- [ ] Niche language registries (Nim, Raku, Chicken, etc.)
- [ ] OPSM-specific registries (agentic, eclexia, error_lang, etc.)
- [ ] Archive/legacy registries (Bower, PEAR, PECL)

## Adapter Architecture Notes

All adapters follow a consistent pattern:
- `fetch_package(name, version)` — returns `{:ok, %ResolvedPackage{}}` or `{:error, reason}`
- `search(query, opts)` — returns `{:ok, [results]}` or `{:error, reason}`
- `exists?(name)` — returns boolean
- `versions(name)` — returns `{:ok, [version_strings]}`
- `tarball_url(name, version)` — returns `{:ok, url}`

HTTP calls go through `Opsm.Verified.Http` (aliased as `VerifiedHttp`) which
handles TLS verification, timeouts, and response parsing.
