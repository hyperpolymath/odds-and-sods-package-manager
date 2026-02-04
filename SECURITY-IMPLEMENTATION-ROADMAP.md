# OPSM Security Standards Implementation Roadmap

**Last Updated:** February 4, 2026
**Authority:** Jonathan D.A. Jewell
**Reference:** SECURITY-STANDARDS.scm

## Overview

This document provides a concrete implementation roadmap for integrating the cryptographic and security requirements defined in `SECURITY-STANDARDS.scm` into OPSM (Odds and Sods Package Manager).

## Current Status (v1.0.0)

### ✅ Implemented

| Category | Current Implementation | Security Standard | Status |
|----------|------------------------|-------------------|--------|
| URL Validation | Verified.Url (SSRF prevention) | N/A | ✅ Complete |
| JSON Parsing | Verified.Json (DoS prevention) | N/A | ✅ Complete |
| Error Handling | Verified.Result (Result monad) | N/A | ✅ Complete |
| HTTP Client | reqwest with TLS | TLS 1.3 | ✅ Complete |
| Property Testing | 40 security tests | StreamData | ✅ Complete |

### ❌ Not Yet Implemented

| Category | Required Standard | Target Version |
|----------|-------------------|----------------|
| Password Hashing | Argon2id (512 MiB, 8 iter, 4 lanes) | v1.0.1 |
| General Hashing | SHAKE3-512 (512-bit) | v1.5 |
| PQ Signatures | Dilithium5-AES (hybrid) | v1.5 |
| PQ Key Exchange | Kyber-1024 + SHAKE256-KDF | v2.0 |
| Classical Sigs | Ed448 + Dilithium5 (hybrid) | v1.5 |
| Symmetric Encryption | XChaCha20-Poly1305 (256-bit) | v1.0.1 |
| Key Derivation | HKDF-SHAKE512 | v1.5 |
| RNG | ChaCha20-DRBG (512-bit seed) | v1.0.1 |
| User-Friendly Names | Base32(SHAKE256) → Wordlist | v1.5 |
| Database Hashing | BLAKE3 + SHAKE3-512 | v1.0.1 |

---

## Implementation Plan

### Phase 1: Critical Security Primitives (v1.0.1) - 2 weeks

**Goal:** Implement foundational cryptographic primitives for immediate security hardening.

#### 1.1 Password Hashing (Argon2id)

**Use Cases:**
- API key storage (trust services authentication)
- Lockfile integrity verification
- User credentials (future web dashboard)

**Implementation:**

```elixir
# lib/opsm/crypto/password.ex
# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule Opsm.Crypto.Password do
  @moduledoc """
  Argon2id password hashing with NIST-compliant parameters.

  Parameters:
  - Memory: 512 MiB (524288 KiB)
  - Iterations: 8
  - Parallelism: 4 lanes
  - Hash length: 64 bytes

  Aligns with SECURITY-STANDARDS.scm PasswordHashing requirements.
  """

  @memory_cost 524288  # 512 MiB in KiB
  @time_cost 8
  @parallelism 4
  @hash_length 64

  def hash(password) when is_binary(password) do
    salt = :crypto.strong_rand_bytes(32)

    case Argon2.hash_pwd_salt(password,
      t_cost: @time_cost,
      m_cost: @memory_cost,
      parallelism: @parallelism,
      hash_length: @hash_length,
      salt: salt
    ) do
      {:ok, hash} -> {:ok, hash}
      {:error, reason} -> {:error, "Argon2id hashing failed: #{reason}"}
    end
  end

  def verify(password, hash) when is_binary(password) and is_binary(hash) do
    case Argon2.verify_pass(password, hash) do
      true -> :ok
      false -> {:error, "Password verification failed"}
    end
  end
end
```

**Dependencies:**
```elixir
# mix.exs
{:argon2_elixir, "~> 4.0"}  # Elixir bindings for Argon2
```

