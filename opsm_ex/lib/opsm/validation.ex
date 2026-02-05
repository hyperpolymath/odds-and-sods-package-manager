# SPDX-License-Identifier: PMPL-1.0
defmodule Opsm.Validation do
  @moduledoc """
  Input validation for security.

  Validates package names, versions, and paths to prevent:
  - Command injection via shell metacharacters
  - Path traversal attacks
  - Atom table exhaustion
  """

  # Proven library is disabled - using inline implementations

  # Package name patterns by registry
  # npm: @scope/name or name, allows alphanumeric, -, _, .
  @npm_pattern ~r|^(@[a-zA-Z0-9][\w.-]*/)?[a-zA-Z0-9][\w.-]*$|

  # cargo: alphanumeric, -, _
  @cargo_pattern ~r/^[a-zA-Z][a-zA-Z0-9_-]*$/

  # hex: alphanumeric, _
  @hex_pattern ~r/^[a-z][a-z0-9_]*$/

  # pypi: PEP 508 names
  @pypi_pattern ~r/^[a-zA-Z0-9]([a-zA-Z0-9._-]*[a-zA-Z0-9])?$/

  # Generic: safe for all registries
  @generic_pattern ~r|^[a-zA-Z0-9@][\w./-]*$|

  # Dangerous shell characters
  @shell_dangerous_chars ~r/[;&|`$(){}[\]<>\\!\n\r\t]/

  # Version patterns
  @semver_pattern ~r/^v?\d+\.\d+\.\d+(-[\w.]+)?(\+[\w.]+)?$/
  @version_keywords ["latest", "next", "stable", "beta", "alpha", "rc"]

  @doc """
  Validate a package name for a specific registry.
  Returns {:ok, name} or {:error, reason}.
  """
  def validate_package_name(name, forth \\ :generic)

  def validate_package_name(nil, _forth), do: {:error, "Package name cannot be nil"}
  def validate_package_name("", _forth), do: {:error, "Package name cannot be empty"}

  def validate_package_name(name, forth) when is_binary(name) do
    cond do
      String.length(name) > 214 ->
        {:error, "Package name too long (max 214 characters)"}

      Regex.match?(@shell_dangerous_chars, name) ->
        {:error, "Package name contains dangerous characters"}

      String.contains?(name, "..") ->
        {:error, "Package name cannot contain path traversal sequences"}

      not valid_for_registry?(name, forth) ->
        {:error, "Package name '#{name}' invalid for @#{forth}"}

      true ->
        {:ok, name}
    end
  end

  def validate_package_name(name, _forth) do
    {:error, "Package name must be a string, got: #{inspect(name)}"}
  end

  @doc """
  Validate a version string.
  Returns {:ok, version} or {:error, reason}.
  """
  def validate_version(nil), do: {:ok, "latest"}
  def validate_version(""), do: {:ok, "latest"}

  def validate_version(version) when is_binary(version) do
    cond do
      version in @version_keywords ->
        {:ok, version}

      Regex.match?(@semver_pattern, version) ->
        {:ok, version}

      Regex.match?(@shell_dangerous_chars, version) ->
        {:error, "Version contains dangerous characters"}

      String.length(version) > 128 ->
        {:error, "Version string too long"}

      # Allow non-semver versions like "1.0" or "2"
      Regex.match?(~r/^v?\d+(\.\d+)*(-[\w.]+)?$/, version) ->
        {:ok, version}

      true ->
        {:error, "Invalid version format: #{version}"}
    end
  end

  @doc """
  Validate a file path to prevent traversal attacks.
  """
  def validate_path(nil), do: {:error, "Path cannot be nil"}
  def validate_path(""), do: {:error, "Path cannot be empty"}

  def validate_path(path) when is_binary(path) do
    cond do
      String.contains?(path, "\0") ->
        {:error, "Path cannot contain null bytes"}

      String.contains?(path, "..") or String.contains?(path, "//") ->
        {:error, "Path cannot contain traversal sequences"}

      true ->
        {:ok, path}
    end
  end

  @doc """
  Sanitize a string for safe shell use.
  Escapes or rejects dangerous characters.
  """
  def sanitize_for_shell(str) when is_binary(str) do
    if Regex.match?(@shell_dangerous_chars, str) do
      {:error, "String contains shell-unsafe characters"}
    else
      {:ok, str}
    end
  end

  @doc """
  Validate package name and version together.
  """
  def validate_install_request(name, version, forth) do
    with {:ok, valid_name} <- validate_package_name(name, forth),
         {:ok, valid_version} <- validate_version(version) do
      {:ok, %{name: valid_name, version: valid_version, forth: forth}}
    end
  end

  # Allowed URL schemes for downloads
  @allowed_schemes ["https", "http"]
  @dangerous_schemes ["file", "ftp", "data", "javascript", "vbscript"]

  @doc """
  Validate a URL for safe download.
  Rejects dangerous schemes like file://, ftp://, data:, etc.
  Returns {:ok, url} or {:error, reason}.
  """
  def validate_url(nil), do: {:error, "URL cannot be nil"}
  def validate_url(""), do: {:error, "URL cannot be empty"}

  def validate_url(url) when is_binary(url) do
    if String.contains?(url, "::1") do
      {:error, "URL host is blocked (loopback)"}
    else
      case URI.parse(url) do
        %URI{scheme: scheme, host: host} when scheme != nil and host != nil ->
          scheme_lower = String.downcase(scheme)

          cond do
            scheme_lower in @dangerous_schemes ->
              {:error, "URL scheme '#{scheme}' is not allowed for security reasons"}

            scheme_lower not in @allowed_schemes ->
              {:error, "URL scheme '#{scheme}' is not supported. Use https:// or http://"}

            String.contains?(host, "..") ->
              {:error, "URL host contains invalid sequence"}

            is_private_or_loopback_ip?(host) ->
              {:error, "URL host is blocked (private/loopback)"}

            String.starts_with?(host, "169.254.") ->
              {:error, "URL host is blocked (link-local)"}

            String.length(url) > 2048 ->
              {:error, "URL too long (max 2048 characters)"}

            true ->
              {:ok, url}
          end

        _ ->
          {:error, "Invalid URL format"}
      end
    end
  end

  def validate_url(url) do
    {:error, "URL must be a string, got: #{inspect(url)}"}
  end

  # Helper function to check for private/loopback IP addresses
  defp is_private_or_loopback_ip?(host) do
    case parse_ipv4(host) do
      {:ok, {a, b, c, _d}} ->
        # Loopback: 127.0.0.0/8
        a == 127 or
        # Private: 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16
        a == 10 or
        (a == 172 and b >= 16 and b <= 31) or
        (a == 192 and b == 168) or
        # Link-local: 169.254.0.0/16
        (a == 169 and b == 254)

      :error ->
        # Check for localhost or IPv6 loopback
        String.downcase(host) in ["localhost", "::1", "0:0:0:0:0:0:0:1"]
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

  @doc """
  Validate URL and return parsed URI struct.
  """
  def validate_and_parse_url(url) do
    with {:ok, valid_url} <- validate_url(url) do
      {:ok, URI.parse(valid_url)}
    end
  end

  @doc """
  Sanitize a file path by expanding and normalizing it.
  Removes any path traversal attempts and returns an absolute path.
  Returns {:ok, sanitized_path} or {:error, reason}.
  """
  def sanitize_path(nil), do: {:error, "Path cannot be nil"}
  def sanitize_path(""), do: {:error, "Path cannot be empty"}

  def sanitize_path(path) when is_binary(path) do
    # Expand to absolute path and normalize
    expanded = Path.expand(path)

    # Verify the expanded path doesn't contain traversal (should be resolved now)
    if String.contains?(expanded, "..") do
      {:error, "Path contains unresolved traversal sequences"}
    else
      {:ok, expanded}
    end
  end

  def sanitize_path(path) do
    {:error, "Path must be a string, got: #{inspect(path)}"}
  end

  # Private functions

  defp valid_for_registry?(name, :npm), do: Regex.match?(@npm_pattern, name)
  defp valid_for_registry?(name, :cargo), do: Regex.match?(@cargo_pattern, name)
  defp valid_for_registry?(name, :crates), do: Regex.match?(@cargo_pattern, name)
  defp valid_for_registry?(name, :hex), do: Regex.match?(@hex_pattern, name)
  defp valid_for_registry?(name, :elixir), do: Regex.match?(@hex_pattern, name)
  defp valid_for_registry?(name, :pypi), do: Regex.match?(@pypi_pattern, name)
  defp valid_for_registry?(name, :python), do: Regex.match?(@pypi_pattern, name)
  defp valid_for_registry?(name, _), do: Regex.match?(@generic_pattern, name)
end
