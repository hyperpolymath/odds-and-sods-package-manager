# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Crypto.PostQuantum.Nif do
  @moduledoc """
  Rust NIF bindings for post-quantum cryptographic operations.

  Provides ML-DSA-87 (Dilithium5), SLH-DSA (SPHINCS+-256f), and
  ML-KEM-1024 (Kyber-1024) via the pqcrypto Rust crate.

  When the NIF is not compiled or available, all functions raise
  :nif_not_loaded. The parent module (PostQuantum) wraps these
  with graceful degradation via available?/0 checks.
  """

  @on_load :load_nif

  def load_nif do
    path = :filename.join(:code.priv_dir(:opsm), ~c"native/libopsm_pq_nif")

    case :erlang.load_nif(path, 0) do
      :ok -> :ok
      {:error, _} -> :ok
    end
  end

  # ML-DSA-87 (Dilithium5) --- FIPS 204
  def dilithium5_keypair, do: :erlang.nif_error(:nif_not_loaded)
  def dilithium5_sign(_message, _secret_key), do: :erlang.nif_error(:nif_not_loaded)
  def dilithium5_verify(_message, _signature, _public_key), do: :erlang.nif_error(:nif_not_loaded)

  # SLH-DSA (SPHINCS+-256f) --- FIPS 205
  def sphincs_plus_keypair, do: :erlang.nif_error(:nif_not_loaded)
  def sphincs_plus_sign(_message, _secret_key), do: :erlang.nif_error(:nif_not_loaded)

  def sphincs_plus_verify(_message, _signature, _public_key),
    do: :erlang.nif_error(:nif_not_loaded)

  # ML-KEM-1024 (Kyber-1024) --- FIPS 203
  def kyber1024_keypair, do: :erlang.nif_error(:nif_not_loaded)
  def kyber1024_encapsulate(_public_key), do: :erlang.nif_error(:nif_not_loaded)
  def kyber1024_decapsulate(_ciphertext, _secret_key), do: :erlang.nif_error(:nif_not_loaded)
end