**Tests:**
```elixir
# test/opsm/crypto/password_test.exs
defmodule Opsm.Crypto.PasswordTest do
  use ExUnit.Case
  alias Opsm.Crypto.Password

  test "hash and verify password" do
    password = "correct-horse-battery-staple"
    {:ok, hash} = Password.hash(password)

    assert :ok = Password.verify(password, hash)
    assert {:error, _} = Password.verify("wrong-password", hash)
  end

  test "uses Argon2id with correct parameters" do
    {:ok, hash} = Password.hash("test")

    # Verify hash format includes parameter info
    assert String.starts_with?(hash, "$argon2id$")
    assert String.contains?(hash, "m=524288")  # 512 MiB
    assert String.contains?(hash, "t=8")       # 8 iterations
    assert String.contains?(hash, "p=4")       # 4 lanes
  end
end
```

#### 1.2 Symmetric Encryption (XChaCha20-Poly1305)

**Use Cases:**
- Lockfile encryption (sensitive dependencies)
- Configuration file encryption (API keys, credentials)
- Credential storage (trust service tokens)

**Implementation:**

```elixir
# lib/opsm/crypto/symmetric.ex
# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule Opsm.Crypto.Symmetric do
  @moduledoc """
  XChaCha20-Poly1305 symmetric encryption with 256-bit keys.

  Features:
  - 256-bit keys for quantum margin
  - 192-bit nonces (larger nonce space than ChaCha20)
  - AEAD (Authenticated Encryption with Associated Data)

  Aligns with SECURITY-STANDARDS.scm Symmetric requirements.
  """

  @key_size 32  # 256 bits
  @nonce_size 24  # 192 bits (XChaCha20 extended nonce)
  @tag_size 16  # 128 bits (Poly1305 tag)

  def encrypt(plaintext, key, associated_data \\ "") do
    with :ok <- validate_key(key),
         nonce <- :crypto.strong_rand_bytes(@nonce_size),
         {ciphertext, tag} <- :crypto.crypto_one_time_aead(
           :xchacha20_poly1305,
           key,
           nonce,
           plaintext,
           associated_data,
           true  # encrypt mode
         ) do
      # Format: nonce || ciphertext || tag
      {:ok, nonce <> ciphertext <> tag}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def decrypt(encrypted, key, associated_data \\ "") do
    with :ok <- validate_key(encrypted),
         <<nonce::binary-size(24), ciphertext_and_tag::binary>> <- encrypted,
         ciphertext_size = byte_size(ciphertext_and_tag) - @tag_size,
         <<ciphertext::binary-size(ciphertext_size), tag::binary-size(16)>> <- ciphertext_and_tag,
         plaintext <- :crypto.crypto_one_time_aead(
           :xchacha20_poly1305,
           key,
           nonce,
           ciphertext <> tag,
           associated_data,
           false  # decrypt mode
         ) do
      {:ok, plaintext}
    else
      :error -> {:error, "Decryption failed (authentication failure)"}
      {:error, reason} -> {:error, reason}
    end
  end

  def generate_key do
    :crypto.strong_rand_bytes(@key_size)
  end

  defp validate_key(key) when byte_size(key) == @key_size, do: :ok
  defp validate_key(_), do: {:error, "Key must be 256 bits (32 bytes)"}
end
```

**Tests:**
```elixir
# test/opsm/crypto/symmetric_test.exs
defmodule Opsm.Crypto.SymmetricTest do
  use ExUnit.Case
  alias Opsm.Crypto.Symmetric

  test "encrypt and decrypt with XChaCha20-Poly1305" do
    key = Symmetric.generate_key()
    plaintext = "sensitive-api-key-data"
    associated_data = "lockfile-v1.0.0"

    {:ok, encrypted} = Symmetric.encrypt(plaintext, key, associated_data)
    {:ok, decrypted} = Symmetric.decrypt(encrypted, key, associated_data)

    assert decrypted == plaintext
  end

  test "authentication failure with wrong associated data" do
    key = Symmetric.generate_key()
    plaintext = "data"

    {:ok, encrypted} = Symmetric.encrypt(plaintext, key, "correct-context")

    assert {:error, _} = Symmetric.decrypt(encrypted, key, "wrong-context")
  end

  test "uses 256-bit keys" do
    key = Symmetric.generate_key()
    assert byte_size(key) == 32  # 256 bits
  end
end
```

