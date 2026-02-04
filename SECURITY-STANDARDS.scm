;;; SECURITY-STANDARDS.scm — OPSM Cryptographic Security Requirements
;;; SPDX-License-Identifier: PMPL-1.0-or-later
;;; Media Type: application/vnd.security-policy+scm

;; This file defines the cryptographic and security requirements for OPSM
;; (Odds and Sods Package Manager) across all components: CLI, mobile, trust
;; pipeline, federation, and storage layers.

(define security-requirements
  '((metadata
      (version . "1.0.0")
      (schema-version . "2026-02-04")
      (created . "2026-02-04")
      (last-updated . "2026-02-04")
      (project . "OPSM (Odds and Sods Package Manager)")
      (authority . "Jonathan D.A. Jewell")
      (compliance . ("NIST FIPS 202" "NIST FIPS 203" "NIST FIPS 204" "NIST SP 800-90Ar1" "WCAG 2.3 AAA")))

    (cryptographic-primitives
      ;; Password Hashing (User Credentials, API Keys)
      ((category . "PasswordHashing")
       (algorithm . "Argon2id")
       (parameters . "memory=512MiB iterations=8 lanes=4")
       (standard . "—")
       (rationale . "Maximum memory/iterations for GPU/ASIC resistance; aligns with proactive security stance.")
       (use-cases . ("user-authentication" "API-key-storage" "lockfile-integrity"))
       (implementation . "rust-argon2 crate with explicit parameters")
       (status . "required"))

      ;; General Hashing (Provenance, Key Derivation, Long-term Storage)
      ((category . "GeneralHashing")
       (algorithm . "SHAKE3-512")
       (output-size . "512-bit")
       (standard . "FIPS 202")
       (rationale . "Post-quantum secure; use for provenance, key derivation, and long-term storage.")
       (use-cases . ("package-provenance" "tarball-checksums" "content-addressing" "lockfile-hashing"))
       (implementation . "sha3 crate with SHAKE256 (SHAKE3 when standardized)")
       (fallback . "BLAKE3 (512-bit) for performance-critical paths")
       (status . "required"))

      ;; Post-Quantum Digital Signatures (Package Signing, Attestations)
      ((category . "PQSignatures")
       (algorithm . "Dilithium5-AES (hybrid)")
       (standard . "ML-DSA-87 (FIPS 204)")
       (rationale . "Hybrid with AES-256 for belt-and-suspenders security. SPHINCS+ as conservative backup.")
       (use-cases . ("package-signing" "attestation-signing" "trust-pipeline-verification"))
       (implementation . "pqcrypto-dilithium crate + AES-256-GCM hybrid wrapper")
       (fallback . "SPHINCS+ (FIPS 205) for conservative PQ backup")
       (status . "required-v1.5"))

      ;; Post-Quantum Key Exchange (Federation, Mirror Communication)
      ((category . "PQKeyExchange")
       (algorithm . "Kyber-1024 + SHAKE256-KDF")
       (standard . "ML-KEM-1024 (FIPS 203)")
       (rationale . "Kyber-1024 for KEM, SHAKE256 for key derivation. SPHINCS+ as backup.")
       (use-cases . ("federation-key-exchange" "mirror-synchronization" "trust-service-communication"))
       (implementation . "pqcrypto-kyber crate + sha3 SHAKE256")
       (fallback . "SPHINCS+ for key exchange if Kyber compromised")
       (status . "required-v2.0"))

      ;; Classical Digital Signatures (Hybrid with PQ)
      ((category . "ClassicalSigs")
       (algorithm . "Ed448 + Dilithium5 (hybrid)")
       (standard . "—")
       (rationale . "Ed448 for classical compatibility; Dilithium5 for PQ. SPHINCS+ as backup. Terminate Ed25519/SHA-1 immediately.")
       (use-cases . ("git-commit-signing" "legacy-compatibility" "hybrid-verification"))
       (implementation . "ed25519-dalek (Ed448 when available) + pqcrypto-dilithium")
       (deprecated . ("Ed25519" "ECDSA-P256" "RSA" "SHA-1"))
       (termination-date . "2026-06-01")
       (status . "required-v1.5"))

      ;; Symmetric Encryption (Package Content, Lockfile Encryption)
      ((category . "Symmetric")
       (algorithm . "XChaCha20-Poly1305")
       (key-size . "256-bit")
       (standard . "—")
       (rationale . "Larger nonce space; 256-bit keys for quantum margin.")
       (use-cases . ("lockfile-encryption" "sensitive-config" "credential-storage"))
       (implementation . "chacha20poly1305 crate with XChaCha20 variant")
       (status . "required"))

      ;; Key Derivation (All Secret Key Material)
      ((category . "KeyDerivation")
       (algorithm . "HKDF-SHAKE512")
       (standard . "FIPS 202")
       (rationale . "Post-quantum KDF; use with all secret key material.")
       (use-cases . ("API-key-derivation" "session-keys" "encryption-keys"))
       (implementation . "hkdf crate + sha3 SHAKE512")
       (status . "required"))

      ;; Random Number Generation (Cryptographic Randomness)
      ((category . "RNG")
       (algorithm . "ChaCha20-DRBG")
       (seed-size . "512-bit")
       (standard . "SP 800-90Ar1")
       (rationale . "CSPRNG for deterministic, high-entropy needs.")
       (use-cases . ("key-generation" "nonce-generation" "salt-generation"))
       (implementation . "rand_chacha crate with ChaCha20Core")
       (status . "required"))

      ;; User-Friendly Hash Names (Driver Identification, Human-Readable IDs)
      ((category . "UserFriendlyHashNames")
       (algorithm . "Base32(SHAKE256(hash)) → Wordlist")
       (standard . "—")
       (rationale . "Memorable, deterministic mapping (e.g., \"Gigantic-Giraffe-7\" for drivers).")
       (use-cases . ("package-version-names" "mirror-identification" "HAR-task-IDs"))
       (implementation . "custom wordlist generator with SHAKE256 + base32")
       (wordlist . "PGP wordlist or custom curated list")
       (status . "required-v1.5"))

      ;; Database Hashing (Content-Addressed Storage, Metadata Integrity)
      ((category . "DatabaseHashing")
       (algorithm . "BLAKE3 (512-bit) + SHAKE3-512")
       (standard . "—")
       (rationale . "BLAKE3 for speed, SHAKE3-512 for long-term storage (semantic XML/ARIA tags).")
       (use-cases . ("package-content-addressing" "metadata-hashing" "cache-keys"))
       (implementation . "blake3 crate for hot paths, sha3 for cold storage")
       (status . "required"))

      ;; Fallback for All Hybrid Systems
      ((category . "Fallback")
       (algorithm . "SPHINCS+")
       (standard . "FIPS 205 (draft)")
       (rationale . "Conservative PQ backup for all hybrid classical+PQ systems; use if primary PQ algorithm is ever compromised.")
       (use-cases . ("emergency-fallback" "conservative-signature-verification" "long-term-archival"))
       (implementation . "pqcrypto-sphincsplus crate")
       (status . "required-v1.5")))

    (infrastructure-security
      ;; Semantic XML/GraphQL Database
      ((category . "SemanticXMLGraphQL")
       (technology . "Virtuoso (VOS) + SPARQL 1.2")
       (standard . "—")
       (rationale . "Supports WCAG 2.3 AAA, ARIA, and formal verification for accessibility/compliance.")
       (use-cases . ("package-metadata-storage" "provenance-graphs" "accessibility-data"))
       (implementation . "OpenLink Virtuoso Open-Source Edition")
       (status . "required-v2.0"))

      ;; VM Execution Environment
      ((category . "VMExecution")
       (technology . "GraalVM (with formal verification)")
       (standard . "—")
       (rationale . "Aligns with preference for introspective, reversible design.")
       (use-cases . ("polyglot-runtime" "sandboxed-package-execution" "formal-verification"))
       (implementation . "GraalVM CE with Truffle framework")
       (status . "required-v2.0"))

      ;; Network Protocol Stack
      ((category . "ProtocolStack")
       (protocols . "QUIC + HTTP/3 + IPv6")
       (deprecated . ("HTTP/1.1" "IPv4" "SHA-1"))
       (standard . "—")
       (rationale . "Terminate HTTP/1.1, IPv4, and SHA-1 per \"danger zone\" policy.")
       (use-cases . ("federation-communication" "registry-fetches" "trust-service-APIs"))
       (implementation . "reqwest with HTTP/3 + quinn QUIC")
       (termination-date . "2026-06-01")
       (status . "required-v2.0"))

      ;; Accessibility Compliance
      ((category . "Accessibility")
       (standards . "WCAG 2.3 AAA + ARIA + Semantic XML")
       (rationale . "CSS-first, HTML-second; full compliance with accessibility requirements.")
       (use-cases . ("mobile-UI" "web-dashboard" "documentation" "error-messages"))
       (implementation . "ReScript TEA with ARIA attributes, semantic HTML")
       (status . "required"))

      ;; Formal Verification
      ((category . "FormalVerification")
       (tools . "Coq/Isabelle (for crypto primitives)")
       (standard . "—")
       (rationale . "Proactive attestation and transparent logic per system design principles.")
       (use-cases . ("verified-library" "cryptographic-proofs" "protocol-correctness"))
       (implementation . "Idris2 proven library with Coq/Isabelle proofs (v1.5)")
       (status . "required-v1.5")))

    (implementation-priorities
      (v1.0
        "Argon2id password hashing"
        "SHAKE256 general hashing (SHAKE3-512 when standardized)"
        "XChaCha20-Poly1305 symmetric encryption"
        "HKDF-SHAKE512 key derivation"
        "ChaCha20-DRBG random number generation"
        "BLAKE3 + SHAKE256 database hashing"
        "WCAG 2.3 AAA accessibility compliance")

      (v1.5
        "Dilithium5-AES hybrid signatures"
        "Ed448 + Dilithium5 hybrid classical signatures"
        "SPHINCS+ fallback implementation"
        "User-friendly hash names (wordlist mapping)"
        "Idris2 proven library with formal verification"
        "Terminate Ed25519, ECDSA-P256, RSA, SHA-1")

      (v2.0
        "Kyber-1024 + SHAKE256-KDF key exchange"
        "QUIC + HTTP/3 + IPv6 protocol stack"
        "Virtuoso + SPARQL 1.2 semantic database"
        "GraalVM formal verification runtime"
        "Disable IPv4, HTTP/1.1, HTTP/2 support"))

    (security-policy
      (threat-model
        "OPSM assumes adversaries with quantum computers (Grover's algorithm, Shor's algorithm)"
        "Supply chain attacks (malicious packages, typosquatting, dependency confusion)"
        "Network adversaries (MITM, traffic analysis, replay attacks)"
        "Insider threats (malicious registry operators, compromised trust services)"
        "Physical access (side-channel attacks, cold boot attacks)")

      (trust-boundaries
        "User's local machine (trusted computing base)"
        "OPSM CLI and mobile wrapper (trusted)"
        "Phoenix API (trusted within localhost boundary)"
        "Trust services (semi-trusted, verified via attestations)"
        "Package registries (untrusted, verified via trust pipeline)"
        "Network infrastructure (untrusted, encrypted and authenticated)")

      (defense-in-depth
        "Hybrid classical + PQ cryptography (belt-and-suspenders)"
        "Formal verification of critical components (Idris2 proven library)"
        "Property-based testing (40 security tests)"
        "SPHINCS+ fallback for all PQ systems"
        "Explicit error handling (Result monad, no panics)"
        "Input validation (Verified library: URL, JSON, Result)"
        "Sandboxed execution (GraalVM, capability-based security)")

      (compliance-requirements
        "FIPS 202: SHA-3 family (SHAKE256, SHAKE512)"
        "FIPS 203: ML-KEM (Kyber-1024)"
        "FIPS 204: ML-DSA (Dilithium5)"
        "FIPS 205: SLH-DSA (SPHINCS+)"
        "SP 800-90Ar1: Deterministic Random Bit Generators (ChaCha20-DRBG)"
        "WCAG 2.3 AAA: Accessibility (UI, documentation, error messages)"
        "GDPR: Data privacy (no telemetry without consent, right to be forgotten)"
        "SLSA: Supply chain levels (v1.5+)"))

    (deprecation-schedule
      ((algorithm . "Ed25519")
       (reason . "Quantum vulnerability (Shor's algorithm)")
       (replacement . "Ed448 + Dilithium5 hybrid")
       (termination-date . "2026-06-01")
       (migration-path . "Hybrid signatures in v1.5, Ed25519 disabled in v2.0"))

      ((algorithm . "SHA-1")
       (reason . "Collision attacks, quantum vulnerability")
       (replacement . "SHAKE3-512")
       (termination-date . "2026-02-04")
       (migration-path . "Immediate termination, SHAKE256 required"))

      ((algorithm . "ECDSA-P256")
       (reason . "Quantum vulnerability (Shor's algorithm)")
       (replacement . "Ed448 + Dilithium5 hybrid")
       (termination-date . "2026-06-01")
       (migration-path . "Hybrid signatures in v1.5, ECDSA disabled in v2.0"))

      ((algorithm . "RSA")
       (reason . "Quantum vulnerability (Shor's algorithm), large key sizes")
       (replacement . "Dilithium5-AES")
       (termination-date . "2026-06-01")
       (migration-path . "Dilithium5 in v1.5, RSA disabled in v2.0"))

      ((protocol . "IPv4")
       (reason . "Security concerns, address exhaustion")
       (replacement . "IPv6")
       (termination-date . "2026-06-01")
       (migration-path . "IPv6-only in v2.0, dual-stack in v1.5"))

      ((protocol . "HTTP/1.1")
       (reason . "Cleartext headers, performance, security issues")
       (replacement . "HTTP/3 + QUIC")
       (termination-date . "2026-06-01")
       (migration-path . "HTTP/3 in v2.0, HTTP/2 fallback in v1.5")))

    (monitoring-and-response
      (security-events
        "Failed authentication attempts (Argon2id verification)"
        "Invalid signatures (Dilithium5, Ed448, SPHINCS+)"
        "Checksum mismatches (SHAKE256, BLAKE3)"
        "Trust pipeline failures (attestation, verification, license)"
        "Network anomalies (QUIC connection failures, certificate issues)")

      (incident-response
        "Automated rollback to SPHINCS+ if Dilithium5/Kyber compromised"
        "Lockfile integrity verification on every operation"
        "Trust service health monitoring (5 microservices)"
        "HAR agent failure detection and fallback to manual review"
        "Federation event propagation for security advisories")

      (audit-logging
        "All cryptographic operations (with algorithm, key size, timestamp)"
        "All package installations (with provenance, attestations)"
        "All trust pipeline verifications (with service responses)"
        "All federation events (with signatures, timestamps)"
        "All user actions (with consent, privacy-preserving)"))))

;; Export for programmatic access
(define (get-algorithm category)
  "Return the algorithm specification for a given security category."
  (let ((primitives (assoc 'cryptographic-primitives security-requirements)))
    (filter (lambda (spec) (equal? (assoc 'category spec) category))
            (cdr primitives))))

(define (get-implementation-priority version)
  "Return the implementation priorities for a given OPSM version."
  (let ((priorities (assoc 'implementation-priorities security-requirements)))
    (assoc version (cdr priorities))))

(define (is-deprecated? algorithm)
  "Check if an algorithm or protocol is deprecated."
  (let ((schedule (assoc 'deprecation-schedule security-requirements)))
    (any (lambda (entry)
           (or (equal? (assoc 'algorithm entry) algorithm)
               (equal? (assoc 'protocol entry) algorithm)))
         (cdr schedule))))
