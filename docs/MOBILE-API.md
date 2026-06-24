<!--
SPDX-License-Identifier: CC-BY-SA-4.0
Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
# OPSM Mobile API Documentation

**Version:** 1.0.0
**Status:** Implemented (2026-01-23)
**Port:** 4051 (HTTP)

## Overview

The OPSM Mobile API provides HTTP endpoints for the Tauri 2.0 mobile wrapper (iOS/Android). It enables mobile clients to perform package management operations by communicating with the Elixir backend via HTTP.

## Architecture

```
┌─────────────────────────────────────────────┐
│  Mobile App (iOS/Android)                   │
│  ┌─────────────────────────────────────┐   │
│  │  ReScript UI (rescript-tea)         │   │
│  │  ↓                                   │   │
│  │  Rust Tauri Commands                │   │
│  │  ↓                                   │   │
│  │  HTTP Client (reqwest)              │   │
│  └─────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
                   ↓ HTTP
┌─────────────────────────────────────────────┐
│  Phoenix Elixir Backend (OPSM)               │
│  ┌─────────────────────────────────────┐   │
│  │  API Router (port 4051)             │   │
│  │  ↓                                   │   │
│  │  PackageController                  │   │
│  │  ↓                                   │   │
│  │  OPSM Core (Resolver, Installer, etc)│   │
│  └─────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
```

## HTTP Endpoints

### 1. Health Check

**GET** `/api/health`

Returns API health status.

**Response:**
```json
{
  "status": "healthy",
  "version": "1.0.0"
}
```

---

### 2. Install Package

**POST** `/api/packages/install`

Install a package from a specific registry.

**Request Body:**
```json
{
  "package": "express",
  "registry": "npm",
  "version": "4.18.2",    // Optional, defaults to "latest"
  "scope": "user",        // Optional: "user" or "system", defaults to "user"
  "dry_run": false        // Optional, defaults to false
}
```

**Response (Success):**
```json
{
  "status": "success",
  "result": {
    "package": "express",
    "version": "4.18.2",
    "registry": "npm",
    "scope": "user",
    "status": "installed"
  }
}
```

**Response (Error):**
```json
{
  "error": "Package not found in npm registry"
}
```

**Status Codes:**
- `200 OK` - Installation successful
- `400 Bad Request` - Invalid parameters or installation failed

---

### 3. Search Packages

**GET** `/api/packages/search?q=express&registry=npm`

Search for packages in one or all registries.

**Query Parameters:**
- `q` (required): Search query string
- `registry` (optional): Registry to search (npm, hex, crates, pypi, nimble, idris2). If omitted, searches all registries.

**Response:**
```json
{
  "results": [
    {
      "name": "express",
      "version": "4.18.2",
      "description": "Fast, unopinionated, minimalist web framework",
      "registry": "npm"
    },
    {
      "name": "express-validator",
      "version": "7.0.1",
      "description": "Express middleware for validator",
      "registry": "npm"
    }
  ]
}
```

**Status Codes:**
- `200 OK` - Search successful (empty array if no results)
- `400 Bad Request` - Invalid query

---

### 4. Get Package Info

**GET** `/api/packages/:name/:version?registry=npm`

Get detailed information about a specific package.

**Path Parameters:**
- `name` (required): Package name
- `version` (required): Package version or "latest"

**Query Parameters:**
- `registry` (required): Registry name

**Example:** `/api/packages/express/4.18.2?registry=npm`

**Response:**
```json
{
  "name": "express",
  "version": "4.18.2",
  "description": "Fast, unopinionated, minimalist web framework",
  "license": "MIT",
  "repository": "https://github.com/expressjs/express",
  "dependencies": {
    "accepts": "~1.3.8",
    "body-parser": "1.20.1"
  },
  "keywords": ["express", "framework", "web", "rest", "restful", "router", "app", "api"]
}
```

**Status Codes:**
- `200 OK` - Package found
- `404 Not Found` - Package not found
- `400 Bad Request` - Invalid parameters

---

### 5. Audit Lockfile

**POST** `/api/lockfile/audit`

Audit a lockfile for security vulnerabilities and sustainability.

**Request Body:**
```json
{
  "lockfile_path": "./opsm.lock",                        // Optional, defaults to "./opsm.lock"
  "repository_url": "https://github.com/user/repo"      // Optional, for sustainability analysis
}
```

**Response:**
```json
{
  "lockfile": {
    "version": "1",
    "packages": 42,
    "generated_at": "2026-01-23T12:00:00Z"
  },
  "audit": {
    // Sustainability analysis from oikos service
  },
  "vulnerabilities": [],
  "recommendations": []
}
```

**Status Codes:**
- `200 OK` - Audit completed
- `400 Bad Request` - Lockfile not found or invalid

---

### 6. List Installed Packages

**GET** `/api/packages/installed`

List all packages installed via OPSM.

**Response:**
```json
{
  "packages": [
    {
      "name": "express",
      "version": "4.18.2",
      "registry": "npm",
      "installed_at": "2026-01-23T12:00:00Z",
      "path": "/home/user/.local/share/opsm/packages/npm/express/4.18.2"
    },
    {
      "name": "tokio",
      "version": "1.35.1",
      "registry": "crates",
      "installed_at": "2026-01-23T12:05:00Z",
      "path": "/home/user/.local/share/opsm/packages/crates/tokio/1.35.1"
    }
  ]
}
```

