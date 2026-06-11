<!--
SPDX-License-Identifier: MPL-2.0
Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
# Selur - Container Image Signing Service

**Selur** is OPSM's container image signing and verification service, integrating Cosign for cryptographic signing and supply chain security.

## Features

- **Cosign Integration**: Industry-standard container signing
- **Keypair Management**: Generate and manage signing keys
- **Image Signing**: Sign container images with cryptographic attestation
- **Signature Verification**: Verify image signatures before deployment
- **Annotations**: Attach metadata to signatures
- **REST API**: Simple HTTP API for all operations

## Quick Start

### Prerequisites

Install Cosign:

```bash
# Linux
curl -LO https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-amd64
chmod +x cosign-linux-amd64
sudo mv cosign-linux-amd64 /usr/local/bin/cosign

# macOS
brew install cosign
```

### Running Locally

```bash
# Set key directory
export SELUR_KEY_DIR=/path/to/keys

# Run service
cargo run --release
```

### Running in Container

```bash
# Build
podman build -t selur:latest -f Containerfile .

# Run with mounted key directory
podman run -p 8086:8086 -v ./keys:/keys selur:latest
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
  "cosign_available": true,
  "cosign_version": "cosign v2.4.1"
}
```

### Generate Keypair

```bash
POST /keygen
Content-Type: application/json

{
  "key_name": "my-signing-key"
}
```

**Response:**
```json
{
  "private_key_path": "/keys/my-signing-key.key",
  "public_key_path": "/keys/my-signing-key.pub",
  "public_key": "-----BEGIN PUBLIC KEY-----\n...\n-----END PUBLIC KEY-----"
}
```

### Sign Container Image

```bash
POST /sign
Content-Type: application/json

{
  "image": "ghcr.io/org/image:tag",
  "key_path": "/keys/signing.key",
  "annotations": {
    "author": "CI/CD Pipeline",
    "commit": "abc123"
  }
}
```

**Request Fields:**
- `image` (required): Full container image reference
- `key_path` (optional): Path to private key (default: `/keys/cosign.key`)
- `annotations` (optional): Key-value metadata to attach

**Response:**
```json
{
  "image": "ghcr.io/org/image:tag",
  "signature_digest": "sha256:abc123...",
  "public_key": "-----BEGIN PUBLIC KEY-----\n...\n-----END PUBLIC KEY-----",
  "signed_at": "2026-02-05T07:00:00Z",
  "annotations": {
    "author": "CI/CD Pipeline",
    "commit": "abc123"
  }
}
```

### Verify Container Image

```bash
POST /verify
Content-Type: application/json

{
  "image": "ghcr.io/org/image:tag",
  "public_key_path": "/keys/signing.pub"
}
```

**Request Fields:**
- `image` (required): Full container image reference
- `public_key_path` (optional): Path to public key (default: `/keys/cosign.pub`)

**Response:**
```json
{
  "image": "ghcr.io/org/image:tag",
  "verified": true,
  "message": "Image signature verified successfully",
  "signatures": [
    {
      "digest": "sha256:def456...",
      "signed_at": "2026-02-05T07:00:00Z",
      "annotations": {
        "author": "CI/CD Pipeline"
      }
    }
  ]
}
```

## Examples

### Complete Signing Workflow

```bash
# 1. Generate keypair
curl -X POST http://localhost:8086/keygen \
  -H "Content-Type: application/json" \
  -d '{"key_name": "prod-signing"}'

# 2. Build and push your image
podman build -t ghcr.io/myorg/app:v1.0.0 .
podman push ghcr.io/myorg/app:v1.0.0

# 3. Sign the image
curl -X POST http://localhost:8086/sign \
  -H "Content-Type: application/json" \
  -d '{
    "image": "ghcr.io/myorg/app:v1.0.0",
    "key_path": "/keys/prod-signing.key",
    "annotations": {
      "build": "12345",
      "commit": "abc123"
    }
  }'

# 4. Verify the signature
curl -X POST http://localhost:8086/verify \
  -H "Content-Type: application/json" \
  -d '{
    "image": "ghcr.io/myorg/app:v1.0.0",
    "public_key_path": "/keys/prod-signing.pub"
  }'
```

### CI/CD Integration

```yaml
# GitHub Actions example
- name: Sign Container Image
  run: |
    curl -X POST http://selur:8086/sign \
      -H "Content-Type: application/json" \
      -d "{
        \"image\": \"${{ env.IMAGE }}\",
        \"annotations\": {
          \"github_sha\": \"${{ github.sha }}\",
          \"github_run\": \"${{ github.run_id }}\"
        }
      }"
```

## Configuration

Environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `SELUR_PORT` | `8086` | HTTP server port |
| `SELUR_KEY_DIR` | `/keys` | Directory for storing keys |
| `RUST_LOG` | `info` | Log level (`debug`, `info`, `warn`, `error`) |

## Integration with OPSM

Selur is automatically integrated with OPSM's container workflow:

```bash
# Sign during container build pipeline
opsm container sign myimage:latest --key /keys/signing.key

# Verify before deployment
opsm container verify myimage:latest --pubkey /keys/signing.pub

# Full pipeline with automatic signing
opsm container pipeline ./Containerfile \
  --registry ghcr.io/org \
  --sign \
  --key /keys/signing.key
```

## Architecture

```
┌─────────────────┐
│   REST API      │
│   (Axum)        │
└────────┬────────┘
         │
    ┌────▼────┐
    │ Cosign  │
    │ v2.4+   │
    └─────────┘
         │
    ┌────▼────────┐
    │ OCI Registry│
    │ (Signatures)│
    └─────────────┘
```

## Security Best Practices

1. **Key Management**:
   - Store private keys securely (use secrets management)
   - Never commit keys to version control
   - Rotate keys periodically
   - Use separate keys for dev/staging/prod

2. **Verification**:
   - Always verify signatures before deployment
   - Use keyless signing with Fulcio/Rekor for public images
   - Implement policy enforcement with admission controllers

3. **Annotations**:
   - Include build metadata (commit SHA, build ID)
   - Add provenance information
   - Track signing time and author

## Cosign Features Supported

- ✓ Image signing with private keys
- ✓ Signature verification
- ✓ Annotations and metadata
- ✓ OCI registry storage
- ✗ Keyless signing (Fulcio) - not yet implemented
- ✗ Transparency log (Rekor) - not yet implemented

## Troubleshooting

**"Cosign not available"**
- Ensure Cosign is installed and in PATH
- Check: `cosign version`

**"Key file not found"**
- Verify `SELUR_KEY_DIR` is set correctly
- Generate keys with `/keygen` endpoint first

**"Signing failed: authentication required"**
- Ensure you have push access to the registry
- Login with: `cosign login ghcr.io`

**"Verification failed: no signatures found"**
- Ensure the image was actually signed
- Check that you're using the correct public key
- Verify the image reference is correct (including digest)

## License

MPL-2.0

## Author

Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
