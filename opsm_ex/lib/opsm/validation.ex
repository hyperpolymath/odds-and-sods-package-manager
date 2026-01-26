# SPDX-License-Identifier: PMPL-1.0
defmodule Opsm.Validation do
  @moduledoc """
  Input validation for security.

  Validates package names, versions, and paths to prevent:
  - Command injection via shell metacharacters
  - Path traversal attacks
  - Atom table exhaustion
  """

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

      String.contains?(path, "..") ->
        {:error, "Path cannot contain traversal sequences (..)"}

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
    case URI.parse(url) do
      %URI{scheme: nil} ->
        {:error, "URL must have a scheme (e.g., https://)"}

      %URI{scheme: _scheme, host: nil} ->
        {:error, "URL must have a host"}

      %URI{scheme: _scheme, host: ""} ->
        {:error, "URL must have a host"}

      %URI{scheme: scheme, host: host} when is_binary(scheme) and is_binary(host) ->
        scheme_lower = String.downcase(scheme)

        cond do
          scheme_lower in @dangerous_schemes ->
            {:error, "URL scheme '#{scheme}' is not allowed for security reasons"}

          scheme_lower not in @allowed_schemes ->
            {:error, "URL scheme '#{scheme}' is not supported. Use https:// or http://"}

          String.contains?(host, "..") ->
            {:error, "URL host contains invalid sequence"}

          String.length(url) > 2048 ->
            {:error, "URL too long (max 2048 characters)"}

          true ->
            {:ok, url}
        end

      _ ->
        {:error, "Invalid URL format"}
    end
  end

  def validate_url(url) do
    {:error, "URL must be a string, got: #{inspect(url)}"}
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
