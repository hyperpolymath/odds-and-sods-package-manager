<!--
SPDX-License-Identifier: CC-BY-SA-4.0
Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
# Svalinn - Container Vulnerability Scanner

**Svalinn** is OPSM's vulnerability scanning service, integrating industry-standard scanners (Trivy, Grype) into a unified REST API.

## Features

- **Multi-Scanner Support**: Integrates Trivy and Grype
- **Unified API**: Single endpoint for all scanners
- **Severity Filtering**: Filter results by severity threshold
- **Deduplication**: Automatic deduplication of findings across scanners
- **Async Scanning**: Non-blocking concurrent scans

## Quick Start

### Prerequisites

Install at least one scanner:

```bash
# Trivy (recommended)
curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin

# Grype (optional)
curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh -s -- -b /usr/local/bin
```

### Running Locally

```bash
cargo run --release
```

### Running in Container

```bash
# Build
podman build -t svalinn:latest -f Containerfile .

# Run
podman run -p 8085:8085 svalinn:latest
```

## API Reference

### Health Check

```bash
GET /health
```

**Response:**
```json
{
  "status": "healthy",
  "version": "1.0.0",
  "scanners": {
    "trivy": true,
    "grype": false
  }
}
```

### Scan Image

```bash
POST /scan
Content-Type: application/json

{
  "image": "alpine:3.19",
  "scanners": ["trivy"],
  "severity_threshold": "HIGH"
}
```

**Request Fields:**
- `image` (required): Container image reference (e.g., `alpine:3.19`, `ghcr.io/org/image:tag`)
- `scanners` (optional): List of scanners to use. Default: all available
  - Valid values: `["trivy"]`, `["grype"]`, `["trivy", "grype"]`
- `severity_threshold` (optional): Minimum severity to report
  - Valid values: `"LOW"`, `"MEDIUM"`, `"HIGH"`, `"CRITICAL"`

**Response:**
```json
{
  "image": "alpine:3.19",
  "scan_time": "2026-02-05T06:53:33.399996601+00:00",
  "scanners_used": ["trivy"],
  "vulnerabilities": [
    {
      "id": "CVE-2024-1234",
      "package": "libssl",
      "version": "3.1.0",
      "severity": "HIGH",
      "fixed_version": "3.1.1",
      "description": "Buffer overflow in SSL handshake",
      "scanner": "trivy"
    }
  ],
  "summary": {
    "total": 15,
    "critical": 2,
    "high": 5,
    "medium": 6,
    "low": 2,
    "unknown": 0
  }
}
```

## Examples

### Basic Scan

```bash
curl -X POST http://localhost:8085/scan \
  -H "Content-Type: application/json" \
  -d '{"image": "alpine:3.19"}'
```

### Scan with Severity Threshold

Only report HIGH and CRITICAL vulnerabilities:

```bash
curl -X POST http://localhost:8085/scan \
  -H "Content-Type: application/json" \
  -d '{
    "image": "nginx:1.25",
    "severity_threshold": "HIGH"
  }'
```

### Specify Scanners

Use only Trivy:

```bash
curl -X POST http://localhost:8085/scan \
  -H "Content-Type: application/json" \
  -d '{
    "image": "postgres:16",
    "scanners": ["trivy"]
  }'
```

### Get Summary Only

```bash
curl -s -X POST http://localhost:8085/scan \
  -H "Content-Type: application/json" \
  -d '{"image": "redis:7"}' | jq '.summary'
```

## Configuration

Environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `SVALINN_PORT` | `8085` | HTTP server port |
| `RUST_LOG` | `info` | Log level (`debug`, `info`, `warn`, `error`) |

## Integration with OPSM

Svalinn is automatically integrated with OPSM's container workflow:

```bash
# Scan during container build pipeline
opsm container scan myimage:latest

# Integrated with trust pipeline
opsm container pipeline ./Containerfile --registry ghcr.io/org
```

## Architecture

```
┌─────────────────┐
│   REST API      │
│   (Axum)        │
└────────┬────────┘
         │
    ┌────┴────┐
    │         │
┌───▼───┐ ┌──▼────┐
│ Trivy │ │ Grype │
└───────┘ └───────┘
```

1. **Request**: Client sends image reference
2. **Dispatch**: Svalinn invokes configured scanners
3. **Parse**: Results parsed into unified format
4. **Dedupe**: Vulnerabilities deduplicated by CVE ID
5. **Filter**: Severity threshold applied
6. **Response**: Unified JSON response returned

## Scanner Comparison

| Feature | Trivy | Grype |
|---------|-------|-------|
| OS Packages | ✓ | ✓ |
| Language Dependencies | ✓ | ✓ |
| SBOM Support | ✓ | ✓ |
| Offline Mode | ✓ | ✓ |
| License Scanning | ✓ | ✗ |
| Secret Detection | ✓ | ✗ |

## License

MPL-2.0

## Author

Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
