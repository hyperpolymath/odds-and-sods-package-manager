# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule Opsm.Crypto.PostQuantum do
  @moduledoc """
  Post-quantum cryptographic primitives via Rust NIFs.

  Implements FIPS 204/203/205 algorithms:
  - ML-DSA-87 (Dilithium5) — digital signatures
  - ML-KEM-1024 (Kyber-1024) — key encapsulation
  - SLH-DSA (SPHINCS+-256f) — stateless hash-based signatures (fallback)

  All operations gracefully degrade when the NIF is not loaded,
  returning `{:error, :pq_not_available}`. This allows the system
  to fall back to classical Ed25519 signatures when PQ crypto
  is not compiled.

  Build the NIF: `mix compile` (requires Rust toolchain + Rustler).

  Aligns with SECURITY-STANDARDS.scm Phase 2 requirements.
  """

  @nif_module Opsm.Crypto.PostQuantum.Nif

  # ==========================================================================
  # Availability
  # ==========================================================================

  @doc """
  Check if post-quantum NIF is loaded and available.

  Returns `true` if the Rust NIF is compiled and loaded, `false` otherwise.
  Use this before calling PQ operations to decide whether to use hybrid mode.
  """
  def available? do
    case :persistent_term.get({__MODULE__, :nif_loaded}, nil) do
      nil ->
        loaded =
          try do
            case @nif_module.dilithium5_keypair() do
              {:ok, _} -> true
              _ -> false
            end
          rescue
            _ -> false
          catch
            _, _ -> false
          end

        :persistent_term.put({__MODULE__, :nif_loaded}, loaded)
        loaded

      value ->
        value
    end
  end

  # ==========================================================================
  # ML-DSA-87 (Dilithium5) — Digital Signatures (FIPS 204)
  # ==========================================================================

  @doc """
  Generate a Dilithium5 key pair.

  Returns `{:ok, %{public_key: binary, secret_key: binary, algorithm: :dilithium5}}`
  or `{:error, :pq_not_available}`.

  Key sizes:
  - Public key: 2592 bytes
  - Secret key: 4896 bytes
  """
  def dilithium5_keypair do
    if available?() do
      @nif_module.dilithium5_keypair()
    else
      {:error, :pq_not_available}
    end
  end

  @doc """
  Sign a message with Dilithium5.

  Returns `{:ok, signature}` where signature is ~4627 bytes,
  or `{:error, reason}`.
  """
  def dilithium5_sign(message, secret_key) when is_binary(message) and is_binary(secret_key) do
    if available?() do
      @nif_module.dilithium5_sign(message, secret_key)
    else
      {:error, :pq_not_available}
    end
  end

  @doc """
  Verify a Dilithium5 signature.

  Returns `:ok` or `{:error, reason}`.
  """
  def dilithium5_verify(message, signature, public_key)
      when is_binary(message) and is_binary(signature) and is_binary(public_key) do
    if available?() do
      @nif_module.dilithium5_verify(message, signature, public_key)
    else
      {:error, :pq_not_available}
    end
  end

  # ==========================================================================
  # SLH-DSA (SPHINCS+-256f) — Hash-based Signatures (FIPS 205)
  # ==========================================================================

  @doc """
  Generate a SPHINCS+-256f key pair.

  Conservative fallback if Dilithium5 is ever broken (hash-based, minimal
  assumptions — security relies only on hash function preimage resistance).

  Returns `{:ok, %{public_key: binary, secret_key: binary, algorithm: :sphincs_plus}}`
  or `{:error, :pq_not_available}`.

  Key sizes:
  - Public key: 64 bytes
  - Secret key: 128 bytes
  - Signature: ~49856 bytes (large but conservative)
  """
  def sphincs_plus_keypair do
    if available?() do
      @nif_module.sphincs_plus_keypair()
    else
      {:error, :pq_not_available}
    end
  end

  @doc """
  Sign a message with SPHINCS+-256f.
  """
  def sphincs_plus_sign(message, secret_key) when is_binary(message) and is_binary(secret_key) do
    if available?() do
      @nif_module.sphincs_plus_sign(message, secret_key)
    else
      {:error, :pq_not_available}
    end
  end

  @doc """
  Verify a SPHINCS+-256f signature.
  """
  def sphincs_plus_verify(message, signature, public_key)
      when is_binary(message) and is_binary(signature) and is_binary(public_key) do
    if available?() do
      @nif_module.sphincs_plus_verify(message, signature, public_key)
    else
      {:error, :pq_not_available}
    end
  end

  # ==========================================================================
  # ML-KEM-1024 (Kyber-1024) — Key Encapsulation (FIPS 203)
  # ==========================================================================

  @doc """
  Generate a Kyber-1024 key pair for key encapsulation.

  Returns `{:ok, %{public_key: binary, secret_key: binary, algorithm: :kyber1024}}`
  or `{:error, :pq_not_available}`.

  Key sizes:
  - Public key: 1568 bytes
  - Secret key: 3168 bytes
  """
  def kyber1024_keypair do
    if available?() do
      @nif_module.kyber1024_keypair()
    else
      {:error, :pq_not_available}
    end
  end

  @doc """
  Encapsulate a shared secret using the recipient's Kyber-1024 public key.

  Returns `{:ok, %{ciphertext: binary, shared_secret: binary}}` (shared_secret is 32 bytes)
  or `{:error, reason}`.
  """
  def kyber1024_encapsulate(public_key) when is_binary(public_key) do
    if available?() do
      @nif_module.kyber1024_encapsulate(public_key)
    else
      {:error, :pq_not_available}
    end
  end

  @doc """
  Decapsulate a shared secret using the recipient's Kyber-1024 secret key.

  Returns `{:ok, shared_secret}` (32 bytes) or `{:error, reason}`.
  """
  def kyber1024_decapsulate(ciphertext, secret_key)
      when is_binary(ciphertext) and is_binary(secret_key) do
    if available?() do
      @nif_module.kyber1024_decapsulate(ciphertext, secret_key)
    else
      {:error, :pq_not_available}
    end
  end

  # ==========================================================================
  # Algorithm metadata
  # ==========================================================================

  @doc """
  List all supported post-quantum algorithms with their properties.
  """
  def algorithms do
    [
      %{
        name: :dilithium5,
        standard: "FIPS 204 (ML-DSA-87)",
        type: :signature,
        security_level: 5,
        pk_bytes: 2592,
        sk_bytes: 4896,
        sig_bytes: 4627,
        available: available?()
      },
      %{
        name: :sphincs_plus,
        standard: "FIPS 205 (SLH-DSA-SHAKE-256f)",
        type: :signature,
        security_level: 5,
        pk_bytes: 64,
        sk_bytes: 128,
        sig_bytes: 49_856,
        available: available?()
      },
      %{
        name: :kyber1024,
        standard: "FIPS 203 (ML-KEM-1024)",
        type: :kem,
        security_level: 5,
        pk_bytes: 1568,
        sk_bytes: 3168,
        ct_bytes: 1568,
        ss_bytes: 32,
        available: available?()
      }
    ]
  end
end