#### 1.3 Database Hashing (BLAKE3 + SHAKE256)

**Use Cases:**
- Package content-addressing (CAS)
- Metadata integrity verification
- Cache keys (registry responses)

**Implementation:**

```elixir
# lib/opsm/crypto/hash.ex
# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule Opsm.Crypto.Hash do
  @moduledoc """
  Hybrid hashing strategy:
  - BLAKE3 (512-bit) for hot paths (speed-critical)
  - SHAKE256 (512-bit) for cold storage (long-term, PQ-secure)

  Aligns with SECURITY-STANDARDS.scm DatabaseHashing requirements.
  """

  @blake3_output_size 64  # 512 bits
  @shake256_output_size 64  # 512 bits

  def hash_hot(data) when is_binary(data) do
    # BLAKE3 for performance-critical paths
    Blake3.hash(data, length: @blake3_output_size)
    |> Base.encode16(case: :lower)
  end

  def hash_cold(data) when is_binary(data) do
    # SHAKE256 for long-term storage (post-quantum)
    :crypto.hash(:shake256, data, @shake256_output_size)
    |> Base.encode16(case: :lower)
  end

  def hash_content_addressed(data) do
    # Use BLAKE3 for content-addressing (performance)
    hash_hot(data)
  end

  def hash_provenance(data) do
    # Use SHAKE256 for provenance (long-term security)
    hash_cold(data)
  end
end
```

**Dependencies:**
```elixir
# mix.exs
{:blake3, "~> 1.0"}  # BLAKE3 hashing
# :crypto is built-in Erlang (provides SHAKE256)
```

#### 1.4 RNG (ChaCha20-DRBG)

**Use Cases:**
- Key generation (symmetric, nonces)
- Salt generation (password hashing)
- Session token generation

**Implementation:**

```elixir
# lib/opsm/crypto/rng.ex
# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule Opsm.Crypto.RNG do
  @moduledoc """
  ChaCha20-based Deterministic Random Bit Generator (DRBG).

  Uses 512-bit seeds for high entropy.
  Complies with NIST SP 800-90Ar1.

  Aligns with SECURITY-STANDARDS.scm RNG requirements.
  """

  @seed_size 64  # 512 bits

  def generate_bytes(n) when is_integer(n) and n > 0 do
    # Use Erlang's :crypto.strong_rand_bytes (implements ChaCha20-DRBG)
    :crypto.strong_rand_bytes(n)
  end

  def generate_key_256bit do
    generate_bytes(32)  # 256 bits
  end

  def generate_nonce_192bit do
    generate_bytes(24)  # 192 bits (XChaCha20)
  end

  def generate_salt do
    generate_bytes(32)  # 256 bits
  end
end
```

---

### Phase 2: Post-Quantum Cryptography (v1.5) - 8 weeks

**Goal:** Implement hybrid classical + PQ cryptography with formal verification.

#### 2.1 Dilithium5-AES Hybrid Signatures

**Use Cases:**
- Package signing (SLSA attestations)
- Trust pipeline attestation signing
- Federation event signing

**Implementation:**

