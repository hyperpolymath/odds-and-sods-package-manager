# SPDX-License-Identifier: MPL-2.0
defmodule Opsm.Registries.Oblibeny do
  @moduledoc """
  Oblibeny package registry API client.

  Oblibeny is a secure edge language with reversibility and accountability.
  Package manager: obli-pkg (Zig)
  Package format: .zpkg with triple post-quantum signatures
  Registry: https://registry.oblibeny.org (planned)

  For now, uses local/git-based package resolution until registry deployed.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Manifest.OpsmToml
  alias Opsm.Verified.Http, as: VerifiedHttp

  @base_url "https://registry.oblibeny.org/api/v1"
  @fallback_mode :git  # Until registry deployed

  @doc """
  Fetch package metadata from oblibeny registry.
  Falls back to git-based resolution if registry unavailable.
  """
  def fetch_package(name, version \\ "latest") do
    case @fallback_mode do
      :git -> fetch_from_git(name, version)
      :registry -> fetch_from_registry(name, version)
    end
  end

  @doc """
  Search for packages in oblibeny registry.
  """
  def search(query, opts \\ []) do
    case @fallback_mode do
      :git -> search_git(query, opts)
      :registry -> search_registry(query, opts)
    end
  end

  @doc """
  Check if a package exists.
  """
  def exists?(name) do
    case @fallback_mode do
      :git -> git_exists?(name)
      :registry -> registry_exists?(name)
    end
  end

  @doc """
  Get all versions of a package.
  """
  def versions(name) do
    case @fallback_mode do
      :git -> git_versions(name)
      :registry -> registry_versions(name)
    end
  end

  # Registry mode (future)

  defp fetch_from_registry(name, version) do
    url = "#{@base_url}/packages/#{URI.encode(name)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        target_version = if version == "latest", do: body["latest_version"], else: version
        {:ok, parse_package(body, target_version)}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp search_registry(query, opts) do
    limit = Keyword.get(opts, :limit, 20)
    url = "#{@base_url}/packages?q=#{URI.encode(query)}&limit=#{limit}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} when is_list(body) ->
        {:ok, Enum.map(body, &parse_search_result/1)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp registry_exists?(name) do
    url = "#{@base_url}/packages/#{URI.encode(name)}"
    case VerifiedHttp.get(url, receive_timeout: 5_000) do
      {:ok, _} -> true
      _ -> false
    end
  end

  defp registry_versions(name) do
    url = "#{@base_url}/packages/#{URI.encode(name)}/versions"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} when is_list(body) ->
        {:ok, Enum.map(body, & &1["version"])}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Git fallback mode (current)

  defp fetch_from_git(name, version) do
    # Try common git patterns
    urls = [
      "https://github.com/hyperpolymath/#{name}",
      "https://gitlab.com/hyperpolymath/#{name}",
      "https://git.sr.ht/~hyperpolymath/#{name}"
    ]

    Enum.find_value(urls, {:error, :not_found}, fn url ->
      case git_fetch(url, version) do
        {:ok, pkg} -> {:ok, pkg}
        _ -> nil
      end
    end)
  end

  defp search_git(_query, _opts) do
    # Git search not implemented yet
    {:ok, []}
  end

  defp git_exists?(name) do
    urls = [
      "https://github.com/hyperpolymath/#{name}",
      "https://gitlab.com/hyperpolymath/#{name}"
    ]

    Enum.any?(urls, fn url ->
      case VerifiedHttp.get(url, receive_timeout: 5_000) do
        {:ok, _} -> true
        _ -> false
      end
    end)
  end

  defp git_versions(_name) do
    # For git mode, versions are git tags
    # This requires git ls-remote or GitHub API
    {:ok, ["main", "master"]}  # Minimal fallback
  end

  defp git_fetch(repo_url, version) do
    # Construct oblibeny.toml URL
    manifest_url = case version do
      "latest" -> "#{repo_url}/raw/main/oblibeny.toml"
      "main" -> "#{repo_url}/raw/main/oblibeny.toml"
      "master" -> "#{repo_url}/raw/master/oblibeny.toml"
      tag -> "#{repo_url}/raw/#{tag}/oblibeny.toml"
    end

    case VerifiedHttp.get(manifest_url, receive_timeout: 10_000) do
      {:ok, %{body: body}} ->
        case parse_toml_manifest(body, repo_url, version) do
          {:ok, pkg} -> {:ok, pkg}
          error -> error
        end

      _ ->
        {:error, :not_found}
    end
  end

  defp parse_toml_manifest(toml_text, repo_url, version) do
    # Use canonical OpsmToml parser; fall back to minimal struct on parse failure.
    manifest =
      case OpsmToml.parse(toml_text) do
        {:ok, m} ->
          %{m | source_forth: :oblibeny}

        {:error, _} ->
          %ManifestFormat{
            name: repo_url |> String.split("/") |> List.last() |> String.trim(),
            version: version,
            description: nil,
            license: nil,
            homepage: repo_url,
            repository: repo_url,
            authors: [],
            keywords: [],
            dependencies: %{},
            dev_dependencies: %{},
            source_forth: :oblibeny,
            raw_manifest: %{}
          }
      end

    pkg = %ResolvedPackage{
      package: manifest.name || (repo_url |> String.split("/") |> List.last() |> String.trim()),
      version: manifest.version || version,
      forth: :oblibeny,
      registry_url: repo_url,
      tarball_url: "#{repo_url}/archive/#{version}.tar.gz",
      checksum: nil,
      checksum_algo: nil,
      manifest: manifest,
      attestations: [],
      resolved_deps: []
    }

    {:ok, pkg}
  end

  # Parsers (for future registry mode)

  defp parse_package(pkg_data, version) do
    %ResolvedPackage{
      package: pkg_data["name"],
      version: version,
      forth: :oblibeny,
      registry_url: @base_url,
      tarball_url: "#{@base_url}/packages/#{pkg_data["name"]}/#{version}/download",
      checksum: pkg_data["checksum"],
      checksum_algo: :sha3_512,  # Oblibeny uses SHA3-512
      manifest: %ManifestFormat{
        name: pkg_data["name"],
        version: version,
        description: pkg_data["description"],
        license: pkg_data["license"],
        homepage: pkg_data["homepage"],
        repository: pkg_data["repository"],
        authors: pkg_data["authors"] || [],
        keywords: pkg_data["keywords"] || [],
        dependencies: pkg_data["dependencies"] || %{},
        dev_dependencies: pkg_data["dev_dependencies"] || %{},
        source_forth: :oblibeny,
        raw_manifest: pkg_data
      },
      attestations: pkg_data["attestations"] || [],
      resolved_deps: []
    }
  end

  defp parse_search_result(result) do
    %{
      name: result["name"],
      version: result["latest_version"],
      description: result["description"],
      downloads: result["downloads"] || 0,
      recent_downloads: result["recent_downloads"] || 0
    }
  end
end
