# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Registries.Bioconductor do
  @moduledoc """
  Bioconductor registry adapter for R bioinformatics packages.
  https://bioconductor.org/
  Uses the Bioconductor package JSON API and VIEWS metadata.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://bioconductor.org"
  @packages_url "https://bioconductor.org/packages/json"
  @release_url "https://bioconductor.org/packages/release/bioc"

  @doc """
  Fetch package metadata from Bioconductor.
  """
  def fetch_package(name, version \\ "latest") do
    url = "#{@packages_url}/#{URI.encode(name)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} when is_map(body) ->
        target_version = if version == "latest" do
          body["Version"] || extract_version_from_body(body)
        else
          version
        end

        deps = parse_dependencies(body)
        {:ok, parse_package(name, body, target_version, deps)}

      {:error, :not_found} ->
        # Fallback: try the release VIEWS endpoint
        fetch_from_views(name, version)

      {:error, %{status: 404}} ->
        fetch_from_views(name, version)

      {:error, %{status: status}} ->
        {:error, "Bioconductor returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_from_views(name, version) do
    url = "#{@release_url}/html/#{URI.encode(name)}.html"

    case VerifiedHttp.get(url, receive_timeout: 10_000) do
      {:ok, _} ->
        # Package exists but we could not get structured JSON; return minimal info
        ver = if version == "latest", do: "unknown", else: version
        {:ok, parse_package(name, %{}, ver, %{})}

      _ ->
        {:error, :not_found}
    end
  end

  @doc """
  Search for Bioconductor packages.
  Uses the Bioconductor package search JSON API.
  """
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    url = "#{@packages_url}/search?q=#{URI.encode_www_form(query)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, results} when is_list(results) ->
        packages = results
        |> Enum.take(limit)
        |> Enum.map(fn pkg ->
          %{
            name: pkg["Package"] || pkg["name"],
            version: pkg["Version"] || pkg["version"],
            description: pkg["Title"] || pkg["description"] || "",
            downloads: pkg["downloads"] || 0
          }
        end)
        {:ok, packages}

      {:ok, %{"packages" => packages}} when is_list(packages) ->
        results = packages
        |> Enum.take(limit)
        |> Enum.map(fn pkg ->
          %{
            name: pkg["Package"] || pkg["name"],
            version: pkg["Version"] || pkg["version"],
            description: pkg["Title"] || pkg["description"] || "",
            downloads: 0
          }
        end)
        {:ok, results}

      {:ok, _} ->
        {:ok, []}

      {:error, %{status: status}} ->
        {:error, "Bioconductor search returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a Bioconductor package exists.
  """
  def exists?(name) do
    url = "#{@packages_url}/#{URI.encode(name)}"

    case VerifiedHttp.get(url, receive_timeout: 5_000) do
      {:ok, _} -> true
      _ ->
        # Fallback: check release HTML page
        views_url = "#{@release_url}/html/#{URI.encode(name)}.html"
        case VerifiedHttp.get(views_url, receive_timeout: 5_000) do
          {:ok, _} -> true
          _ -> false
        end
    end
  end

  @doc """
  Get all versions of a Bioconductor package.
  Bioconductor ties package versions to release cycles; typically only current release is available.
  """
  def versions(name) do
    url = "#{@packages_url}/#{URI.encode(name)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} when is_map(body) ->
        ver = body["Version"] || extract_version_from_body(body)
        if ver, do: {:ok, [ver]}, else: {:ok, []}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get source tarball URL for a Bioconductor package.
  """
  def tarball_url(name, version) do
    {:ok, "#{@release_url}/src/contrib/#{name}_#{version}.tar.gz"}
  end

  # Parsers

  defp extract_version_from_body(body) do
    body["version"] || body["latest_version"] || nil
  end

  defp parse_dependencies(body) do
    depends = parse_dep_field(Map.get(body, "Depends", ""))
    imports = parse_dep_field(Map.get(body, "Imports", ""))
    Map.merge(depends, imports)
  end

  # Parse R-style dependency field: "pkg1 (>= 1.0), pkg2, pkg3 (< 2.0)"
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

  defp parse_package(name, body, version, deps) do
    description = Map.get(body, "Title") || Map.get(body, "Description", "")
    license = Map.get(body, "License")
    authors = parse_authors(Map.get(body, "Author"))
    homepage = Map.get(body, "URL")

    %ResolvedPackage{
      package: name,
      version: version,
      forth: :bioconductor,
      registry_url: "#{@api_url}/packages/#{name}",
      tarball_url: "#{@release_url}/src/contrib/#{name}_#{version}.tar.gz",
      checksum: nil,
      checksum_algo: nil,
      manifest: %ManifestFormat{
        name: name,
        version: version,
        description: description,
        license: license,
        homepage: homepage,
        repository: Map.get(body, "git_url") || Map.get(body, "BugReports"),
        authors: authors,
        keywords: parse_bioc_views(Map.get(body, "biocViews", "")),
        dependencies: deps,
        dev_dependencies: parse_dep_field(Map.get(body, "Suggests", "")),
        source_forth: :bioconductor,
        raw_manifest: body
      },
      attestations: [],
      resolved_deps: []
    }
  end

  defp parse_authors(nil), do: []
  defp parse_authors(author) when is_binary(author) do
    author
    |> String.split(",")
    |> Enum.map(fn a ->
      a |> String.split(["<", "["], parts: 2) |> hd() |> String.trim()
    end)
    |> Enum.reject(&(&1 == ""))
  end
  defp parse_authors(_), do: []

  # biocViews is a comma-separated list of classification terms
  defp parse_bioc_views(views) when is_binary(views) do
    views
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end
  defp parse_bioc_views(_), do: []
end
