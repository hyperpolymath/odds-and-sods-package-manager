# Vordr - Runtime Verification Service

**Vordr** is OPSM's runtime verification and policy enforcement service, validating container configurations against security best practices using OPA policies and built-in rules.

## Features

- **OPA Integration**: Custom Rego policy support with Open Policy Agent
- **Built-in Policy Engine**: Works without OPA for common security rules
- **Severity Levels**: CRITICAL, HIGH, MEDIUM, LOW, INFO
- **Comprehensive Checks**: Privileged mode, capabilities, volumes, resources
- **REST API**: Simple HTTP API for policy verification

## Quick Start

### Running Locally

```bash
# Without OPA (built-in engine)
cargo run --release

# With OPA (custom policies)
export VORDR_POLICY_DIR=/path/to/policies
cargo run --release
```

### Running in Container

```bash
# Build
podman build -t vordr:latest -f Containerfile .

# Run with policy directory
podman run -p 8087:8087 -v ./policies:/policies vordr:latest
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
  "opa_available": false,
  "opa_version": null,
  "policies_loaded": 0
}
```

### Verify Container

```bash
POST /verify
Content-Type: application/json

{
  "image": "nginx:1.25",
  "config": {
    "privileged": false,
    "user": "1000",
    "capabilities": [],
    "read_only_root": true,
    "no_new_privileges": true,
    "resources": {
      "memory_limit": "512Mi",
      "cpu_limit": "1000m"
    },
    "volumes": [],
    "security_context": {
      "run_as_non_root": true,
      "run_as_user": 1000
    }
  }
}
```

**Response:**
```json
{
  "allowed": true,
  "violations": [],
  "evaluation_time": "2026-02-05T07:00:00Z",
  "policy_used": "builtin"
}
```

### List Policies

```bash
GET /policies
```

**Response:**
```json
{
  "policies": [
    {
      "name": "default",
      "path": "/policies/default.rego",
      "description": null
    }
  ]
}
```

## Built-in Security Rules

Vordr's built-in policy engine enforces these rules:

| Rule | Severity | Description |
|------|----------|-------------|
| **no_privileged** | CRITICAL | Privileged containers not allowed |
| **non_root_user** | HIGH | Must run as non-root user |
| **no_dangerous_caps** | HIGH | No SYS_ADMIN, NET_ADMIN, SYS_MODULE capabilities |
| **no_writable_host_paths** | HIGH | Host path volumes must be read-only |
| **read_only_root** | MEDIUM | Read-only root filesystem recommended |
| **no_new_privileges** | MEDIUM | Should set no-new-privileges flag |
| **memory_limit** | LOW | Memory limit should be set |
| **cpu_limit** | LOW | CPU limit should be set |

## Examples

### Secure Container (Passes)

```bash
curl -X POST http://localhost:8087/verify \
  -H "Content-Type: application/json" \
  -d '{
    "image": "alpine:3.19",
    "config": {
      "privileged": false,
      "user": "1000",
      "read_only_root": true,
      "no_new_privileges": true,
      "resources": {
        "memory_limit": "512Mi",
        "cpu_limit": "1000m"
      }
    }
  }'
```

**Result:**
```json
{
  "allowed": true,
  "violations": []
}
```

### Insecure Container (Blocked)

```bash
curl -X POST http://localhost:8087/verify \
  -H "Content-Type: application/json" \
  -d '{
    "image": "nginx:latest",
    "config": {
      "privileged": true,
      "user": "root",
      "capabilities": ["SYS_ADMIN"]
    }
  }'
```

**Result:**
```json
{
  "allowed": false,
  "violations": [
    {
      "rule": "no_privileged",
      "severity": "CRITICAL",
      "message": "Privileged containers are not allowed",
      "field": "privileged"
    },
    {
      "rule": "non_root_user",
      "severity": "HIGH",
      "message": "Container must run as non-root user",
      "field": "user"
    },
    {
      "rule": "no_dangerous_caps",
      "severity": "HIGH",
      "message": "Dangerous capability not allowed: SYS_ADMIN",
      "field": "capabilities"
    }
  ]
}
```

## OPA Custom Policies

When OPA is installed, you can write custom Rego policies:

**Example Policy (`/policies/default.rego`):**
```rego
package container

# Deny privileged containers
deny[msg] {
    input.config.privileged == true
    msg := "Privileged mode is forbidden"
}

# Deny root user
deny[msg] {
    input.config.user == "root"
    msg := "Running as root is not allowed"
}

# Deny containers without resource limits
deny[msg] {
    not input.config.resources.memory_limit
    msg := "Memory limit must be specified"
}

# Deny host network mode
deny[msg] {
    input.config.network_mode == "host"
    msg := "Host network mode is not permitted"
}
```

## Configuration

Environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `VORDR_PORT` | `8087` | HTTP server port |
| `VORDR_POLICY_DIR` | `/policies` | OPA policy directory |
| `RUST_LOG` | `info` | Log level |

## Integration with OPSM

Vordr is automatically integrated with OPSM's container workflow:

```bash
# Verify before deployment
opsm container verify myimage:latest

# Full pipeline with verification
opsm container pipeline ./Containerfile \
  --registry ghcr.io/org \
  --verify

# Check against custom policy
opsm container verify myimage:latest --policy strict.rego
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
┌───▼───┐ ┌──▼────────┐
│  OPA  │ │  Built-in │
│(Rego) │ │  Engine   │
└───────┘ └───────────┘
```

## Verification Flow

1. **Request**: Client sends container config
2. **Engine Selection**: Use OPA if available, otherwise built-in
3. **Evaluation**: Apply security policies
4. **Violations**: Collect all policy violations
5. **Decision**: Allow only if no HIGH/CRITICAL violations
6. **Response**: Return decision with violation details

## Policy Development

### Testing Policies

```bash
# Test with curl
curl -X POST http://localhost:8087/verify \
  -H "Content-Type: application/json" \
  -d @test-config.json

# Test OPA policy locally
opa eval -d policy.rego -i input.json 'data.container.deny'
```

### Best Practices

1. **Start Strict**: Begin with strict policies, relax as needed
2. **Severity Matters**: Use CRITICAL for security issues, LOW for recommendations
3. **Clear Messages**: Write actionable violation messages
4. **Test Thoroughly**: Test policies against known good/bad configs
5. **Document**: Add comments to explain policy rationale

## Troubleshooting

**"OPA not available - using built-in policy engine"**
- This is informational - built-in engine works fine for common cases
- Install OPA if you need custom policies: `brew install opa`

**"Policy file not found"**
- Check `VORDR_POLICY_DIR` is set correctly
- Ensure `.rego` files exist in policy directory
- Default policy path: `/policies/default.rego`

**Container allowed despite security issues**
- Built-in engine only blocks HIGH/CRITICAL violations
- MEDIUM/LOW violations are warnings only
- Use custom OPA policies for stricter enforcement

## License

MPL-2.0

## Author

Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
