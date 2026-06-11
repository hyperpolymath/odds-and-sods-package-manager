# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Transport.Protocol do
  @moduledoc """
  Transport protocol negotiation and abstraction layer.

  Provides automatic protocol selection with graceful degradation:
    QUIC/HTTP3 → HTTP/2 → HTTP/1.1

  The transport layer sits between VerifiedHttp and the actual network I/O,
  allowing OPSM to leverage QUIC's advantages (0-RTT, multiplexing, connection
  migration) when available while falling back to HTTP/2 or HTTP/1.1.

  Protocol selection is per-host and cached in an ETS table for the session
  lifetime, avoiding repeated negotiation overhead.
  """

  require Logger

  @type protocol :: :quic | :http2 | :http1
  @type transport_result :: {:ok, protocol(), map()} | {:error, term()}

  # ETS table for caching protocol support per host
  @cache_table :opsm_protocol_cache
  # Cache entry TTL: 5 minutes
  @cache_ttl_ms 300_000

  @doc """
  Initialize the protocol cache. Called at application startup.
  """
  @spec init() :: :ok
  def init do
    if :ets.whereis(@cache_table) == :undefined do
      :ets.new(@cache_table, [:named_table, :public, :set, read_concurrency: true])
    end

    :ok
  end

  @doc """
  Determine the best available protocol for a given host.

  Checks (in order):
  1. ETS cache for a recent probe result
  2. QUIC availability (NIF loaded + host supports Alt-Svc h3)
  3. Falls back to HTTP/2 or HTTP/1.1

  Returns the recommended protocol atom.
  """
  @spec negotiate(String.t()) :: protocol()
  def negotiate(host) do
    case cached_protocol(host) do
      {:ok, proto} ->
        proto

      :miss ->
        proto = probe_host(host)
        cache_protocol(host, proto)
        proto
    end
  end

  @doc """
  Returns whether QUIC/HTTP3 transport is available on this system.

  Requires the Rust NIF to be compiled and loaded.
  """
  @spec quic_available?() :: boolean()
  def quic_available? do
    Opsm.Transport.Quic.available?()
  end

  @doc """
  Returns the list of supported protocols in preference order.
  """
  @spec supported_protocols() :: [protocol()]
  def supported_protocols do
    if quic_available?() do
      [:quic, :http2, :http1]
    else
      [:http2, :http1]
    end
  end

  @doc """
  Get transport statistics for a host.
  """
  @spec host_stats(String.t()) :: map()
  def host_stats(host) do
    case :ets.lookup(@cache_table, {:stats, host}) do
      [{_, stats}] -> stats
      [] -> %{requests: 0, avg_latency_ms: 0, protocol: :unknown}
    end
  rescue
    ArgumentError -> %{requests: 0, avg_latency_ms: 0, protocol: :unknown}
  end

  @doc """
  Record a request's latency for adaptive protocol selection.
  """
  @spec record_latency(String.t(), protocol(), non_neg_integer()) :: :ok
  def record_latency(host, protocol, latency_ms) do
    key = {:stats, host}

    stats =
      case :ets.lookup(@cache_table, key) do
        [{_, existing}] -> existing
        [] -> %{requests: 0, total_latency_ms: 0, protocol: protocol}
      end

    updated = %{
      stats
      | requests: stats.requests + 1,
        total_latency_ms: Map.get(stats, :total_latency_ms, 0) + latency_ms,
        protocol: protocol
    }

    avg = if updated.requests > 0, do: div(updated.total_latency_ms, updated.requests), else: 0
    :ets.insert(@cache_table, {key, Map.put(updated, :avg_latency_ms, avg)})
    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc """
  Clear the protocol cache (useful for testing or after network changes).
  """
  @spec clear_cache() :: :ok
  def clear_cache do
    if :ets.whereis(@cache_table) != :undefined do
      :ets.delete_all_objects(@cache_table)
    end

    :ok
  end

  @doc """
  Force a specific protocol for a host (for testing or user overrides).
  """
  @spec force_protocol(String.t(), protocol()) :: :ok
  def force_protocol(host, protocol) when protocol in [:quic, :http2, :http1] do
    cache_protocol(host, protocol)
    :ok
  end

  # =============================================================================
  # Internal: Cache Operations
  # =============================================================================

  defp cached_protocol(host) do
    case :ets.lookup(@cache_table, {:proto, host}) do
      [{_, {proto, timestamp}}] ->
        if System.monotonic_time(:millisecond) - timestamp < @cache_ttl_ms do
          {:ok, proto}
        else
          :miss
        end

      [] ->
        :miss
    end
  rescue
    ArgumentError -> :miss
  end

  defp cache_protocol(host, proto) do
    timestamp = System.monotonic_time(:millisecond)
    :ets.insert(@cache_table, {{:proto, host}, {proto, timestamp}})
  rescue
    ArgumentError -> :ok
  end

  # =============================================================================
  # Internal: Host Probing
  # =============================================================================

  defp probe_host(host) do
    if quic_available?() && quic_probe(host) do
      Logger.debug("QUIC/HTTP3 available for #{host}")
      :quic
    else
      # HTTP/2 is widely supported; Req/Finch handles ALPN negotiation.
      # We optimistically assume HTTP/2 is available for HTTPS hosts.
      Logger.debug("HTTP/2 available for #{host}")
      :http2
    end
  end

  defp quic_probe(host) do
    case Opsm.Transport.Quic.probe(host, 443) do
      {:ok, true} -> true
      _ -> false
    end
  end
end
