# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule Opsm.Registries.Nimble do
  @moduledoc """
  Nimble Package Directory adapter for Nim packages.

  Nimble is the package manager for the Nim programming language.
  Website: https://nimble.directory/
  API: https://nimble.directory/api

  Package format: .nimble files
  Build system: nimble build / nim c
  """

  alias Opsm.Types.{ResolvedPackage, ManifestFormat}
  alias Opsm.Verified.Http, as: VerifiedHttp

  require Logger

  @base_url "https://nimble.directory"
  @api_base "#{@base_url}/api"

  @doc """
  Fetch package metadata from Nimble registry.

  ## Examples

      iex> Nimble.fetch_package("jester", "latest")
      {:ok, %ResolvedPackage{name: "jester", ...}}

      iex> Nimble.fetch_package("jester", "0.5.0")
      {:ok, %ResolvedPackage{version: "0.5.0", ...}}
  """
  @spec fetch_package(String.t(), String.t()) ::
    {:ok, ResolvedPackage.t()} | {:error, term()}
  def fetch_package(name, version \\ "latest") do
    Logger.debug("Fetching Nimble package: #{name}@#{version}")

    url = "#{@api_base}/packages/#{URI.encode(name)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        parse_package(body, name, version)

      {:error, :not_found} ->
        Logger.warning("Nimble package not found: #{name}")
        {:error, :not_found}

      {:error, %{status: 404}} ->
        Logger.warning("Nimble package not found: #{name}")
        {:error, :not_found}

      {:error, %{status: status}} ->
        Logger.error("Nimble registry returned status #{status} for #{name}")
        {:error, "Registry returned status #{status}"}

      {:error, reason} ->
        Logger.error("Failed to fetch from Nimble: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Search for packages on Nimble.

  ## Options

  - `:limit` - Maximum number of results (default: 20)

  ## Examples

      iex> Nimble.search("http", limit: 10)
      {:ok, [%ResolvedPackage{name: "jester", ...}, ...]}
  """
  @spec search(String.t(), keyword()) ::
    {:ok, [ResolvedPackage.t()]} | {:error, term()}
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    Logger.debug("Searching Nimble for: #{query} (limit: #{limit})")

    url = "#{@api_base}/search?query=#{URI.encode(query)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        packages = body
        |> get_in(["packages"]) || []
        |> Enum.take(limit)
        |> Enum.map(&parse_search_result/1)

        {:ok, packages}

      {:error, %{status: status}} ->
        Logger.error("Nimble search returned status #{status}")
        {:error, "Search failed with status #{status}"}

      {:error, reason} ->
        Logger.error("Nimble search failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Check if a package exists in Nimble registry.

  ## Examples

      iex> Nimble.exists?("jester")
      true

      iex> Nimble.exists?("this-does-not-exist-xyz")
      false
  """
  @spec exists?(String.t()) :: boolean()
  def exists?(name) do
    case fetch_package(name) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  List all available versions for a package.

  Returns versions in descending order (newest first).

  ## Examples

      iex> Nimble.versions("jester")
      {:ok, ["0.6.0", "0.5.0", "0.4.3"]}
  """
  @spec versions(String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def versions(name) do
    case fetch_package(name) do
      {:ok, pkg} ->
        # metadata field doesn't exist in ResolvedPackage type, just use version
        versions = [pkg.version]
        sorted = Enum.sort(versions, {:desc, Version})
        {:ok, sorted}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private functions

  defp parse_package(body, name, requested_version) do
    # Extract basic info
    pkg_name = body["name"] || name
    description = body["description"] || ""
    license = body["license"] || "Unknown"
    url = body["url"] || ""
    web = body["web"] || ""

    # Extract versions
    versions_data = body["versions"] || []

    # Resolve target version
    target_version = if requested_version == "latest" do
      case versions_data do
        [latest | _] -> latest["version"] || latest["name"]
        [] -> "0.0.0"
      end
    else
      requested_version
    end

    # Find version data
    version_info = Enum.find(versions_data, fn v ->
      (v["version"] || v["name"]) == target_version
    end) || List.first(versions_data) || %{}

    # Extract dependencies
    deps_list = parse_dependencies(version_info["requires"] || [])

    # Convert to map format for ManifestFormat
    deps = Enum.into(deps_list, %{}, fn dep -> {dep, "*"} end)

    # Build download URL
    download_url = build_download_url(url, target_version)

    # Create manifest
    manifest = %ManifestFormat{
      name: pkg_name,
      version: target_version,
      description: description,
      license: license,
      homepage: web,
      repository: url,
      source_forth: :nimble,
      dependencies: deps,
      dev_dependencies: %{},
      raw_manifest: %{
        "registry" => "nimble",
        "language" => "nim",
        "manifest_format" => "nimble",
        "build_system" => "nimble",
        "versions" => Enum.map(versions_data, fn v ->
          v["version"] || v["name"]
        end),
        "tags" => body["tags"] || [],
        "author" => body["author"],
        "nimble_file" => "#{pkg_name}.nimble"
      }
    }

    package = %ResolvedPackage{
      package: pkg_name,
      version: target_version,
      forth: :nimble,
      registry_url: @base_url,
      tarball_url: download_url,
      checksum: nil,
      checksum_algo: :sha256,
      manifest: manifest,
      attestations: [],
      resolved_deps: []
    }

    Logger.info("Parsed Nimble package: #{pkg_name}@#{target_version}")
    {:ok, package}
  end

  defp parse_search_result(result) do
    name = result["name"]
    version = result["version"] || "unknown"

    manifest = %ManifestFormat{
      name: name,
      version: version,
      description: result["description"] || "",
      homepage: result["web"] || result["url"] || "",
      repository: result["url"] || "",
      source_forth: :nimble,
      license: nil,
      dependencies: %{},
      dev_dependencies: %{},
      raw_manifest: %{
        "registry" => "nimble",
        "language" => "nim",
        "tags" => result["tags"] || []
      }
    }

    %ResolvedPackage{
      package: name,
      version: version,
      forth: :nimble,
      registry_url: @base_url,
      tarball_url: result["url"],
      checksum: nil,
      checksum_algo: :sha256,
      manifest: manifest,
      attestations: [],
      resolved_deps: []
    }
  end

  defp parse_dependencies(requires) when is_list(requires) do
    Enum.reduce(requires, %{}, fn dep, acc ->
      case parse_dependency_spec(dep) do
        {:ok, name, version} -> Map.put(acc, name, version)
        :error -> acc
      end
    end)
  end

  defp parse_dependencies(_), do: %{}

  defp parse_dependency_spec(dep) when is_binary(dep) do
    # Nim dependencies format: "name >= 1.0.0" or just "name"
    case String.split(dep, [" ", "\t"], parts: 2, trim: true) do
      [name, version] ->
        {:ok, String.trim(name), String.trim(version)}

      [name] ->
        {:ok, String.trim(name), "*"}

      _ ->
        :error
    end
  end

  defp parse_dependency_spec(%{"name" => name, "version" => version}) do
    {:ok, name, version}
  end

  defp parse_dependency_spec(%{"name" => name}) do
    {:ok, name, "*"}
  end

  defp parse_dependency_spec(_), do: :error

  defp build_download_url(repo_url, version) when is_binary(repo_url) do
    cond do
      String.contains?(repo_url, "github.com") ->
        # GitHub tarball URL
        repo_url
        |> String.replace(".git", "")
        |> String.trim_trailing("/")
        |> Kernel.<>("/archive/refs/tags/v#{version}.tar.gz")

      String.contains?(repo_url, "gitlab.com") ->
        # GitLab tarball URL
        repo_url
        |> String.replace(".git", "")
        |> String.trim_trailing("/")
        |> Kernel.<>("/-/archive/v#{version}/package-v#{version}.tar.gz")

      true ->
        # Generic git clone URL
        repo_url
    end
  end

  defp build_download_url(_, _), do: nil
end
