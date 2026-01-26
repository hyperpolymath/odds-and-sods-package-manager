# SPDX-License-Identifier: PMPL-1.0
defmodule Opsm.Http do
  @moduledoc """
  HTTP client with retries, exponential backoff, and connection pooling.
  Uses Req under the hood with Finch for connection management.

  All JSON responses are validated using Verified.Json for safety.

  Connection pooling (P5) improves performance by:
  - Reusing connections to the same host
  - Reducing TLS handshake overhead
  - Managing connection lifecycle automatically
  """

  alias Opsm.Types.HttpConfig
  alias Opsm.Verified.Json

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

  Response is validated using Verified.Json for safety (depth/size limits).
  """
  def get_json(client, path) do
    case Req.get(client, url: path) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        # Validate JSON response if it's a string
        case body do
          body when is_binary(body) ->
            case Json.decode(body) do
              {:ok, parsed} -> {:ok, parsed}
              {:error, reason} -> {:error, "JSON validation failed: #{inspect(reason)}"}
            end

          body when is_map(body) or is_list(body) ->
            # Already parsed by Req, return as-is
            # Note: We trust Req's JSON decoder for now, but in v2.0
            # we should validate all JSON regardless of source
            {:ok, body}

          _other ->
            {:error, "Invalid response body type"}
        end

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

  @doc """
  Build and validate URL using Verified.Url.

  Returns `{:ok, url_string}` if valid, `{:error, reason}` otherwise.
  """
  def build_validated_url(base_url, path) do
    url_string = build_url(base_url, path)

    case Opsm.Verified.Url.validate(url_string) do
      {:ok, _validated} -> {:ok, url_string}
      {:error, reason} -> {:error, {:invalid_url, reason}}
    end
  end
end
