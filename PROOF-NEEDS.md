<!--
SPDX-License-Identifier: CC-BY-SA-4.0
Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
# PROOF-NEEDS.md — odds-and-sods-package-manager (OPSM)

## Current State

- **src/abi/*.idr**: YES — `Types.idr`, `Layout.idr`, `Foreign.idr`, `opsm-abi.ipkg`
- **Dangerous patterns**: 0 in own code (hits in deps/proven vendored bindings)
- **LOC**: ~102,000 (Elixir + Rust + Idris2 + vendored deps)
- **ABI layer**: Complete Idris2 ABI with ipkg build

## What Needs Proving

| Component | What | Why |
|-----------|------|-----|
| Package installation integrity | Install operations don't corrupt existing packages | Package managers must never break the system |
| Dependency resolution | Resolution algorithm terminates and produces consistent solution | Non-terminating or inconsistent resolution breaks builds |
| PQ crypto (pq_crypto NIF) | Post-quantum cryptographic operations are correct | Package signing with broken crypto is worthless |
| QUIC transport | Transport layer delivers data correctly | Corrupt downloads install wrong packages |
| Verified HTTP (opsm/verified/http.ex) | HTTP operations enforce security policies | Unverified HTTP allows MITM attacks on package downloads |
| Safe exec | Command execution respects sandboxing invariants | Package scripts must not escape sandbox |
| Validation module | Input validation is complete (no bypass paths) | Malformed input to package manager is an attack vector |

## Recommended Prover

**Idris2** — ABI layer already complete with ipkg. Extend with dependency resolution termination proof and package integrity invariants. PQ crypto proofs may need **Coq** with Jasmin/EasyCrypt.

## Priority

**HIGH** — Package managers are high-value attack targets. OPSM handles package installation, dependency resolution, and cryptographic signing. A bug in any of these is a supply chain vulnerability. The PQ crypto NIF is especially critical.
