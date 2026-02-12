# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule Opsm.Crypto.PostQuantumTest do
  use ExUnit.Case, async: true

  alias Opsm.Crypto.PostQuantum

  describe "available?/0" do
    test "returns boolean indicating NIF status" do
      result = PostQuantum.available?()
      assert is_boolean(result)
    end
  end

  describe "algorithms/0" do
    test "lists all three PQ algorithms" do
      algos = PostQuantum.algorithms()
      assert length(algos) == 3

      names = Enum.map(algos, & &1.name)
      assert :dilithium5 in names
      assert :sphincs_plus in names
      assert :kyber1024 in names
    end

    test "all algorithms have correct metadata" do
      for algo <- PostQuantum.algorithms() do
        assert algo.security_level == 5
        assert is_boolean(algo.available)
        assert is_binary(algo.standard)
        assert algo.type in [:signature, :kem]
      end
    end

    test "signature algorithms have correct key sizes" do
      dilithium = Enum.find(PostQuantum.algorithms(), & &1.name == :dilithium5)
      assert dilithium.pk_bytes == 2592
      assert dilithium.sk_bytes == 4896
      assert dilithium.sig_bytes == 4627

      sphincs = Enum.find(PostQuantum.algorithms(), & &1.name == :sphincs_plus)
      assert sphincs.pk_bytes == 64
      assert sphincs.sk_bytes == 128
      assert sphincs.sig_bytes == 49_856
    end

    test "KEM algorithm has correct sizes" do
      kyber = Enum.find(PostQuantum.algorithms(), & &1.name == :kyber1024)
      assert kyber.pk_bytes == 1568
      assert kyber.sk_bytes == 3168
      assert kyber.ct_bytes == 1568
      assert kyber.ss_bytes == 32
    end
  end

  # NIF-dependent tests — only run if NIF is loaded
  # Run with: mix test --include integration
  describe "dilithium5 (requires NIF)" do
    @tag :integration
    test "keypair generation" do
      assert {:ok, keys} = PostQuantum.dilithium5_keypair()
      assert byte_size(keys.public_key) == 2592
      assert byte_size(keys.secret_key) == 4896
      assert keys.algorithm == :dilithium5
    end

    @tag :integration
    test "sign and verify" do
      {:ok, keys} = PostQuantum.dilithium5_keypair()
      message = "test message for dilithium5"

      assert {:ok, sig} = PostQuantum.dilithium5_sign(message, keys.secret_key)
      assert :ok = PostQuantum.dilithium5_verify(message, sig, keys.public_key)
    end

    @tag :integration
    test "verification fails with wrong message" do
      {:ok, keys} = PostQuantum.dilithium5_keypair()
      {:ok, sig} = PostQuantum.dilithium5_sign("original", keys.secret_key)
      assert {:error, _} = PostQuantum.dilithium5_verify("tampered", sig, keys.public_key)
    end

    @tag :integration
    test "verification fails with wrong key" do
      {:ok, keys1} = PostQuantum.dilithium5_keypair()
      {:ok, keys2} = PostQuantum.dilithium5_keypair()
      {:ok, sig} = PostQuantum.dilithium5_sign("message", keys1.secret_key)
      assert {:error, _} = PostQuantum.dilithium5_verify("message", sig, keys2.public_key)
    end
  end

  describe "sphincs_plus (requires NIF)" do
    @tag :integration
    test "keypair generation" do
      assert {:ok, keys} = PostQuantum.sphincs_plus_keypair()
      assert byte_size(keys.public_key) == 64
      assert byte_size(keys.secret_key) == 128
      assert keys.algorithm == :sphincs_plus
    end

    @tag :integration
    test "sign and verify" do
      {:ok, keys} = PostQuantum.sphincs_plus_keypair()
      message = "test message for sphincs+"

      assert {:ok, sig} = PostQuantum.sphincs_plus_sign(message, keys.secret_key)
      assert :ok = PostQuantum.sphincs_plus_verify(message, sig, keys.public_key)
    end
  end

  describe "kyber1024 (requires NIF)" do
    @tag :integration
    test "keypair generation" do
      assert {:ok, keys} = PostQuantum.kyber1024_keypair()
      assert byte_size(keys.public_key) == 1568
      assert byte_size(keys.secret_key) == 3168
      assert keys.algorithm == :kyber1024
    end

    @tag :integration
    test "encapsulate and decapsulate" do
      {:ok, keys} = PostQuantum.kyber1024_keypair()

      assert {:ok, enc} = PostQuantum.kyber1024_encapsulate(keys.public_key)
      assert byte_size(enc.shared_secret) == 32

      assert {:ok, ss} = PostQuantum.kyber1024_decapsulate(enc.ciphertext, keys.secret_key)
      assert ss == enc.shared_secret
    end
  end

  describe "graceful degradation (no NIF)" do
    test "dilithium5 operations return error when NIF not loaded" do
      unless PostQuantum.available?() do
        assert {:error, :pq_not_available} = PostQuantum.dilithium5_keypair()
        assert {:error, :pq_not_available} = PostQuantum.dilithium5_sign("msg", "key")
        assert {:error, :pq_not_available} = PostQuantum.dilithium5_verify("msg", "sig", "pk")
      end
    end

    test "sphincs+ operations return error when NIF not loaded" do
      unless PostQuantum.available?() do
        assert {:error, :pq_not_available} = PostQuantum.sphincs_plus_keypair()
        assert {:error, :pq_not_available} = PostQuantum.sphincs_plus_sign("msg", "key")
        assert {:error, :pq_not_available} = PostQuantum.sphincs_plus_verify("msg", "sig", "pk")
      end
    end

    test "kyber1024 operations return error when NIF not loaded" do
      unless PostQuantum.available?() do
        assert {:error, :pq_not_available} = PostQuantum.kyber1024_keypair()
        assert {:error, :pq_not_available} = PostQuantum.kyber1024_encapsulate("pk")
        assert {:error, :pq_not_available} = PostQuantum.kyber1024_decapsulate("ct", "sk")
      end
    end
  end
end
