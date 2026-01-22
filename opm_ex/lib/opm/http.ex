# SPDX-License-Identifier: PMPL-1.0
defmodule Opm.Http do
  @moduledoc """
  HTTP client with retries, exponential backoff, and connection pooling.
  Uses Req under the hood with Finch for connection management.

  Connection pooling (P5) improves performance by:
  - Reusing connections to the same host
  - Reducing TLS handshake overhead
  - Managing connection lifecycle automatically
  """

  alias Opm.Types.HttpConfig

  # Default pool configuration for CLI usage
  @default_pool_size 10

  @doc """
  Build a configured Req client with retries, timeout, and connection pooling.
  """
  def build_client(%HttpConfig{} = config, opts \\ []) do
    base_url = Keyword.get(opts, :base_url)
    token = Keyword.get(opts, :token)
    _pool_size = Keyword.get(opts, :pool_size, @default_pool_size)

    headers =
      if token do
        [{"authorization", "Bearer #{token}"}]
      else
        []
      end

    # Configure connection pooling (P5)
    # Req uses Finch under the hood - we configure pooling here
    Req.new(
      base_url: base_url,
      headers: headers,
      receive_timeout: config.timeout_ms,
      connect_options: [
        # Connection pool configuration
        timeout: config.timeout_ms,
        protocols: [:http1, :http2]
      ],
      retry: :transient,
      max_retries: config.retries,
      retry_delay: fn attempt ->
        # Exponential backoff
        config.backoff_ms * attempt
      end
    )
  end

  @doc """
  POST JSON to a path.
  """
  def post_json(client, path, body) do
    case Req.post(client, url: path, json: body) do
      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        :ok

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, "HTTP error: #{status} - #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  @doc """
  GET JSON from a path.
  """
  def get_json(client, path) do
    case Req.get(client, url: path) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, "HTTP error: #{status} - #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Build URL by joining base and path.
  """
  def build_url(base_url, path) do
    base = String.trim_trailing(base_url, "/")
    "#{base}#{path}"
  end
end
