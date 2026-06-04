<!--
SPDX-License-Identifier: MPL-2.0
Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
# OPSM Crypto Usage Examples

**Date:** February 5, 2026
**Version:** v1.0.1+
**Status:** Production Ready

This guide provides practical examples for using OPSM's Phase 1 cryptographic features.

## Table of Contents

1. [API Key Storage](#api-key-storage)
2. [Lockfile Encryption](#lockfile-encryption)
3. [Package Integrity Verification](#package-integrity-verification)
4. [Session Token Generation](#session-token-generation)
5. [Best Practices](#best-practices)

---

## API Key Storage

### Basic Usage

Store and retrieve API keys securely:

```elixir
alias Opsm.Crypto.ApiKeyStorage

# 1. Generate a master key (do this once, store securely!)
master_key = ApiKeyStorage.generate_master_key()

# Save master key to environment variable or secrets manager
# export OPSM_MASTER_KEY=$(echo $master_key | base64)

# 2. Store an API key
{:ok, key_id} = ApiKeyStorage.store_key(
  "ghp_your_github_token_here",
  master_key,
  service: "github"
)

# Save key_id for later retrieval (e.g., in config file)
IO.puts("Key ID: #{key_id}")

# 3. Retrieve the API key when needed
{:ok, api_key} = ApiKeyStorage.retrieve_key(key_id, master_key)
# Use api_key for GitHub API calls
```

### With Expiration

Set expiration dates for temporary access:

```elixir
# Store a key that expires in 30 days
expires_at = DateTime.utc_now() |> DateTime.add(30 * 24 * 3600, :second)

{:ok, key_id} = ApiKeyStorage.store_key(
  "temporary-access-token",
  master_key,
  service: "registry",
  expires_at: expires_at
)

# Retrieval will fail after expiration
case ApiKeyStorage.retrieve_key(key_id, master_key) do
  {:ok, key} ->
    IO.puts("Using key: #{key}")
  {:error, "API key has expired"} ->
    IO.puts("Token expired, please refresh")
end
```

### Managing Multiple Keys

List and manage multiple API keys:

```elixir
# Store keys for different services
{:ok, github_id} = ApiKeyStorage.store_key(
  "github-token",
  master_key,
  service: "github"
)

{:ok, gitlab_id} = ApiKeyStorage.store_key(
  "gitlab-token",
  master_key,
  service: "gitlab"
)

{:ok, npm_id} = ApiKeyStorage.store_key(
  "npm-token",
  master_key,
  service: "npm"
)

# List all stored keys (metadata only, no decryption)
keys = ApiKeyStorage.list_keys()

Enum.each(keys, fn key ->
  status = if key.expired?, do: "EXPIRED", else: "Active"
  IO.puts("#{key.service}: #{key.key_id} [#{status}]")
end)

# Delete a key when no longer needed
:ok = ApiKeyStorage.delete_key(github_id)
```

### CLI Integration Example

Integrate API key storage into CLI commands:

```elixir
# In your CLI module
defmodule Opsm.CLI.Auth do
  alias Opsm.Crypto.ApiKeyStorage

  def login(service, api_key) do
    master_key = get_master_key_from_env()

    case ApiKeyStorage.store_key(api_key, master_key, service: service) do
      {:ok, key_id} ->
        # Save key_id to config file
        save_config(%{service => %{key_id: key_id}})
        IO.puts("✓ Logged in to #{service}")

      {:error, reason} ->
        IO.puts("✗ Login failed: #{reason}")
    end
  end

  def get_auth_token(service) do
    master_key = get_master_key_from_env()
    config = load_config()

    case config[service] do
      %{key_id: key_id} ->
        ApiKeyStorage.retrieve_key(key_id, master_key)

      nil ->
        {:error, "Not logged in to #{service}"}
    end
  end

  defp get_master_key_from_env do
    case System.get_env("OPSM_MASTER_KEY") do
      nil ->
        raise "OPSM_MASTER_KEY not set. Run: export OPSM_MASTER_KEY=$(opsm auth init)"

      encoded ->
        Base.decode64!(encoded)
    end
  end
end
```

---

## Lockfile Encryption

### Encrypting Sensitive Lockfiles

Use lockfile encryption for projects with sensitive dependencies:

```elixir
alias Opsm.{Lockfile, Crypto.Symmetric}

# 1. Generate an encryption key (or derive from password)
encryption_key = Symmetric.generate_key()

# Save this key securely (environment variable, secrets manager)

# 2. Create and encrypt a lockfile
lockfile = Lockfile.new()
|> Lockfile.add_package(%{
  name: "proprietary-lib",
  version: "1.0.0",
  forth: :cargo,
  checksum: "abc123",
  source_url: "https://private-registry.company.com/lib.tar.gz"
})

# Write encrypted lockfile
{:ok, path} = Lockfile.write(
  lockfile,
  "opsm.lock.encrypted",
  encrypt: true,
  key: encryption_key
)

IO.puts("✓ Encrypted lockfile written to: #{path}")

# 3. Read encrypted lockfile
{:ok, loaded} = Lockfile.read(
  "opsm.lock.encrypted",
  decrypt: true,
  key: encryption_key
)

IO.puts("Loaded #{map_size(loaded.packages)} packages")
```

### Password-Based Encryption

Derive encryption key from a password:

```elixir
alias Opsm.Crypto.{Password, Symmetric}

defmodule LockfileEncryption do
  # Derive encryption key from password using Argon2id
  def derive_key_from_password(password) do
    {:ok, hash} = Password.hash(password)

    # Use first 32 bytes of hash as encryption key
    <<key::binary-size(32), _rest::binary>> = hash
    key
  end

  def encrypt_lockfile(lockfile, password) do
    key = derive_key_from_password(password)
    Lockfile.write(lockfile, "opsm.lock.encrypted", encrypt: true, key: key)
  end

  def decrypt_lockfile(password) do
    key = derive_key_from_password(password)
    Lockfile.read("opsm.lock.encrypted", decrypt: true, key: key)
  end
end

# Usage
lockfile = Lockfile.new()
LockfileEncryption.encrypt_lockfile(lockfile, "my-secure-password")

# Later...
{:ok, loaded} = LockfileEncryption.decrypt_lockfile("my-secure-password")
```

---

## Package Integrity Verification

### Verifying Lockfile Integrity

Automatic tamper detection with SHA3-512:

```elixir
alias Opsm.Lockfile

# Create lockfile with integrity hash
lockfile = Lockfile.new()
|> Lockfile.add_package(%{
  name: "lodash",
  version: "4.17.21",
  forth: :npm,
  checksum: "abc123"
})

# Write lockfile (integrity hash computed automatically)
{:ok, path} = Lockfile.write(lockfile, "opsm.lock")

# Read lockfile (integrity verified automatically)
case Lockfile.read("opsm.lock") do
  {:ok, loaded} ->
    IO.puts("✓ Lockfile integrity verified")
    IO.puts("Hash algorithm: #{loaded.integrity_algo}")
    IO.puts("Integrity hash: #{String.slice(loaded.integrity_hash, 0, 16)}...")

  {:error, reason} ->
    IO.puts("✗ Lockfile integrity check failed: #{reason}")
end
```

### Manual Integrity Verification

Verify integrity explicitly:

```elixir
alias Opsm.Lockfile

# Read without automatic verification
{:ok, lockfile} = Lockfile.read("opsm.lock", verify_integrity: false)

# Manually verify integrity
case Lockfile.verify_integrity(lockfile) do
  :ok ->
    IO.puts("✓ Integrity check passed")

  {:ok, :no_integrity_hash} ->
    IO.puts("⚠ Old lockfile format (no integrity hash)")

  {:error, reason} ->
    IO.puts("✗ TAMPERING DETECTED: #{reason}")
    # Take action: refuse to install, alert user, etc.
end
```

### Computing Package Checksums

Use BLAKE2b for package content hashing:

```elixir
alias Opsm.Crypto.Hash

# Hash package tarball (BLAKE2b - fast)
package_data = File.read!("lodash-4.17.21.tgz")
checksum = Hash.hash_content_addressed(package_data)

# Add to lockfile
lockfile = Lockfile.add_package(lockfile, %{
  name: "lodash",
  version: "4.17.21",
  forth: :npm,
  checksum: checksum,
  checksum_algo: "blake2b"  # Default in v1.0.1+
})

# Verify package on install
actual_checksum = Hash.hash_content_addressed(downloaded_package)

case Lockfile.verify_package(lockfile, "lodash", :npm, actual_checksum) do
  :ok ->
    IO.puts("✓ Package integrity verified")

  {:mismatch, %{expected: expected, actual: actual}} ->
    IO.puts("✗ CHECKSUM MISMATCH!")
    IO.puts("Expected: #{expected}")
    IO.puts("Actual:   #{actual}")
    # Refuse to install, alert user
end
```

### Long-Term Provenance Hashing

Use SHA3-512 for supply chain tracking:

```elixir
alias Opsm.Crypto.Hash

# Hash provenance data (SHA3-512 - post-quantum secure)
provenance_data = %{
  package: "lodash",
  version: "4.17.21",
  source: "https://registry.npmjs.org",
  downloaded_at: DateTime.utc_now(),
  attestations: [...]
}

json = Jason.encode!(provenance_data)
provenance_hash = Hash.hash_provenance(json)

# Store for long-term verification
File.write!("provenance/lodash-4.17.21.json", json)
File.write!("provenance/lodash-4.17.21.sha3-512", provenance_hash)
```

---

## Session Token Generation

### Generating Secure Tokens

Use ChaCha20-DRBG for cryptographically secure tokens:

```elixir
alias Opsm.Crypto.{RNG, ApiKeyStorage}

# Generate session token (URL-safe base64)
session_token = ApiKeyStorage.generate_token(32)
IO.puts("Session token: #{session_token}")

# Generate raw random bytes
random_bytes = RNG.generate_bytes(32)
IO.puts("Byte length: #{byte_size(random_bytes)}")

# Generate 256-bit encryption key
encryption_key = RNG.generate_key_256bit()

# Generate salt for password hashing
salt = RNG.generate_salt()
```

### Token-Based Authentication

Implement token-based auth:

```elixir
defmodule Opsm.Auth.Tokens do
  alias Opsm.Crypto.{ApiKeyStorage, Password}

  @token_expiry 24 * 3600  # 24 hours

  def create_session_token(user_id) do
    token = ApiKeyStorage.generate_token(32)
    expires_at = DateTime.utc_now() |> DateTime.add(@token_expiry, :second)

    # Store token hash (not plaintext)
    {:ok, token_hash} = Password.hash(token)

    # Save to database
    save_session(%{
      user_id: user_id,
      token_hash: token_hash,
      expires_at: expires_at
    })

    {:ok, token}
  end

  def verify_session_token(token) do
    case get_session_by_token(token) do
      nil ->
        {:error, :invalid_token}

      session ->
        if DateTime.compare(DateTime.utc_now(), session.expires_at) == :lt do
          case Password.verify(token, session.token_hash) do
            :ok -> {:ok, session.user_id}
            {:error, _} -> {:error, :invalid_token}
          end
        else
          {:error, :token_expired}
        end
    end
  end
end
```

---

## Best Practices

### 1. Master Key Management

**DO:**
- Generate master keys once and store securely
- Use environment variables or secrets managers
- Rotate master keys periodically (every 90 days)
- Use different master keys for different environments (dev/staging/prod)

**DON'T:**
- Commit master keys to version control
- Share master keys via email or chat
- Store master keys in configuration files
- Use weak or predictable master keys

```bash
# Good: Generate and store master key
export OPSM_MASTER_KEY=$(openssl rand -base64 32)

# Good: Use secrets manager
aws secretsmanager create-secret \
  --name opsm-master-key \
  --secret-string "$OPSM_MASTER_KEY"

# Bad: Hardcoded in config
# config :opsm, master_key: "hardcoded-key-123"
```

### 2. Lockfile Security

**DO:**
- Always verify lockfile integrity before installing
- Use encrypted lockfiles for sensitive projects
- Commit encrypted lockfiles to version control
- Store encryption keys separately from lockfiles

**DON'T:**
- Disable integrity verification in production
- Use weak encryption keys
- Share lockfile encryption keys publicly

```elixir
# Good: Verify integrity before install
case Lockfile.read("opsm.lock") do
  {:ok, lockfile} ->
    install_packages(lockfile)
  {:error, reason} ->
    IO.puts("Lockfile integrity check failed: #{reason}")
    System.halt(1)
end

# Bad: Skip verification
Lockfile.read("opsm.lock", verify_integrity: false)
```

### 3. API Key Hygiene

**DO:**
- Set expiration dates for temporary keys
- Delete keys when no longer needed
- Use service-specific keys (not one key for everything)
- Audit stored keys regularly

**DON'T:**
- Store API keys without expiration
- Reuse API keys across services
- Leave old/unused keys in storage

```elixir
# Good: Regular cleanup
keys = ApiKeyStorage.list_keys()

Enum.each(keys, fn key ->
  if key.expired? do
    ApiKeyStorage.delete_key(key.key_id)
    IO.puts("Deleted expired key: #{key.service}")
  end
end)

# Good: Set expiration
ApiKeyStorage.store_key(
  key,
  master_key,
  service: "temp-access",
  expires_at: DateTime.utc_now() |> DateTime.add(3600, :second)
)
```

### 4. Error Handling

**DO:**
- Handle decryption failures gracefully
- Provide helpful error messages
- Log security-relevant errors
- Fail closed (deny access on error)

**DON'T:**
- Ignore cryptographic errors
- Expose sensitive error details to users
- Continue execution after integrity check failure

```elixir
# Good: Graceful error handling
case ApiKeyStorage.retrieve_key(key_id, master_key) do
  {:ok, key} ->
    use_key(key)

  {:error, "API key has expired"} ->
    IO.puts("Your API key has expired. Please refresh it with: opsm auth refresh")

  {:error, reason} ->
    Logger.error("Key retrieval failed: #{reason}")
    IO.puts("Failed to retrieve API key. Please check your master key.")
end

# Bad: Ignore errors
{:ok, key} = ApiKeyStorage.retrieve_key(key_id, master_key)
```

### 5. Testing

Always test crypto integrations:

```elixir
defmodule MyApp.CryptoIntegrationTest do
  use ExUnit.Case
  alias Opsm.Crypto.ApiKeyStorage

  test "API key storage roundtrip" do
    master_key = ApiKeyStorage.generate_master_key()
    api_key = "test-api-key"

    {:ok, key_id} = ApiKeyStorage.store_key(api_key, master_key)
    {:ok, retrieved} = ApiKeyStorage.retrieve_key(key_id, master_key)

    assert retrieved == api_key
  end

  test "wrong master key fails" do
    master_key = ApiKeyStorage.generate_master_key()
    wrong_key = ApiKeyStorage.generate_master_key()

    {:ok, key_id} = ApiKeyStorage.store_key("secret", master_key)
    assert {:error, _} = ApiKeyStorage.retrieve_key(key_id, wrong_key)
  end
end
```

---

## Security Considerations

### Threat Model

OPSM's crypto assumes:
- **Adversaries with quantum computers** (using post-quantum algorithms)
- **Supply chain attacks** (lockfile tampering, malicious packages)
- **Network adversaries** (MITM, traffic analysis)
- **Filesystem access** (unauthorized file reads)

### Mitigation Strategies

1. **Lockfile Integrity**: SHA3-512 hashes detect tampering
2. **Encryption**: ChaCha20-Poly1305 protects sensitive data at rest
3. **Key Derivation**: Argon2id resists brute-force attacks
4. **Randomness**: ChaCha20-DRBG provides high-entropy tokens
5. **Service Isolation**: Different contexts prevent cross-service attacks

### Compliance

All crypto complies with:
- **RFC 9106** (Argon2id)
- **RFC 7539** (ChaCha20-Poly1305)
- **FIPS 202** (SHA3-512, BLAKE2b)
- **NIST SP 800-90Ar1** (ChaCha20-DRBG)

---

## Troubleshooting

### Common Issues

**Problem:** "Master key not set"
```bash
# Solution: Set environment variable
export OPSM_MASTER_KEY=$(openssl rand -base64 32)
```

**Problem:** "Lockfile integrity verification failed"
```elixir
# Solution: Check for file corruption or tampering
{:ok, lockfile} = Lockfile.read("opsm.lock", verify_integrity: false)
lockfile_fixed = Lockfile.compute_integrity_hash(lockfile)
Lockfile.write(lockfile_fixed, "opsm.lock")
```

**Problem:** "Decryption failed (authentication failure)"
```elixir
# Solution: Ensure using correct encryption key
# Keys cannot be recovered - must re-encrypt with new key
```

---

## Further Reading

- **CRYPTO-PHASE1-COMPLETE.md**: Phase 1 implementation details
- **CRYPTO-INTEGRATION-COMPLETE.md**: Integration completion report
- **SECURITY-STANDARDS.scm**: Full cryptographic specifications
- **SECURITY-QUICK-REFERENCE.md**: Quick algorithm reference

---

**Questions or Issues?**
- GitHub Issues: https://github.com/hyperpolymath/odds-and-sods-package-manager/issues
- Security: security@hyperpolymath.org
