# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Registries.FpmRegistry do
  @moduledoc """
  Fortran Package Manager (fpm) registry adapter.
  https://github.com/fortran-lang/fpm-registry
  Queries the fpm package registry for Fortran package metadata.

  API endpoints used:
  - GET /registry/:name.json             - Package metadata
  - GET /registry.json                   - Full registry listing
  - GET /packages/:name/:version.json    - Specific version

  The fpm registry is hosted via the fpm-registry GitHub repository.
  The canonical API base URL is https://fpm-registry.vercel.app for the
  web frontend, with raw data accessible from the GitHub repository.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @base_url "https://fpm-registry.vercel.app"
  @github_raw "https://raw.githubusercontent.com/fortran-lang/fpm-registry/main"

  @doc """
  Fetch package metadata from the fpm registry.
  """
  def fetch_package(name, version \\ "latest") do
    url = "#{@base_url}/registry/#{URI.encode(name)}.json"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        ver = resolve_version(body, version)
        {:ok, build_resolved_package(name, body, ver)}

      {:error, :not_found} ->
        fetch_from_github(name, version)

      {:error, %{status: 404}} ->
        fetch_from_github(name, version)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Search for Fortran packages matching a query string.
  """
  def search(query, _opts \\ []) do
    url = "#{@base_url}/registry.json"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"packages" => packages}} when is_list(packages) ->
        filter_packages(packages, query)

      {:ok, packages} when is_list(packages) ->
        filter_packages(packages, query)

      {:ok, packages} when is_map(packages) ->
        # Registry might be a name->info map
        packages
        |> Enum.map(fn {name, info} -> Map.put(info, "name", name) end)
        |> filter_packages(query)

      {:ok, _} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a package exists in the fpm registry.
  """
  def exists?(name) do
    case fetch_package(name) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Get all available versions for a Fortran package.
  """
  def versions(name) do
    url = "#{@base_url}/registry/#{URI.encode(name)}.json"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"versions" => vers}} when is_list(vers) ->
        {:ok, Enum.map(vers, fn v -> v["version"] || v end) |> Enum.reject(&is_nil/1)}

      {:ok, body} ->
        case body["version"] do
          nil -> {:ok, []}
          v -> {:ok, [v]}
        end

      {:error, :not_found} -> {:error, :not_found}
      {:error, %{status: 404}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp fetch_from_github(name, version) do
    url = "#{@github_raw}/registry/#{URI.encode(name)}.json"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        ver = resolve_version(body, version)
        {:ok, build_resolved_package(name, body, ver)}

      {:error, :not_found} -> {:error, :not_found}
      {:error, %{status: 404}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_version(body, "latest") do
    body["version"] || "0.0.0"
  end

  defp resolve_version(_body, version), do: version

  defp filter_packages(packages, query) do
    q_down = String.downcase(query)

    matches =
      packages
      |> Enum.filter(fn pkg ->
        name = String.downcase(pkg["name"] || "")
        desc = String.downcase(pkg["description"] || "")
        String.contains?(name, q_down) or String.contains?(desc, q_down)
      end)
      |> Enum.take(20)
      |> Enum.map(fn pkg ->
        %{
          name: pkg["name"],
          version: pkg["version"],
          description: pkg["description"]
        }
      end)

    {:ok, matches}
  end

  defp build_resolved_package(name, body, version) do
    deps =
      (body["dependencies"] || %{})
      |> normalise_deps()

    repo = body["git"] || body["repository"] || body["git-url"]

    manifest = %ManifestFormat{
      name: name,
      version: version,
      description: body["description"],
      license: body["license"],
      homepage: body["homepage"],
      repository: repo,
      authors: extract_authors(body),
      keywords: body["keywords"] || body["categories"] || [],
      dependencies: deps,
      source_forth: :fpm
    }

    tarball_url =
      case repo do
        url when is_binary(url) and url != "" ->
          if String.contains?(url, "github.com") do
            "#{url}/archive/refs/tags/v#{version}.tar.gz"
          else
            nil
          end

        _ ->
          nil
      end

    %ResolvedPackage{
      package: name,
      version: version,
      forth: :fpm,
      registry_url: "#{@base_url}/registry/#{name}",
      manifest: manifest,
      tarball_url: tarball_url,
      checksum: nil,
      attestations: []
    }
  end

  defp normalise_deps(deps) when is_map(deps) do
    Enum.map(deps, fn
      {k, v} when is_binary(v) -> {k, v}
      {k, %{"version" => v}} -> {k, v}
      {k, %{"git" => _}} -> {k, "*"}
      {k, _} -> {k, "*"}
    end)
    |> Map.new()
  end

  defp normalise_deps(deps) when is_list(deps) do
    deps
    |> Enum.map(fn
      %{"name" => n, "version" => v} -> {n, v}
      d when is_binary(d) -> {d, "*"}
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end

  defp normalise_deps(_), do: %{}

  defp extract_authors(body) do
    case body["author"] || body["maintainer"] do
      a when is_binary(a) -> [a]
      a when is_list(a) -> a
      _ -> []
    end
  end
end
