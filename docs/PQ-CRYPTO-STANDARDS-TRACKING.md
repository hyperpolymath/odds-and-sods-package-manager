# SPDX-License-Identifier: MPL-2.0
# PQ Crypto Standards Tracking

Tracks post-quantum cryptographic algorithm standardization status and OPSM's
migration path from draft names to final NIST standard names.

Author: Jonathan D.A. Jewell
Last updated: 2026-03-10

## Current Algorithms in OPSM

OPSM implements three post-quantum algorithms via Rust NIFs
(`opsm_ex/native/opsm_pq_nif/src/lib.rs` and `opsm_ex/native/pq_crypto/src/lib.rs`):

| Algorithm (Code) | NIST Standard Name | FIPS | Purpose | Security Level |
|-------------------|--------------------|------|---------|----------------|
| Dilithium5 | **ML-DSA-87** | FIPS 204 | Digital signatures | Category 5 |
| Kyber-1024 | **ML-KEM-1024** | FIPS 203 | Key encapsulation | Category 5 |
| SPHINCS+-256f | **SLH-DSA-SHAKE-256f** | FIPS 205 | Hash-based signatures (fallback) | Category 5 |

## NIST Standardization Status

| Standard | Status | Published | Notes |
|----------|--------|-----------|-------|
| FIPS 203 (ML-KEM) | **Final** | August 2024 | Replaces CRYSTALS-Kyber |
| FIPS 204 (ML-DSA) | **Final** | August 2024 | Replaces CRYSTALS-Dilithium |
| FIPS 205 (SLH-DSA) | **Final** | August 2024 | Replaces SPHINCS+ |

All three standards were published as final on 13 August 2024. The draft
names (Dilithium, Kyber, SPHINCS+) are superseded by the official NIST
names (ML-DSA, ML-KEM, SLH-DSA).

## Rust Crate Status

### Current crates (used by OPSM)

| Crate | Version | Status | Advisory |
|-------|---------|--------|----------|
| `pqcrypto-dilithium` | 0.5.x | **Unmaintained** | RUSTSEC-2024-0380 — replaced by `pqcrypto-mldsa` |
| `pqcrypto-kyber` | 0.8.x | **Unmaintained** | RUSTSEC-2024-0381 — replaced by `pqcrypto-mlkem` |
| `pqcrypto-sphincsplus` | 0.7.x | Active | No advisory yet, but SLH-DSA crate expected |
| `pqcrypto-traits` | 0.3.x | Active | Common trait definitions |
| `rustler` | 0.35.x | Active | NIF bridge; 0.37.x available |

### Migration target crates

| New Crate | Replaces | Notes |
|-----------|----------|-------|
| `pqcrypto-mldsa` | `pqcrypto-dilithium` | FIPS 204 final standard names |
| `pqcrypto-mlkem` | `pqcrypto-kyber` | FIPS 203 final standard names |
| `pqcrypto-slhdsa` | `pqcrypto-sphincsplus` | FIPS 205 final standard names (when available) |

### Alternative implementations

| Crate | Notes |
|-------|-------|
| `oqs` / `oqs-sys` | liboqs bindings; covers all algorithms but adds C dependency |
| `ml-kem` | Pure Rust ML-KEM from RustCrypto project |
| `ml-dsa` | Pure Rust ML-DSA from RustCrypto project |
| `slh-dsa` | Pure Rust SLH-DSA from RustCrypto project |

The RustCrypto pure-Rust implementations (`ml-kem`, `ml-dsa`, `slh-dsa`) are
preferable long-term as they avoid C build dependencies and use the final
NIST standard names natively.

## Migration Plan

### Phase 1: Cargo.toml updates (Target: Q2 2026)

Replace deprecated crates in both NIF locations:

```toml
# Before (deprecated)
pqcrypto-dilithium = "0.5"
pqcrypto-kyber = "0.8"

# After (NIST standard names)
pqcrypto-mldsa = "0.1"    # or ml-dsa from RustCrypto
pqcrypto-mlkem = "0.1"    # or ml-kem from RustCrypto
```

### Phase 2: API name migration (Target: Q2 2026)

Update Rust source to use NIST standard function/type names:

| Current (draft) | Target (final) |
|-----------------|----------------|
| `dilithium5::keypair()` | `mldsa87::keypair()` |
| `dilithium5::sign()` | `mldsa87::sign()` |
| `dilithium5::open()` | `mldsa87::open()` |
| `kyber1024::keypair()` | `mlkem1024::keypair()` |
| `kyber1024::encapsulate()` | `mlkem1024::encapsulate()` |
| `kyber1024::decapsulate()` | `mlkem1024::decapsulate()` |
| `sphincsshake256fsimple` | `slhdsa_shake_256f` (TBD) |

### Phase 3: Elixir API migration (Target: Q3 2026)

The NIF module name (`Opsm.Crypto.PostQuantum.Nif`) and Elixir-side atom
names (`:dilithium5`, `:kyber1024`, `:sphincs_plus`) should be updated to
use NIST names (`:ml_dsa_87`, `:ml_kem_1024`, `:slh_dsa_256f`).

Provide backward-compatible aliases during transition period.

### Phase 4: Rustler upgrade (Target: Q2 2026)

Upgrade `rustler` from 0.35.x to 0.37.x in both NIF Cargo.toml files.
The `opsm_pq_nif` NIF already uses the newer `rustler::init!` macro
without explicit function list (v0.35+ syntax), so this should be
straightforward.

## Files Affected

| File | Role |
|------|------|
| `opsm_ex/native/pq_crypto/Cargo.toml` | PQ crypto NIF dependencies |
| `opsm_ex/native/pq_crypto/src/lib.rs` | PQ crypto NIF implementation (has build errors) |
| `opsm_ex/native/opsm_pq_nif/Cargo.toml` | PQ NIF dependencies (primary) |
| `opsm_ex/native/opsm_pq_nif/src/lib.rs` | PQ NIF implementation (builds clean) |

## Audit Notes (2026-03-10)

- `cargo audit` reports RUSTSEC-2024-0380 and RUSTSEC-2024-0381 for the
  deprecated `pqcrypto-dilithium` and `pqcrypto-kyber` crates
- `pq_crypto` NIF has 35 compile errors (pre-existing); `opsm_pq_nif` builds clean
- Both NIFs use identical algorithms but `opsm_pq_nif` is the actively maintained one
- Consider removing the duplicate `pq_crypto` NIF or consolidating
