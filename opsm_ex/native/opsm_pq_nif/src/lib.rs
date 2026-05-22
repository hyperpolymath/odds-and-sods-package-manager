// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// Post-quantum cryptographic NIFs for OPSM.
//
// Implements:
// - ML-DSA-87 (Dilithium5)  -- FIPS 204 digital signatures
// - SLH-DSA (SPHINCS+-256f) -- FIPS 205 hash-based signatures
// - ML-KEM-1024 (Kyber-1024) -- FIPS 203 key encapsulation

#![forbid(unsafe_code)]
use pqcrypto_dilithium::dilithium5;
use pqcrypto_kyber::kyber1024;
use pqcrypto_sphincsplus::sphincsshake256fsimple as sphincs;
use pqcrypto_traits::kem::{
    Ciphertext as KemCiphertext, PublicKey as KemPk, SecretKey as KemSk, SharedSecret,
};
use pqcrypto_traits::sign::{
    PublicKey as SignPk, SecretKey as SignSk, SignedMessage,
};
use rustler::{Binary, Encoder, Env, NewBinary, Term};

mod atoms {
    rustler::atoms! {
        ok,
        error,
        public_key,
        secret_key,
        algorithm,
        dilithium5,
        sphincs_plus,
        kyber1024,
        ciphertext,
        shared_secret,
    }
}

// =============================================================================
// ML-DSA-87 (Dilithium5) -- FIPS 204
// =============================================================================

/// Generate a Dilithium5 key pair.
///
/// Returns `{:ok, %{public_key: <<...>>, secret_key: <<...>>, algorithm: :dilithium5}}`.
/// Public key: 2592 bytes, secret key: 4896 bytes.
#[rustler::nif]
fn dilithium5_keypair(env: Env) -> Term {
    let (pk, sk) = dilithium5::keypair();
    let pk_bytes = pk.as_bytes();
    let sk_bytes = sk.as_bytes();

    let mut pk_bin = NewBinary::new(env, pk_bytes.len());
    pk_bin.as_mut_slice().copy_from_slice(pk_bytes);

    let mut sk_bin = NewBinary::new(env, sk_bytes.len());
    sk_bin.as_mut_slice().copy_from_slice(sk_bytes);

    let map = Term::map_new(env);
    let map = map
        .map_put(
            atoms::public_key().encode(env),
            Binary::from(pk_bin).to_term(env),
        )
        .unwrap();
    let map = map
        .map_put(
            atoms::secret_key().encode(env),
            Binary::from(sk_bin).to_term(env),
        )
        .unwrap();
    let map = map
        .map_put(
            atoms::algorithm().encode(env),
            atoms::dilithium5().encode(env),
        )
        .unwrap();

    (atoms::ok(), map).encode(env)
}

/// Sign a message with Dilithium5.
///
/// Uses the `sign` (combined) API which produces a signed message blob
/// containing both the signature and the original message data.
/// Returns `{:ok, <<signed_message>>}` or `{:error, reason}`.
#[rustler::nif]
fn dilithium5_sign<'a>(env: Env<'a>, message: Binary<'a>, secret_key: Binary<'a>) -> Term<'a> {
    match dilithium5::SecretKey::from_bytes(secret_key.as_slice()) {
        Ok(sk) => {
            let sm = dilithium5::sign(message.as_slice(), &sk);
            let sig_bytes = sm.as_bytes();

            let mut sig_bin = NewBinary::new(env, sig_bytes.len());
            sig_bin.as_mut_slice().copy_from_slice(sig_bytes);

            (atoms::ok(), Binary::from(sig_bin)).encode(env)
        }
        Err(_) => (atoms::error(), "Invalid secret key").encode(env),
    }
}

