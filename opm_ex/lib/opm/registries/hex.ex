# SPDX-License-Identifier: PMPL-1.0
defmodule Opm.Registries.Hex do
  @moduledoc """
  Hex.pm Registry API client.
  https://hex.pm/api
  """

  alias Opm.Types.{ManifestFormat, ResolvedPackage}

  @base_url "https://hex.pm/api"
  @repo_url "https://repo.hex.pm"

  @doc """
  Fetch package metadata from hex.pm.
  """
  def fetch_package(name, version \\ "latest") do
    url = "#{@base_url}/packages/#{URI.encode(name)}"

    case Req.get(url, receive_timeout: 10_000) do
      {:ok, %{status: 200, body: body}} ->
        releases = body["releases"] || []

        target_version = if version == "latest" do
          case releases do
            [latest | _] -> latest["version"]
            [] -> nil
          end
        else
          version
        end

        release = Enum.find(releases, fn r -> r["version"] == target_version end)
        {:ok, parse_package(body, release, target_version)}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status}} ->
        {:error, "hex.pm returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Search for packages on hex.pm.
  """
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    url = "#{@base_url}/packages?search=#{URI.encode(query)}&page=1&per_page=#{limit}"

    case Req.get(url, receive_timeout: 10_000) do
      {:ok, %{status: 200, body: body}} when is_list(body) ->
        {:ok, Enum.map(body, &parse_search_result/1)}

      {:ok, %{status: 200, body: _}} ->
        {:ok, []}

      {:ok, %{status: status}} ->
        {:error, "hex.pm search returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a package exists.
  """
  def exists?(name) do
    url = "#{@base_url}/packages/#{URI.encode(name)}"

    case Req.head(url, receive_timeout: 5_000) do
      {:ok, %{status: 200}} -> true
      _ -> false
    end
  end

  @doc """
  Get all versions of a package.
  """
  def versions(name) do
    url = "#{@base_url}/packages/#{URI.encode(name)}"

    case Req.get(url, receive_timeout: 10_000) do
      {:ok, %{status: 200, body: body}} ->
        releases = body["releases"] || []
        {:ok, Enum.map(releases, & &1["version"]) |> Enum.reject(&is_nil/1)}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get tarball URL for a specific version.
  """
  def tarball_url(name, version) do
    {:ok, "#{@repo_url}/tarballs/#{name}-#{version}.tar"}
  end

  # Parsers

  defp parse_package(pkg, release, version) do
    meta = pkg["meta"] || %{}
    checksum = if release, do: release["checksum"], else: nil

    %ResolvedPackage{
      package: pkg["name"],
      version: version,
      forth: :hex,
      registry_url: "https://hex.pm",
      tarball_url: "#{@repo_url}/tarballs/#{pkg["name"]}-#{version}.tar",
      checksum: checksum,
      checksum_algo: :sha256,
      manifest: %ManifestFormat{
        name: pkg["name"],
        version: version,
        description: meta["description"],
        license: extract_licenses(meta["licenses"]),
        homepage: meta["links"]["Homepage"] || meta["links"]["homepage"],
        repository: meta["links"]["GitHub"] || meta["links"]["github"] || meta["links"]["Repository"],
        authors: meta["maintainers"] || [],
        keywords: [],
        dependencies: %{},  # Would need to fetch release details
        dev_dependencies: %{},
        source_forth: :hex,
        raw_manifest: pkg
      },
      attestations: [],
      resolved_deps: []
    }
  end

  defp parse_search_result(pkg) do
    meta = pkg["meta"] || %{}
    releases = pkg["releases"] || []
    latest = List.first(releases)

    %{
      name: pkg["name"],
      version: if(latest, do: latest["version"], else: nil),
      description: meta["description"],
      downloads: pkg["downloads"]["all"] || 0,
      recent_downloads: pkg["downloads"]["recent"] || 0
    }
  end

  defp extract_licenses(nil), do: nil
  defp extract_licenses([]), do: nil
  defp extract_licenses(licenses) when is_list(licenses), do: Enum.join(licenses, " OR ")
  defp extract_licenses(license), do: license
end
