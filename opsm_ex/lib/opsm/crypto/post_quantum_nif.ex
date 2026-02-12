# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule Opsm.Crypto.PostQuantum.Nif do
  @moduledoc """
  Rust NIF bindings for post-quantum cryptography.

  This module is loaded from the `pq_crypto` Rust NIF crate.
  If Rustler is not available or the NIF is not compiled, functions
  raise `:nif_not_loaded`. Callers should use `Opsm.Crypto.PostQuantum`
  which provides graceful fallback.

  Build: `mix compile` with `{:rustler, "~> 0.35"}` in deps.
  """

  @on_load :load_nif

  def load_nif do
    nif_path = :filename.join(:code.priv_dir(:opsm), ~c"native/pq_crypto")

    case :erlang.load_nif(nif_path, 0) do
      :ok -> :ok
      {:error, {:load_failed, _}} -> :ok  # NIF not compiled yet — graceful degradation
      {:error, {:reload, _}} -> :ok       # Already loaded
      {:error, reason} ->
        require Logger
        Logger.warning("PQ crypto NIF not available: #{inspect(reason)}")
        :ok
    end
  end

  # Dilithium5 (ML-DSA-87) — FIPS 204
  def dilithium5_keypair, do: :erlang.nif_error(:nif_not_loaded)
  def dilithium5_sign(_message, _secret_key), do: :erlang.nif_error(:nif_not_loaded)
  def dilithium5_verify(_message, _signature, _public_key), do: :erlang.nif_error(:nif_not_loaded)

  # SPHINCS+-256f (SLH-DSA) — FIPS 205
  def sphincs_plus_keypair, do: :erlang.nif_error(:nif_not_loaded)
  def sphincs_plus_sign(_message, _secret_key), do: :erlang.nif_error(:nif_not_loaded)
  def sphincs_plus_verify(_message, _signature, _public_key), do: :erlang.nif_error(:nif_not_loaded)

  # Kyber-1024 (ML-KEM-1024) — FIPS 203
  def kyber1024_keypair, do: :erlang.nif_error(:nif_not_loaded)
  def kyber1024_encapsulate(_public_key), do: :erlang.nif_error(:nif_not_loaded)
  def kyber1024_decapsulate(_ciphertext, _secret_key), do: :erlang.nif_error(:nif_not_loaded)
end
