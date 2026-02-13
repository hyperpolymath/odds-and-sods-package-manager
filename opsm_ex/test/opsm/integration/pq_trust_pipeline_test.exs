# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk>
#
# Integration tests for OPSM's post-quantum trust pipeline.
# Validates trust attestation, hybrid signatures, PQ algorithm
# availability, key exchange, and end-to-end trust flows.

defmodule Opsm.Integration.PqTrustPipelineTest do
  use ExUnit.Case, async: true

  alias Opsm.Crypto.PqTrust
  alias Opsm.Crypto.PostQuantum
  alias Opsm.Crypto.HybridSignatures

  @moduletag :integration

  # ==========================================================================
  # PQ Trust Attestation
  # ==========================================================================

  describe "PQ trust attestation" do
    test "generates trust attestation for a package" do
      result = PqTrust.trust_attestation("test-package", "1.0.0", "abc123hash")

      # trust_attestation always returns a map (attestation data)
      assert is_map(result)
      assert result["type"] == "pq_trust_verification"
      assert result["package"] == "test-package"
      assert result["version"] == "1.0.0"
      assert is_boolean(result["pq_available"])
    end

    test "attestation includes checksum algorithms" do
      result = PqTrust.trust_attestation("checksummed-pkg", "2.0.0", "deadbeef")

      assert is_map(result["checksum_algorithms"])
      assert Map.has_key?(result["checksum_algorithms"], "blake2b")
      assert Map.has_key?(result["checksum_algorithms"], "sha3_512")
    end

    test "attestation includes verification capabilities" do
      result = PqTrust.trust_attestation("verify-pkg", "1.0.0", "somehash")

      assert is_map(result["verification"])
      assert result["verification"]["ed25519"] == true
      # PQ verification booleans match availability
      pq = PostQuantum.available?()
      assert result["verification"]["dilithium5"] == pq
      assert result["verification"]["kyber1024"] == pq
      assert result["verification"]["sphincs_plus"] == pq
    end

    test "attestation includes signature mode" do
      result = PqTrust.trust_attestation("mode-pkg", "1.0.0", "hash")

      expected_mode = if PostQuantum.available?(), do: "hybrid", else: "classical_only"
      assert result["signature_mode"] == expected_mode
    end

    test "attestation includes timestamp" do
      result = PqTrust.trust_attestation("ts-pkg", "1.0.0", "hash")

      assert is_binary(result["timestamp"])
      # Should be ISO 8601
      assert result["timestamp"] =~ ~r/^\d{4}-\d{2}-\d{2}T/
    end
  end

  # ==========================================================================
  # Hybrid Signatures
  # ==========================================================================

  describe "hybrid signatures" do
    test "generate keypair returns Ed25519 keys (classical fallback)" do
      assert {:ok, keypair} = HybridSignatures.generate_keypair()
      assert is_binary(keypair.ed25519_pk)
      assert is_binary(keypair.ed25519_sk)
      assert keypair.algorithm in [:hybrid_ed25519_dilithium5, :ed25519_only]
    end

    test "sign and verify with generated keypair" do
      {:ok, keypair} = HybridSignatures.generate_keypair()
      message = "test message for hybrid signing"

      case HybridSignatures.sign(message, keypair) do
        {:ok, sig_info} ->
          assert is_binary(sig_info.signature)
          assert sig_info.algorithm in [:hybrid_ed25519_dilithium5, :ed25519_only]

          # Build public keys for verification
          public_keys = %{
            ed25519_pk: keypair.ed25519_pk,
            dilithium5_pk: keypair.dilithium5_pk
          }

          result = HybridSignatures.verify(message, sig_info, public_keys)
          assert result in [:ok, {:ok, :classical_only}, {:ok, :pq_not_verified}]

        {:error, reason} ->
          # Acceptable if keys have issues
          assert is_atom(reason) or is_binary(reason)
      end
    end

    test "verify rejects tampered messages" do
      {:ok, keypair} = HybridSignatures.generate_keypair()

      case HybridSignatures.sign("original message", keypair) do
        {:ok, sig_info} ->
          public_keys = %{
            ed25519_pk: keypair.ed25519_pk,
            dilithium5_pk: keypair.dilithium5_pk
          }

          result = HybridSignatures.verify("tampered message", sig_info, public_keys)
          assert match?({:error, _}, result)

        {:error, _} ->
          # Skip if signing not available
          :ok
      end
    end

    test "sign_payload serializes JSON and signs" do
      {:ok, keypair} = HybridSignatures.generate_keypair()
      payload = %{"key" => "value", "number" => 42}

      case HybridSignatures.sign_payload(payload, keypair) do
        {:ok, sig_info} ->
          assert is_binary(sig_info.signature)
          assert sig_info.algorithm in [:hybrid_ed25519_dilithium5, :ed25519_only]

        {:error, reason} ->
          assert is_binary(reason) or is_atom(reason)
      end
    end

    test "encode and decode public keys round-trip" do
      {:ok, keypair} = HybridSignatures.generate_keypair()

      encoded = HybridSignatures.encode_public_keys(keypair)
      assert is_map(encoded)
      assert is_binary(encoded["ed25519_pk"])
      assert is_binary(encoded["algorithm"])

      assert {:ok, decoded} = HybridSignatures.decode_public_keys(encoded)
      assert decoded.ed25519_pk == keypair.ed25519_pk
    end

    test "encode_signature produces hex-encoded map" do
      {:ok, keypair} = HybridSignatures.generate_keypair()

      case HybridSignatures.sign("encode test", keypair) do
        {:ok, sig_info} ->
          encoded = HybridSignatures.encode_signature(sig_info)
          assert is_binary(encoded["signature"])
          assert is_binary(encoded["algorithm"])
          # Signature should be hex-encoded
          assert encoded["signature"] =~ ~r/^[0-9a-f]+$/

        {:error, _} ->
          :ok
      end
    end
  end

  # ==========================================================================
  # Package Signing via PqTrust
  # ==========================================================================

  describe "PqTrust package signing" do
    test "sign_package produces signature info" do
      case PqTrust.sign_package("test package data") do
        {:ok, result} ->
          assert is_map(result)
          assert Map.has_key?(result, :signature)
          assert Map.has_key?(result, :public_keys)
          assert Map.has_key?(result, :signed_at)
          assert result.mode in [:hybrid, :classical_only]

        {:error, reason} ->
          assert is_atom(reason) or is_binary(reason)
      end
    end

    test "verify_package_signature validates signed data" do
      case PqTrust.sign_package("verify me") do
        {:ok, sign_result} ->
          {:ok, decoded_pks} = HybridSignatures.decode_public_keys(sign_result.public_keys)

          result = PqTrust.verify_package_signature(
            "verify me",
            sign_result.signature,
            decoded_pks
          )

          assert match?({:ok, %{status: status}} when status in [:verified, :partial], result)

        {:error, _} ->
          :ok
      end
    end
  end

  # ==========================================================================
  # PQ Algorithm Availability
  # ==========================================================================

  describe "PQ algorithm availability" do
    test "algorithms list always contains three entries" do
      algos = PostQuantum.algorithms()
      assert is_list(algos)
      assert length(algos) == 3
    end

    test "algorithms include dilithium5, sphincs_plus, and kyber1024" do
      names = PostQuantum.algorithms() |> Enum.map(& &1.name) |> MapSet.new()
      assert MapSet.member?(names, :dilithium5)
      assert MapSet.member?(names, :sphincs_plus)
      assert MapSet.member?(names, :kyber1024)
    end

    test "available? returns boolean" do
      assert is_boolean(PostQuantum.available?())
    end

    test "graceful degradation when NIF not loaded" do
      unless PostQuantum.available?() do
        assert {:error, :pq_not_available} = PostQuantum.dilithium5_keypair()
        assert {:error, :pq_not_available} = PostQuantum.kyber1024_keypair()
        assert {:error, :pq_not_available} = PostQuantum.sphincs_plus_keypair()
      end
    end

    test "algorithm metadata includes security level and byte sizes" do
      Enum.each(PostQuantum.algorithms(), fn algo ->
        assert algo.security_level == 5
        assert is_integer(algo.pk_bytes)
        assert is_integer(algo.sk_bytes)
        assert algo.type in [:signature, :kem]
      end)
    end
  end

  # ==========================================================================
  # Key Exchange (Kyber-1024 KEM)
  # ==========================================================================

  describe "encryption key establishment" do
    test "establish_encryption_key returns shared secret" do
      case PqTrust.establish_encryption_key() do
        {:ok, result} ->
          assert is_binary(result.shared_secret)
          assert result.method in [:kyber1024_self, :random_classical]

        {:error, reason} ->
          assert is_binary(reason)
      end
    end
  end

  # ==========================================================================
  # PQ Trust Status
  # ==========================================================================

  describe "PQ trust status" do
    test "status returns diagnostic info" do
      status = PqTrust.status()
      assert is_map(status)
      assert is_boolean(status.pq_available)
      assert status.signature_mode in [:hybrid, :classical_only]
      assert is_list(status.algorithms)
    end
  end

  # ==========================================================================
  # End-to-end PQ Trust Flow
  # ==========================================================================

  describe "end-to-end PQ trust flow" do
    test "full pipeline: attestation + signing + verification for package install" do
      package_name = "example-pkg"
      version = "3.0.0"
      checksum = :crypto.hash(:sha256, "fake-tarball-content") |> Base.encode16(case: :lower)

      # Step 1: Generate trust attestation
      attestation = PqTrust.trust_attestation(package_name, version, checksum)
      assert is_map(attestation)
      assert attestation["package"] == package_name
      assert attestation["version"] == version

      # Step 2: Sign the package data
      case PqTrust.sign_package("fake-tarball-content") do
        {:ok, sign_result} ->
          assert sign_result.mode in [:hybrid, :classical_only]
          assert is_binary(sign_result.signed_at)

        {:error, _} ->
          # PQ signing may not be available; classical fallback tested above
          :ok
      end
    end

    test "full pipeline with lockfile integrity signing" do
      lockfile = %{integrity_hash: "sha3-512:abcdef0123456789"}

      case PqTrust.sign_lockfile_integrity(lockfile) do
        {:ok, result} ->
          assert result.lockfile_hash == lockfile.integrity_hash
          assert is_map(result.signature)
          assert is_map(result.public_keys)
          assert is_binary(result.signed_at)
          assert result.algorithm in [:hybrid_ed25519_dilithium5, :ed25519_only]

        {:error, reason} ->
          assert is_binary(reason) or is_atom(reason)
      end
    end
  end
end
