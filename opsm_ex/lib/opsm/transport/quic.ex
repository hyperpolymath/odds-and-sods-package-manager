# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Transport.Quic do
  @moduledoc """
  QUIC/HTTP3 transport client for OPSM registry fetches.

  Provides high-level HTTP/3 operations over QUIC with:
  - 0-RTT connection resumption for repeat registry queries
  - Multiplexed streams (no head-of-line blocking)
  - Connection migration (resilient to network changes)
  - Graceful fallback to HTTP/2 when QUIC unavailable

  ## Architecture

  ```
  Opsm.Transport.Quic (this module — high-level API)
       ↓
  Opsm.Transport.QuicNif (NIF stubs)
       ↓
  native/quic_transport (Rust: quinn + h3 + rustler)
       ↓
  QUIC/UDP transport
  ```

  ## Fallback Behavior

  When the QUIC NIF is not available (not compiled), all operations
  transparently delegate to Req (HTTP/2 or HTTP/1.1). This ensures
  OPSM always works, with QUIC as a performance optimization.

  ## Usage

      # Automatic protocol selection
      {:ok, response} = Opsm.Transport.Quic.get("https://registry.npmjs.org/express")

      # Force QUIC
      {:ok, response} = Opsm.Transport.Quic.get("https://registry.npmjs.org/express", protocol: :quic)

      # Check availability
      Opsm.Transport.Quic.available?()  # => true/false
  """

  alias Opsm.Transport.{QuicNif, Protocol}
  alias Opsm.Verified.{Url, Json}
  require Logger

  @type response :: %{
          status: non_neg_integer(),
          body: binary() | map() | list(),
          headers: [{String.t(), String.t()}],
          protocol: Protocol.protocol(),
          latency_ms: non_neg_integer()
        }

  @type request_opts :: [
          timeout: non_neg_integer(),
          headers: [{String.t(), String.t()}],
          protocol: Protocol.protocol() | :auto,
          retry: non_neg_integer()
        ]

  # Connection pool: host -> {conn_ref, session_ticket}
  @conn_table :opsm_quic_connections

  @doc """
  Initialize QUIC connection pool. Called at application startup.
  """
  @spec init() :: :ok
  def init do
    if :ets.whereis(@conn_table) == :undefined do
      :ets.new(@conn_table, [:named_table, :public, :set])
    end

    Protocol.init()
    :ok
  end

  @doc """
  Check if QUIC/HTTP3 is available on this system.
  """
  @spec available?() :: boolean()
  def available? do
    QuicNif.nif_loaded?()
  end

  @doc """
  Probe whether a specific host supports QUIC.
  """
  @spec probe(String.t(), non_neg_integer()) :: {:ok, boolean()} | {:error, term()}
  def probe(host, port \\ 443) do
    if available?() do
      case QuicNif.probe(host, port) do
        {:ok, result} -> {:ok, result}
        {:error, reason} -> {:error, reason}
      end
    else
      {:ok, false}
    end
  end

  @doc """
  Make an HTTP GET request using the best available protocol.

  Validates the URL, selects the optimal transport protocol, and executes
  the request with automatic fallback on failure.
  """
  @spec get(String.t(), request_opts()) :: {:ok, response()} | {:error, term()}
  def get(url_string, opts \\ []) do
    with {:ok, validated_url} <- Url.validate(url_string) do
      url = Url.to_string(validated_url)
      host = extract_host(url)
      requested_proto = Keyword.get(opts, :protocol, :auto)

      protocol =
        case requested_proto do
          :auto -> Protocol.negotiate(host)
          proto -> proto
        end

      start_time = System.monotonic_time(:millisecond)

      result =
        case protocol do
          :quic -> quic_get(url, host, opts)
          _ -> http_get(url, opts)
        end

      elapsed = System.monotonic_time(:millisecond) - start_time

      case result do
        {:ok, response} ->
          Protocol.record_latency(host, protocol, elapsed)
          {:ok, Map.merge(response, %{protocol: protocol, latency_ms: elapsed})}

        {:error, _reason} when protocol == :quic ->
          # QUIC failed — fallback to HTTP/2
          Logger.info("QUIC failed for #{host}, falling back to HTTP/2")
          Protocol.force_protocol(host, :http2)
          fallback_start = System.monotonic_time(:millisecond)

          case http_get(url, opts) do
            {:ok, response} ->
              fallback_elapsed = System.monotonic_time(:millisecond) - fallback_start
              Protocol.record_latency(host, :http2, fallback_elapsed)
              {:ok, Map.merge(response, %{protocol: :http2, latency_ms: fallback_elapsed})}

            error ->
              error
          end

        error ->
          error
      end
    end
  end

  @doc """
  Make an HTTP GET request and parse JSON response.
  """
  @spec get_json(String.t(), request_opts()) :: {:ok, map() | list()} | {:error, term()}
  def get_json(url_string, opts \\ []) do
    case get(url_string, opts) do
      {:ok, %{body: body}} when is_binary(body) ->
        Json.decode(body)

      {:ok, %{body: body}} when is_map(body) or is_list(body) ->
        {:ok, body}

      {:ok, _} ->
        {:error, :invalid_response_body}

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Make an HTTP POST request with JSON body.
  """
  @spec post_json(String.t(), map() | list(), request_opts()) ::
          {:ok, response()} | {:error, term()}
  def post_json(url_string, body, opts \\ []) do
    with {:ok, validated_url} <- Url.validate(url_string),
         {:ok, json_body} <- Json.encode(body) do
      url = Url.to_string(validated_url)
      host = extract_host(url)
      protocol = Keyword.get(opts, :protocol, :auto)

      proto =
        case protocol do
          :auto -> Protocol.negotiate(host)
          p -> p
        end

      start_time = System.monotonic_time(:millisecond)

      result =
        case proto do
          :quic -> quic_post(url, host, json_body, opts)
          _ -> http_post(url, json_body, opts)
        end

      elapsed = System.monotonic_time(:millisecond) - start_time

      case result do
        {:ok, response} ->
          Protocol.record_latency(host, proto, elapsed)
          {:ok, Map.merge(response, %{protocol: proto, latency_ms: elapsed})}

        {:error, _} when proto == :quic ->
          Logger.info("QUIC POST failed for #{host}, falling back to HTTP/2")
          Protocol.force_protocol(host, :http2)
          http_post(url, json_body, opts)

        error ->
          error
      end
    end
  end

  @doc """
  POST JSON and parse JSON response.
  """
  @spec post_json_get_json(String.t(), map() | list(), request_opts()) ::
          {:ok, map() | list()} | {:error, term()}
  def post_json_get_json(url_string, body, opts \\ []) do
    case post_json(url_string, body, opts) do
      {:ok, %{body: resp_body}} when is_binary(resp_body) ->
        Json.decode(resp_body)

      {:ok, %{body: resp_body}} when is_map(resp_body) or is_list(resp_body) ->
        {:ok, resp_body}

      {:ok, _} ->
        {:error, :invalid_response_body}

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Close all QUIC connections and clear the connection pool.
  """
  @spec close_all() :: :ok
  def close_all do
    if :ets.whereis(@conn_table) != :undefined do
      :ets.foldl(
        fn {_host, {conn_ref, _ticket}}, _acc ->
          try do
            QuicNif.close(conn_ref)
          rescue
            _ -> :ok
          end
        end,
        :ok,
        @conn_table
      )

      :ets.delete_all_objects(@conn_table)
    end

    :ok
  end

  @doc """
  Get statistics about a QUIC connection to a host.
  """
  @spec connection_stats(String.t()) :: {:ok, map()} | {:error, :not_connected}
  def connection_stats(host) do
    case :ets.lookup(@conn_table, host) do
      [{_, {conn_ref, _}}] ->
        case QuicNif.connection_stats(conn_ref) do
          {:ok, stats} -> {:ok, stats}
          {:error, reason} -> {:error, reason}
        end

      [] ->
        {:error, :not_connected}
    end
  rescue
    ArgumentError -> {:error, :not_connected}
  end

  @doc """
  Return a summary of the transport layer status.
  """
  @spec status() :: map()
  def status do
    %{
      quic_available: available?(),
      supported_protocols: Protocol.supported_protocols(),
      active_connections: active_connection_count(),
      nif_loaded: QuicNif.nif_loaded?()
    }
  end

  # =============================================================================
  # Internal: QUIC Operations
  # =============================================================================

  defp quic_get(url, host, opts) do
    timeout = Keyword.get(opts, :timeout, 10_000)
    headers = Keyword.get(opts, :headers, [])

    with {:ok, conn_ref} <- get_or_create_connection(host, 443, timeout) do
      path = extract_path(url)

      case QuicNif.h3_get(conn_ref, path, headers) do
        {:ok, {status, resp_headers, body}} ->
          {:ok, %{status: status, headers: resp_headers, body: body}}

        {:error, reason} ->
          # Connection may be stale — remove from pool
          :ets.delete(@conn_table, host)
          {:error, {:quic_error, reason}}
      end
    end
  rescue
    e -> {:error, {:quic_exception, Exception.message(e)}}
  end

  defp quic_post(url, host, json_body, opts) do
    timeout = Keyword.get(opts, :timeout, 10_000)
    headers = Keyword.get(opts, :headers, [])
    headers = [{"content-type", "application/json"} | headers]

    with {:ok, conn_ref} <- get_or_create_connection(host, 443, timeout) do
      path = extract_path(url)

      case QuicNif.h3_post(conn_ref, path, json_body, headers) do
        {:ok, {status, resp_headers, body}} ->
          {:ok, %{status: status, headers: resp_headers, body: body}}

        {:error, reason} ->
          :ets.delete(@conn_table, host)
          {:error, {:quic_error, reason}}
      end
    end
  rescue
    e -> {:error, {:quic_exception, Exception.message(e)}}
  end

  defp get_or_create_connection(host, port, timeout) do
    case :ets.lookup(@conn_table, host) do
      [{_, {_conn_ref, session_ticket}}] ->
        # Try 0-RTT resumption with cached session ticket
        case QuicNif.connect_0rtt(host, port, session_ticket) do
          {:ok, new_ref} ->
            :ets.insert(@conn_table, {host, {new_ref, session_ticket}})
            {:ok, new_ref}

          {:error, _} ->
            # 0-RTT failed, full handshake
            fresh_connect(host, port, timeout)
        end

      [] ->
        fresh_connect(host, port, timeout)
    end
  rescue
    ArgumentError -> fresh_connect(host, port, timeout)
  end

  defp fresh_connect(host, port, timeout) do
    case QuicNif.connect(host, port, timeout: timeout) do
      {:ok, conn_ref} ->
        :ets.insert(@conn_table, {host, {conn_ref, nil}})
        {:ok, conn_ref}

      {:error, reason} ->
        {:error, {:quic_connect_failed, reason}}
    end
  end

  # =============================================================================
  # Internal: HTTP/2 and HTTP/1.1 Fallback (via Req)
  # =============================================================================

  defp http_get(url, opts) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    headers = Keyword.get(opts, :headers, [])
    retry_count = Keyword.get(opts, :retry, 2)

    try do
      case Req.get(url,
             receive_timeout: timeout,
             retry: :transient,
             max_retries: retry_count,
             headers: headers
           ) do
        {:ok, %Req.Response{status: status, body: body, headers: resp_headers}}
        when status in 200..299 ->
          {:ok, %{status: status, body: body, headers: resp_headers}}

        {:ok, %Req.Response{status: status}} ->
          {:error, {:http_error, status}}

        {:error, %Req.TransportError{reason: reason}} ->
          {:error, {:transport_error, reason}}

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      e -> {:error, {:exception, e}}
    end
  end

  defp http_post(url, json_body, opts) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    headers = Keyword.get(opts, :headers, [])
    retry_count = Keyword.get(opts, :retry, 2)
    headers = [{"content-type", "application/json"} | headers]

    try do
      case Req.post(url,
             body: json_body,
             receive_timeout: timeout,
             retry: :transient,
             max_retries: retry_count,
             headers: headers
           ) do
        {:ok, %Req.Response{status: status, body: body, headers: resp_headers}}
        when status in 200..299 ->
          {:ok, %{status: status, body: body, headers: resp_headers}}

        {:ok, %Req.Response{status: status}} ->
          {:error, {:http_error, status}}

        {:error, %Req.TransportError{reason: reason}} ->
          {:error, {:transport_error, reason}}

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      e -> {:error, {:exception, e}}
    end
  end

  # =============================================================================
  # Internal: URL Helpers
  # =============================================================================

  defp extract_host(url) do
    uri = URI.parse(url)
    uri.host || "localhost"
  end

  defp extract_path(url) do
    uri = URI.parse(url)
    path = uri.path || "/"
    query = uri.query

    if query do
      "#{path}?#{query}"
    else
      path
    end
  end

  defp active_connection_count do
    if :ets.whereis(@conn_table) != :undefined do
      :ets.info(@conn_table, :size)
    else
      0
    end
  end
end
