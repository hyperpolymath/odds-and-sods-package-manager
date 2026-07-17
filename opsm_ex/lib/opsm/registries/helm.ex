# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Registries.Helm do
  @moduledoc """
  Helm chart registry adapter via Artifact Hub.
  https://artifacthub.io/
  Uses the Artifact Hub REST API v1 for Kubernetes Helm chart metadata.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://artifacthub.io/api/v1"
  @web_url "https://artifacthub.io"

  @doc """
  Fetch Helm chart metadata from Artifact Hub.
  Chart names may include the repository prefix (e.g., "bitnami/nginx").
  """
  def fetch_package(name, version \\ "latest") do
    {repo_name, chart_name} = split_chart_name(name)

    url =
      if version == "latest" do
        "#{@api_url}/packages/helm/#{repo_name}/#{URI.encode(chart_name)}"
      else
        "#{@api_url}/packages/helm/#{repo_name}/#{URI.encode(chart_name)}/#{version}"
      end

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} when is_map(body) ->
        target_version = body["version"] || version
        deps = extract_deps(body)
        {:ok, parse_package(name, body, target_version, deps)}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, %{status: status}} ->
        {:error, "Artifact Hub returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Search for Helm charts on Artifact Hub.
  """
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    offset = Keyword.get(opts, :offset, 0)

    url =
      "#{@api_url}/packages/search?" <>
        "ts_query_web=#{URI.encode_www_form(query)}" <>
        "&kind=0" <>
        "&limit=#{limit}" <>
        "&offset=#{offset}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"packages" => packages}} when is_list(packages) ->
        results =
          packages
          |> Enum.take(limit)
          |> Enum.map(&parse_search_result/1)

        {:ok, results}

      {:ok, packages} when is_list(packages) ->
        results =
          packages
          |> Enum.take(limit)
          |> Enum.map(&parse_search_result/1)

        {:ok, results}

      {:ok, _} ->
        {:ok, []}

      {:error, %{status: status}} ->
        {:error, "Artifact Hub search returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a Helm chart exists on Artifact Hub.
  """
  def exists?(name) do
    {repo_name, chart_name} = split_chart_name(name)
    url = "#{@api_url}/packages/helm/#{repo_name}/#{URI.encode(chart_name)}"

    case VerifiedHttp.get(url, receive_timeout: 5_000) do
      {:ok, _} -> true
      _ -> false
    end
  end

  @doc """
  Get all versions of a Helm chart.
  """
  def versions(name) do
    {repo_name, chart_name} = split_chart_name(name)
    url = "#{@api_url}/packages/helm/#{repo_name}/#{URI.encode(chart_name)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"available_versions" => versions}} when is_list(versions) ->
        ver_list =
          versions
          |> Enum.map(fn v ->
            case v do
              %{"version" => ver} -> ver
              ver when is_binary(ver) -> ver
              _ -> nil
            end
          end)
          |> Enum.reject(&is_nil/1)

        {:ok, ver_list}

      {:ok, %{"version" => ver}} ->
        {:ok, [ver]}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get chart download URL. Returns the content URL from Artifact Hub metadata.
  """
  def tarball_url(name, version) do
    {repo_name, chart_name} = split_chart_name(name)
    url = "#{@api_url}/packages/helm/#{repo_name}/#{URI.encode(chart_name)}/#{version}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"content_url" => content_url}} when is_binary(content_url) ->
        {:ok, content_url}

      {:ok, _} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Helpers

  # Helm charts on Artifact Hub use "repo/chart" naming; default repo to "artifact-hub"
  defp split_chart_name(name) do
    case String.split(name, "/", parts: 2) do
      [repo, chart] -> {repo, chart}
      [chart] -> {"artifact-hub", chart}
    end
  end

  # Parsers

  defp extract_deps(body) do
    case body do
      %{"dependencies" => deps} when is_list(deps) ->
        Enum.reduce(deps, %{}, fn dep, acc ->
          dep_name = dep["name"]
          constraint = dep["version"] || ">= 0.0.0"
          if dep_name, do: Map.put(acc, dep_name, constraint), else: acc
        end)

      %{"data" => %{"dependencies" => deps}} when is_list(deps) ->
        Enum.reduce(deps, %{}, fn dep, acc ->
          dep_name = dep["name"]
          constraint = dep["version"] || ">= 0.0.0"
          if dep_name, do: Map.put(acc, dep_name, constraint), else: acc
        end)

      _ ->
        %{}
    end
  end

  defp parse_search_result(pkg) do
    %{
      name: pkg["name"] || pkg["normalized_name"],
      version: pkg["version"],
      description: pkg["description"] || "",
      downloads: pkg["stars"] || 0
    }
  end

  defp parse_package(name, body, version, deps) do
    description = body["description"] || ""
    license = body["license"]
    homepage = body["home_url"] || body["homepage"]
    repository = extract_repository(body)
    maintainers = body["maintainers"] || []
    keywords = body["keywords"] || []
    content_url = body["content_url"]

    %ResolvedPackage{
      package: name,
      version: version,
      forth: :helm,
      registry_url: "#{@web_url}/packages/helm/#{name}/#{version}",
      tarball_url: content_url,
      checksum: body["digest"],
      checksum_algo: if(body["digest"], do: :sha256, else: nil),
      manifest: %ManifestFormat{
        name: name,
        version: version,
        description: description,
        license: license,
        homepage: homepage,
        repository: repository,
        authors: Enum.map(maintainers, fn m -> m["name"] || m["email"] || "" end),
        keywords: keywords,
        dependencies: deps,
        dev_dependencies: %{},
        source_forth: :helm,
        raw_manifest: body
      },
      attestations: extract_attestations(body),
      resolved_deps: []
    }
  end

  defp extract_repository(body) do
    case body do
      %{"repository" => %{"url" => url}} ->
        url

      %{"links" => links} when is_list(links) ->
        source = Enum.find(links, fn l -> l["name"] == "source" end)
        if source, do: source["url"], else: nil

      _ ->
        nil
    end
  end

  defp extract_attestations(body) do
    case body do
      %{"signed" => true} -> [%{type: :signed, uri: nil, digest: nil}]
      _ -> []
    end
  end
end
