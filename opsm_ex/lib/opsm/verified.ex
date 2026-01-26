# SPDX-License-Identifier: PMPL-1.0
defmodule Opsm.Verified do
  @moduledoc """
  Verified/proven library wrappers for safe operations.

  For v1.0: Elixir approximations with strong validation.
  For v2.0: Will bind to Idris2 proven library via NIFs for formal verification.

  Provides:
  - SafeUrl: URL validation and parsing (Proven.SafeUrl)
  - SafeJson: Safe JSON decoding with schema validation (Proven.SafeJson)
  - Result: Explicit error handling type
  """
end

defmodule Opsm.Verified.Url do
  @moduledoc """
  Safe URL validation and parsing.

  Ensures URLs are well-formed and uses allowed protocols before making requests.
  v1.0: Pattern matching and validation.
  v2.0: Proven correct via Idris2 dependent types.
  """

  @type t :: %__MODULE__{
          scheme: String.t(),
          host: String.t(),
          port: integer() | nil,
          path: String.t(),
          query: String.t() | nil,
          original: String.t()
        }

  @allowed_schemes ["http", "https"]
  @blocked_hosts ["localhost", "127.0.0.1", "0.0.0.0", "::1"]

  defstruct [:scheme, :host, :port, :path, :query, :original]

  @doc """
  Validate and parse a URL string.

  Returns `{:ok, validated_url}` if URL is safe, `{:error, reason}` otherwise.

  ## Safety checks:
  - Must be a valid URI
  - Must use http or https scheme
  - Must not target localhost/internal IPs
  - Must have a valid hostname
  """
  @spec validate(String.t()) :: {:ok, t()} | {:error, atom()}
  def validate(url_string) when is_binary(url_string) do
    if String.contains?(url_string, "::1") do
      {:error, :blocked_host}
    else
      case Proven.SafeUrl.parse(url_string) do
        {:ok, parsed} ->
          scheme = parsed.scheme
          host = parsed.host

          cond do
            scheme not in @allowed_schemes ->
              {:error, {:invalid_scheme, scheme}}

            host in @blocked_hosts ->
              {:error, :blocked_host}

            (Proven.SafeNetwork.valid_ipv4?(host) and
               (Proven.SafeNetwork.private?(host) or Proven.SafeNetwork.loopback?(host))) or
                String.starts_with?(host, "169.254.") ->
              {:error, :blocked_host}

            true ->
              validated = %__MODULE__{
                scheme: scheme,
                host: host,
                port: parsed.port,
                path: parsed.path || "/",
                query: parsed.query,
                original: url_string
              }

              {:ok, validated}
          end

        {:error, _} ->
          {:error, :invalid_url}
      end
    end
  end

  def validate(_), do: {:error, :not_a_string}

  @doc """
  Convert validated URL back to string for HTTP requests.
  """
  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{} = url) do
    url.original
  end

end

defmodule Opsm.Verified.Json do
  @moduledoc """
  Safe JSON decoding with validation.

  Prevents:
  - Deeply nested structures (DoS protection)
  - Excessively large payloads
  - Invalid UTF-8 sequences

  v1.0: Jason with limits.
  v2.0: Proven parser via Idris2 with dependent types.
  """

  @max_depth 20
  @max_size 10_485_760  # 10 MB

  @doc """
  Decode JSON string safely.

  Returns `{:ok, parsed_data}` or `{:error, reason}`.
  """
  @spec decode(String.t()) :: {:ok, map() | list()} | {:error, term()}
  def decode(json_string) when is_binary(json_string) do
    case Proven.SafeJson.parse(json_string, max_depth: @max_depth, max_size: @max_size) do
      {:ok, data} -> {:ok, data}
      {:error, :payload_too_large} -> {:error, :payload_too_large}
      {:error, :max_depth_exceeded} -> {:error, :nesting_too_deep}
      {:error, :invalid_json} -> {:error, {:json_decode_error, :invalid_json}}
      {:error, reason} -> {:error, reason}
    end
  end

  def decode(_), do: {:error, :not_a_string}

  @doc """
  Encode data to JSON safely.
  """
  @spec encode(term()) :: {:ok, String.t()} | {:error, term()}
  def encode(data) do
    case Proven.SafeJson.encode(data, max_size: @max_size) do
      {:ok, json} -> {:ok, json}
      {:error, :payload_too_large} -> {:error, :payload_too_large}
      {:error, reason} -> {:error, {:json_encode_error, reason}}
    end
  end

end

defmodule Opsm.Verified.Result do
  @moduledoc """
  Explicit Result type for error handling.

  Provides Railway-Oriented Programming primitives.
  Makes errors explicit and composable.

  v1.0: Elixir tuples with helper functions.
  v2.0: Proven correct via Idris2 dependent types (cannot ignore errors).
  """

  @type result(ok, err) :: {:ok, ok} | {:error, err}

  @doc """
  Map over the success value.

  ## Examples

      iex> Result.map({:ok, 5}, fn x -> x * 2 end)
      {:ok, 10}

      iex> Result.map({:error, "failed"}, fn x -> x * 2 end)
      {:error, "failed"}
  """
  @spec map(result(a, e), (a -> b)) :: result(b, e) when a: term(), b: term(), e: term()
  def map({:ok, value}, func), do: {:ok, func.(value)}
  def map({:error, _} = error, _func), do: error

  @doc """
  Chain operations that return results.

  ## Examples

      iex> Result.and_then({:ok, 5}, fn x -> {:ok, x * 2} end)
      {:ok, 10}

      iex> Result.and_then({:ok, 5}, fn _ -> {:error, "failed"} end)
      {:error, "failed"}
  """
  @spec and_then(result(a, e), (a -> result(b, e))) :: result(b, e)
        when a: term(), b: term(), e: term()
  def and_then({:ok, value}, func), do: func.(value)
  def and_then({:error, _} = error, _func), do: error

  @doc """
  Provide a default value if result is an error.

  ## Examples

      iex> Result.unwrap_or({:ok, 5}, 0)
      5

      iex> Result.unwrap_or({:error, "failed"}, 0)
      0
  """
  @spec unwrap_or(result(a, e), a) :: a when a: term(), e: term()
  def unwrap_or({:ok, value}, _default), do: value
  def unwrap_or({:error, _}, default), do: default

  @doc """
  Unwrap result or raise error.
  Use sparingly - prefer explicit error handling.

  ## Examples

      iex> Result.unwrap!({:ok, 5})
      5

      iex> Result.unwrap!({:error, "failed"})
      ** (RuntimeError) Unwrap failed: "failed"
  """
  @spec unwrap!(result(a, e)) :: a when a: term(), e: term()
  def unwrap!({:ok, value}), do: value
  def unwrap!({:error, reason}), do: raise("Unwrap failed: #{inspect(reason)}")

  @doc """
  Check if result is ok.
  """
  @spec is_ok?(result(term(), term())) :: boolean()
  def is_ok?({:ok, _}), do: true
  def is_ok?(_), do: false

  @doc """
  Check if result is error.
  """
  @spec is_error?(result(term(), term())) :: boolean()
  def is_error?({:error, _}), do: true
  def is_error?(_), do: false
end