/// Verify a Dilithium5 signature.
///
/// Expects `signature` to be the signed message blob produced by `dilithium5_sign/2`.
/// Reconstructs the `SignedMessage` and calls `open` to verify + extract.
/// Returns `:ok` on success or `{:error, reason}` on failure.
#[rustler::nif]
fn dilithium5_verify<'a>(
    env: Env<'a>,
    message: Binary<'a>,
    signature: Binary<'a>,
    public_key: Binary<'a>,
) -> Term<'a> {
    match dilithium5::PublicKey::from_bytes(public_key.as_slice()) {
        Ok(pk) => {
            // signature is the full signed-message blob from sign() (sig || msg).
            match dilithium5::SignedMessage::from_bytes(signature.as_slice()) {
                Ok(sm) => match dilithium5::open(&sm, &pk) {
                    Ok(opened) => {
                        // Verify the opened message matches the expected message.
                        if opened == message.as_slice() {
                            atoms::ok().encode(env)
                        } else {
                            (atoms::error(), "Message mismatch").encode(env)
                        }
                    }
                    Err(_) => (atoms::error(), "Signature verification failed").encode(env),
                },
                Err(_) => (atoms::error(), "Invalid signed message format").encode(env),
            }
        }
        Err(_) => (atoms::error(), "Invalid public key").encode(env),
    }
}

// =============================================================================
// SLH-DSA (SPHINCS+-256f) -- FIPS 205
// =============================================================================

/// Generate a SPHINCS+-256f key pair.
///
/// Returns `{:ok, %{public_key: <<...>>, secret_key: <<...>>, algorithm: :sphincs_plus}}`.
/// Public key: 64 bytes, secret key: 128 bytes.
/// Signatures are large (~49856 bytes) but security relies only on hash
/// function preimage resistance (conservative fallback).
#[rustler::nif]
fn sphincs_plus_keypair(env: Env) -> Term {
    let (pk, sk) = sphincs::keypair();
    let pk_bytes = pk.as_bytes();
    let sk_bytes = sk.as_bytes();

    let mut pk_bin = NewBinary::new(env, pk_bytes.len());
    pk_bin.as_mut_slice().copy_from_slice(pk_bytes);

    let mut sk_bin = NewBinary::new(env, sk_bytes.len());
    sk_bin.as_mut_slice().copy_from_slice(sk_bytes);

    let map = Term::map_new(env);
    let map = map
        .map_put(
            atoms::public_key().encode(env),
            Binary::from(pk_bin).to_term(env),
        )
        .unwrap();
    let map = map
        .map_put(
            atoms::secret_key().encode(env),
            Binary::from(sk_bin).to_term(env),
        )
        .unwrap();
    let map = map
        .map_put(
            atoms::algorithm().encode(env),
            atoms::sphincs_plus().encode(env),
        )
        .unwrap();

    (atoms::ok(), map).encode(env)
}

/// Sign a message with SPHINCS+-256f.
///
/// Returns `{:ok, <<signed_message>>}` or `{:error, reason}`.
/// Signed message is large (~49856 + message_len bytes).
#[rustler::nif]
fn sphincs_plus_sign<'a>(env: Env<'a>, message: Binary<'a>, secret_key: Binary<'a>) -> Term<'a> {
    match sphincs::SecretKey::from_bytes(secret_key.as_slice()) {
        Ok(sk) => {
            let sm = sphincs::sign(message.as_slice(), &sk);
            let sig_bytes = sm.as_bytes();

            let mut sig_bin = NewBinary::new(env, sig_bytes.len());
            sig_bin.as_mut_slice().copy_from_slice(sig_bytes);

            (atoms::ok(), Binary::from(sig_bin)).encode(env)
        }
        Err(_) => (atoms::error(), "Invalid secret key").encode(env),
    }
}

/// Verify a SPHINCS+-256f signature.
///
/// Scheduled on DirtyCpu because SPHINCS+ verification is computationally
/// expensive and should not block the BEAM scheduler.
/// Returns `:ok` on success or `{:error, reason}` on failure.
#[rustler::nif(schedule = "DirtyCpu")]
fn sphincs_plus_verify<'a>(
    env: Env<'a>,
    message: Binary<'a>,
    signature: Binary<'a>,
    public_key: Binary<'a>,
) -> Term<'a> {
    match sphincs::PublicKey::from_bytes(public_key.as_slice()) {
        Ok(pk) => {
            // signature is the full signed-message blob from sign() (sig || msg).
            match sphincs::SignedMessage::from_bytes(signature.as_slice()) {
                Ok(sm) => match sphincs::open(&sm, &pk) {
                    Ok(opened) => {
                        if opened == message.as_slice() {
                            atoms::ok().encode(env)
                        } else {
                            (atoms::error(), "Message mismatch").encode(env)
                        }
                    }
                    Err(_) => (atoms::error(), "Signature verification failed").encode(env),
                },
                Err(_) => (atoms::error(), "Invalid signed message format").encode(env),
            }
        }
        Err(_) => (atoms::error(), "Invalid public key").encode(env),
    }
}

