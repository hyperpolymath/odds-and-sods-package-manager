# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Crypto.HashTest do
  use ExUnit.Case, async: true
  alias Opsm.Crypto.Hash

  describe "hash_hot/1 (BLAKE3)" do
    test "hashes data with BLAKE3" do
      data = "package-content"
      hash = Hash.hash_hot(data)

      assert is_binary(hash)
      # 512 bits = 64 bytes = 128 hex chars
      assert String.length(hash) == 128
    end

    test "produces deterministic hashes" do
      data = "deterministic-test"
      hash1 = Hash.hash_hot(data)
      hash2 = Hash.hash_hot(data)

      assert hash1 == hash2
    end

    test "produces different hashes for different data" do
      hash1 = Hash.hash_hot("data1")
      hash2 = Hash.hash_hot("data2")

      assert hash1 != hash2
    end

    test "handles empty data" do
      hash = Hash.hash_hot("")
      assert String.length(hash) == 128
    end

    test "handles large data" do
      large_data = String.duplicate("A", 1_000_000)
      hash = Hash.hash_hot(large_data)

      assert String.length(hash) == 128
    end
  end

  describe "hash_cold/1 (SHAKE256)" do
    test "hashes data with SHAKE256" do
      data = "provenance-data"
      hash = Hash.hash_cold(data)

      assert is_binary(hash)
      # 512 bits = 64 bytes = 128 hex chars
      assert String.length(hash) == 128
    end

    test "produces deterministic hashes" do
      data = "deterministic-test"
      hash1 = Hash.hash_cold(data)
      hash2 = Hash.hash_cold(data)

      assert hash1 == hash2
    end

    test "produces different hashes for different data" do
      hash1 = Hash.hash_cold("data1")
      hash2 = Hash.hash_cold("data2")

      assert hash1 != hash2
    end

    test "handles empty data" do
      hash = Hash.hash_cold("")
      assert String.length(hash) == 128
    end
  end

  describe "hash_content_addressed/1" do
    test "uses BLAKE3 (hot path)" do
      data = "content"
      ca_hash = Hash.hash_content_addressed(data)
      blake3_hash = Hash.hash_hot(data)

      assert ca_hash == blake3_hash
    end

    test "produces consistent content addresses" do
      data = "same-content"
      hash1 = Hash.hash_content_addressed(data)
      hash2 = Hash.hash_content_addressed(data)

      assert hash1 == hash2
    end
  end

  describe "hash_provenance/1" do
    test "uses SHAKE256 (cold storage)" do
      data = "supply-chain-data"
      prov_hash = Hash.hash_provenance(data)
      shake_hash = Hash.hash_cold(data)

      assert prov_hash == shake_hash
    end

    test "produces consistent provenance hashes" do
      data = "provenance"
      hash1 = Hash.hash_provenance(data)
      hash2 = Hash.hash_provenance(data)

      assert hash1 == hash2
    end
  end

  describe "hash separation" do
    test "BLAKE3 and SHAKE256 produce different hashes for same input" do
      data = "test-data"
      blake3_hash = Hash.hash_hot(data)
      shake_hash = Hash.hash_cold(data)

      # Different algorithms should produce different outputs
      assert blake3_hash != shake_hash
    end
  end

  describe "security properties" do
    test "collision resistance (different inputs -> different outputs)" do
      # Property: H(x) != H(y) for x != y (with overwhelming probability)
      inputs = ["a", "b", "c", "aa", "ab", "ba", "test1", "test2"]
      hot_hashes = Enum.map(inputs, &Hash.hash_hot/1)
      cold_hashes = Enum.map(inputs, &Hash.hash_cold/1)

      assert length(Enum.uniq(hot_hashes)) == length(hot_hashes)
      assert length(Enum.uniq(cold_hashes)) == length(cold_hashes)
    end

    test "avalanche effect (single bit change -> significant hash change)" do
      data1 = "test"
      # Single character different
      data2 = "tesa"

      hash1_hot = Hash.hash_hot(data1)
      hash2_hot = Hash.hash_hot(data2)

      hash1_cold = Hash.hash_cold(data1)
      hash2_cold = Hash.hash_cold(data2)

      # Hashes should be completely different despite minimal input difference
      assert hash1_hot != hash2_hot
      assert hash1_cold != hash2_cold

      # Count differing hex characters (should be ~50%)
      diff_count_hot =
        Enum.zip(String.graphemes(hash1_hot), String.graphemes(hash2_hot))
        |> Enum.count(fn {c1, c2} -> c1 != c2 end)

      # At least 25% of characters should differ (avalanche effect)
      assert diff_count_hot > 32
    end

    test "output is lowercase hex" do
      hash_hot = Hash.hash_hot("test")
      hash_cold = Hash.hash_cold("test")

      assert hash_hot == String.downcase(hash_hot)
      assert hash_cold == String.downcase(hash_cold)
      assert Regex.match?(~r/^[0-9a-f]+$/, hash_hot)
      assert Regex.match?(~r/^[0-9a-f]+$/, hash_cold)
    end
  end
end
