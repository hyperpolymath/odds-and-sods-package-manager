# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Registries.Raco do
  @moduledoc """
  Racket package registry adapter.
  https://pkgs.racket-lang.org/
  Queries the Racket package catalog for package metadata.

  API endpoints used:
  - GET /pkg/:name                  - Package detail (JSON via Accept header)
  - GET /pkgs-all.json.gz           - Full package listing (compressed)
  - GET /search/api/search?q=:query - Search packages

  The Racket pkg catalog exposes JSON data via pkgs.racket-lang.org.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @base_url "https://pkgs.racket-lang.org"

  @doc """
  Fetch package metadata from the Racket package catalog.
  """
  def fetch_package(name, version \\ "latest") do
    url = "#{@base_url}/pkg/#{URI.encode(name)}.json"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        ver = resolve_version(body, version)
        {:ok, build_resolved_package(name, body, ver)}

      {:error, :not_found} -> {:error, :not_found}
      {:error, %{status: 404}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Search for Racket packages matching a query string.
  """
  def search(query, _opts \\ []) do
    url = "#{@base_url}/search/api/search?q=#{URI.encode_www_form(query)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, results} when is_list(results) ->
        matches =
          results
          |> Enum.take(20)
          |> Enum.map(fn pkg ->
            %{
              name: pkg["name"],
              version: pkg["version"] || pkg["checksum_version"],
              description: pkg["description"] || pkg["blurb"]
            }
          end)

        {:ok, matches}

      {:ok, %{"results" => results}} when is_list(results) ->
        matches =
          results
          |> Enum.take(20)
          |> Enum.map(fn pkg ->
            %{
              name: pkg["name"],
              version: pkg["version"],
              description: pkg["description"]
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
  Check if a package exists in the Racket catalog.
  """
  def exists?(name) do
    case fetch_package(name) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Get all available versions for a package.
  Racket packages are typically single-version (source-based), so this
  returns the currently published version.
  """
  def versions(name) do
    case fetch_package(name) do
      {:ok, pkg} -> {:ok, [pkg.version]}
      {:error, _} = err -> err
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp resolve_version(body, "latest") do
    body["version"] || body["checksum_version"] || "0.0.0"
  end

  defp resolve_version(_body, version), do: version

  defp build_resolved_package(name, body, version) do
    deps =
      (body["dependencies"] || body["deps"] || [])
      |> normalise_deps()

    source_url = body["source"] || body["source_url"]

    manifest = %ManifestFormat{
      name: name,
      version: version,
      description: body["description"] || body["blurb"],
      license: extract_license(body),
      homepage: "#{@base_url}/pkg/#{name}",
      repository: source_url,
      authors: extract_authors(body),
      keywords: body["tags"] || body["categories"] || [],
      dependencies: deps,
      source_forth: :raco
    }

    %ResolvedPackage{
      package: name,
      version: version,
      forth: :raco,
      registry_url: "#{@base_url}/pkg/#{name}",
      manifest: manifest,
      tarball_url: source_url,
      checksum: body["checksum"],
      checksum_algo: if(body["checksum"], do: :sha1),
      attestations: []
    }
  end

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

  defp normalise_deps(deps) when is_map(deps), do: deps
  defp normalise_deps(_), do: %{}

  defp extract_license(body) do
    body["license"] || get_in(body, ["ring", "license"])
  end

  defp extract_authors(body) do
    case body["author"] || body["authors"] do
      a when is_binary(a) -> [a]
      a when is_list(a) -> a
      _ -> []
    end
  end
end