// =============================================================================
// ML-KEM-1024 (Kyber-1024) -- FIPS 203
// =============================================================================

/// Generate a Kyber-1024 key pair for key encapsulation.
///
/// Returns `{:ok, %{public_key: <<...>>, secret_key: <<...>>, algorithm: :kyber1024}}`.
/// Public key: 1568 bytes, secret key: 3168 bytes.
#[rustler::nif]
fn kyber1024_keypair(env: Env) -> Term {
    let (pk, sk) = kyber1024::keypair();
    let pk_bytes = pk.as_bytes();
    let sk_bytes = sk.as_bytes();

    let mut pk_bin = NewBinary::new(env, pk_bytes.len());
    pk_bin.as_mut_slice().copy_from_slice(pk_bytes);

    let mut sk_bin = NewBinary::new(env, sk_bytes.len());
    sk_bin.as_mut_slice().copy_from_slice(sk_bytes);

    let map = Term::map_new(env);
    let map = map
        .map_put(
            atoms::public_key().encode(env),
            Binary::from(pk_bin).to_term(env),
        )
        .unwrap();
    let map = map
        .map_put(
            atoms::secret_key().encode(env),
            Binary::from(sk_bin).to_term(env),
        )
        .unwrap();
    let map = map
        .map_put(
            atoms::algorithm().encode(env),
            atoms::kyber1024().encode(env),
        )
        .unwrap();

    (atoms::ok(), map).encode(env)
}

/// Encapsulate a shared secret using the recipient's Kyber-1024 public key.
///
/// Returns `{:ok, %{ciphertext: <<...>>, shared_secret: <<...>>}}`
/// where shared_secret is 32 bytes, or `{:error, reason}`.
#[rustler::nif]
fn kyber1024_encapsulate<'a>(env: Env<'a>, public_key: Binary<'a>) -> Term<'a> {
    match kyber1024::PublicKey::from_bytes(public_key.as_slice()) {
        Ok(pk) => {
            let (ss, ct) = kyber1024::encapsulate(&pk);
            let ct_bytes = ct.as_bytes();
            let ss_bytes = ss.as_bytes();

            let mut ct_bin = NewBinary::new(env, ct_bytes.len());
            ct_bin.as_mut_slice().copy_from_slice(ct_bytes);

            let mut ss_bin = NewBinary::new(env, ss_bytes.len());
            ss_bin.as_mut_slice().copy_from_slice(ss_bytes);

            let map = Term::map_new(env);
            let map = map
                .map_put(
                    atoms::ciphertext().encode(env),
                    Binary::from(ct_bin).to_term(env),
                )
                .unwrap();
            let map = map
                .map_put(
                    atoms::shared_secret().encode(env),
                    Binary::from(ss_bin).to_term(env),
                )
                .unwrap();

            (atoms::ok(), map).encode(env)
        }
        Err(_) => (atoms::error(), "Invalid public key").encode(env),
    }
}

/// Decapsulate a shared secret using the recipient's Kyber-1024 secret key.
///
/// Returns `{:ok, <<shared_secret>>}` (32 bytes) or `{:error, reason}`.
#[rustler::nif]
fn kyber1024_decapsulate<'a>(
    env: Env<'a>,
    ciphertext: Binary<'a>,
    secret_key: Binary<'a>,
) -> Term<'a> {
    match (
        kyber1024::Ciphertext::from_bytes(ciphertext.as_slice()),
        kyber1024::SecretKey::from_bytes(secret_key.as_slice()),
    ) {
        (Ok(ct), Ok(sk)) => {
            let ss = kyber1024::decapsulate(&ct, &sk);
            let ss_bytes = ss.as_bytes();

            let mut ss_bin = NewBinary::new(env, ss_bytes.len());
            ss_bin.as_mut_slice().copy_from_slice(ss_bytes);

            (atoms::ok(), Binary::from(ss_bin)).encode(env)
        }
        _ => (atoms::error(), "Invalid ciphertext or secret key").encode(env),
    }
}

// =============================================================================
// NIF registration
// =============================================================================

rustler::init!("Elixir.Opsm.Crypto.PostQuantum.Nif");
