# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule Opsm.Registries.GithubPackages do
  @moduledoc """
  GitHub Packages registry adapter.
  https://npm.pkg.github.com (npm scope) and https://ghcr.io (containers)
  Queries the GitHub Packages API for package metadata across supported types:
  npm, containers (ghcr.io), Maven, NuGet, and RubyGems.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://api.github.com"

  @doc """
  Fetch package metadata from GitHub Packages.
  Name format: "owner/package_name" with optional package_type in opts.
  Supported package types: :npm, :container, :maven, :nuget, :rubygems.
  """
  def fetch_package(name, version \\ "latest") do
    {owner, package_name, package_type} = parse_package_name(name)
    url = "#{@api_url}/users/#{owner}/packages/#{package_type}/#{URI.encode(package_name)}/versions"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, versions_list} when is_list(versions_list) ->
        target = find_target_version(versions_list, version)

        case target do
          nil ->
            {:error, :not_found}

          version_data ->
            ver = extract_version_tag(version_data)
            {:ok, parse_github_package(owner, package_name, package_type, version_data, ver)}
        end

      {:ok, _} ->
        {:error, :not_found}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, %{status: status}} ->
        {:error, "GitHub Packages returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp find_target_version(versions_list, "latest") do
    List.first(versions_list)
  end

  defp find_target_version(versions_list, target_version) do
    Enum.find(versions_list, fn v ->
      tags = get_in(v, ["metadata", "container", "tags"]) || []
      v["name"] == target_version || target_version in tags
    end) || List.first(versions_list)
  end

  @doc """
  Search for packages across GitHub Packages.
  Uses the GitHub search API to find packages matching the query.
  """
  def search(query, opts \\ []) do
    per_page = Keyword.get(opts, :limit, 20)
    url = "#{@api_url}/search/repositories?q=#{URI.encode_www_form(query)}+has:packages&per_page=#{per_page}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"items" => items}} when is_list(items) ->
        results = Enum.map(items, fn item ->
          %{
            name: item["full_name"],
            version: nil,
            description: item["description"]
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
  Check if a package exists on GitHub Packages.
  """
  def exists?(name) do
    {owner, package_name, package_type} = parse_package_name(name)
    url = "#{@api_url}/users/#{owner}/packages/#{package_type}/#{URI.encode(package_name)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Get all available versions for a package on GitHub Packages.
  Returns version tags or names, newest first.
  """
  def versions(name) do
    {owner, package_name, package_type} = parse_package_name(name)
    url = "#{@api_url}/users/#{owner}/packages/#{package_type}/#{URI.encode(package_name)}/versions"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, versions_list} when is_list(versions_list) ->
        version_names = Enum.map(versions_list, fn v ->
          extract_version_tag(v)
        end)
        {:ok, version_names}

      {:ok, _} ->
        {:ok, []}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  defp parse_package_name(name) do
    parts = String.split(name, "/", parts: 3)

    case parts do
      [owner, type, pkg] when type in ~w(npm container maven nuget rubygems) ->
        {owner, pkg, type}

      [owner, pkg] ->
        {owner, pkg, "container"}

      [pkg] ->
        {"_", pkg, "container"}
    end
  end

  defp extract_version_tag(version_data) do
    tags = get_in(version_data, ["metadata", "container", "tags"]) || []

    cond do
      version_data["name"] && version_data["name"] != "" ->
        version_data["name"]

      length(tags) > 0 ->
        List.first(tags)

      true ->
        to_string(version_data["id"] || "unknown")
    end
  end

  defp parse_github_package(owner, package_name, package_type, version_data, version) do
    full_name = "#{owner}/#{package_name}"

    registry_base = case package_type do
      "container" -> "https://ghcr.io/#{owner}/#{package_name}"
      "npm" -> "https://npm.pkg.github.com/#{owner}/#{package_name}"
      _ -> "https://github.com/#{owner}/#{package_name}/packages"
    end

    manifest = %ManifestFormat{
      name: full_name,
      version: version,
      description: version_data["description"] || "GitHub Package #{full_name}",
      license: nil,
      homepage: "https://github.com/#{owner}/#{package_name}",
      repository: "https://github.com/#{owner}/#{package_name}",
      authors: [owner],
      keywords: [],
      dependencies: %{},
      dev_dependencies: %{},
      source_forth: :github_packages,
      raw_manifest: version_data
    }

    %ResolvedPackage{
      package: full_name,
      version: version,
      forth: :github_packages,
      registry_url: registry_base,
      tarball_url: nil,
      checksum: nil,
      checksum_algo: :sha256,
      manifest: manifest,
      attestations: [],
      resolved_deps: []
    }
  end
end
