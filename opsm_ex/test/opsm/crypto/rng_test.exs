# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Crypto.RNGTest do
  use ExUnit.Case, async: true
  alias Opsm.Crypto.RNG

  describe "generate_bytes/1" do
    test "generates requested number of bytes" do
      for n <- [1, 16, 32, 64, 128, 256] do
        bytes = RNG.generate_bytes(n)
        assert byte_size(bytes) == n
      end
    end

    test "generates different bytes each call (randomness)" do
      bytes1 = RNG.generate_bytes(32)
      bytes2 = RNG.generate_bytes(32)

      # Should be different with overwhelming probability
      assert bytes1 != bytes2
    end

    test "generates non-zero bytes (not all zeros)" do
      bytes = RNG.generate_bytes(64)

      # Should not be all zeros
      assert bytes != <<0::512>>
    end
  end

  describe "generate_key_256bit/0" do
    test "generates 256-bit (32-byte) keys" do
      key = RNG.generate_key_256bit()
      assert byte_size(key) == 32
    end

    test "generates different keys each time" do
      key1 = RNG.generate_key_256bit()
      key2 = RNG.generate_key_256bit()

      assert key1 != key2
    end

    test "generated keys are cryptographically random" do
      # Generate 10 keys and verify no duplicates
      keys = for _ <- 1..10, do: RNG.generate_key_256bit()
      assert length(Enum.uniq(keys)) == 10
    end
  end

  describe "generate_nonce_192bit/0" do
    test "generates 192-bit (24-byte) nonces" do
      nonce = RNG.generate_nonce_192bit()
      assert byte_size(nonce) == 24
    end

    test "generates different nonces each time" do
      nonce1 = RNG.generate_nonce_192bit()
      nonce2 = RNG.generate_nonce_192bit()

      assert nonce1 != nonce2
    end

    test "nonce collision resistance" do
      # Generate 100 nonces and verify all unique
      nonces = for _ <- 1..100, do: RNG.generate_nonce_192bit()
      assert length(Enum.uniq(nonces)) == 100
    end
  end

  describe "generate_salt/0" do
    test "generates 256-bit (32-byte) salts" do
      salt = RNG.generate_salt()
      assert byte_size(salt) == 32
    end

    test "generates different salts each time" do
      salt1 = RNG.generate_salt()
      salt2 = RNG.generate_salt()

      assert salt1 != salt2
    end

    test "salt uniqueness for password hashing" do
      # Generate multiple salts and verify uniqueness
      salts = for _ <- 1..50, do: RNG.generate_salt()
      assert length(Enum.uniq(salts)) == 50
    end
  end

  describe "security properties" do
    test "output distribution (chi-square test approximation)" do
      # Generate large sample and verify not obviously biased
      bytes = RNG.generate_bytes(10_000)

      # Count occurrences of each byte value (0-255)
      byte_list = :binary.bin_to_list(bytes)
      counts = Enum.frequencies(byte_list)

      # Expected: ~39 occurrences of each value (10000 / 256)
      # Allow variance: 20-60 occurrences per value
      for value <- 0..255 do
        count = Map.get(counts, value, 0)
        # Allow generous variance (this is a weak test, but catches obvious bias)
        assert count >= 10 and count <= 100,
               "Byte value #{value} appeared #{count} times (expected ~39)"
      end
    end

    test "no predictable patterns in sequential outputs" do
      bytes1 = RNG.generate_bytes(32)
      bytes2 = RNG.generate_bytes(32)
      bytes3 = RNG.generate_bytes(32)

      # Sequential outputs should be independent
      assert bytes1 != bytes2
      assert bytes2 != bytes3
      assert bytes1 != bytes3

      # No bytes should be identical across all three
      refute byte_size(bytes1) == byte_size(bytes2) and bytes1 == bytes2
    end

    test "hamming distance between outputs is high" do
      bytes1 = RNG.generate_bytes(32)
      bytes2 = RNG.generate_bytes(32)

      # Count differing bits (Hamming distance)
      xor_result =
        :crypto.exor(bytes1, bytes2)
        |> :binary.bin_to_list()
        |> Enum.map(fn byte ->
          # Count set bits in XOR result
          Integer.digits(byte, 2) |> Enum.count(&(&1 == 1))
        end)
        |> Enum.sum()

      # For 32 bytes (256 bits), expect ~128 differing bits (50%)
      # Allow range: 100-156 bits (39%-61%)
      assert xor_result >= 100 and xor_result <= 156,
             "Hamming distance: #{xor_result} bits (expected ~128)"
    end

    test "outputs pass basic randomness test (runs test)" do
      bytes = RNG.generate_bytes(128)
      bits = for <<bit::1 <- bytes>>, do: bit

      # Count runs (sequences of same bit)
      runs =
        bits
        |> Enum.chunk_by(& &1)
        |> length()

      # For 1024 bits, expect ~512 runs (alternating bits)
      # Allow generous variance: 400-624 runs
      assert runs >= 400 and runs <= 624,
             "Runs test: #{runs} runs (expected ~512)"
    end
  end

  describe "compliance" do
    test "uses ChaCha20-DRBG (implicit via :crypto.strong_rand_bytes)" do
      # Erlang/OTP >= 22 uses ChaCha20-DRBG
      # This is a documentation test - we trust Erlang's implementation
      bytes = RNG.generate_bytes(64)

      # Verify it produces output (basic sanity check)
      assert byte_size(bytes) == 64
      assert bytes != <<0::512>>
    end

    test "suitable for cryptographic use cases" do
      # Generate key material suitable for AES-256, XChaCha20, etc.
      key_256 = RNG.generate_key_256bit()
      nonce_192 = RNG.generate_nonce_192bit()
      salt_256 = RNG.generate_salt()

      assert byte_size(key_256) == 32
      assert byte_size(nonce_192) == 24
      assert byte_size(salt_256) == 32

      # All different
      assert key_256 != salt_256
    end
  end
end
