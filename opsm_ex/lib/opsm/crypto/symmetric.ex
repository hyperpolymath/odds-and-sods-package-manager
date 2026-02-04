# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule Opsm.Crypto.Symmetric do
  @moduledoc """
  XChaCha20-Poly1305 symmetric encryption with 256-bit keys.

  Features:
  - 256-bit keys for quantum margin
  - 192-bit nonces (larger nonce space than ChaCha20)
  - AEAD (Authenticated Encryption with Associated Data)

  Aligns with SECURITY-STANDARDS.scm Symmetric requirements.
  """

  @key_size 32  # 256 bits
  @nonce_size 24  # 192 bits (XChaCha20 extended nonce)
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
             :xchacha20_poly1305,
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
         <<nonce::binary-size(24), ciphertext_and_tag::binary>> <- encrypted,
         ciphertext_size = byte_size(ciphertext_and_tag) - @tag_size,
         <<ciphertext::binary-size(ciphertext_size), tag::binary-size(16)>> <-
           ciphertext_and_tag,
         plaintext <-
           :crypto.crypto_one_time_aead(
             :xchacha20_poly1305,
             key,
             nonce,
             ciphertext <> tag,
             associated_data,
             false
           ) do
      {:ok, plaintext}
    else
      :error -> {:error, "Decryption failed (authentication failure)"}
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

  defp validate_key(key) when byte_size(key) == @key_size, do: :ok
  defp validate_key(_), do: {:error, "Key must be 256 bits (32 bytes)"}
end
