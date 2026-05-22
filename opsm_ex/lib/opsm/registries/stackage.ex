# SPDX-License-Identifier: MPL-2.0
defmodule Opsm.Registries.Stackage do
  @moduledoc """
  Haskell Stackage registry adapter.
  https://www.stackage.org/
  Queries Stackage snapshots for curated Haskell package sets.

  API endpoints used:
  - GET /lts/:name                       - Package info in latest LTS
  - GET /nightly/:name                   - Package info in nightly
  - GET /api/snapshots                   - List snapshots
  - GET /lts/cabal.config                - Full LTS package set

  Falls back to Hackage for detailed package metadata since Stackage
  curates from Hackage.
  Hackage JSON: https://hackage.haskell.org/package/:name
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @stackage_url "https://www.stackage.org"
  @hackage_url "https://hackage.haskell.org"

  @doc """
  Fetch package metadata from Stackage (with Hackage fallback).
  """
  def fetch_package(name, version \\ "latest") do
    url = "#{@hackage_url}/package/#{URI.encode(name)}.json"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        ver = resolve_version(body, name, version)
        {:ok, build_resolved_package(name, body, ver)}

      {:error, :not_found} -> {:error, :not_found}
      {:error, %{status: 404}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Search for Haskell packages on Hackage/Stackage.
  Uses the Hackage search endpoint since Stackage does not expose one.
  """
  def search(query, _opts \\ []) do
    url = "#{@hackage_url}/packages/search.json?terms=#{URI.encode_www_form(query)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, results} when is_list(results) ->
        matches =
          results
          |> Enum.take(20)
          |> Enum.map(fn pkg ->
            %{
              name: pkg["name"],
              version: pkg["version"],
              description: pkg["synopsis"] || pkg["description"]
            }
          end)

        {:ok, matches}

      {:ok, _} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a package exists in Stackage/Hackage.
  """
  def exists?(name) do
    case fetch_package(name) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Get all available versions for a package from Hackage.
  """
  def versions(name) do
    url = "#{@hackage_url}/package/#{URI.encode(name)}.json"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        vers = extract_versions(body, name)
        {:ok, vers}

      {:error, :not_found} -> {:error, :not_found}
      {:error, %{status: 404}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp resolve_version(body, name, "latest") do
    case body do
      # Hackage package JSON has version map keyed by version string
      %{^name => versions_map} when is_map(versions_map) ->
        versions_map
        |> Map.keys()
        |> Enum.sort(&version_compare/2)
        |> List.last() || "0.0.0"

      _ ->
        body["version"] || "0.0.0"
    end
  end

  defp resolve_version(_body, _name, version), do: version

  defp extract_versions(body, name) do
    case body do
      %{^name => versions_map} when is_map(versions_map) ->
        Map.keys(versions_map)

      _ ->
        case body["version"] do
          nil -> []
          v -> [v]
        end
    end
  end

  defp version_compare(a, b), do: a <= b

  defp build_resolved_package(name, body, version) do
    pkg_info = extract_pkg_info(body, name)

    deps =
      (pkg_info["dependencies"] || %{})
      |> normalise_deps()

    manifest = %ManifestFormat{
      name: name,
      version: version,
      description: pkg_info["synopsis"] || pkg_info["description"],
      license: pkg_info["license"],
      homepage: pkg_info["homepage"] || "#{@hackage_url}/package/#{name}",
      repository: pkg_info["source-repository"] || pkg_info["repository"],
      authors: extract_authors(pkg_info),
      keywords: pkg_info["category"] |> List.wrap(),
      dependencies: deps,
      source_forth: :stackage
    }

    tarball = "#{@hackage_url}/package/#{name}-#{version}/#{name}-#{version}.tar.gz"

    %ResolvedPackage{
      package: name,
      version: version,
      forth: :stackage,
      registry_url: "#{@stackage_url}/lts/package/#{name}",
      manifest: manifest,
      tarball_url: tarball,
      checksum: nil,
      attestations: []
    }
  end

  defp extract_pkg_info(body, name) do
    case body do
      %{^name => _} -> body[name] || %{}
      _ -> body
    end
  end

  defp normalise_deps(deps) when is_map(deps), do: deps

  defp normalise_deps(deps) when is_list(deps) do
    deps
    |> Enum.map(fn
      d when is_binary(d) -> {d, "*"}
      %{"name" => n, "version" => v} -> {n, v}
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end

  defp normalise_deps(_), do: %{}

  defp extract_authors(info) do
    case info["author"] || info["maintainer"] do
      a when is_binary(a) -> [a]
      a when is_list(a) -> a
      _ -> []
    end
  end
end
