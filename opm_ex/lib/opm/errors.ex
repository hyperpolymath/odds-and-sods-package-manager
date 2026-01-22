# SPDX-License-Identifier: PMPL-1.0
defmodule Opm.Errors do
  @moduledoc """
  Standardized error formatting and messages.

  Error format: "Error: {what} - {why} - {how to fix}"

  Categories:
  - :network - Network/API errors
  - :validation - Input validation errors
  - :not_found - Package/resource not found
  - :config - Configuration errors
  - :toolchain - Missing toolchain
  - :install - Installation failures
  - :security - Security/trust failures
  """

  @type error_category ::
          :network
          | :validation
          | :not_found
          | :config
          | :toolchain
          | :install
          | :security
          | :internal

  @type opm_error :: {error_category(), String.t(), String.t() | nil}

  @doc """
  Format an error for display.
  Returns a formatted error string.
  """
  def format({_category, what, how_to_fix}) do
    base = "Error: #{what}"

    if how_to_fix do
      "#{base}\n  → #{how_to_fix}"
    else
      base
    end
  end

  def format({:error, reason}) when is_binary(reason) do
    "Error: #{reason}"
  end

  def format({:error, reason}) do
    "Error: #{inspect(reason)}"
  end

  def format(other) do
    "Error: #{inspect(other)}"
  end

  @doc """
  Print an error to stderr with proper formatting.
  """
  def print_error(error) do
    IO.puts(:stderr, format(error))
  end

  # Common error constructors

  @doc """
  Package not found error.
  """
  def package_not_found(name, forth) do
    {:not_found, "Package '#{name}' not found in @#{forth}",
     "Check the package name spelling or try a different registry"}
  end

  def package_not_found(name) do
    {:not_found, "Package '#{name}' not found in any registry",
     "Use 'opm search #{name}' to find similar packages"}
  end

  @doc """
  Registry/network error.
  """
  def registry_error(forth, reason) do
    {:network, "Failed to connect to @#{forth} registry: #{inspect(reason)}",
     "Check your internet connection or try again later"}
  end

  def network_timeout(forth) do
    {:network, "Request to @#{forth} timed out",
     "The registry may be slow or unavailable. Try again later"}
  end

  @doc """
  Validation errors.
  """
  def invalid_package_name(name, reason) do
    {:validation, "Invalid package name '#{name}': #{reason}",
     "Package names must be alphanumeric with optional @scope/prefix"}
  end

  def invalid_version(version) do
    {:validation, "Invalid version '#{version}'",
     "Use semver format (1.2.3), 'latest', or keywords like 'stable', 'beta'"}
  end

  @doc """
  Toolchain errors.
  """
  def missing_toolchain(forth, required_tools) do
    tools = Enum.join(required_tools, ", ")
    {:toolchain, "Missing toolchain for @#{forth}",
     "Install one of: #{tools}"}
  end

  @doc """
  Installation errors.
  """
  def download_failed(package, reason) do
    {:install, "Failed to download '#{package}': #{reason}",
     "Check your internet connection or verify the package exists"}
  end

  def checksum_mismatch(package, expected, actual) do
    {:security, "Checksum verification failed for '#{package}'",
     "Expected: #{String.slice(expected, 0..15)}..., got: #{String.slice(actual, 0..15)}...\n  This may indicate a corrupted download or tampering. Try again or verify the source."}
  end

  def unpack_failed(package, reason) do
    {:install, "Failed to unpack '#{package}': #{reason}",
     "The package archive may be corrupted. Try 'opm clean cache' and reinstall"}
  end

  def install_path_exists(path) do
    {:install, "Installation path already exists: #{path}",
     "Use 'opm remove <package>' first or 'opm reinstall <package>'"}
  end

  @doc """
  Trust/security errors.
  """
  def trust_failed(package, reasons) do
    reasons_str = Enum.join(reasons, "\n    - ")
    {:security, "Trust verification failed for '#{package}'",
     "Issues found:\n    - #{reasons_str}\n  Use --skip-trust to bypass (not recommended)"}
  end

  def no_attestations(package) do
    {:security, "No attestations found for '#{package}'",
     "This package has no signed attestations. Proceed with caution"}
  end

  @doc """
  Configuration errors.
  """
  def config_not_found do
    {:config, "Configuration file not found",
     "Create opm.toml in current directory or ~/.config/opm/opm.toml"}
  end

  def config_parse_error(path, reason) do
    {:config, "Failed to parse config at #{path}: #{inspect(reason)}",
     "Check the TOML syntax in your configuration file"}
  end

  def invalid_url(service, url) do
    {:config, "Invalid URL for #{service}: #{url}",
     "URLs must start with http:// or https://"}
  end

  @doc """
  Unknown registry error.
  """
  def unknown_registry(forth) do
    {:validation, "Unknown registry: @#{forth}",
     "Supported registries: npm, cargo, hex, pypi, gem, nuget, maven, pub, go"}
  end

  @doc """
  Command not implemented.
  """
  def not_implemented(command) do
    {:internal, "'#{command}' is not yet implemented",
     "This feature is coming soon"}
  end
end
