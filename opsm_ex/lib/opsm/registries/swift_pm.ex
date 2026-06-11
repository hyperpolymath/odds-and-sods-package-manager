# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Registries.SwiftPM do
  @moduledoc """
  Swift Package Manager registry adapter.
  https://swiftpackageindex.com
  Uses the Swift Package Index API.
  """

  alias Opsm.Types.{ResolvedPackage, ManifestFormat}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://swiftpackageindex.com/api"
  @web_url "https://swiftpackageindex.com"

  def fetch_package(name, version \\ "latest") do
    # Swift packages are identified by owner/repo
    {owner, repo} = parse_package_id(name)
    url = "#{@api_url}/packages/#{URI.encode(owner)}/#{URI.encode(repo)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        target_version = if version == "latest" do
          get_in(body, ["releases", "stable", "reference", "version"]) ||
          get_in(body, ["releases", "latest", "reference", "version"])
        else
          version
        end

        {:ok, %ResolvedPackage{
          package: name,
          version: target_version || version,
          forth: :swift,
          registry_url: "#{@web_url}/#{owner}/#{repo}",
          tarball_url: body["url"],
          checksum: nil,
          checksum_algo: nil,
          manifest: %ManifestFormat{
            name: repo,
            version: target_version || version,
            description: body["summary"],
            license: nil,
            homepage: "#{@web_url}/#{owner}/#{repo}",
            repository: body["url"],
            authors: [owner],
            keywords: body["keywords"] || [],
            dependencies: %{},
            dev_dependencies: %{},
            source_forth: :swift,
            raw_manifest: body
          },
          attestations: [],
          resolved_deps: []
        }}

      {:error, :not_found} -> {:error, :not_found}
      {:error, %{status: 404}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    url = "#{@api_url}/search?query=#{URI.encode(query)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"results" => results}} when is_list(results) ->
        packages = results
          |> Enum.take(limit)
          |> Enum.map(fn r ->
            %{
              name: r["package"] || r["repositoryName"],
              version: nil,
              description: r["summary"],
              downloads: 0
            }
          end)
        {:ok, packages}
      _ -> {:ok, []}
    end
  end

  def exists?(name) do
    {owner, repo} = parse_package_id(name)
    url = "#{@api_url}/packages/#{URI.encode(owner)}/#{URI.encode(repo)}"
    case VerifiedHttp.get(url, receive_timeout: 5_000) do
      {:ok, _} -> true
      _ -> false
    end
  end

  def versions(name) do
    {owner, repo} = parse_package_id(name)
    url = "#{@api_url}/packages/#{URI.encode(owner)}/#{URI.encode(repo)}"
    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"versions" => versions}} when is_list(versions) ->
        vers = Enum.map(versions, fn v -> v["reference"]["version"] || v["version"] end)
          |> Enum.reject(&is_nil/1)
        {:ok, vers}
      _ -> {:ok, []}
    end
  end

  def tarball_url(name, _version) do
    {owner, repo} = parse_package_id(name)
    {:ok, "https://github.com/#{owner}/#{repo}"}
  end

  defp parse_package_id(name) do
    case String.split(name, "/", parts: 2) do
      [owner, repo] -> {owner, repo}
      [repo] -> {"apple", repo}
    end
  end
end
