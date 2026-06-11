# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Crypto.SymmetricTest do
  use ExUnit.Case, async: true
  alias Opsm.Crypto.Symmetric

  describe "encrypt/3 and decrypt/3" do
    test "encrypt and decrypt with ChaCha20-Poly1305" do
      key = Symmetric.generate_key()
      plaintext = "sensitive-api-key-data"
      associated_data = "lockfile-v1.0.0"

      {:ok, encrypted} = Symmetric.encrypt(plaintext, key, associated_data)
      {:ok, decrypted} = Symmetric.decrypt(encrypted, key, associated_data)

      assert decrypted == plaintext
    end

    test "authentication failure with wrong associated data" do
      key = Symmetric.generate_key()
      plaintext = "data"

      {:ok, encrypted} = Symmetric.encrypt(plaintext, key, "correct-context")

      assert {:error, _} = Symmetric.decrypt(encrypted, key, "wrong-context")
    end

    test "authentication failure with wrong key" do
      key1 = Symmetric.generate_key()
      key2 = Symmetric.generate_key()
      plaintext = "secret"

      {:ok, encrypted} = Symmetric.encrypt(plaintext, key1, "context")

      assert {:error, _} = Symmetric.decrypt(encrypted, key2, "context")
    end

    test "encryption without associated data" do
      key = Symmetric.generate_key()
      plaintext = "no-context-data"

      {:ok, encrypted} = Symmetric.encrypt(plaintext, key)
      {:ok, decrypted} = Symmetric.decrypt(encrypted, key)

      assert decrypted == plaintext
    end

    test "handles empty plaintext" do
      key = Symmetric.generate_key()

      {:ok, encrypted} = Symmetric.encrypt("", key)
      {:ok, decrypted} = Symmetric.decrypt(encrypted, key)

      assert decrypted == ""
    end

    test "handles large plaintext" do
      key = Symmetric.generate_key()
      large_plaintext = String.duplicate("A", 10_000)

      {:ok, encrypted} = Symmetric.encrypt(large_plaintext, key)
      {:ok, decrypted} = Symmetric.decrypt(encrypted, key)

      assert decrypted == large_plaintext
    end
  end

  describe "generate_key/0" do
    test "generates 256-bit keys" do
      key = Symmetric.generate_key()
      assert byte_size(key) == 32  # 256 bits
    end

    test "generates different keys each time" do
      key1 = Symmetric.generate_key()
      key2 = Symmetric.generate_key()
      assert key1 != key2
    end
  end

  describe "validation" do
    test "rejects invalid key size for encryption" do
      invalid_key = :crypto.strong_rand_bytes(16)  # 128 bits, too small
      plaintext = "data"

      assert {:error, "Key must be 256 bits (32 bytes)"} =
               Symmetric.encrypt(plaintext, invalid_key)
    end

    test "rejects invalid key size for decryption" do
      key = Symmetric.generate_key()
      {:ok, encrypted} = Symmetric.encrypt("data", key)

      invalid_key = :crypto.strong_rand_bytes(16)

      assert {:error, "Key must be 256 bits (32 bytes)"} =
               Symmetric.decrypt(encrypted, invalid_key)
    end

    test "encrypted output includes nonce, ciphertext, and tag" do
      key = Symmetric.generate_key()
      plaintext = "test"

      {:ok, encrypted} = Symmetric.encrypt(plaintext, key)

      # nonce (12) + ciphertext (4) + tag (16) = 32 bytes minimum
      assert byte_size(encrypted) >= 12 + byte_size(plaintext) + 16
    end
  end

  describe "security properties" do
    test "same plaintext produces different ciphertexts (random nonce)" do
      key = Symmetric.generate_key()
      plaintext = "same-data"

      {:ok, encrypted1} = Symmetric.encrypt(plaintext, key)
      {:ok, encrypted2} = Symmetric.encrypt(plaintext, key)

      # Different nonces mean different ciphertexts
      assert encrypted1 != encrypted2
    end

    test "ciphertext cannot be decrypted without correct key (confidentiality)" do
      key = Symmetric.generate_key()
      wrong_key = Symmetric.generate_key()
      plaintext = "confidential"

      {:ok, encrypted} = Symmetric.encrypt(plaintext, key)

      assert {:error, _} = Symmetric.decrypt(encrypted, wrong_key)
    end

    test "tampered ciphertext is rejected (integrity)" do
      key = Symmetric.generate_key()
      plaintext = "authentic"

      {:ok, encrypted} = Symmetric.encrypt(plaintext, key)

      # Tamper with a byte in the ciphertext
      <<nonce::binary-size(24), rest::binary>> = encrypted
      <<first_byte, rest_bytes::binary>> = rest
      tampered = nonce <> <<Bitwise.bxor(first_byte, 1)>> <> rest_bytes

      assert {:error, _} = Symmetric.decrypt(tampered, key)
    end
  end
end
