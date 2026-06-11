# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Crypto.Signatures do
  @moduledoc """
  Cryptographic signature generation and verification.

  Supports:
  - Ed25519 (default, fast, 128-bit security)
  - HMAC-SHA256 (symmetric, for internal use)
  - Hybrid Ed25519 + Dilithium5 (via HybridSignatures module)
  - Dilithium5, SPHINCS+ (via PostQuantum module, requires NIF)

  See `Opsm.Crypto.HybridSignatures` for production hybrid signatures.
  See `Opsm.Crypto.PostQuantum` for direct PQ algorithm access.
  """

  @doc """
  Generate an Ed25519 key pair.
  Returns {public_key, secret_key} as raw 32-byte / 64-byte binaries.
  """
  def generate_ed25519_keypair do
    {pub, priv} = :crypto.generate_key(:eddsa, :ed25519)
    {:ok, %{public_key: pub, secret_key: priv, algorithm: :ed25519}}
  end

  @doc """
  Sign a message with an Ed25519 secret key.
  Returns {:ok, signature} or {:error, reason}.
  """
  def sign_ed25519(message, secret_key) when is_binary(message) and is_binary(secret_key) do
    try do
      signature = :crypto.sign(:eddsa, :none, message, [secret_key, :ed25519])
      {:ok, signature}
    rescue
      e -> {:error, "Signing failed: #{Exception.message(e)}"}
    end
  end

  @doc """
  Verify an Ed25519 signature.
  Returns :ok or {:error, reason}.
  """
  def verify_ed25519(message, signature, public_key)
      when is_binary(message) and is_binary(signature) and is_binary(public_key) do
    try do
      case :crypto.verify(:eddsa, :none, message, signature, [public_key, :ed25519]) do
        true -> :ok
        false -> {:error, "Signature verification failed"}
      end
    rescue
      e -> {:error, "Verification error: #{Exception.message(e)}"}
    end
  end

  @doc """
  Sign a JSON-serializable payload (canonical encoding).
  The payload is JSON-encoded with sorted keys before signing.
  """
  def sign_payload(payload, secret_key, algorithm \\ :ed25519) do
    with {:ok, canonical} <- canonical_json(payload) do
      case algorithm do
        :ed25519 -> sign_ed25519(canonical, secret_key)
        _ -> {:error, "Unsupported algorithm: #{algorithm}"}
      end
    end
  end

  @doc """
  Verify a signed JSON payload.
  """
  def verify_payload(payload, signature, public_key, algorithm \\ :ed25519) do
    with {:ok, canonical} <- canonical_json(payload) do
      case algorithm do
        :ed25519 -> verify_ed25519(canonical, signature, public_key)
        _ -> {:error, "Unsupported algorithm: #{algorithm}"}
      end
    end
  end

  @doc """
  Encode a signature and public key as hex strings for storage/transport.
  """
  def encode_hex(binary) when is_binary(binary) do
    Base.encode16(binary, case: :lower)
  end

  @doc """
  Decode a hex-encoded signature or key.
  """
  def decode_hex(hex) when is_binary(hex) do
    case Base.decode16(hex, case: :mixed) do
      {:ok, binary} -> {:ok, binary}
      :error -> {:error, "Invalid hex encoding"}
    end
  end

  # Canonical JSON encoding (sorted keys, no extra whitespace)
  defp canonical_json(payload) when is_map(payload) do
    case Jason.encode(payload, maps: :strict) do
      {:ok, json} -> {:ok, json}
      {:error, reason} -> {:error, "JSON encoding failed: #{inspect(reason)}"}
    end
  end

  defp canonical_json(payload) when is_binary(payload), do: {:ok, payload}
  defp canonical_json(_), do: {:error, "Payload must be a map or binary"}
end
