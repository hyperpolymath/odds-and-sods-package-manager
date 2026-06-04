<!--
SPDX-License-Identifier: MPL-2.0
Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
# OPSM Container Integration

**Comprehensive container security with Chainguard Wolfi, vulnerability scanning, image signing, and runtime protection.**

## Overview

OPSM provides end-to-end container security through integration with specialized services:

```
┌─────────────────────────────────────────────────────┐
│         OPSM Container Security Pipeline            │
├─────────────────────────────────────────────────────┤
│ 1. Build    → Chainguard Wolfi (minimal images)    │
│ 2. Scan     → Svalinn (Trivy + Grype)              │
│ 3. Sign     → Selur (Cosign + Sigstore)            │
│ 4. Verify   → Vordr (OPA policies)                 │
│ 5. Monitor  → Cerro-Torre (eBPF + Falco)           │
└─────────────────────────────────────────────────────┘
```

## Quick Start

### 1. Start Security Services

```bash
# Using selur-compose
just compose-up -d

# Or manually with docker-compose
docker-compose -f selur-compose.yml up -d
```

### 2. Build a Secure Container

```bash
# Build with OPSM CLI
opsm container build ./opsm_ex --version latest

# Or with Justfile
just container-build latest
```

### 3. Run Security Pipeline

```bash
# Full pipeline: build → scan → sign → push
opsm container pipeline ./opsm_ex

# Or with Justfile
just container-pipeline latest ghcr.io/hyperpolymath
```

## Architecture

### Services

| Service | Port | Purpose | Technology |
|---------|------|---------|------------|
| **opsm** | 4466 | Main API/CLI | Elixir |
| **claim-forge** | 8080 | Attestation generation | Rust |
| **checky-monkey** | 8081 | Code verification | Rust + AFL++ |
| **palimpsest** | 8082 | License analysis | Gleam |
| **cicd-hyper-a** | 8083 | Package registry | Elixir |
| **oikos** | 8084 | Sustainability analysis | Rust |
| **svalinn** | 8085 | Vulnerability scanning | Trivy + Grype |
| **selur** | 8086 | Image signing | Cosign + Sigstore |
| **vordr** | 8087 | Runtime verification | OPA |
| **cerro-torre** | 8088 | Security monitoring | eBPF + Falco |

### Security Features

**Build Security:**
- Chainguard Wolfi minimal base images (CVE-free)
- Multi-stage builds (reduced attack surface)
- Non-root containers
- Read-only root filesystems
- Minimal capabilities (CAP_DROP all by default)

**Vulnerability Management:**
- Trivy vulnerability database
- Grype security scanning
- Threshold-based blocking (critical/high)
- CVE tracking and reporting

**Image Signing:**
- Cosign keyless signing
- Sigstore transparency log
- Ed25519 signature verification
- SLSA provenance attestations

**Runtime Protection:**
- OPA policy enforcement (Vordr)
- eBPF syscall monitoring (Cerro-Torre)
- Falco runtime security rules
- Network segmentation (trust/public networks)

## CLI Usage

### Build Commands

```bash
# Build container image
opsm container build <path> [--version <tag>]

# Examples
opsm container build ./opsm_ex --version v1.0.1
opsm container build ./services/claim-forge
```

### Security Scanning

```bash
# Scan for vulnerabilities
opsm container scan <image>

# Example
opsm container scan opsm:latest
# Output:
#   ✓ Scan complete
#   Critical: 0
#   High: 0
#   Medium: 2
#   Low: 5
```

### Image Signing

```bash
# Sign image
opsm container sign <image>

# Verify signature
opsm container verify <image>

# Examples
opsm container sign opsm:latest
opsm container verify opsm:latest
```

### Registry Operations

```bash
# Push to registry
opsm container push <image>

# Example
opsm container push opsm:latest
# Pushes to: $CONTAINER_REGISTRY/opsm:latest
```

### Full Pipeline

```bash
# Complete security pipeline
opsm container pipeline <path> [--version <tag>]

# Example
opsm container pipeline ./opsm_ex --version v1.0.1
# Steps:
#   1. Build image from Containerfile
#   2. Scan with Svalinn (blocks on critical/high CVEs)
#   3. Sign with Selur (Cosign)
#   4. Push to registry
```

## Justfile Integration

### Container Commands

```bash
# Build
just container-build <tag>

# Scan
just container-scan <image> <tag>

# Sign
just container-sign <image> <tag> [key_path]

# Verify
just container-verify <image> <tag> [pubkey_path]

# Full pipeline
just container-pipeline <tag> <registry>
```

### Selur-Compose Commands

```bash
# Start all services
just compose-up [-d]

# Stop services
just compose-down

# View logs
just compose-logs [service]

# Restart service
just compose-restart <service>

# Execute command in service
just compose-exec <service> <cmd>

# Show status
just compose-ps

# Validate configuration
just compose-validate

# Full stack deployment
just compose-deploy
```

## Configuration

### Environment Variables

```bash
# Container registry
export CONTAINER_REGISTRY=ghcr.io/hyperpolymath

# Security services
export SVALINN_URL=http://localhost:8085
export SELUR_URL=http://localhost:8086
export VORDR_URL=http://localhost:8087
export CERRO_URL=http://localhost:8088

# Signing keys
export SIGNING_KEY=/keys/signing.key
export VERIFY_KEY=/keys/signing.pub
```

### selur-compose.yml

The `selur-compose.yml` provides secure defaults:

