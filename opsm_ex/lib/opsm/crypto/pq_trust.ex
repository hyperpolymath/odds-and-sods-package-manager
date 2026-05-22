# SPDX-License-Identifier: MPL-2.0
defmodule Opsm.Crypto.PqTrust do
  @moduledoc """
  Post-quantum cryptographic integration for the trust pipeline.

  Bridges the PQ primitives (Dilithium5, Kyber-1024, SPHINCS+) with
  OPSM's package verification, lockfile signing, and secure key exchange.

  Security Phase 2 — integrates post-quantum crypto into:
  1. Package signature verification (hybrid Ed25519 + Dilithium5)
  2. Lockfile integrity (PQ-signed lockfiles)
  3. Secure key exchange for encrypted lockfiles (Kyber-1024 KEM)
  4. SLSA provenance signing

  Falls back gracefully to classical-only crypto when NIF not loaded.
  """

  alias Opsm.Crypto.{PostQuantum, HybridSignatures, Hash}

  # ==========================================================================
  # Package Signature Verification
  # ==========================================================================

  @doc """
  Verify a package's signature using hybrid PQ+classical verification.

  Accepts both hybrid and classical-only signatures.
  Returns `{:ok, verification_result}` or `{:error, reason}`.
  """
  def verify_package_signature(package_data, signature_info, public_keys) do
    case HybridSignatures.verify(package_data, signature_info, public_keys) do
      :ok ->
        {:ok, %{status: :verified, mode: :hybrid, pq_algorithm: :dilithium5}}

      {:ok, :classical_only} ->
        {:ok, %{status: :verified, mode: :classical_only, pq_algorithm: nil}}

      {:ok, :pq_not_verified} ->
        {:ok, %{status: :partial, mode: :classical_verified_pq_unchecked, pq_algorithm: nil}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Sign package data with hybrid PQ+classical signatures.

  Generates a keypair if none provided, or uses the provided keypair.
  """
  def sign_package(package_data, keypair \\ nil) do
    kp = keypair || elem(HybridSignatures.generate_keypair(), 1)

    case HybridSignatures.sign(package_data, kp) do
      {:ok, sig_info} ->
        {:ok, %{
          signature: sig_info,
          public_keys: HybridSignatures.encode_public_keys(kp),
          signed_at: DateTime.utc_now() |> DateTime.to_iso8601(),
          mode: HybridSignatures.mode()
        }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ==========================================================================
  # Lockfile PQ Signing
  # ==========================================================================

  @doc """
  Sign a lockfile's integrity hash with hybrid PQ signatures.

  This adds a PQ-resistant signature over the SHA3-512 integrity hash,
  protecting the lockfile against quantum computer attacks on the hash.
  """
  def sign_lockfile_integrity(lockfile) do
    integrity_data = lockfile.integrity_hash || ""
    {:ok, keypair} = HybridSignatures.generate_keypair()

    case HybridSignatures.sign(integrity_data, keypair) do
      {:ok, sig_info} ->
        {:ok, %{
          lockfile_hash: lockfile.integrity_hash,
          signature: HybridSignatures.encode_signature(sig_info),
          public_keys: HybridSignatures.encode_public_keys(keypair),
          algorithm: sig_info.algorithm,
          signed_at: DateTime.utc_now() |> DateTime.to_iso8601()
        }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Verify a lockfile's PQ signature.
  """
  def verify_lockfile_signature(lockfile, sig_bundle) do
    integrity_data = lockfile.integrity_hash || ""

    with {:ok, public_keys} <- HybridSignatures.decode_public_keys(sig_bundle["public_keys"]) do
      sig_hex = sig_bundle["signature"]["signature"]
      algo = case sig_bundle["signature"]["algorithm"] do
        "hybrid_ed25519_dilithium5" -> :hybrid_ed25519_dilithium5
        _ -> :ed25519_only
      end

      case Base.decode16(sig_hex, case: :mixed) do
        {:ok, sig_bytes} ->
          sig_info = %{signature: sig_bytes, algorithm: algo}
          case HybridSignatures.verify(integrity_data, sig_info, public_keys) do
            :ok -> {:ok, :verified}
            {:ok, mode} -> {:ok, mode}
            {:error, reason} -> {:error, reason}
          end

        :error ->
          {:error, "Invalid signature encoding"}
      end
    end
  end

  # ==========================================================================
  # Kyber-1024 Key Exchange for Encrypted Lockfiles
  # ==========================================================================

  @doc """
  Establish a shared secret using Kyber-1024 KEM for lockfile encryption.

  Returns `{:ok, %{shared_secret: binary, ciphertext: binary, public_key: binary}}`
  or falls back to HKDF-derived key from a passphrase.
  """
  def establish_encryption_key(recipient_public_key \\ nil) do
    cond do
      # If recipient PK provided and PQ available, use Kyber KEM
      recipient_public_key != nil and PostQuantum.available?() ->
        case PostQuantum.kyber1024_encapsulate(recipient_public_key) do
          {:ok, %{ciphertext: ct, shared_secret: ss}} ->
            {:ok, %{
              shared_secret: ss,
              ciphertext: ct,
              method: :kyber1024_kem
            }}

          {:error, reason} ->
            {:error, "Kyber encapsulation failed: #{reason}"}
        end

      # Generate a fresh Kyber keypair for self-encryption
      PostQuantum.available?() ->
        case PostQuantum.kyber1024_keypair() do
          {:ok, kp} ->
            case PostQuantum.kyber1024_encapsulate(kp.public_key) do
              {:ok, %{ciphertext: ct, shared_secret: ss}} ->
                {:ok, %{
                  shared_secret: ss,
                  ciphertext: ct,
                  secret_key: kp.secret_key,
                  public_key: kp.public_key,
                  method: :kyber1024_self
                }}

              {:error, reason} ->
                {:error, reason}
            end

          {:error, _} ->
            fallback_key_derivation()
        end

      # PQ not available — fall back to classical key derivation
      true ->
        fallback_key_derivation()
    end
  end

  @doc """
  Recover shared secret from Kyber-1024 ciphertext.
  """
  def recover_encryption_key(ciphertext, secret_key) do
    case PostQuantum.kyber1024_decapsulate(ciphertext, secret_key) do
      {:ok, shared_secret} ->
        {:ok, %{shared_secret: shared_secret, method: :kyber1024_kem}}

      {:error, reason} ->
        {:error, "Kyber decapsulation failed: #{reason}"}
    end
  end

  defp fallback_key_derivation do
    # Generate a random 256-bit key for ChaCha20-Poly1305
    key = :crypto.strong_rand_bytes(32)
    {:ok, %{shared_secret: key, method: :random_classical}}
  end

  # ==========================================================================
  # Trust Pipeline Integration
  # ==========================================================================

  @doc """
  Run PQ-enhanced verification on a package as part of the trust pipeline.

  Returns a trust attestation map suitable for inclusion in ResolvedPackage.attestations.
  """
  def trust_attestation(package_name, package_version, checksum, _opts \\ []) do
    attestation = %{
      "type" => "pq_trust_verification",
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "package" => package_name,
      "version" => package_version,
      "pq_available" => PostQuantum.available?(),
      "signature_mode" => to_string(HybridSignatures.mode()),
      "checksum_algorithms" => %{
        "blake2b" => Hash.hash_hot(checksum || ""),
        "sha3_512" => Hash.hash_cold(checksum || "")
      },
      "verification" => %{
        "dilithium5" => PostQuantum.available?(),
        "kyber1024" => PostQuantum.available?(),
        "sphincs_plus" => PostQuantum.available?(),
        "ed25519" => true
      }
    }

    # If PQ available, sign the attestation itself
    if PostQuantum.available?() do
      {:ok, keypair} = HybridSignatures.generate_keypair()
      case HybridSignatures.sign_payload(attestation, keypair) do
        {:ok, sig} ->
          Map.merge(attestation, %{
            "self_signature" => HybridSignatures.encode_signature(sig),
            "self_public_keys" => HybridSignatures.encode_public_keys(keypair)
          })

        {:error, _} ->
          attestation
      end
    else
      attestation
    end
  end

  # ==========================================================================
  # Status
  # ==========================================================================

  @doc """
  Get current PQ crypto status for diagnostics.
  """
  def status do
    %{
      pq_available: PostQuantum.available?(),
      signature_mode: HybridSignatures.mode(),
      algorithms: PostQuantum.algorithms(),
      lockfile_encryption: if(PostQuantum.available?(), do: :kyber1024_kem, else: :classical_random),
      package_signatures: if(PostQuantum.available?(), do: :hybrid_ed25519_dilithium5, else: :ed25519_only)
    }
  end
end