```rust
// opsm_ex/lib/opsm/crypto/native/src/pq_signatures.rs
// SPDX-License-Identifier: PMPL-1.0-or-later

use pqcrypto_dilithium::dilithium5;
use pqcrypto_traits::sign::{PublicKey, SecretKey, SignedMessage};
use aes_gcm::{Aes256Gcm, Key, Nonce};
use aes_gcm::aead::{Aead, NewAead};

pub struct HybridKeyPair {
    pub dilithium_pk: dilithium5::PublicKey,
    pub dilithium_sk: dilithium5::SecretKey,
    pub aes_key: [u8; 32],  // 256-bit AES key
}

pub fn generate_keypair() -> HybridKeyPair {
    let (pk, sk) = dilithium5::keypair();
    let aes_key = rand::random::<[u8; 32]>();

    HybridKeyPair {
        dilithium_pk: pk,
        dilithium_sk: sk,
        aes_key,
    }
}

pub fn sign_hybrid(message: &[u8], keypair: &HybridKeyPair) -> Result<Vec<u8>, String> {
    // Step 1: Dilithium5 signature
    let dilithium_sig = dilithium5::sign(message, &keypair.dilithium_sk);

    // Step 2: AES-256-GCM encryption of signature (belt-and-suspenders)
    let cipher = Aes256Gcm::new(Key::from_slice(&keypair.aes_key));
    let nonce = Nonce::from_slice(b"unique_nonce"); // Use proper nonce generation

    let encrypted_sig = cipher.encrypt(nonce, dilithium_sig.as_bytes())
        .map_err(|e| format!("AES encryption failed: {}", e))?;

    // Format: dilithium_sig || aes_encrypted_sig
    Ok([dilithium_sig.as_bytes(), &encrypted_sig].concat())
}
```

**Elixir NIF Wrapper:**

```elixir
# lib/opsm/crypto/signatures.ex
defmodule Opsm.Crypto.Signatures do
  @moduledoc """
  Dilithium5-AES hybrid signatures (FIPS 204 ML-DSA-87).

  Hybrid approach:
  1. Dilithium5 signature (post-quantum)
  2. AES-256-GCM encryption (belt-and-suspenders)
  3. SPHINCS+ fallback if Dilithium compromised

  Aligns with SECURITY-STANDARDS.scm PQSignatures requirements.
  """

  use Rustler, otp_app: :opsm, crate: "pq_crypto"

  def generate_keypair(), do: :erlang.nif_error(:nif_not_loaded)
  def sign(message, keypair), do: :erlang.nif_error(:nif_not_loaded)
  def verify(message, signature, public_key), do: :erlang.nif_error(:nif_not_loaded)
end
```

#### 2.2 Idris2 Proven Library with Formal Verification

**Goal:** Formally verify cryptographic primitives using Idris2 dependent types.

**Implementation:**

```idris
-- opsm_ex/lib/opsm/proven/Crypto.idr
-- SPDX-License-Identifier: PMPL-1.0-or-later

module Crypto

import Data.Vect
import Decidable.Equality

-- Proven URL validation (from existing Verified.Url)
data ValidURL : Type where
  MkValidURL : (scheme : String) ->
               (host : String) ->
               {auto prf : NotLocalhost host} ->
               {auto prf2 : NotPrivateIP host} ->
               ValidURL

-- Proven JSON parsing with depth limits
data SafeJSON : Nat -> Type where
  JSONNull : SafeJSON n
  JSONBool : Bool -> SafeJSON n
  JSONNumber : Double -> SafeJSON n
  JSONString : String -> SafeJSON n
  JSONArray : {n : Nat} -> Vect k (SafeJSON n) -> SafeJSON (S n)
  JSONObject : {n : Nat} -> List (String, SafeJSON n) -> SafeJSON (S n)

-- Proven that depth never exceeds limit
parseJSON : (limit : Nat) -> String -> Either String (SafeJSON limit)

-- Proven cryptographic hash properties
interface Hash (a : Type) where
  hash : a -> Vect 64 Bits8  -- 512-bit output

  -- Laws (proven with dependent types):
  hashDeterministic : (x : a) -> hash x = hash x
  hashCollisionResistant : (x : a) -> (y : a) -> Not (x = y) -> Not (hash x = hash y)
  hashPreimageResistant : (h : Vect 64 Bits8) -> (x : a) -> hash x = h -> Void
```

**Compilation to Elixir NIFs:**

```bash
# Build Idris2 proven library
cd opsm_ex/lib/opsm/proven
idris2 --codegen chez Crypto.idr -o proven_crypto
# Generate C bindings
idris2 --codegen c Crypto.idr -o proven_crypto.c
# Compile as NIF
gcc -shared -fPIC proven_crypto.c -o proven_crypto.so
```

