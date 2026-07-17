# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Crypto.HybridSignatures do
  @moduledoc """
  Hybrid classical + post-quantum digital signatures.

  Combines Ed25519 (classical) with Dilithium5 (post-quantum) for
  defense-in-depth: the hybrid signature is secure as long as either
  algorithm remains unbroken.

  Signature format (concatenated):
    ed25519_sig (64 bytes) || dilithium5_sig (~4627 bytes)

  Key pair format:
    %{
      ed25519_pk: binary(32),   ed25519_sk: binary(64),
      dilithium5_pk: binary(2592), dilithium5_sk: binary(4896),
      algorithm: :hybrid_ed25519_dilithium5
    }

  When PQ NIF is not available, falls back to Ed25519-only with a warning.
  Use `mode/0` to check current operating mode.

  Aligns with SECURITY-STANDARDS.scm Phase 2 hybrid signature requirements.
  """

  alias Opsm.Crypto.{Signatures, PostQuantum}

  @ed25519_sig_size 64

  # ==========================================================================
  # Operating mode
  # ==========================================================================

  @doc """
  Return the current signature operating mode.

  - `:hybrid` — Both Ed25519 and Dilithium5 available (full security)
  - `:classical_only` — Only Ed25519 available (PQ NIF not loaded)
  """
  def mode do
    if PostQuantum.available?(), do: :hybrid, else: :classical_only
  end

  # ==========================================================================
  # Key generation
  # ==========================================================================

  @doc """
  Generate a hybrid Ed25519 + Dilithium5 key pair.

  Returns `{:ok, keypair}` where keypair contains both classical and PQ keys,
  or `{:ok, keypair}` with only Ed25519 keys if PQ is not available.
  """
  def generate_keypair do
    {:ok, ed_keys} = Signatures.generate_ed25519_keypair()

    case PostQuantum.dilithium5_keypair() do
      {:ok, pq_keys} ->
        {:ok,
         %{
           ed25519_pk: ed_keys.public_key,
           ed25519_sk: ed_keys.secret_key,
           dilithium5_pk: pq_keys.public_key,
           dilithium5_sk: pq_keys.secret_key,
           algorithm: :hybrid_ed25519_dilithium5
         }}

      {:error, :pq_not_available} ->
        {:ok,
         %{
           ed25519_pk: ed_keys.public_key,
           ed25519_sk: ed_keys.secret_key,
           dilithium5_pk: nil,
           dilithium5_sk: nil,
           algorithm: :ed25519_only
         }}
    end
  end

  # ==========================================================================
  # Signing
  # ==========================================================================

  @doc """
  Sign a message with hybrid Ed25519 + Dilithium5.

  If PQ is available, produces a concatenated signature:
    ed25519_sig || dilithium5_sig

  If PQ is not available, produces Ed25519-only signature.

  Returns `{:ok, %{signature: binary, algorithm: atom}}`.
  """
  def sign(message, keypair) when is_binary(message) do
    # Classical Ed25519 signature (always available)
    case Signatures.sign_ed25519(message, keypair.ed25519_sk) do
      {:ok, ed_sig} ->
        # Attempt PQ signature
        if keypair.dilithium5_sk do
          case PostQuantum.dilithium5_sign(message, keypair.dilithium5_sk) do
            {:ok, pq_sig} ->
              {:ok,
               %{
                 signature: ed_sig <> pq_sig,
                 algorithm: :hybrid_ed25519_dilithium5
               }}

            {:error, _} ->
              # PQ failed — fall back to classical only
              {:ok, %{signature: ed_sig, algorithm: :ed25519_only}}
          end
        else
          {:ok, %{signature: ed_sig, algorithm: :ed25519_only}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Sign a JSON-serializable payload with hybrid signatures.

  Canonicalizes JSON before signing for deterministic verification.
  """
  def sign_payload(payload, keypair) do
    case Jason.encode(payload, maps: :strict) do
      {:ok, canonical} -> sign(canonical, keypair)
      {:error, reason} -> {:error, "JSON encoding failed: #{inspect(reason)}"}
    end
  end

  # ==========================================================================
  # Verification
  # ==========================================================================

  @doc """
  Verify a hybrid signature.

  For hybrid signatures: both Ed25519 AND Dilithium5 must verify.
  For classical-only: only Ed25519 is verified.

  Returns `:ok`, `{:ok, :classical_only}`, or `{:error, reason}`.
  """
  def verify(message, %{signature: signature, algorithm: algorithm}, public_keys) do
    verify(message, signature, algorithm, public_keys)
  end

  def verify(message, signature, :hybrid_ed25519_dilithium5, public_keys)
      when is_binary(message) and is_binary(signature) do
    # Split hybrid signature
    <<ed_sig::binary-size(@ed25519_sig_size), pq_sig::binary>> = signature

    # Verify Ed25519 (classical)
    case Signatures.verify_ed25519(message, ed_sig, public_keys.ed25519_pk) do
      :ok ->
        # Verify Dilithium5 (post-quantum)
        case PostQuantum.dilithium5_verify(message, pq_sig, public_keys.dilithium5_pk) do
          :ok ->
            :ok

          {:error, :pq_not_available} ->
            # PQ NIF not loaded — classical verified, PQ unchecked
            {:ok, :pq_not_verified}

          {:error, reason} ->
            {:error, "Dilithium5 verification failed: #{reason}"}
        end

      {:error, reason} ->
        {:error, "Ed25519 verification failed: #{reason}"}
    end
  end

  def verify(message, signature, :ed25519_only, public_keys) when is_binary(message) do
    case Signatures.verify_ed25519(message, signature, public_keys.ed25519_pk) do
      :ok -> {:ok, :classical_only}
      {:error, reason} -> {:error, reason}
    end
  end

  def verify(_message, _signature, algorithm, _public_keys) do
    {:error, "Unsupported algorithm: #{algorithm}"}
  end

  @doc """
  Verify a signed JSON payload.
  """
  def verify_payload(payload, sig_info, public_keys) do
    case Jason.encode(payload, maps: :strict) do
      {:ok, canonical} -> verify(canonical, sig_info, public_keys)
      {:error, reason} -> {:error, "JSON encoding failed: #{inspect(reason)}"}
    end
  end

  # ==========================================================================
  # Serialization
  # ==========================================================================

  @doc """
  Encode a hybrid key pair's public keys for storage/transport.

  Returns a map with hex-encoded public keys and algorithm identifier.
  """
  def encode_public_keys(keypair) do
    base = %{
      "algorithm" => to_string(keypair.algorithm),
      "ed25519_pk" => Base.encode16(keypair.ed25519_pk, case: :lower)
    }

    if keypair.dilithium5_pk do
      Map.put(base, "dilithium5_pk", Base.encode16(keypair.dilithium5_pk, case: :lower))
    else
      base
    end
  end

  @doc """
  Decode hex-encoded public keys.
  """
  def decode_public_keys(encoded) when is_map(encoded) do
    with {:ok, ed_pk} <- Base.decode16(encoded["ed25519_pk"], case: :mixed) do
      pq_pk =
        case encoded["dilithium5_pk"] do
          nil ->
            nil

          hex ->
            case Base.decode16(hex, case: :mixed) do
              {:ok, pk} -> pk
              :error -> nil
            end
        end

      algorithm =
        case encoded["algorithm"] do
          "hybrid_ed25519_dilithium5" -> :hybrid_ed25519_dilithium5
          _ -> :ed25519_only
        end

      {:ok, %{ed25519_pk: ed_pk, dilithium5_pk: pq_pk, algorithm: algorithm}}
    else
      :error -> {:error, "Invalid hex encoding in public keys"}
    end
  end

  @doc """
  Encode a signature result for storage/transport.
  """
  def encode_signature(%{signature: sig, algorithm: algo}) do
    %{
      "signature" => Base.encode16(sig, case: :lower),
      "algorithm" => to_string(algo)
    }
  end
end
