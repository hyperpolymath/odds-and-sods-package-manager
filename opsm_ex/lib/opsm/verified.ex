# SPDX-License-Identifier: PMPL-1.0-or-later
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
  @spec validate(String.t()) :: {:ok, t()} | {:error, atom() | {:invalid_scheme, String.t()}}
  def validate(url_string) when is_binary(url_string) do
    if String.contains?(url_string, "::1") do
      {:error, :blocked_host}
    else
      parsed = URI.parse(url_string)

      cond do
        is_nil(parsed.scheme) ->
          {:error, :missing_scheme}

        # Check scheme before host - dangerous/invalid schemes should be
        # reported as scheme errors even if host is also missing
        parsed.scheme not in @allowed_schemes ->
          {:error, {:invalid_scheme, parsed.scheme}}

        is_nil(parsed.host) or parsed.host == "" ->
          {:error, :missing_host}

        parsed.host in @blocked_hosts ->
          {:error, :blocked_host}

        is_private_or_loopback_ip?(parsed.host) or String.starts_with?(parsed.host, "169.254.") ->
          {:error, :blocked_host}

        true ->
          validated = %__MODULE__{
            scheme: parsed.scheme,
            host: parsed.host,
            port: parsed.port,
            path: parsed.path || "/",
            query: parsed.query,
            original: url_string
          }

          {:ok, validated}
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

  # Helper function to check for private/loopback IP addresses
  defp is_private_or_loopback_ip?(host) do
    case parse_ipv4(host) do
      {:ok, {a, b, _c, _d}} ->
        # Loopback: 127.0.0.0/8
        a == 127 or
        # Private: 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16
        a == 10 or
        (a == 172 and b >= 16 and b <= 31) or
        (a == 192 and b == 168)

      :error ->
        false
    end
  end

  # Parse IPv4 address
  defp parse_ipv4(str) do
    case String.split(str, ".") do
      [a, b, c, d] ->
        with {a_int, ""} <- Integer.parse(a),
             {b_int, ""} <- Integer.parse(b),
             {c_int, ""} <- Integer.parse(c),
             {d_int, ""} <- Integer.parse(d),
             true <- a_int >= 0 and a_int <= 255,
             true <- b_int >= 0 and b_int <= 255,
             true <- c_int >= 0 and c_int <= 255,
             true <- d_int >= 0 and d_int <= 255 do
          {:ok, {a_int, b_int, c_int, d_int}}
        else
          _ -> :error
        end

      _ ->
        :error
    end
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
    # Check size limit
    if byte_size(json_string) > @max_size do
      {:error, :payload_too_large}
    else
      case Jason.decode(json_string) do
        {:ok, data} ->
          # Check depth after parsing
          if check_depth(data, @max_depth) do
            {:ok, data}
          else
            {:error, :nesting_too_deep}
          end

        {:error, %Jason.DecodeError{}} ->
          {:error, {:json_decode_error, :invalid_json}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def decode(_), do: {:error, :not_a_string}

  @doc """
  Encode data to JSON safely.
  """
  @spec encode(term()) :: {:ok, String.t()} | {:error, term()}
  def encode(data) do
    case Jason.encode(data) do
      {:ok, json} ->
        if byte_size(json) > @max_size do
          {:error, :payload_too_large}
        else
          {:ok, json}
        end

      {:error, %Jason.EncodeError{} = error} ->
        {:error, {:json_encode_error, error.message}}

      {:error, reason} ->
        {:error, {:json_encode_error, reason}}
    end
  end

  # Check nesting depth recursively
  defp check_depth(_data, 0), do: false
  defp check_depth(data, depth) when is_map(data) do
    Enum.all?(data, fn {_k, v} -> check_depth(v, depth - 1) end)
  end
  defp check_depth(data, depth) when is_list(data) do
    Enum.all?(data, fn v -> check_depth(v, depth - 1) end)
  end
  defp check_depth(_data, _depth), do: true

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
