# OPSM Security Standards - Quick Reference

**Authority:** Jonathan D.A. Jewell
**Last Updated:** February 4, 2026
**Full Specification:** `SECURITY-STANDARDS.scm`
**Implementation Plan:** `SECURITY-IMPLEMENTATION-ROADMAP.md`

## 🔐 Cryptographic Primitives Summary

| Category | Algorithm | Standard | Key Size | Status |
|----------|-----------|----------|----------|--------|
| **Password Hashing** | Argon2id | — | 512 MiB, 8 iter, 4 lanes | v1.0.1 |
| **General Hashing** | SHAKE3-512 | FIPS 202 | 512-bit | v1.5 |
| **PQ Signatures** | Dilithium5-AES | ML-DSA-87 (FIPS 204) | — | v1.5 |
| **PQ Key Exchange** | Kyber-1024 | ML-KEM-1024 (FIPS 203) | — | v2.0 |
| **Classical Sigs** | Ed448 + Dilithium5 | — | Hybrid | v1.5 |
| **Symmetric Crypto** | XChaCha20-Poly1305 | — | 256-bit | v1.0.1 |
| **Key Derivation** | HKDF-SHAKE512 | FIPS 202 | — | v1.5 |
| **RNG** | ChaCha20-DRBG | SP 800-90Ar1 | 512-bit seed | v1.0.1 |
| **Database Hash** | BLAKE3 + SHAKE3-512 | — | 512-bit | v1.0.1 |
| **Fallback (PQ)** | SPHINCS+ | FIPS 205 (draft) | — | v1.5 |

## ⚠️ Deprecated Algorithms (Termination: 2026-06-01)