- **Image verification**: All images must be signed
- **Vulnerability scanning**: Images scanned on pull
- **Network isolation**: Trust network (172.20.0.0/16) for services
- **Security policies**: No new privileges, minimal capabilities
- **Audit logging**: All actions logged to `/var/log/opsm/audit.log`

### Customization

```yaml
# Override security defaults
x-selur-config:
  scan_threshold: high  # medium, high, critical
  seccomp_default: runtime/default
  network_policies:
    - name: trust-isolation
      deny_external: true
```

## Examples

### Example 1: Build and Deploy OPSM

```bash
# 1. Start services
just compose-up -d

# 2. Build OPSM container
cd opsm_ex
opsm container build . --version v1.0.1

# 3. Run security pipeline
opsm container pipeline . --version v1.0.1

# 4. Verify deployment
just compose-ps
```

### Example 2: Custom Service Container

```bash
# 1. Create Containerfile
cat > services/my-service/Containerfile <<EOF
FROM cgr.dev/chainguard/wolfi-base:latest
RUN apk add --no-cache rust
COPY . /app
WORKDIR /app
RUN cargo build --release
USER 1000
CMD ["/app/target/release/my-service"]
EOF

# 2. Build with security
opsm container pipeline ./services/my-service --version latest

# 3. Add to selur-compose.yml
# (Add service definition to selur-compose.yml)

# 4. Deploy
just compose-deploy
```

### Example 3: Verify Third-Party Image

```bash
# Scan external image
opsm container scan nginx:latest

# If scanning fails, pull and re-sign
docker pull nginx:latest
opsm container sign nginx:latest
opsm container verify nginx:latest
```

## Security Best Practices

### Container Images

1. **Use Chainguard Wolfi base images**
   ```dockerfile
   FROM cgr.dev/chainguard/wolfi-base:latest
   ```

2. **Multi-stage builds**
   ```dockerfile
   FROM cgr.dev/chainguard/rust:latest AS builder
   # Build here
   FROM cgr.dev/chainguard/wolfi-base:latest
   COPY --from=builder /app/target/release/app /app/
   ```

3. **Non-root user**
   ```dockerfile
   RUN adduser -D -u 1000 appuser
   USER appuser
   ```

4. **Read-only filesystem**
   ```yaml
   read_only: true
   tmpfs:
     - /tmp:noexec,nosuid,nodev
   ```

### Vulnerability Management

1. **Block on critical/high CVEs**
   - Pipeline automatically fails on critical or high vulnerabilities
   - Review scan results before overriding

2. **Regular scanning**
   ```bash
   # Scan all running containers
   just compose-ps | awk '{print $1}' | xargs -I {} opsm container scan {}
   ```

3. **Update base images**
   ```bash
   # Pull latest Wolfi base
   docker pull cgr.dev/chainguard/wolfi-base:latest
   ```

### Image Signing

1. **Generate signing keys**
   ```bash
   mkdir -p secrets
   cosign generate-key-pair --output-key-prefix secrets/signing
   ```

2. **Sign all production images**
   ```bash
   opsm container sign myapp:latest
   ```

3. **Verify before deployment**
   ```bash
   opsm container verify myapp:latest
   ```

## Troubleshooting

### Service Not Starting

```bash
# Check logs
just compose-logs <service>

# Restart service
just compose-restart <service>

# Rebuild service
just compose-build <service>
just compose-up -d
```

### Scan Failures

```bash
# Update vulnerability database
docker exec svalinn trivy image --download-db-only

# Retry scan
opsm container scan <image>
```

### Signature Verification Failures

```bash
# Check key paths
echo $SIGNING_KEY
echo $VERIFY_KEY

# Verify key permissions
ls -la /keys/

# Test with cosign directly
cosign verify --key /keys/signing.pub <image>
```

### Network Issues

```bash
# Check network connectivity
docker network inspect opsm-trust
docker network inspect opsm-public

# Restart networking
just compose-down
just compose-up -d
```

## Integration with Package Publishing

Container integration works seamlessly with OPSM's package publishing:

```bash
# 1. Publish package to registry
opsm publish ./my-package

# 2. Build container with package
opsm container build ./my-package --version latest

# 3. Run security pipeline
opsm container pipeline ./my-package

# 4. Deploy container
docker run ghcr.io/hyperpolymath/my-package:latest
```

## Monitoring and Observability

### View Runtime Events (Cerro-Torre)

```bash
# Stream security events
just compose-logs cerro-torre -f

# Check for policy violations
curl http://localhost:8088/events?severity=high
```

### Audit Logs

```bash
# View audit log
cat /var/log/opsm/audit.log

# Filter by service
grep "claim-forge" /var/log/opsm/audit.log
```

### Health Checks

```bash
# Check all services
just compose-ps

# Individual service health
curl http://localhost:8085/health  # Svalinn
curl http://localhost:8086/health  # Selur
curl http://localhost:8087/health  # Vordr
```

## Contributing

To add a new service to the container ecosystem:

1. Create `services/<name>/Containerfile`
2. Add service to `selur-compose.yml`
3. Update `CONTAINER-INTEGRATION.md` documentation
4. Test with `just compose-deploy`

## License

MPL-2.0 (Palimpsest License)

## References

- [Chainguard Wolfi](https://github.com/wolfi-dev)
- [Cosign](https://github.com/sigstore/cosign)
- [Trivy](https://github.com/aquasecurity/trivy)
- [Falco](https://falco.org/)
- [OPA](https://www.openpolicyagent.org/)
