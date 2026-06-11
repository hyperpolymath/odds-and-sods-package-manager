# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Registries.Cran do
  @moduledoc """
  CRAN (Comprehensive R Archive Network) API client.
  https://crandb.r-pkg.org/
  Uses CouchDB-backed CRAN metadata API.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @crandb_url "https://crandb.r-pkg.org"
  @cran_mirror "https://cran.r-project.org"

  @doc """
  Fetch package metadata from CRAN.
  """
  def fetch_package(name, version \\ "latest") do
    target_version = if version == "latest" do
      fetch_latest_version(name)
    else
      version
    end

    case target_version do
      nil ->
        {:error, :not_found}

      ver ->
        # Fetch version-specific metadata
        url = "#{@crandb_url}/#{name}/#{ver}"
        case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
          {:ok, body} ->
            {:ok, parse_package(name, body, ver)}

          {:error, :not_found} ->
            {:error, :not_found}

          {:error, %{status: 404}} ->
            {:error, :not_found}

          {:error, %{status: status}} ->
            {:error, "CRAN API returned status #{status}"}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp fetch_latest_version(name) do
    url = "#{@crandb_url}/#{name}"
    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"Version" => version}} -> version
      _ ->
        # Fallback: get version list
        case versions_internal(name) do
          {:ok, [latest | _]} -> latest
          _ -> nil
        end
    end
  end

  @doc """
  Search for CRAN packages.
  """
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    url = "#{@crandb_url}/-/search?q=#{URI.encode(query)}&size=#{limit}"
    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"rows" => rows}} when is_list(rows) ->
        results = Enum.map(rows, fn row ->
          %{
            name: Map.get(row, "Package") || Map.get(row, "name"),
            version: Map.get(row, "Version") || Map.get(row, "version"),
            description: Map.get(row, "Title") || Map.get(row, "description", ""),
            downloads: 0
          }
        end)
        {:ok, results}

      {:ok, _} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a CRAN package exists.
  """
  def exists?(name) do
    url = "#{@crandb_url}/#{name}"

    case VerifiedHttp.get(url, receive_timeout: 5_000) do
      {:ok, _} -> true
      _ -> false
    end
  end

  @doc """
  Get all versions of a CRAN package.
  """
  def versions(name) do
    versions_internal(name)
  end

  defp versions_internal(name) do
    url = "#{@crandb_url}/#{name}/all"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"versions" => versions_map}} when is_map(versions_map) ->
        # Extract version strings and sort (newest first)
        version_list = versions_map
        |> Map.keys()
        |> Enum.sort(:desc)
        {:ok, version_list}

      {:ok, _} ->
        # Fallback: try to get just the latest version
        fetch_latest_as_list(name)

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_latest_as_list(name) do
    case VerifiedHttp.get_json("#{@crandb_url}/#{name}", receive_timeout: 10_000) do
      {:ok, %{"Version" => version}} -> {:ok, [version]}
      _ -> {:ok, []}
    end
  end

  @doc """
  Get tarball URL for a specific version.
  """
  def tarball_url(name, version) do
    {:ok, "#{@cran_mirror}/src/contrib/#{name}_#{version}.tar.gz"}
  end

  # Parsers

  defp parse_package(name, metadata, version) do
    # Parse dependencies from "Depends" and "Imports" fields
    deps = parse_dependencies(metadata)

    # Extract package metadata
    description = Map.get(metadata, "Title") || Map.get(metadata, "Description", "")
    license = Map.get(metadata, "License")
    homepage = Map.get(metadata, "URL")
    repository = Map.get(metadata, "Repository")
    authors = parse_authors(Map.get(metadata, "Author"))

    %ResolvedPackage{
      package: name,
      version: version,
      forth: :cran,
      registry_url: "#{@crandb_url}/#{name}",
      tarball_url: "#{@cran_mirror}/src/contrib/#{name}_#{version}.tar.gz",
      checksum: nil,
      checksum_algo: nil,
      manifest: %ManifestFormat{
        name: name,
        version: version,
        description: description,
        license: license,
        homepage: homepage,
        repository: repository,
        authors: authors || [],
        keywords: [],
        dependencies: deps,
        dev_dependencies: %{},
        source_forth: :cran,
        raw_manifest: metadata
      },
      attestations: [],
      resolved_deps: []
    }
  end

  defp parse_dependencies(metadata) do
    # R packages can have dependencies in multiple fields
    depends = parse_dep_field(Map.get(metadata, "Depends", ""))
    imports = parse_dep_field(Map.get(metadata, "Imports", ""))

    Map.merge(depends, imports)
  end

  # Parse R dependency field format: "pkg1 (>= 1.0), pkg2, pkg3 (< 2.0)"
  defp parse_dep_field(field) when is_binary(field) do
    field
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "R (")))
    |> Enum.reduce(%{}, fn dep_str, acc ->
      case parse_single_dep(dep_str) do
        {pkg, constraint} -> Map.put(acc, pkg, constraint)
        nil -> acc
      end
    end)
  end
  defp parse_dep_field(_), do: %{}

  # Parse single dependency: "pkg (>= 1.0)" -> {"pkg", ">= 1.0"}
  defp parse_single_dep(dep_str) do
    case String.split(dep_str, "(", parts: 2) do
      [pkg] ->
        pkg = String.trim(pkg)
        if pkg != "" and pkg != "R", do: {pkg, "*"}, else: nil

      [pkg, constraint_part] ->
        pkg = String.trim(pkg)
        constraint = constraint_part |> String.trim_trailing(")") |> String.trim()
        if pkg != "" and pkg != "R", do: {pkg, constraint}, else: nil
    end
  end

  # Parse R author field - can be complex, extract names
  defp parse_authors(nil), do: []
  defp parse_authors(author) when is_binary(author) do
    # Simple extraction - R author fields can be very complex
    # Format examples: "John Doe <john@example.com>", "John Doe [aut, cre]"
    author
    |> String.split(",")
    |> Enum.map(fn a ->
      a
      |> String.split(["<", "["], parts: 2)
      |> hd()
      |> String.trim()
    end)
    |> Enum.reject(&(&1 == ""))
  end
  defp parse_authors(_), do: []
end
