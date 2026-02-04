# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule Opsm.Crypto.Password do
  @moduledoc """
  Argon2id password hashing with NIST-compliant parameters.

  Parameters:
  - Memory: 512 MiB (524288 KiB)
  - Iterations: 8
  - Parallelism: 4 lanes
  - Hash length: 64 bytes

  Aligns with SECURITY-STANDARDS.scm PasswordHashing requirements.
  """

  @memory_cost 524_288  # 512 MiB in KiB
  @time_cost 8
  @parallelism 4
  @hash_length 64

  @doc """
  Hash a password using Argon2id with security-compliant parameters.

  ## Examples

      iex> {:ok, hash} = Opsm.Crypto.Password.hash("correct-horse-battery-staple")
      iex> String.starts_with?(hash, "$argon2id$")
      true
  """
  def hash(password) when is_binary(password) do
    salt = :crypto.strong_rand_bytes(32)

    case Argon2.hash_pwd_salt(password,
           t_cost: @time_cost,
           m_cost: @memory_cost,
           parallelism: @parallelism,
           hash_length: @hash_length,
           salt: salt
         ) do
      {:ok, hash} -> {:ok, hash}
      {:error, reason} -> {:error, "Argon2id hashing failed: #{reason}"}
    end
  end

  @doc """
  Verify a password against an Argon2id hash.

  ## Examples

      iex> {:ok, hash} = Opsm.Crypto.Password.hash("password123")
      iex> Opsm.Crypto.Password.verify("password123", hash)
      :ok
      iex> Opsm.Crypto.Password.verify("wrong", hash)
      {:error, "Password verification failed"}
  """
  def verify(password, hash) when is_binary(password) and is_binary(hash) do
    case Argon2.verify_pass(password, hash) do
      true -> :ok
      false -> {:error, "Password verification failed"}
    end
  end
end
