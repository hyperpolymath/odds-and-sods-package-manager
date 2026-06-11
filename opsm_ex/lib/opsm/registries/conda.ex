# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Registries.Conda do
  @moduledoc """
  Conda/Anaconda registry API client.
  https://api.anaconda.org/
  Supports conda-forge and other Anaconda channels.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://api.anaconda.org"
  @default_owner "conda-forge"

  @doc """
  Fetch package metadata from Anaconda registry.
  Package names can be "owner/name" or just "name" (defaults to conda-forge).
  """
  def fetch_package(name, version \\ "latest") do
    {owner, pkg_name} = parse_package_name(name)

    target_version = if version == "latest" do
      fetch_latest_version(owner, pkg_name)
    else
      version
    end

    case target_version do
      nil ->
        {:error, :not_found}

      ver ->
        # Fetch package metadata
        url = "#{@api_url}/package/#{owner}/#{pkg_name}"
        case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
          {:ok, body} ->
            # Fetch file/version details
            files = fetch_files(owner, pkg_name)
            {:ok, parse_package(owner, pkg_name, body, ver, files)}

          {:error, :not_found} ->
            {:error, :not_found}

          {:error, %{status: 404}} ->
            {:error, :not_found}

          {:error, %{status: status}} ->
            {:error, "Anaconda API returned status #{status}"}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp parse_package_name(name) do
    case String.split(name, "/", parts: 2) do
      [owner, pkg] -> {owner, pkg}
      [pkg] -> {@default_owner, pkg}
    end
  end

  defp fetch_latest_version(owner, pkg_name) do
    url = "#{@api_url}/package/#{owner}/#{pkg_name}"
    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"latest_version" => version}} -> version
      {:ok, %{"versions" => versions}} when is_list(versions) and versions != [] ->
        List.last(versions)
      _ ->
        # Fallback: get version list from files
        case versions_internal(owner, pkg_name) do
          {:ok, [latest | _]} -> latest
          _ -> nil
        end
    end
  end

  defp fetch_files(owner, pkg_name) do
    url = "#{@api_url}/package/#{owner}/#{pkg_name}/files"
    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, files} when is_list(files) -> files
      {:ok, %{"files" => files}} when is_list(files) -> files
      _ -> []
    end
  end

  @doc """
  Search for Conda packages.
  """
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    url = "#{@api_url}/search?name=#{URI.encode(query)}"
    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, results} when is_list(results) ->
        {:ok, parse_search_results(results, limit)}

      {:ok, %{"packages" => packages}} when is_list(packages) ->
        {:ok, parse_search_results(packages, limit)}

      {:ok, _} ->
        {:ok, []}

      {:error, _} ->
        {:ok, []}
    end
  end

  defp parse_search_results(results, limit) do
    results
    |> Enum.take(limit)
    |> Enum.map(fn result ->
      %{
        name: "#{result["owner"]}/#{result["name"]}" || result["name"],
        version: result["version"] || result["latest_version"] || "unknown",
        description: result["summary"] || result["description"] || "",
        downloads: result["downloads"] || 0
      }
    end)
  end

  @doc """
  Check if a Conda package exists.
  """
  def exists?(name) do
    {owner, pkg_name} = parse_package_name(name)
    url = "#{@api_url}/package/#{owner}/#{pkg_name}"

    case VerifiedHttp.get(url, receive_timeout: 5_000) do
      {:ok, _} -> true
      _ -> false
    end
  end

  @doc """
  Get all versions of a Conda package.
  """
  def versions(name) do
    {owner, pkg_name} = parse_package_name(name)
    versions_internal(owner, pkg_name)
  end

  defp versions_internal(owner, pkg_name) do
    url = "#{@api_url}/package/#{owner}/#{pkg_name}/files"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, files} when is_list(files) ->
        versions = extract_versions_from_files(files)
        if versions == [] do
          {:error, :not_found}
        else
          {:ok, versions}
        end

      {:ok, %{"files" => files}} when is_list(files) ->
        versions = extract_versions_from_files(files)
        if versions == [] do
          {:error, :not_found}
        else
          {:ok, versions}
        end

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_versions_from_files(files) do
    files
    |> Enum.map(fn file -> file["version"] end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.reverse()
  end

  @doc """
  Get tarball URL for a specific version.
  Conda packages are typically .tar.bz2 or .conda files.
  """
  def tarball_url(name, version) do
    {owner, pkg_name} = parse_package_name(name)

    # Fetch files to find the specific tarball for this version
    case fetch_files(owner, pkg_name) do
      files when is_list(files) ->
        case find_tarball_for_version(files, version) do
          nil -> {:error, :not_found}
          url -> {:ok, url}
        end
      _ ->
        {:error, :not_found}
    end
  end

  defp find_tarball_for_version(files, version) do
    files
    |> Enum.find(fn file -> file["version"] == version end)
    |> case do
      nil -> nil
      file -> file["download_url"] || "#{@api_url}#{file["url"]}"
    end
  end

  # Parsers

  defp parse_package(owner, pkg_name, info, version, files) do
    full_name = "#{owner}/#{pkg_name}"

    # Extract dependencies from package info (if available)
    deps = extract_dependencies(info, version, files)

    # Find tarball for this version
    tarball = find_tarball_for_version(files, version)

    # Extract checksum from files metadata
    checksum = extract_checksum(files, version)

    %ResolvedPackage{
      package: full_name,
      version: version,
      forth: :conda,
      registry_url: "#{@api_url}/package/#{owner}/#{pkg_name}",
      tarball_url: tarball,
      checksum: checksum,
      checksum_algo: if(checksum, do: :md5, else: nil),
      manifest: %ManifestFormat{
        name: full_name,
        version: version,
        description: info["summary"] || info["description"],
        license: info["license"] || nil,
        homepage: info["home"] || info["url"] || "https://anaconda.org/#{owner}/#{pkg_name}",
        repository: info["dev_url"] || info["doc_url"] || nil,
        authors: [],
        keywords: [],
        dependencies: deps,
        dev_dependencies: %{},
        source_forth: :conda,
        raw_manifest: info
      },
      attestations: [],
      resolved_deps: []
    }
  end

  defp extract_dependencies(info, version, files) do
    # Try to extract dependencies from package info
    # Conda dependencies can be in various places
    cond do
      is_map(info["depends"]) -> info["depends"]
      is_list(info["depends"]) -> parse_conda_depends_list(info["depends"])
      true ->
        # Try to find dependencies in files metadata
        case Enum.find(files, fn f -> f["version"] == version end) do
          nil -> %{}
          file -> parse_conda_depends_list(file["dependencies"] || [])
        end
    end
  end

  defp parse_conda_depends_list(depends) when is_list(depends) do
    depends
    |> Enum.reduce(%{}, fn dep, acc ->
      case parse_conda_dependency(dep) do
        {pkg, constraint} -> Map.put(acc, pkg, constraint)
        nil -> acc
      end
    end)
  end
  defp parse_conda_depends_list(_), do: %{}

  # Parse Conda dependency strings like "python >=3.8" or "numpy"
  defp parse_conda_dependency(dep) when is_binary(dep) do
    case String.split(dep, " ", parts: 2) do
      [pkg, constraint] -> {String.trim(pkg), String.trim(constraint)}
      [pkg] -> {String.trim(pkg), "*"}
    end
  end
  defp parse_conda_dependency(_), do: nil

  defp extract_checksum(files, version) do
    case Enum.find(files, fn f -> f["version"] == version end) do
      nil -> nil
      file -> file["md5"] || file["sha256"]
    end
  end
end
