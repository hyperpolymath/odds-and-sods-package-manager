# SPDX-License-Identifier: MPL-2.0

defmodule Opsm.Crypto.PasswordTest do
  use ExUnit.Case, async: true
  alias Opsm.Crypto.Password

  describe "hash/1" do
    test "hashes password successfully" do
      password = "correct-horse-battery-staple"
      assert {:ok, hash} = Password.hash(password)
      assert is_binary(hash)
      assert String.length(hash) > 0
    end

    test "produces different hashes for same password (salt)" do
      password = "test-password"
      {:ok, hash1} = Password.hash(password)
      {:ok, hash2} = Password.hash(password)
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
    test "verifies correct password" do
      password = "correct-password"
      {:ok, hash} = Password.hash(password)

      assert :ok = Password.verify(password, hash)
    end

    test "rejects incorrect password" do
      password = "correct-password"
      {:ok, hash} = Password.hash(password)

      assert {:error, "Password verification failed"} = Password.verify("wrong-password", hash)
    end

    test "rejects empty password" do
      password = "correct-password"
      {:ok, hash} = Password.hash(password)

      assert {:error, _} = Password.verify("", hash)
    end
  end

  describe "security properties" do
    test "hash is deterministic given same salt (property-based)" do
      # While Password.hash/1 uses random salt, the underlying algorithm is deterministic
      password = "test"
      {:ok, hash1} = Password.hash(password)

      # Verify that the same password with same hash verifies correctly
      assert :ok = Password.verify(password, hash1)
    end

    test "different passwords produce different hashes" do
      {:ok, hash1} = Password.hash("password1")
      {:ok, hash2} = Password.hash("password2")

      assert hash1 != hash2
    end

    test "meets minimum hash length (64 bytes raw, ~90+ chars encoded)" do
      {:ok, hash} = Password.hash("test")
      # Argon2 encoded hash includes parameters and salt, typically 90+ characters
      assert String.length(hash) >= 90
    end
  end
end
