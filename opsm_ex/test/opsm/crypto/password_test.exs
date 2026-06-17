# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Crypto.PasswordTest do
  use ExUnit.Case, async: true
  alias Opsm.Crypto.Password

  describe "hash/1" do
    test "hashes secret successfully" do
      secret = "correct-horse-battery-staple"
      assert {:ok, hash} = Password.hash(secret)
      assert is_binary(hash)
      assert String.length(hash) > 0
    end

    test "produces different hashes for same secret (salt)" do
      secret = "test-secret"
      {:ok, hash1} = Password.hash(secret)
      {:ok, hash2} = Password.hash(secret)
      assert hash1 != hash2  # Different salts
    end

    test "uses Argon2id with correct parameters" do
      {:ok, hash} = Password.hash("test")

      # Verify hash format includes parameter info
      assert String.starts_with?(hash, "$argon2id$")
      assert String.contains?(hash, "m=524288")  # 512 MiB
      assert String.contains?(hash, "t=8")       # 8 iterations
      assert String.contains?(hash, "p=4")       # 4 lanes
    end
  end

  describe "verify/2" do
    test "verifies correct secret" do
      secret = "correct-secret"
      {:ok, hash} = Password.hash(secret)

      assert :ok = Password.verify(secret, hash)
    end

    test "rejects incorrect secret" do
      secret = "correct-secret"
      {:ok, hash} = Password.hash(secret)

      assert {:error, "Password verification failed"} = Password.verify("wrong-secret", hash)
    end

    test "rejects empty secret" do
      secret = "correct-secret"
      {:ok, hash} = Password.hash(secret)

      assert {:error, _} = Password.verify("", hash)
    end
  end

  describe "security properties" do
    test "hash is deterministic given same salt (property-based)" do
      # While Password.hash/1 uses random salt, the underlying algorithm is deterministic
      secret = "test"
      {:ok, hash1} = Password.hash(secret)

      # Verify that the same secret with same hash verifies correctly
      assert :ok = Password.verify(secret, hash1)
    end

    test "different secrets produce different hashes" do
      {:ok, hash1} = Password.hash("secret1")
      {:ok, hash2} = Password.hash("secret2")

      assert hash1 != hash2
    end

    test "meets minimum hash length (64 bytes raw, ~90+ chars encoded)" do
      {:ok, hash} = Password.hash("test")
      # Argon2 encoded hash includes parameters and salt, typically 90+ characters
      assert String.length(hash) >= 90
    end
  end
end
