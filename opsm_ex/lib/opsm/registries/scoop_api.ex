# SPDX-License-Identifier: MPL-2.0
defmodule Opsm.Registries.ScoopApi do
  @moduledoc """
  Scoop package manager registry adapter.
  https://scoop.sh/
  Queries Scoop manifests via the GitHub API, resolving packages from
  the main bucket (ScoopInstaller/Main) and extras bucket
  (ScoopInstaller/Extras). Scoop is a command-line installer for Windows.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @main_raw "https://raw.githubusercontent.com/ScoopInstaller/Main/master/bucket"
  @extras_raw "https://raw.githubusercontent.com/ScoopInstaller/Extras/master/bucket"
  @scoop_search_api "https://scoopsearch.github.io/api/search"

  @headers [{"accept", "application/vnd.github.v3+json"},
            {"user-agent", "opsm/0.1.0 (https://github.com/hyperpolymath/opsm)"}]

  @doc """
  Fetch package manifest from Scoop buckets.
  Tries main bucket first, then extras.
  """
  def fetch_package(name, version \\ "latest") do
    case fetch_from_bucket(name, @main_raw, :main) do
      {:ok, _} = result -> maybe_pin_version(result, version)
      {:error, :not_found} ->
        case fetch_from_bucket(name, @extras_raw, :extras) do
          {:ok, _} = result -> maybe_pin_version(result, version)
          {:error, _} = err -> err
        end
      {:error, _} = err -> err
    end
  end

  defp fetch_from_bucket(name, raw_base, bucket) do
    url = "#{raw_base}/#{URI.encode(name)}.json"

    case VerifiedHttp.get_json(url, headers: @headers, receive_timeout: 10_000) do
      {:ok, body} ->
        {:ok, parse_scoop_manifest(name, body, bucket)}

      {:error, :not_found} -> {:error, :not_found}
      {:error, %{status: 404}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_pin_version({:ok, pkg}, "latest"), do: {:ok, pkg}
  defp maybe_pin_version({:ok, pkg}, version) do
    updated_manifest = %{pkg.manifest | version: version}
    {:ok, %{pkg | version: version, manifest: updated_manifest}}
  end

  defp parse_scoop_manifest(name, body, bucket) do
    # Scoop manifests have architecture-specific URLs
    arch = body["architecture"] || %{}
    arch_64 = arch["64bit"] || %{}

    url = arch_64["url"] || body["url"]
    hash = arch_64["hash"] || body["hash"]

    # Normalize URL (can be string or list)
    download_url = case url do
      u when is_binary(u) -> u
      [u | _] when is_binary(u) -> u
      _ -> nil
    end

    download_hash = case hash do
      h when is_binary(h) -> h
      [h | _] when is_binary(h) -> h
      _ -> nil
    end

    deps = (body["depends"] || [])
           |> List.wrap()
           |> Enum.map(fn dep -> {dep, "*"} end)
           |> Map.new()

    bucket_name = case bucket do
      :main -> "ScoopInstaller/Main"
      :extras -> "ScoopInstaller/Extras"
    end

    manifest = %ManifestFormat{
      name: name,
      version: body["version"] || "0.0.0",
      description: body["description"],
      license: normalize_license(body["license"]),
      homepage: body["homepage"],
      repository: "https://github.com/#{bucket_name}",
      keywords: body["suggest"] |> extract_suggestions(),
      dependencies: deps,
      source_forth: :scoop_api,
      raw_manifest: body
    }

    %ResolvedPackage{
      package: name,
      version: body["version"] || "0.0.0",
      forth: :scoop_api,
      registry_url: "https://scoop.sh",
      manifest: manifest,
      tarball_url: download_url,
      checksum: download_hash,
      checksum_algo: if(download_hash, do: :sha256),
      attestations: [],
      resolved_deps: []
    }
  end

  defp normalize_license(license) when is_binary(license), do: license
  defp normalize_license(%{"identifier" => id}), do: id
  defp normalize_license(_), do: nil

  defp extract_suggestions(nil), do: []
  defp extract_suggestions(suggest) when is_map(suggest), do: Map.keys(suggest)
  defp extract_suggestions(_), do: []

  @doc """
  Search for packages across Scoop buckets.
  Uses the community Scoop search API.
  """
  def search(query, _opts \\ []) do
    url = "#{@scoop_search_api}?q=#{URI.encode(query)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} when is_map(body) ->
        hits = body["hits"] || body["results"] || []
        results = hits
        |> Enum.take(20)
        |> Enum.map(fn hit ->
          %{
            name: hit["name"] || hit["_source"]["name"],
            version: hit["version"] || hit["_source"]["version"],
            description: hit["description"] || hit["_source"]["description"]
          }
        end)
        {:ok, results}

      {:ok, items} when is_list(items) ->
        results = items
        |> Enum.take(20)
        |> Enum.map(fn item ->
          %{name: item["name"], version: item["version"], description: item["description"]}
        end)
        {:ok, results}

      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Check if a package exists in any Scoop bucket.
  """
  def exists?(name) do
    case fetch_package(name) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Get available versions. Scoop manifests typically track one version.
  Check autoupdate config for version history.
  """
  def versions(name) do
    case fetch_package(name) do
      {:ok, pkg} -> {:ok, [pkg.version]}
      {:error, _} = err -> err
    end
  end
end
