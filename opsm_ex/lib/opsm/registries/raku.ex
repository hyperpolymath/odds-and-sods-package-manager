# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule Opsm.Registries.Raku do
  @moduledoc """
  Perl6/Raku module registry adapter.
  https://raku.land/
  Queries Raku.Land for Raku (formerly Perl 6) module metadata.

  API endpoints used:
  - GET /api/v1/dists/:identity        - Distribution metadata
  - GET /api/v1/search?q=:query        - Search distributions
  - GET /api/v1/dists                  - List all distributions

  Raku.Land aggregates modules from the Raku ecosystem (zef, CPAN-Raku,
  and p6c archives) into a unified searchable index.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @base_url "https://raku.land/api/v1"

  @doc """
  Fetch module metadata from Raku.Land.
  """
  def fetch_package(name, version \\ "latest") do
    url = "#{@base_url}/dists/#{URI.encode(name)}"

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
  Search for Raku modules matching a query string.
  """
  def search(query, _opts \\ []) do
    url = "#{@base_url}/search?q=#{URI.encode_www_form(query)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"dists" => dists}} when is_list(dists) ->
        {:ok, format_search_results(dists)}

      {:ok, results} when is_list(results) ->
        {:ok, format_search_results(results)}

      {:ok, _} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a module exists on Raku.Land.
  """
  def exists?(name) do
    case fetch_package(name) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Get all available versions for a Raku module.
  """
  def versions(name) do
    url = "#{@base_url}/dists/#{URI.encode(name)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"versions" => vers}} when is_list(vers) ->
        version_list =
          vers
          |> Enum.map(fn v -> v["version"] || v end)
          |> Enum.reject(&is_nil/1)

        {:ok, version_list}

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

  defp resolve_version(body, "latest") do
    body["version"] || body["latest_version"] || "0.0.0"
  end

  defp resolve_version(_body, version), do: version

  defp format_search_results(dists) do
    dists
    |> Enum.take(20)
    |> Enum.map(fn d ->
      %{
        name: d["name"] || d["identity"],
        version: d["version"] || d["latest_version"],
        description: d["description"] || d["blurb"]
      }
    end)
  end

  defp build_resolved_package(name, body, version) do
    deps =
      (body["depends"] || body["dependencies"] || %{})
      |> normalise_deps()

    source_url = body["source-url"] || body["repo-url"] || body["repository"]

    manifest = %ManifestFormat{
      name: name,
      version: version,
      description: body["description"] || body["blurb"],
      license: extract_license(body),
      homepage: body["homepage"] || "https://raku.land/#{body["ecosystem"]}/#{name}",
      repository: source_url,
      authors: extract_authors(body),
      keywords: body["tags"] || body["keywords"] || [],
      dependencies: deps,
      source_forth: :raku
    }

    tarball = body["download-url"] || body["dist-url"]

    %ResolvedPackage{
      package: name,
      version: version,
      forth: :raku,
      registry_url: "https://raku.land/#{body["ecosystem"] || "zef"}/#{name}",
      manifest: manifest,
      tarball_url: tarball,
      checksum: body["checksum"] || body["sha256"],
      checksum_algo: if(body["checksum"] || body["sha256"], do: :sha256),
      attestations: []
    }
  end

  defp normalise_deps(deps) when is_map(deps) do
    Enum.map(deps, fn
      {k, v} when is_binary(v) -> {k, v}
      {k, _} -> {k, "*"}
    end)
    |> Map.new()
  end

  defp normalise_deps(deps) when is_list(deps) do
    deps
    |> Enum.map(fn
      d when is_binary(d) -> {d, "*"}
      %{"name" => n, "version" => v} -> {n, v}
      %{"name" => n} -> {n, "*"}
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end

  defp normalise_deps(_), do: %{}

  defp extract_license(body) do
    case body["license"] do
      l when is_binary(l) -> l
      l when is_list(l) -> Enum.join(l, " AND ")
      _ -> nil
    end
  end

  defp extract_authors(body) do
    case body["authors"] || body["auth"] do
      a when is_list(a) -> Enum.map(a, &to_string/1)
      a when is_binary(a) -> [a]
      _ -> []
    end
  end
end
