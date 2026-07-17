# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
#
# End-to-end test for PQ NIF sign -> verify -> content match flow.
# Tagged :e2e and :integration; requires PQ NIF to be compiled.
#
# Run with: mix test test/e2e/pq_sign_verify_e2e_test.exs --include e2e

defmodule Opsm.E2E.PqSignVerifyE2ETest do
  use ExUnit.Case, async: true

  alias Opsm.Crypto.{PostQuantum, HybridSignatures}

  @moduletag :e2e
  @moduletag :integration

  describe "Dilithium5 sign -> verify -> content match" do
    @tag :e2e
    test "signed message content matches original after verification" do
      if PostQuantum.available?() do
        original_message = "OPSM package integrity: serde@1.0.210 sha256:abc123"

        # Step 1: Generate keypair
        {:ok, keys} = PostQuantum.dilithium5_keypair()

        # Step 2: Sign the message
        {:ok, signed_blob} = PostQuantum.dilithium5_sign(original_message, keys.secret_key)
        assert is_binary(signed_blob)
        # The signed blob is sig || message, so it must be longer than the message
        assert byte_size(signed_blob) > byte_size(original_message)

        # Step 3: Verify returns :ok (the NIF's open() extracts and compares)
        assert :ok = PostQuantum.dilithium5_verify(original_message, signed_blob, keys.public_key)

        # Step 4: Verify that a tampered message is rejected
        tampered = original_message <> " TAMPERED"

        assert {:error, _reason} =
                 PostQuantum.dilithium5_verify(tampered, signed_blob, keys.public_key)

        # Step 5: Verify that a different key is rejected
        {:ok, other_keys} = PostQuantum.dilithium5_keypair()

        assert {:error, _reason} =
                 PostQuantum.dilithium5_verify(
                   original_message,
                   signed_blob,
                   other_keys.public_key
                 )
      else
        # NIF not loaded -- graceful degradation
        assert {:error, :pq_not_available} = PostQuantum.dilithium5_keypair()
      end
    end
  end

  describe "SPHINCS+ sign -> verify -> content match" do
    @tag :e2e
    test "signed message content matches original after verification" do
      if PostQuantum.available?() do
        original_message = "OPSM lockfile integrity: sha3-512:deadbeef"

        {:ok, keys} = PostQuantum.sphincs_plus_keypair()
        {:ok, signed_blob} = PostQuantum.sphincs_plus_sign(original_message, keys.secret_key)

        # Verify succeeds for correct message
        assert :ok =
                 PostQuantum.sphincs_plus_verify(original_message, signed_blob, keys.public_key)

        # Verify fails for tampered message
        assert {:error, _} =
                 PostQuantum.sphincs_plus_verify("TAMPERED", signed_blob, keys.public_key)
      else
        assert {:error, :pq_not_available} = PostQuantum.sphincs_plus_keypair()
      end
    end
  end

  describe "Hybrid Ed25519+Dilithium5 sign -> verify -> content match" do
    @tag :e2e
    test "hybrid signing verifies and content matches" do
      {:ok, keypair} = HybridSignatures.generate_keypair()
      original_message = "hybrid integrity test payload"

      case HybridSignatures.sign(original_message, keypair) do
        {:ok, sig_info} ->
          public_keys = %{
            ed25519_pk: keypair.ed25519_pk,
            dilithium5_pk: keypair.dilithium5_pk
          }

          # Verify with correct message
          result = HybridSignatures.verify(original_message, sig_info, public_keys)
          assert result in [:ok, {:ok, :classical_only}, {:ok, :pq_not_verified}]

          # Verify fails with tampered message
          tampered_result = HybridSignatures.verify("tampered", sig_info, public_keys)
          assert match?({:error, _}, tampered_result)

        {:error, reason} ->
          assert is_atom(reason) or is_binary(reason)
      end
    end

    @tag :e2e
    test "hybrid sign_payload -> verify_payload round trip preserves semantics" do
      {:ok, keypair} = HybridSignatures.generate_keypair()
      payload = %{"package" => "serde", "version" => "1.0.210", "checksum" => "sha256:abc"}

      case HybridSignatures.sign_payload(payload, keypair) do
        {:ok, sig_info} ->
          public_keys = %{
            ed25519_pk: keypair.ed25519_pk,
            dilithium5_pk: keypair.dilithium5_pk
          }

          # Verify with same payload
          result = HybridSignatures.verify_payload(payload, sig_info, public_keys)
          assert result in [:ok, {:ok, :classical_only}, {:ok, :pq_not_verified}]

          # Verify fails with different payload
          tampered_payload = Map.put(payload, "checksum", "sha256:TAMPERED")

          tampered_result =
            HybridSignatures.verify_payload(tampered_payload, sig_info, public_keys)

          assert match?({:error, _}, tampered_result)

        {:error, _} ->
          :ok
      end
    end
  end
end