| Algorithm/Protocol | Replacement | Reason |
|-------------------|-------------|--------|
| **Ed25519** | Ed448 + Dilithium5 | Quantum vulnerability (Shor's algorithm) |
| **SHA-1** | SHAKE3-512 | Collision attacks, immediate termination |
| **ECDSA-P256** | Ed448 + Dilithium5 | Quantum vulnerability |
| **RSA** | Dilithium5-AES | Quantum vulnerability, large key sizes |
| **IPv4** | IPv6 | Security concerns, address exhaustion |
| **HTTP/1.1** | HTTP/3 + QUIC | Cleartext headers, security issues |

## 📋 Implementation Checklist

### ✅ v1.0.0 (Current)
- [x] URL validation (SSRF prevention)
- [x] JSON parsing (DoS prevention)
- [x] Result monad (error handling)
- [x] Property-based security tests (40 tests)

### 🔨 v1.0.1 (Next - 2 weeks)
- [ ] Argon2id password hashing
- [ ] XChaCha20-Poly1305 symmetric encryption
- [ ] BLAKE3 + SHAKE256 database hashing
- [ ] ChaCha20-DRBG random number generation

### 🚀 v1.5 (8 weeks)
- [ ] Dilithium5-AES hybrid signatures
- [ ] Ed448 + Dilithium5 classical signatures
- [ ] SPHINCS+ fallback implementation
- [ ] Idris2 proven library with formal verification
- [ ] User-friendly hash names (wordlist mapping)
- [ ] Terminate Ed25519, ECDSA, RSA, SHA-1

### 🌐 v2.0 (12 weeks)
- [ ] Kyber-1024 + SHAKE256-KDF key exchange
- [ ] QUIC + HTTP/3 + IPv6 protocol stack
- [ ] Virtuoso + SPARQL 1.2 semantic database
- [ ] GraalVM formal verification runtime
- [ ] Disable IPv4, HTTP/1.1, HTTP/2

## 🎯 Use Cases by Primitive

### Argon2id (Password Hashing)
```elixir
# API key storage
Opsm.Crypto.Password.hash(api_key)

# Lockfile integrity verification
Opsm.Crypto.Password.verify(lockfile_hash, stored_hash)
```

### XChaCha20-Poly1305 (Symmetric Encryption)
```elixir
# Lockfile encryption
Opsm.Crypto.Symmetric.encrypt(lockfile_json, key, "context")

# Credential storage
Opsm.Crypto.Symmetric.encrypt(trust_service_token, key, "trust-token")
```

### BLAKE3 + SHAKE256 (Hashing)
```elixir
# Content-addressing (hot path)
Opsm.Crypto.Hash.hash_hot(package_tarball)

# Provenance (cold storage, PQ-secure)
Opsm.Crypto.Hash.hash_cold(attestation_data)
```

### Dilithium5-AES (PQ Signatures - v1.5)
```rust
// Package signing
let keypair = generate_keypair();
let signature = sign_hybrid(&package_data, &keypair);
```

## 🛡️ Security Policies

### Threat Model
- **Quantum adversaries** (Grover's algorithm, Shor's algorithm)
- **Supply chain attacks** (malicious packages, dependency confusion)
- **Network adversaries** (MITM, traffic analysis)
- **Insider threats** (compromised registries, trust services)

### Defense-in-Depth Strategy
1. **Hybrid cryptography** (classical + PQ, belt-and-suspenders)
2. **Formal verification** (Idris2 proven library, Coq/Isabelle proofs)
3. **Property-based testing** (40+ security property tests)
4. **SPHINCS+ fallback** (conservative PQ backup if Dilithium/Kyber compromised)
5. **Explicit error handling** (Result monad, no panics)
6. **Input validation** (Verified library: URL, JSON, Result)

### Compliance Standards
- **NIST FIPS 202:** SHA-3 family (SHAKE256, SHAKE512)
- **NIST FIPS 203:** ML-KEM (Kyber-1024)
- **NIST FIPS 204:** ML-DSA (Dilithium5)
- **NIST FIPS 205:** SLH-DSA (SPHINCS+)
- **NIST SP 800-90Ar1:** ChaCha20-DRBG
- **WCAG 2.3 AAA:** Accessibility (UI, docs, errors)
- **SLSA:** Supply chain levels 1-4

## 📚 Documentation

| Document | Purpose |
|----------|---------|
| **SECURITY-STANDARDS.scm** | Complete specification (500+ lines) |
| **SECURITY-IMPLEMENTATION-ROADMAP.md** | Implementation guide with code examples (600+ lines) |
| **SECURITY-QUICK-REFERENCE.md** | This document (quick lookup) |
| **SECURITY.md** | User-facing security policy (existing) |

## 🔗 Dependencies

### Elixir/Erlang
```elixir
{:argon2_elixir, "~> 4.0"}       # Argon2id
{:blake3, "~> 1.0"}              # BLAKE3 hashing
# :crypto (built-in)              # SHAKE256, ChaCha20-DRBG
```

### Rust (NIFs for PQ crypto - v1.5)
```toml
pqcrypto-dilithium = "0.5"       # Dilithium5
pqcrypto-kyber = "0.8"           # Kyber-1024
pqcrypto-sphincsplus = "0.7"     # SPHINCS+
aes-gcm = "0.10"                 # AES-256-GCM (hybrid)
chacha20poly1305 = "0.10"        # XChaCha20-Poly1305
```

### Idris2 (Formal verification - v1.5)
```
idris2 --version >= 0.7.0
```

## 🚨 Migration Path

### Immediate (v1.0.1)
1. Add Argon2id for API key storage
2. Implement XChaCha20-Poly1305 for lockfile encryption
3. Deploy BLAKE3 for content-addressing
4. Use ChaCha20-DRBG for all key generation

### Gradual (v1.5)
1. Add Dilithium5 signatures (optional, hybrid with Ed448)
2. Implement SPHINCS+ fallback
3. Formal verification with Idris2
4. Deprecation warnings for Ed25519, SHA-1, RSA

### Breaking (v2.0)
1. Require Dilithium5 signatures (reject Ed25519, RSA)
2. IPv6-only networking (reject IPv4)
3. HTTP/3 + QUIC only (reject HTTP/1.1, HTTP/2)
4. Kyber-1024 for all key exchange

## 📞 Contact

**Security Issues:** security@hyperpolymath.org
**General Questions:** jonathan.jewell@open.ac.uk
**Documentation:** https://github.com/hyperpolymath/odds-and-sods-package-manager

---

**Remember:** Security is not a feature, it's a foundation. These standards ensure OPSM remains secure against both classical and quantum adversaries for decades to come.
