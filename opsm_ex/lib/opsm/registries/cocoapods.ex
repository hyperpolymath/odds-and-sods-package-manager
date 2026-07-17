# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Registries.CocoaPods do
  @moduledoc """
  CocoaPods Trunk API client for iOS/macOS dependencies.
  https://trunk.cocoapods.org/
  Uses the CocoaPods Trunk REST API.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://trunk.cocoapods.org/api/v1"

  @doc """
  Fetch pod metadata from the CocoaPods Trunk API.
  """
  def fetch_package(name, version \\ "latest") do
    target_version =
      if version == "latest" do
        fetch_latest_version(name)
      else
        version
      end

    case target_version do
      nil ->
        {:error, :not_found}

      ver ->
        # Fetch pod info
        url = "#{@api_url}/pods/#{name}"

        case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
          {:ok, body} ->
            deps = fetch_podspec_deps(name, ver)
            {:ok, parse_pod(name, body, ver, deps)}

          {:error, :not_found} ->
            {:error, :not_found}

          {:error, %{status: 404}} ->
            {:error, :not_found}

          {:error, %{status: status}} ->
            {:error, "CocoaPods Trunk returned status #{status}"}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp fetch_latest_version(name) do
    url = "#{@api_url}/pods/#{name}/specs"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, specs} when is_list(specs) ->
        # Specs are typically returned in reverse chronological order
        case specs do
          [%{"version" => version} | _] -> version
          [%{"name" => version} | _] -> version
          _ -> nil
        end

      {:ok, %{"versions" => versions}} when is_list(versions) ->
        List.first(versions)

      _ ->
        # Fallback: get version list
        case versions_internal(name) do
          {:ok, [latest | _]} -> latest
          _ -> nil
        end
    end
  end

  defp fetch_podspec_deps(name, version) do
    # Try to get the specific version's podspec
    url = "#{@api_url}/pods/#{name}/specs/#{version}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, spec} when is_map(spec) ->
        parse_podspec_dependencies(spec)

      _ ->
        # Fallback: try to get from main pod endpoint
        case VerifiedHttp.get_json("#{@api_url}/pods/#{name}", receive_timeout: 10_000) do
          {:ok, pod_info} when is_map(pod_info) ->
            parse_podspec_dependencies(pod_info)

          _ ->
            %{}
        end
    end
  end

  defp parse_podspec_dependencies(spec) do
    # Parse dependencies from podspec JSON
    # Format can be:
    # "dependencies": {"AFNetworking": ["~> 3.0"], "Firebase": []}
    # or "dependencies": {"AFNetworking": "~> 3.0"}
    case spec do
      %{"dependencies" => deps} when is_map(deps) ->
        Enum.reduce(deps, %{}, fn {name, constraint}, acc ->
          version_str =
            case constraint do
              [ver | _] when is_binary(ver) -> ver
              ver when is_binary(ver) -> ver
              [] -> ">= 0.0.0"
              _ -> ">= 0.0.0"
            end

          Map.put(acc, name, version_str)
        end)

      _ ->
        %{}
    end
  end

  @doc """
  Search for CocoaPods.
  Uses the CocoaPods Trunk search API.
  """
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    url = "#{@api_url}/pods/search?query=#{URI.encode_www_form(query)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, results} when is_list(results) ->
        pods =
          results
          |> Enum.take(limit)
          |> Enum.map(fn pod ->
            %{
              name: pod["name"] || pod["pod"],
              version: pod["version"] || pod["latest_version"],
              description: pod["summary"] || pod["description"],
              downloads: pod["stats"]["download_total"] || 0
            }
          end)

        {:ok, pods}

      {:ok, %{"pods" => pods}} when is_list(pods) ->
        results =
          pods
          |> Enum.take(limit)
          |> Enum.map(fn pod ->
            %{
              name: pod["name"] || pod["pod"],
              version: pod["version"] || pod["latest_version"],
              description: pod["summary"] || pod["description"],
              downloads: pod["stats"]["download_total"] || 0
            }
          end)

        {:ok, results}

      _ ->
        {:ok, []}
    end
  end

  @doc """
  Check if a CocoaPod exists.
  """
  def exists?(name) do
    url = "#{@api_url}/pods/#{name}"

    case VerifiedHttp.get(url, receive_timeout: 5_000) do
      {:ok, _} -> true
      _ -> false
    end
  end

  @doc """
  Get all versions of a CocoaPod.
  """
  def versions(name) do
    versions_internal(name)
  end

  defp versions_internal(name) do
    url = "#{@api_url}/pods/#{name}/specs"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, specs} when is_list(specs) ->
        versions =
          specs
          |> Enum.map(fn spec ->
            spec["version"] || spec["name"]
          end)
          |> Enum.filter(&(&1 != nil))
          |> Enum.reverse()

        if versions == [] do
          # Fallback: try to get from main pod endpoint
          fetch_latest_as_list(name)
        else
          {:ok, versions}
        end

      {:ok, %{"versions" => versions}} when is_list(versions) ->
        {:ok, Enum.reverse(versions)}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}

      _ ->
        fetch_latest_as_list(name)
    end
  end

  defp fetch_latest_as_list(name) do
    case VerifiedHttp.get_json("#{@api_url}/pods/#{name}", receive_timeout: 10_000) do
      {:ok, %{"version" => version}} -> {:ok, [version]}
      {:ok, %{"versions" => [latest | _]}} -> {:ok, [latest]}
      _ -> {:ok, []}
    end
  end

  @doc """
  Get source URL for a specific version.

  CocoaPods does not host centralized tarballs. Instead, each pod's
  `podspec.json` declares a `source` field pointing to the upstream
  repository (usually a git URL with a tag). This function fetches
  the podspec for the given version and extracts the source URL,
  preferring HTTP archives over git tag archives.

  Returns `{:ok, url}` where `url` may be:
  - An HTTP archive URL (if the podspec declares `source.http`)
  - A git tag archive URL (constructed from `source.git` + `source.tag`)
  - A fallback URL to the podspec JSON on the CocoaPods Specs repo
  """
  def tarball_url(name, version) do
    url = "#{@api_url}/pods/#{name}/specs/#{version}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"source" => %{"http" => http_url}}} ->
        {:ok, http_url}

      {:ok, %{"source" => %{"git" => git_url, "tag" => tag}}} ->
        {:ok, "#{git_url}/archive/refs/tags/#{tag}.tar.gz"}

      {:ok, %{"source" => %{"git" => git_url}}} ->
        {:ok, "#{git_url}/archive/refs/tags/#{version}.tar.gz"}

      _ ->
        # Generic fallback (may not work for all pods)
        {:ok,
         "https://github.com/CocoaPods/Specs/raw/master/Specs/#{name}/#{version}/#{name}.podspec.json"}
    end
  end

  # Parsers

  defp parse_pod(name, info, version, deps) do
    homepage = info["homepage"] || info["url"]

    repo =
      case info["source"] do
        %{"git" => git_url} -> git_url
        _ -> nil
      end

    %ResolvedPackage{
      package: name,
      version: version,
      forth: :cocoapods,
      registry_url: "https://cocoapods.org/pods/#{name}",
      tarball_url:
        case tarball_url(name, version) do
          {:ok, url} -> url
          _ -> nil
        end,
      checksum: nil,
      checksum_algo: nil,
      manifest: %ManifestFormat{
        name: name,
        version: version,
        description: info["summary"] || info["description"],
        license: extract_license(info["license"]),
        homepage: homepage,
        repository: repo,
        authors: extract_authors(info["authors"]),
        keywords: info["tags"] || [],
        dependencies: deps,
        dev_dependencies: %{},
        source_forth: :cocoapods,
        raw_manifest: info
      },
      attestations: [],
      resolved_deps: []
    }
  end

  defp extract_license(nil), do: nil
  defp extract_license(license) when is_binary(license), do: license
  defp extract_license(%{"type" => type}), do: type
  defp extract_license(_), do: nil

  defp extract_authors(nil), do: []
  defp extract_authors(authors) when is_binary(authors), do: [authors]

  defp extract_authors(authors) when is_map(authors) do
    Enum.map(authors, fn {name, email} -> "#{name} <#{email}>" end)
  end

  defp extract_authors(authors) when is_list(authors), do: authors
  defp extract_authors(_), do: []
end
