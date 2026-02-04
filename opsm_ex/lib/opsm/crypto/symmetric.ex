# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule Opsm.Crypto.Symmetric do
  @moduledoc """
  ChaCha20-Poly1305 symmetric encryption with 256-bit keys.

  Features:
  - 256-bit keys for quantum margin
  - 96-bit nonces (sufficient for most use cases)
  - AEAD (Authenticated Encryption with Associated Data)

  Aligns with SECURITY-STANDARDS.scm Symmetric requirements.

  Note: Using standard ChaCha20-Poly1305 instead of XChaCha20-Poly1305
  due to library availability. 96-bit nonces are secure when used correctly
  (never reuse nonces with the same key).
  """

  @key_size 32  # 256 bits
  @nonce_size 12  # 96 bits (ChaCha20-Poly1305 standard nonce)
  @tag_size 16  # 128 bits (Poly1305 tag)

  @doc """
  Encrypt plaintext with XChaCha20-Poly1305 AEAD.

  Returns encrypted data in format: nonce || ciphertext || tag

  ## Examples

      iex> key = Opsm.Crypto.Symmetric.generate_key()
      iex> {:ok, encrypted} = Opsm.Crypto.Symmetric.encrypt("secret data", key, "context")
      iex> byte_size(encrypted) > 24 + 16
      true
  """
  def encrypt(plaintext, key, associated_data \\ "")
      when is_binary(plaintext) and is_binary(key) do
    with :ok <- validate_key(key),
         nonce <- :crypto.strong_rand_bytes(@nonce_size),
         {ciphertext, tag} <-
           :crypto.crypto_one_time_aead(
             :chacha20_poly1305,
             key,
             nonce,
             plaintext,
             associated_data,
             true
           ) do
      # Format: nonce || ciphertext || tag
      {:ok, nonce <> ciphertext <> tag}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Decrypt ciphertext encrypted with XChaCha20-Poly1305 AEAD.

  ## Examples

      iex> key = Opsm.Crypto.Symmetric.generate_key()
      iex> {:ok, encrypted} = Opsm.Crypto.Symmetric.encrypt("secret", key, "ctx")
      iex> {:ok, decrypted} = Opsm.Crypto.Symmetric.decrypt(encrypted, key, "ctx")
      iex> decrypted
      "secret"
  """
  def decrypt(encrypted, key, associated_data \\ "")
      when is_binary(encrypted) and is_binary(key) do
    with :ok <- validate_key(key),
         <<nonce::binary-size(12), ciphertext_and_tag::binary>> <- encrypted,
         ciphertext_size = byte_size(ciphertext_and_tag) - @tag_size,
         <<ciphertext::binary-size(ciphertext_size), tag::binary-size(16)>> <-
           ciphertext_and_tag do
      # Decrypt uses 7-arity function with tag as separate parameter
      case :crypto.crypto_one_time_aead(
             :chacha20_poly1305,
             key,
             nonce,
             ciphertext,
             associated_data,
             tag,
             false
           ) do
        plaintext when is_binary(plaintext) -> {:ok, plaintext}
        :error -> {:error, "Decryption failed (authentication failure)"}
      end
    else
      :error -> {:error, "Invalid encrypted data format"}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Generate a cryptographically secure 256-bit key.

  ## Examples

      iex> key = Opsm.Crypto.Symmetric.generate_key()
      iex> byte_size(key)
      32
  """
  def generate_key do
    :crypto.strong_rand_bytes(@key_size)
  end

  @doc """
  Generate a 96-bit nonce for ChaCha20-Poly1305.

  WARNING: Never reuse a nonce with the same key. Generate a new nonce
  for each encryption operation.
  """
  def generate_nonce do
    :crypto.strong_rand_bytes(@nonce_size)
  end

  defp validate_key(key) when byte_size(key) == @key_size, do: :ok
  defp validate_key(_), do: {:error, "Key must be 256 bits (32 bytes)"}
end
