# SPDX-License-Identifier: PMPL-1.0
defmodule Opm.Verified do
  @moduledoc """
  Verified/proven library wrappers for safe operations.

  For v1.0: Elixir approximations with strong validation.
  For v2.0: Will bind to Idris2 proven library via NIFs for formal verification.

  Provides:
  - SafeUrl: URL validation and parsing
  - SafeJson: Safe JSON decoding with schema validation
  - Result: Explicit error handling type
  """
end

defmodule Opm.Verified.Url do
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
    # Pre-check for IPv6 localhost patterns before URI.parse
    # URI.parse may not handle ::1 correctly in all cases
    if String.contains?(url_string, "::1") do
      {:error, :blocked_host}
    else
      case URI.parse(url_string) do
        %URI{scheme: nil} ->
          {:error, :missing_scheme}

        %URI{scheme: scheme} when scheme not in @allowed_schemes ->
          {:error, {:invalid_scheme, scheme}}

        %URI{host: nil} ->
          {:error, :missing_host}

        %URI{host: ""} ->
          {:error, :missing_host}

        %URI{scheme: scheme, host: host} = uri when scheme in @allowed_schemes ->
          if host in @blocked_hosts or is_private_ip?(host) do
            {:error, :blocked_host}
          else
            validated = %__MODULE__{
              scheme: scheme,
              host: host,
              port: uri.port,
              path: uri.path || "/",
              query: uri.query,
              original: url_string
            }

            {:ok, validated}
          end

        _other ->
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

  # Check if hostname is a private/internal IP address.
  defp is_private_ip?(host) do
    cond do
      String.starts_with?(host, "192.168.") -> true
      String.starts_with?(host, "10.") -> true
      String.match?(host, ~r/^172\.(1[6-9]|2[0-9]|3[0-1])\./) -> true
      String.starts_with?(host, "169.254.") -> true
      host == "localhost" -> true
      true -> false
    end
  end
end

defmodule Opm.Verified.Json do
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
          if valid_depth?(data, @max_depth) do
            {:ok, data}
          else
            {:error, :nesting_too_deep}
          end

        {:error, %Jason.DecodeError{} = error} ->
          {:error, {:json_decode_error, error.data}}

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
      {:ok, json} -> {:ok, json}
      {:error, reason} -> {:error, {:json_encode_error, reason}}
    end
  end

  # Check nesting depth to prevent DoS via deeply nested structures
  defp valid_depth?(_data, 0), do: false

  defp valid_depth?(data, depth) when is_map(data) do
    Enum.all?(data, fn {_k, v} -> valid_depth?(v, depth - 1) end)
  end

  defp valid_depth?(data, depth) when is_list(data) do
    Enum.all?(data, fn item -> valid_depth?(item, depth - 1) end)
  end

  defp valid_depth?(_data, _depth), do: true
end

defmodule Opm.Verified.Result do
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