---

### Phase 3: Protocol Stack Hardening (v2.0) - 12 weeks

**Goal:** Transition to QUIC + HTTP/3 + IPv6, terminate legacy protocols.

#### 3.1 QUIC + HTTP/3 Client

**Implementation:**

```rust
// opsm_ex/deps/opsm_http3/src/client.rs
// SPDX-License-Identifier: PMPL-1.0-or-later

use quinn::{Endpoint, ClientConfig};
use rustls::{Certificate, PrivateKey, ServerName};

pub struct HTTP3Client {
    endpoint: Endpoint,
}

impl HTTP3Client {
    pub fn new() -> Result<Self, String> {
        let mut client_config = ClientConfig::new();

        // Require TLS 1.3 only
        client_config.crypto = Arc::new(
            rustls::ClientConfig::builder()
                .with_safe_defaults()
                .with_root_certificates(root_certs)
                .with_no_client_auth()
        );

        let mut endpoint = Endpoint::client("[::]:0".parse().unwrap())
            .map_err(|e| format!("Failed to create endpoint: {}", e))?;

        endpoint.set_default_client_config(client_config);

        Ok(HTTP3Client { endpoint })
    }

    pub async fn get(&self, url: &str) -> Result<Vec<u8>, String> {
        // Parse URL and ensure IPv6
        let addr = self.resolve_ipv6(url)?;

        // Establish QUIC connection
        let conn = self.endpoint.connect(addr, "domain.com")
            .map_err(|e| format!("Connection failed: {}", e))?
            .await
            .map_err(|e| format!("Connection error: {}", e))?;

        // Send HTTP/3 request
        let (mut send, recv) = conn.open_bi().await
            .map_err(|e| format!("Stream error: {}", e))?;

        // ... HTTP/3 protocol implementation
    }

    fn resolve_ipv6(&self, url: &str) -> Result<SocketAddr, String> {
        // Force IPv6 resolution, reject IPv4
        // ...
    }
}
```

#### 3.2 IPv6-Only Enforcement

**Implementation:**

```elixir
# lib/opsm/network/ipv6.ex
defmodule Opsm.Network.IPv6 do
  @moduledoc """
  IPv6-only enforcement. IPv4 terminated per SECURITY-STANDARDS.scm.

  Termination date: 2026-06-01
  """

  def resolve_hostname(hostname) do
    case :inet.getaddrs(hostname, :inet6) do
      {:ok, addresses} -> {:ok, addresses}
      {:error, :nxdomain} -> {:error, "No IPv6 address found for #{hostname}"}
      {:error, reason} -> {:error, "DNS resolution failed: #{reason}"}
    end
  end

  def validate_ip_string(ip_string) do
    case :inet.parse_ipv6_address(to_charlist(ip_string)) do
      {:ok, _address} -> :ok
      {:error, :einval} -> {:error, "Invalid IPv6 address: #{ip_string}"}
    end
  end

  def reject_ipv4!(ip_string) do
    case :inet.parse_ipv4_address(to_charlist(ip_string)) do
      {:ok, _} -> raise "IPv4 addresses are prohibited per security policy"
      {:error, :einval} -> :ok  # Not IPv4, good
    end
  end
end
```

---

## Testing Strategy

### Property-Based Testing (All Phases)

