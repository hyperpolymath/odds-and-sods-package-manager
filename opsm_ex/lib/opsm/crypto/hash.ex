# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule Opsm.Crypto.Hash do
  @moduledoc """
  Hybrid hashing strategy:
  - BLAKE3 (512-bit) for hot paths (speed-critical)
  - SHAKE256 (512-bit) for cold storage (long-term, PQ-secure)

  Aligns with SECURITY-STANDARDS.scm DatabaseHashing requirements.
  """

  @blake3_output_size 64  # 512 bits
  @shake256_output_size 64  # 512 bits

  @doc """
  Hash data using BLAKE3 (performance-critical paths).

  Returns hex-encoded hash (128 characters for 512-bit output).

  ## Examples

      iex> hash = Opsm.Crypto.Hash.hash_hot("package-content")
      iex> String.length(hash)
      128
  """
  def hash_hot(data) when is_binary(data) do
    # BLAKE3 for performance-critical paths
    Blake3.hash(data, length: @blake3_output_size)
    |> Base.encode16(case: :lower)
  end

  @doc """
  Hash data using SHAKE256 (long-term storage, post-quantum).

  Returns hex-encoded hash (128 characters for 512-bit output).

  ## Examples

      iex> hash = Opsm.Crypto.Hash.hash_cold("provenance-data")
      iex> String.length(hash)
      128
  """
  def hash_cold(data) when is_binary(data) do
    # SHAKE256 for long-term storage (post-quantum)
    # Using crypto_one_time/5 for XOF (extendable-output function)
    state = :crypto.hash_init(:shake256)
    state = :crypto.hash_update(state, data)
    :crypto.hash_final(state, @shake256_output_size)
    |> Base.encode16(case: :lower)
  end

  @doc """
  Hash for content-addressing (uses BLAKE3 for performance).

  ## Examples

      iex> hash1 = Opsm.Crypto.Hash.hash_content_addressed("content")
      iex> hash2 = Opsm.Crypto.Hash.hash_content_addressed("content")
      iex> hash1 == hash2
      true
  """
  def hash_content_addressed(data) do
    # Use BLAKE3 for content-addressing (performance)
    hash_hot(data)
  end

  @doc """
  Hash for provenance tracking (uses SHAKE256 for long-term security).

  ## Examples

      iex> hash = Opsm.Crypto.Hash.hash_provenance("supply-chain-data")
      iex> String.length(hash)
      128
  """
  def hash_provenance(data) do
    # Use SHAKE256 for provenance (long-term security)
    hash_cold(data)
  end
end