**Status Codes:**
- `200 OK` - List retrieved (empty array if no packages)
- `400 Bad Request` - Error reading installed packages

---

## Configuration

The API server is configured via environment variables or `config/config.exs`:

```elixir
config :opsm,
  api_port: 4051,                              # HTTP port for mobile API
  registry_port: 4050                          # HTTP port for registry gateway (separate service)
```

## Testing

### Manual Testing

Start a lightweight Plug host for the mobile API (recommended: keep it separate from core):
```bash
cd opsm_mobile/api
# Use your preferred Plug/Phoenix host app to mount Opsm.Api.Router
```

Test endpoints with curl:
```bash
# Health check
curl http://localhost:4051/api/health

# Search packages
curl "http://localhost:4051/api/packages/search?q=express&registry=npm"

# Get package info
curl "http://localhost:4051/api/packages/express/latest?registry=npm"

# List installed
curl http://localhost:4051/api/packages/installed

# Install package
curl -X POST http://localhost:4051/api/packages/install \
  -H "Content-Type: application/json" \
  -d '{"package": "express", "registry": "npm", "version": "4.18.2"}'

# Audit lockfile
curl -X POST http://localhost:4051/api/lockfile/audit \
  -H "Content-Type: application/json" \
  -d '{"lockfile_path": "./opsm.lock", "repository_url": "https://github.com/user/repo"}'
```

### Integration with Tauri Commands

The Rust Tauri commands (in `mobile/src-tauri/src/commands.rs`) will use `reqwest` to make HTTP requests to these endpoints.

Example Rust command:
```rust
#[tauri::command]
async fn search_packages(query: String, registry: Option<String>) -> Result<Vec<PackageResult>, String> {
    let url = format!("http://localhost:4051/api/packages/search?q={}", query);
    let url = if let Some(reg) = registry {
        format!("{}&registry={}", url, reg)
    } else {
        url
    };

    let response = reqwest::get(&url)
        .await
        .map_err(|e| e.to_string())?
        .json::<SearchResponse>()
        .await
        .map_err(|e| e.to_string())?;

    Ok(response.results)
}
```

## Implementation Files

### Core API Files

- **Router:** `opsm_mobile/api/router.ex`
  - HTTP endpoint routing
  - Request/response handling
  - JSON parsing/encoding

- **Controller:** `opsm_mobile/api/package_controller.ex`
  - Business logic for each endpoint
  - Calls into OPSM core modules
  - Error handling and formatting

- **Host App:** (separate Plug/Phoenix host)
  - Mounts `Opsm.Api.Router`
  - Starts API server on port 4051

### Underlying OPSM Modules

The API controller delegates to these existing modules:

- **Installer:** `lib/opsm/package/installer.ex`
  - `install/3` - Install packages
  - `list_installed/1` - List installed packages
  - `remove/2` - Uninstall packages

- **Registry:** `lib/opsm/registries/registry.ex`
  - `search/3` - Search single registry
  - `search_all/2` - Search all registries
  - `fetch/2` - Get package info

- **Wiring:** `lib/opsm/wiring.ex`
  - `run_audit/2` - Run sustainability analysis
  - Trust pipeline orchestration

- **Lockfile:** `lib/opsm/lockfile.ex`
  - `read/1` - Parse lockfile
  - `write/2` - Generate lockfile
  - Dependency tracking

## Security Considerations

### Input Validation

All inputs are validated via `Opsm.Validation`:
- Package names checked for invalid characters
- Versions validated against semver constraints
- Registry names whitelisted

### URL Safety

URLs are validated via `Opsm.Verified.Url` (v1.5 will use Idris2 NIFs for formal verification):
- Blocks localhost and private IP addresses
- Prevents SSRF attacks
- Validates URL structure

### JSON Parsing

JSON parsing uses `Opsm.Verified.Json` with limits:
- Maximum depth: 20 levels
- Maximum size: 10MB
- Prevents DoS via deeply nested JSON

### Trust Pipeline

Package installations go through 5-microservice verification:
1. **claim-forge** - Generate attestation
2. **checky-monkey** - Verify signatures
3. **palimpsest-license** - Check licenses
4. **oikos** - Score sustainability
5. **cicd-hyper-a** - Publish with provenance

## Future Enhancements (v1.1+)

### v1.1 (Q1 2026)

- [ ] Parallel downloads for faster installation
- [ ] History tracking (operation log)
- [ ] Undo/rollback operations
- [ ] Batch install endpoint
- [ ] Package update notifications

### v1.5 (Q2 2026)

- [ ] WebSocket support for real-time progress
- [ ] Proven library (Idris2 NIFs) for security
- [ ] SLSA attestation validation
- [ ] Interactive TUI via API

### v2.0 (Q3 2026)

- [ ] GraphQL API alongside REST
- [ ] Streaming responses for large lists
- [ ] Rate limiting and authentication
- [ ] Multi-region federation support

## Contributing

To add new endpoints:

1. Add route in `opsm_mobile/api/router.ex`
2. Implement handler in `opsm_mobile/api/package_controller.ex`
3. Add tests in `test/opsm/api/`
4. Update this documentation

## License

PMPL-1.0 (Polymath Public Meta-License)