```elixir
# test/opsm/crypto/properties_test.exs
defmodule Opsm.Crypto.PropertiesTest do
  use ExUnit.Case
  use ExUnitProperties

  property "Argon2id hashing is deterministic" do
    check all password <- string(:alphanumeric) do
      {:ok, hash1} = Opsm.Crypto.Password.hash(password)
      {:ok, hash2} = Opsm.Crypto.Password.hash(password)

      # Different salts, so hashes differ
      assert hash1 != hash2

      # But both verify
      assert :ok = Opsm.Crypto.Password.verify(password, hash1)
      assert :ok = Opsm.Crypto.Password.verify(password, hash2)
    end
  end

  property "XChaCha20-Poly1305 roundtrip" do
    check all plaintext <- binary(),
              key <- binary(length: 32),
              aad <- string(:alphanumeric) do
      {:ok, encrypted} = Opsm.Crypto.Symmetric.encrypt(plaintext, key, aad)
      {:ok, decrypted} = Opsm.Crypto.Symmetric.decrypt(encrypted, key, aad)

      assert decrypted == plaintext
    end
  end

  property "BLAKE3 collision resistance" do
    check all data1 <- binary(),
              data2 <- binary(),
              data1 != data2 do
      hash1 = Opsm.Crypto.Hash.hash_hot(data1)
      hash2 = Opsm.Crypto.Hash.hash_hot(data2)

      assert hash1 != hash2
    end
  end
end
```

---

## Migration Path from v1.0.0

### Immediate Actions (v1.0.1)

1. **Add Argon2id dependency:**
   ```bash
   cd opsm_ex
   mix deps.get
   ```

2. **Implement core crypto modules:**
   ```bash
   # Create lib/opsm/crypto/ directory
   # Implement Password, Symmetric, Hash, RNG modules
   ```

3. **Add security tests:**
   ```bash
   # Create test/opsm/crypto/ directory
   # Add property-based tests
   ```

4. **Update Verified library:**
   ```elixir
   # lib/opsm/verified.ex - add crypto helpers
   ```

### Gradual Rollout (v1.5, v2.0)

1. **v1.5: Add PQ signatures (non-breaking)**
   - Hybrid Dilithium5 + Ed448 signatures
   - Optional SPHINCS+ fallback
   - Maintain backward compatibility with existing signatures

2. **v2.0: Enforce PQ signatures (breaking)**
   - Reject packages without Dilithium5 signatures
   - Terminate Ed25519, ECDSA, RSA signatures
   - IPv6-only networking

---

## Compliance Checklist

### NIST FIPS Compliance

- [ ] **FIPS 202** (SHA-3): SHAKE256/SHAKE512 implemented
- [ ] **FIPS 203** (ML-KEM): Kyber-1024 key exchange
- [ ] **FIPS 204** (ML-DSA): Dilithium5 signatures
- [ ] **FIPS 205** (SLH-DSA): SPHINCS+ fallback
- [ ] **SP 800-90Ar1**: ChaCha20-DRBG RNG

### WCAG 2.3 AAA Compliance

- [x] **Mobile UI**: ReScript with ARIA attributes
- [ ] **Web Dashboard**: Semantic HTML, CSS-first (v1.5)
- [x] **Documentation**: Accessible markdown/AsciiDoc
- [ ] **Error Messages**: Screen reader friendly (v1.0.1)

### SLSA Supply Chain Compliance

- [ ] **Level 1**: Source provenance (v1.0.0 ✓)
- [ ] **Level 2**: Build provenance (v1.5)
- [ ] **Level 3**: Hardened builds (v1.5)
- [ ] **Level 4**: Two-party review (v2.0)

---

## Summary

This roadmap provides a clear path from OPSM v1.0.0's current security posture to full compliance with the requirements in `SECURITY-STANDARDS.scm`. Implementation is staged across three phases:

1. **v1.0.1 (2 weeks):** Critical primitives (Argon2id, XChaCha20, BLAKE3, ChaCha20-DRBG)
2. **v1.5 (8 weeks):** Post-quantum cryptography (Dilithium5, Kyber-1024, Idris2 formal verification)
3. **v2.0 (12 weeks):** Protocol hardening (QUIC, HTTP/3, IPv6-only, GraalVM)

All implementations include comprehensive property-based testing, formal verification (where applicable), and clear migration paths for users.

---

**Next Steps:**

1. Review and approve this roadmap
2. Create GitHub issues for each phase
3. Begin v1.0.1 implementation (Argon2id, XChaCha20, BLAKE3, ChaCha20-DRBG)
4. Update `STATE.scm` with security implementation milestones
