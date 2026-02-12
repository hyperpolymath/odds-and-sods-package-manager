# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule Opsm.Transport.QuicNif do
  @moduledoc """
  NIF bindings for QUIC/HTTP3 transport via the `quinn` Rust crate.

  This module provides low-level QUIC operations. Use `Opsm.Transport.Quic`
  for the high-level API with error handling and fallback logic.

  When the NIF is not compiled (no Rust toolchain, missing deps), all functions
  return `:nif_not_loaded` errors and the system gracefully falls back to HTTP/2.
  """

  @on_load :load_nif

  @doc false
  def load_nif do
    nif_path =
      :opsm
      |> :code.priv_dir()
      |> Path.join("native/quic_transport")

    case :erlang.load_nif(String.to_charlist(nif_path), 0) do
      :ok ->
        :ok

      {:error, {:load_failed, _reason}} ->
        # NIF not compiled - QUIC will be unavailable, HTTP/2 fallback used
        :ok

      {:error, reason} ->
        require Logger
        Logger.warning("QUIC NIF load failed: #{inspect(reason)} — falling back to HTTP/2")
        :ok
    end
  end

  @doc """
  Check if the QUIC NIF is loaded and functional.
  """
  def nif_loaded? do
    false
  end

  @doc """
  Probe whether a host:port supports QUIC/HTTP3.
  Returns `true` if QUIC handshake succeeds within timeout.
  """
  def probe(_host, _port, _timeout_ms \\ 3000) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @doc """
  Open a QUIC connection to a host:port.
  Returns an opaque connection reference.
  """
  def connect(_host, _port, _opts \\ []) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @doc """
  Send an HTTP/3 GET request on an established QUIC connection.
  Returns `{status, headers, body}`.
  """
  def h3_get(_conn_ref, _path, _headers \\ []) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @doc """
  Send an HTTP/3 POST request on an established QUIC connection.
  Returns `{status, headers, body}`.
  """
  def h3_post(_conn_ref, _path, _body, _headers \\ []) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @doc """
  Close a QUIC connection gracefully.
  """
  def close(_conn_ref) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @doc """
  Get connection statistics (RTT, bytes sent/received, streams).
  """
  def connection_stats(_conn_ref) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @doc """
  Perform a 0-RTT reconnection to a previously-connected host.
  Uses cached session tickets for zero round-trip resumption.
  """
  def connect_0rtt(_host, _port, _session_ticket) do
    :erlang.nif_error(:nif_not_loaded)
  end
end
