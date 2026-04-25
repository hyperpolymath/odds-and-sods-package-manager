# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule Opsm.Verified.Http do
  @moduledoc """
  Safe HTTP client that validates URLs before making requests.

  All HTTP operations go through URL validation to prevent:
  - SSRF attacks (Server-Side Request Forgery)
  - Requests to internal/private networks
  - Requests using unsafe protocols

  v1.0: Wraps Req with Verified.Url validation.
  v2.0: Proven correct via Idris2 dependent types (requests to valid URLs only).
  """

  alias Opsm.Verified.{Url, Json, Result}
  alias Opsm.Network.Ipv6
  require Logger

  @type http_options :: [
          timeout: integer(),
          headers: [{String.t(), String.t()}],
          retry: integer()
        ]

  @doc """
  Make a verified GET request using QUIC/HTTP3 transport with automatic fallback.

  Leverages `Opsm.Transport.Quic` for protocol negotiation:
  QUIC/HTTP3 → HTTP/2 → HTTP/1.1. Falls back transparently when QUIC is unavailable.
  """
  @spec get_quic(String.t(), http_options()) :: {:ok, map()} | {:error, term()}
  def get_quic(url_string, opts \\ []) do
    Opsm.Transport.Quic.get(url_string, opts)
  end

  @doc """
  Make a verified GET request using QUIC transport and parse JSON response.
  """
  @spec get_json_quic(String.t(), http_options()) :: {:ok, map() | list()} | {:error, term()}
  def get_json_quic(url_string, opts \\ []) do
    Opsm.Transport.Quic.get_json(url_string, opts)
  end

  @doc """
  Make a verified GET request.

  URL is validated before request. Returns `{:ok, response}` or `{:error, reason}`.
  """
  @spec get(String.t(), http_options()) :: {:ok, map()} | {:error, term()}
  def get(url_string, opts \\ []) do
    with {:ok, validated_url} <- Url.validate(url_string),
         :ok <- validate_ipv6_policy(validated_url.host),
         {:ok, response} <- do_get(Url.to_string(validated_url), opts) do
      {:ok, response}
    end
  end

  @doc """
  Make a verified GET request and parse JSON response.

  URL is validated and JSON is safely parsed with depth/size limits.
  """
  @spec get_json(String.t(), http_options()) :: {:ok, map() | list()} | {:error, term()}
  def get_json(url_string, opts \\ []) do
    url_string
    |> get(opts)
    |> Result.and_then(fn response ->
      case response do
        %{body: body} when is_binary(body) ->
          Json.decode(body)

        %{body: body} when is_map(body) or is_list(body) ->
          # Already decoded by Req
          {:ok, body}

        _ ->
          {:error, :invalid_response_body}
      end
    end)
  end

  @doc """
  Make a verified POST request with JSON body.

  URL is validated and request body is safely encoded.
  """
  @spec post_json(String.t(), map() | list(), http_options()) ::
          {:ok, map()} | {:error, term()}
  def post_json(url_string, body, opts \\ []) do
    with {:ok, validated_url} <- Url.validate(url_string),
         :ok <- validate_ipv6_policy(validated_url.host),
         {:ok, json_body} <- Json.encode(body),
         {:ok, response} <- do_post(Url.to_string(validated_url), json_body, opts) do
      {:ok, response}
    end
  end

  @doc """
  Make a verified POST request with JSON body and parse JSON response.
  """
  @spec post_json_get_json(String.t(), map() | list(), http_options()) ::
          {:ok, map() | list()} | {:error, term()}
  def post_json_get_json(url_string, body, opts \\ []) do
    url_string
    |> post_json(body, opts)
    |> Result.and_then(fn response ->
      case response do
        %{body: body} when is_binary(body) ->
          Json.decode(body)

        %{body: body} when is_map(body) or is_list(body) ->
          {:ok, body}

        _ ->
          {:error, :invalid_response_body}
      end
    end)
  end

  # =============================================================================
  # Internal HTTP Operations (using Req)
  # =============================================================================

  defp do_get(url, opts) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    headers = Keyword.get(opts, :headers, [])
    retry_count = Keyword.get(opts, :retry, 2)

    try do
      result =
        Req.get(url,
          receive_timeout: timeout,
          retry: :transient,
          max_retries: retry_count,
          headers: headers
        )

      case result do
        {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
          {:ok, %{status: status, body: body}}

        {:ok, %Req.Response{status: status}} ->
          Logger.warning("HTTP GET returned status #{status} for #{url}")
          {:error, {:http_error, status}}

        {:error, %Req.TransportError{reason: reason}} ->
          Logger.warning("HTTP GET transport error for #{url}: #{inspect(reason)}")
          {:error, {:transport_error, reason}}

        {:error, reason} ->
          Logger.warning("HTTP GET failed for #{url}: #{inspect(reason)}")
          {:error, reason}
      end
    rescue
      exception ->
        Logger.error("HTTP GET exception for #{url}: #{inspect(exception)}")
        {:error, {:exception, exception}}
    end
  end

  # Validate IPv6 policy for outbound requests.
  # In :enforce_ipv6 mode, blocks connections to hosts without AAAA records.
  defp validate_ipv6_policy(host) do
    if Ipv6.mode() == :enforce_ipv6 do
      Ipv6.validate_host(host)
    else
      :ok
    end
  end

  defp do_post(url, json_body, opts) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    headers = Keyword.get(opts, :headers, [])
    retry_count = Keyword.get(opts, :retry, 2)

    headers = [{"content-type", "application/json"} | headers]

    try do
      result =
        Req.post(url,
          body: json_body,
          receive_timeout: timeout,
          retry: :transient,
          max_retries: retry_count,
          headers: headers
        )

      case result do
        {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
          {:ok, %{status: status, body: body}}

        {:ok, %Req.Response{status: status}} ->
          Logger.warning("HTTP POST returned status #{status} for #{url}")
          {:error, {:http_error, status}}

        {:error, %Req.TransportError{reason: reason}} ->
          Logger.warning("HTTP POST transport error for #{url}: #{inspect(reason)}")
          {:error, {:transport_error, reason}}

        {:error, reason} ->
          Logger.warning("HTTP POST failed for #{url}: #{inspect(reason)}")
          {:error, reason}
      end
    rescue
      exception ->
        Logger.error("HTTP POST exception for #{url}: #{inspect(exception)}")
        {:error, {:exception, exception}}
    end
  end
end
