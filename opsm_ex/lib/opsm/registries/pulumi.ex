# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Registries.Pulumi do
  @moduledoc """
  Pulumi Registry adapter.
  https://www.pulumi.com/registry/
  Queries the Pulumi Registry API for provider and component package metadata,
  versions, and documentation. Supports both native and bridged providers.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://www.pulumi.com/registry/api"
  @github_api "https://api.github.com"

  @doc """
  Fetch package metadata from the Pulumi Registry.
  Name is the provider/component name (e.g., "aws", "gcp", "kubernetes").
  """
  def fetch_package(name, version \\ "latest") do
    url = "#{@api_url}/packages/#{URI.encode(name)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        ver = resolve_version(body, name, version)
        {:ok, parse_pulumi_package(name, body, ver)}

      {:error, :not_found} ->
        # Fallback: try the GitHub releases API for pulumi-<name> repo
        fetch_from_github(name, version)

      {:error, %{status: 404}} ->
        fetch_from_github(name, version)

      {:error, %{status: status}} ->
        {:error, "Pulumi Registry returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_from_github(name, version) do
    url = "#{@github_api}/repos/pulumi/pulumi-#{name}/releases"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, releases} when is_list(releases) and length(releases) > 0 ->
        target = find_github_release(releases, version)

        case target do
          nil ->
            {:error, :not_found}

          release ->
            ver = release["tag_name"] |> String.trim_leading("v")
            {:ok, parse_github_release(name, release, ver)}
        end

      {:ok, _} ->
        {:error, :not_found}

      {:error, _} ->
        {:error, :not_found}
    end
  end

  defp find_github_release(releases, "latest"), do: List.first(releases)
  defp find_github_release(releases, target_version) do
    Enum.find(releases, List.first(releases), fn r ->
      tag = String.trim_leading(r["tag_name"] || "", "v")
      tag == target_version
    end)
  end

  defp resolve_version(body, _name, "latest") do
    body["version"] ||
      get_in(body, ["latest_version"]) ||
      "0.0.0"
  end

  defp resolve_version(_body, _name, requested), do: requested

  @doc """
  Search for packages in the Pulumi Registry.
  Returns matching packages with name, version, and description.
  """
  def search(query, _opts \\ []) do
    url = "#{@api_url}/search?q=#{URI.encode_www_form(query)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"packages" => packages}} when is_list(packages) ->
        results = packages
        |> Enum.take(20)
        |> Enum.map(fn pkg ->
          %{
            name: pkg["name"],
            version: pkg["version"],
            description: pkg["description"]
          }
        end)
        {:ok, results}

      {:ok, packages} when is_list(packages) ->
        results = packages
        |> Enum.take(20)
        |> Enum.map(fn pkg ->
          %{
            name: pkg["name"],
            version: pkg["version"],
            description: pkg["description"]
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
  Check if a package exists in the Pulumi Registry.
  """
  def exists?(name) do
    url = "#{@api_url}/packages/#{URI.encode(name)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, _} -> true
      {:error, _} ->
        # Fallback: check GitHub
        github_url = "#{@github_api}/repos/pulumi/pulumi-#{name}"
        case VerifiedHttp.get_json(github_url, receive_timeout: 10_000) do
          {:ok, _} -> true
          {:error, _} -> false
        end
    end
  end

  @doc """
  Get all available versions of a Pulumi package.
  Returns version strings, newest first.
  """
  def versions(name) do
    url = "#{@api_url}/packages/#{URI.encode(name)}/versions"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"versions" => versions_list}} when is_list(versions_list) ->
        ver_strs = versions_list
        |> Enum.map(fn v ->
          cond do
            is_binary(v) -> v
            is_map(v) -> v["version"]
            true -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)
        {:ok, ver_strs}

      {:ok, _} ->
        # Fallback: get versions from GitHub releases
        fetch_github_versions(name)

      {:error, :not_found} ->
        fetch_github_versions(name)

      {:error, %{status: 404}} ->
        fetch_github_versions(name)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_github_versions(name) do
    url = "#{@github_api}/repos/pulumi/pulumi-#{name}/releases?per_page=100"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, releases} when is_list(releases) ->
        ver_strs = releases
        |> Enum.map(fn r -> String.trim_leading(r["tag_name"] || "", "v") end)
        |> Enum.reject(fn v -> v == "" end)
        {:ok, ver_strs}

      {:error, _} ->
        {:error, :not_found}
    end
  end

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  defp parse_pulumi_package(name, body, version) do
    manifest = %ManifestFormat{
      name: name,
      version: version,
      description: body["description"],
      license: body["license"],
      homepage: "https://www.pulumi.com/registry/packages/#{name}",
      repository: body["repository"] || body["repoUrl"],
      authors: extract_authors(body),
      keywords: body["keywords"] || body["categories"] || [],
      dependencies: extract_dependencies(body),
      dev_dependencies: %{},
      source_forth: :pulumi,
      raw_manifest: body
    }

    %ResolvedPackage{
      package: name,
      version: version,
      forth: :pulumi,
      registry_url: "https://www.pulumi.com/registry/packages/#{name}",
      tarball_url: nil,
      checksum: nil,
      checksum_algo: :sha256,
      manifest: manifest,
      attestations: [],
      resolved_deps: []
    }
  end

  defp parse_github_release(name, release, version) do
    manifest = %ManifestFormat{
      name: name,
      version: version,
      description: release["body"] |> truncate_description(),
      license: nil,
      homepage: "https://www.pulumi.com/registry/packages/#{name}",
      repository: "https://github.com/pulumi/pulumi-#{name}",
      authors: [release["author"]["login"] || "pulumi"],
      keywords: [],
      dependencies: %{},
      dev_dependencies: %{},
      source_forth: :pulumi,
      raw_manifest: release
    }

    %ResolvedPackage{
      package: name,
      version: version,
      forth: :pulumi,
      registry_url: "https://www.pulumi.com/registry/packages/#{name}",
      tarball_url: release["tarball_url"],
      checksum: nil,
      checksum_algo: :sha256,
      manifest: manifest,
      attestations: [],
      resolved_deps: []
    }
  end

  defp extract_authors(body) do
    publisher = body["publisher"] || body["owner"]
    if publisher && publisher != "", do: [publisher], else: ["pulumi"]
  end

  defp extract_dependencies(body) do
    (body["dependencies"] || %{})
    |> Enum.reduce(%{}, fn
      {k, v}, acc when is_binary(v) -> Map.put(acc, k, v)
      {k, _}, acc -> Map.put(acc, k, "*")
    end)
  end

  defp truncate_description(nil), do: nil
  defp truncate_description(text) do
    if String.length(text) > 200 do
      String.slice(text, 0, 197) <> "..."
    else
      text
    end
  end
end
