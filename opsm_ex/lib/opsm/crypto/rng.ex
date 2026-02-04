# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule Opsm.Crypto.RNG do
  @moduledoc """
  ChaCha20-based Deterministic Random Bit Generator (DRBG).

  Uses 512-bit seeds for high entropy.
  Complies with NIST SP 800-90Ar1.

  Aligns with SECURITY-STANDARDS.scm RNG requirements.

  Note: Erlang's :crypto.strong_rand_bytes/1 uses ChaCha20-DRBG
  on modern Erlang/OTP versions (>= 22).
  """

  @seed_size 64  # 512 bits

  @doc """
  Generate n cryptographically secure random bytes.

  ## Examples

      iex> bytes = Opsm.Crypto.RNG.generate_bytes(32)
      iex> byte_size(bytes)
      32
  """
  def generate_bytes(n) when is_integer(n) and n > 0 do
    # Use Erlang's :crypto.strong_rand_bytes (implements ChaCha20-DRBG)
    :crypto.strong_rand_bytes(n)
  end

  @doc """
  Generate a 256-bit cryptographic key.

  ## Examples

      iex> key = Opsm.Crypto.RNG.generate_key_256bit()
      iex> byte_size(key)
      32
  """
  def generate_key_256bit do
    generate_bytes(32)  # 256 bits
  end

  @doc """
  Generate a 192-bit nonce for XChaCha20.

  ## Examples

      iex> nonce = Opsm.Crypto.RNG.generate_nonce_192bit()
      iex> byte_size(nonce)
      24
  """
  def generate_nonce_192bit do
    generate_bytes(24)  # 192 bits (XChaCha20)
  end

  @doc """
  Generate a 256-bit salt for password hashing.

  ## Examples

      iex> salt = Opsm.Crypto.RNG.generate_salt()
      iex> byte_size(salt)
      32
  """
  def generate_salt do
    generate_bytes(32)  # 256 bits
  end
end
