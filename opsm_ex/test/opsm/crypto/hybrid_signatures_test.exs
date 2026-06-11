# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Crypto.HybridSignaturesTest do
  use ExUnit.Case, async: true

  alias Opsm.Crypto.{HybridSignatures, PostQuantum}

  describe "mode/0" do
    test "returns :hybrid or :classical_only" do
      mode = HybridSignatures.mode()
      assert mode in [:hybrid, :classical_only]
    end
  end

  describe "generate_keypair/0" do
    test "generates keypair with Ed25519 keys" do
      {:ok, keypair} = HybridSignatures.generate_keypair()
      assert is_binary(keypair.ed25519_pk)
      assert is_binary(keypair.ed25519_sk)
      assert byte_size(keypair.ed25519_pk) == 32
    end

    test "keypair algorithm matches PQ availability" do
      {:ok, keypair} = HybridSignatures.generate_keypair()

      if PostQuantum.available?() do
        assert keypair.algorithm == :hybrid_ed25519_dilithium5
        assert is_binary(keypair.dilithium5_pk)
        assert is_binary(keypair.dilithium5_sk)
      else
        assert keypair.algorithm == :ed25519_only
        assert is_nil(keypair.dilithium5_pk)
        assert is_nil(keypair.dilithium5_sk)
      end
    end
  end

  describe "sign/2 and verify/3" do
    test "sign and verify with generated keypair" do
      {:ok, keypair} = HybridSignatures.generate_keypair()
      message = "test message for hybrid signatures"

      {:ok, sig_info} = HybridSignatures.sign(message, keypair)
      assert is_binary(sig_info.signature)
      assert sig_info.algorithm in [:hybrid_ed25519_dilithium5, :ed25519_only]

      result = HybridSignatures.verify(message, sig_info, keypair)
      assert result in [:ok, {:ok, :classical_only}, {:ok, :pq_not_verified}]
    end

    test "verification fails with wrong message" do
      {:ok, keypair} = HybridSignatures.generate_keypair()
      {:ok, sig_info} = HybridSignatures.sign("original message", keypair)

      result = HybridSignatures.verify("tampered message", sig_info, keypair)
      assert match?({:error, _}, result)
    end

    test "verification fails with wrong key" do
      {:ok, keypair1} = HybridSignatures.generate_keypair()
      {:ok, keypair2} = HybridSignatures.generate_keypair()

      {:ok, sig_info} = HybridSignatures.sign("message", keypair1)
      result = HybridSignatures.verify("message", sig_info, keypair2)
      assert match?({:error, _}, result)
    end
  end

  describe "sign_payload/2 and verify_payload/3" do
    test "sign and verify JSON payload" do
      {:ok, keypair} = HybridSignatures.generate_keypair()
      payload = %{"package" => "test-pkg", "version" => "1.0.0"}

      {:ok, sig_info} = HybridSignatures.sign_payload(payload, keypair)
      result = HybridSignatures.verify_payload(payload, sig_info, keypair)
      assert result in [:ok, {:ok, :classical_only}, {:ok, :pq_not_verified}]
    end

    test "payload verification fails with different payload" do
      {:ok, keypair} = HybridSignatures.generate_keypair()
      {:ok, sig_info} = HybridSignatures.sign_payload(%{"a" => 1}, keypair)
      result = HybridSignatures.verify_payload(%{"a" => 2}, sig_info, keypair)
      assert match?({:error, _}, result)
    end
  end

  describe "encode/decode public keys" do
    test "round-trip encoding" do
      {:ok, keypair} = HybridSignatures.generate_keypair()
      encoded = HybridSignatures.encode_public_keys(keypair)

      assert is_binary(encoded["ed25519_pk"])
      assert is_binary(encoded["algorithm"])

      {:ok, decoded} = HybridSignatures.decode_public_keys(encoded)
      assert decoded.ed25519_pk == keypair.ed25519_pk
    end
  end

  describe "encode_signature/1" do
    test "encodes signature as hex map" do
      {:ok, keypair} = HybridSignatures.generate_keypair()
      {:ok, sig_info} = HybridSignatures.sign("test", keypair)

      encoded = HybridSignatures.encode_signature(sig_info)
      assert is_binary(encoded["signature"])
      assert is_binary(encoded["algorithm"])
    end
  end
end
