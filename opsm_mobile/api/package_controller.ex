# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Api.PackageController do
  @moduledoc """
  Controller logic for mobile API endpoints.

  Bridges HTTP API calls to OPSM core functionality (install, search, audit, etc.).
  All functions return {:ok, result} or {:error, reason} tuples.
  """

  require Logger

  alias Opsm.Package.Installer
  alias Opsm.Registries.Registry
  alias Opsm.Lockfile
  alias Opsm.Wiring
  alias Opsm.Types.OpsmConfig

  @doc """
  Install a package.

  ## Parameters
    - params: Map with keys:
      - "package" (required): Package name
      - "registry" (optional): Registry name (npm, hex, crates, etc.)
      - "version" (optional): Version constraint (default: "latest")
      - "scope" (optional): "user" or "system" (default: "user")
      - "dry_run" (optional): Boolean (default: false)

  ## Examples
      iex> install(%{"package" => "express", "registry" => "npm"})
      {:ok, %{package: "express", version: "4.18.2", installed_at: "..."}}
  """
  def install(%{"package" => package_name} = params) do
    registry = params["registry"]
    version = params["version"] || "latest"
    scope = Opsm.Validation.safe_to_scope(params["scope"] || "user")
    dry_run = params["dry_run"] || false

    Logger.info("API: Installing #{package_name}@#{version} from @#{registry}")

    case registry do
      nil ->
        # No registry specified - discovery mode not yet implemented in API
        {:error, "registry parameter is required for API installs"}

      registry_str ->
        registry_atom = Opsm.Validation.safe_to_forth(registry_str)

        case Installer.install(registry_atom, package_name,
               version: version,
               scope: scope,
               dry_run: dry_run
             ) do
          {:ok, result} ->
            {:ok,
             %{
               package: package_name,
               version: version,
               registry: registry_str,
               scope: scope,
               status: if(dry_run, do: "dry_run", else: "installed"),
               result: result
             }}

          {:error, reason} ->
            Logger.error("API: Install failed for #{package_name}: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  def install(_params) do
    {:error, "Missing required parameter: package"}
  end

  @doc """
  Search for packages.

  ## Parameters
    - query: Search query string
    - registry: Optional registry to search (nil = search all)

  ## Examples
      iex> search("express", "npm")
      {:ok, [%{name: "express", version: "4.18.2", ...}]}
  """
  def search(query, registry \\ nil) when is_binary(query) do
    Logger.info("API: Searching for '#{query}' in #{registry || "all registries"}")

    case registry do
      nil ->
        # Search across all registries
        case Registry.search_all(query, limit: 20) do
          results when is_list(results) ->
            {:ok, Enum.map(results, &format_search_result/1)}

          {:error, reason} ->
            Logger.error("API: Search all failed: #{inspect(reason)}")
            {:error, reason}
        end

      registry_str ->
        registry_atom = Opsm.Validation.safe_to_forth(registry_str)

        case Registry.search(registry_atom, query, limit: 20) do
          {:ok, results} ->
            {:ok, Enum.map(results, &format_search_result/1)}

          {:error, reason} ->
            Logger.error("API: Search failed for #{registry_str}: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  @doc """
  Get detailed package information.

  ## Parameters
    - name: Package name
    - version: Package version (or "latest")
    - registry: Optional registry name

  ## Examples
      iex> get_package_info("express", "4.18.2", "npm")
      {:ok, %{name: "express", version: "4.18.2", ...}}
  """
  def get_package_info(name, version, registry \\ nil) when is_binary(name) do
    Logger.info("API: Getting info for #{name}@#{version} from #{registry || "auto"}")

    case registry do
      nil ->
        # Try to discover which registry has this package
        {:error, "registry parameter is required for get_package_info"}

      registry_str ->
        registry_atom = Opsm.Validation.safe_to_forth(registry_str)

        case Registry.fetch(registry_atom, name) do
          {:ok, package_info} ->
            # Filter to specific version if not "latest"
            result =
              if version == "latest" do
                package_info
              else
                # TODO: Filter versions from package_info
                package_info
              end

            {:ok, format_package_info(result)}

          {:error, :not_found} ->
            {:error, :not_found}

          {:error, reason} ->
            Logger.error("API: Fetch failed for #{name}: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  @doc """
  Audit a lockfile for security vulnerabilities and sustainability.

  ## Parameters
    - params: Map with keys:
      - "lockfile_path" (optional): Path to opsm.lock (default: "./opsm.lock")
      - "repository_url" (optional): Repository URL for sustainability analysis

  ## Examples
      iex> audit_lockfile(%{"repository_url" => "https://github.com/user/repo"})
      {:ok, %{vulnerabilities: [], sustainability: %{...}}}
  """
  def audit_lockfile(params \\ %{}) do
    lockfile_path = params["lockfile_path"] || "./opsm.lock"
    repository_url = params["repository_url"]

    Logger.info("API: Auditing lockfile at #{lockfile_path}")

    with {:ok, lockfile} <- Lockfile.read(lockfile_path),
         {:ok, config} <- load_config() do
      # Run audit via Wiring module
      audit_result =
        if repository_url do
          case Wiring.run_audit(config, repository_url) do
            {:ok, result} -> result
            {:error, reason} -> %{error: reason}
          end
        else
          %{message: "No repository_url provided, skipping sustainability analysis"}
        end

      # TODO: Add vulnerability scanning (CVE checks)
      # For v1.0, just return sustainability analysis

      {:ok,
       %{
         lockfile: %{
           version: lockfile.version,
           packages: map_size(lockfile.packages),
           generated_at: lockfile.generated_at
         },
         audit: audit_result,
         vulnerabilities: [],
         # Placeholder for v1.1
         recommendations: []
       }}
    else
      {:error, :not_found} ->
        {:error, "Lockfile not found at #{lockfile_path}"}

      {:error, reason} ->
        Logger.error("API: Audit failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  List all installed packages.

  ## Examples
      iex> list_installed()
      {:ok, [%{name: "express", version: "4.18.2", forth: "npm", ...}]}
  """
  def list_installed(opts \\ []) do
    Logger.info("API: Listing installed packages")

    installed = Installer.list_installed(opts)

    formatted =
      Enum.map(installed, fn pkg ->
        %{
          name: pkg["name"],
          version: pkg["version"],
          registry: pkg["forth"],
          installed_at: pkg["installed_at"],
          path: pkg["path"]
        }
      end)

    {:ok, formatted}
  end

  # Private helpers

  defp format_search_result(result) when is_map(result) do
    %{
      name: result.name || result["name"],
      version: result.version || result["version"],
      description: result.description || result["description"],
      registry: result.forth || result["forth"] || "unknown"
    }
  end

  defp format_package_info(info) when is_map(info) do
    %{
      name: info.name || info["name"],
      version: info.version || info["version"],
      description: info.description || info["description"],
      license: info.license || info["license"],
      repository: info.repository || info["repository"],
      dependencies: info.dependencies || info["dependencies"] || %{},
      keywords: info.keywords || info["keywords"] || []
    }
  end

  defp load_config do
    # Load OPSM configuration for trust pipeline services
    # For v1.0, use default configuration
    config = %OpsmConfig{
      checky_monkey: %{base_url: "http://localhost:7002"},
      palimpsest_license: %{base_url: "http://localhost:7003"},
      oikos: %{base_url: "http://localhost:7005"},
      http: %{timeout: 30_000}
    }

    {:ok, config}
  end
end
