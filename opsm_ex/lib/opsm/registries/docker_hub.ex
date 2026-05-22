# SPDX-License-Identifier: MPL-2.0
defmodule Opsm.Registries.DockerHub do
  @moduledoc """
  Docker Hub registry adapter.
  https://hub.docker.com/v2/
  Queries the Docker Hub API for image metadata, tags, and search.
  Supports both official library images and user/org repositories.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://hub.docker.com/v2"

  @doc """
  Fetch image metadata from Docker Hub.
  Name can be "library/nginx" or just "nginx" for official images,
  or "namespace/repo" for user images.
  """
  def fetch_package(name, version \\ "latest") do
    {namespace, repo} = parse_image_name(name)
    tag = if version == "latest", do: "latest", else: version

    url = "#{@api_url}/repositories/#{namespace}/#{repo}/tags/#{tag}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, tag_data} ->
        # Also fetch the repository metadata for description, etc.
        case fetch_repo_metadata(namespace, repo) do
          {:ok, repo_data} ->
            {:ok, parse_image(namespace, repo, tag_data, repo_data, tag)}

          {:error, _} ->
            {:ok, parse_image(namespace, repo, tag_data, %{}, tag)}
        end

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, %{status: status}} ->
        {:error, "Docker Hub returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_repo_metadata(namespace, repo) do
    url = "#{@api_url}/repositories/#{namespace}/#{repo}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} -> {:ok, body}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Search for images on Docker Hub.
  Returns a list of matching repositories with name, version, and description.
  """
  def search(query, opts \\ []) do
    page_size = Keyword.get(opts, :limit, 20)
    url = "#{@api_url}/search/repositories/?query=#{URI.encode_www_form(query)}&page_size=#{page_size}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"results" => results}} when is_list(results) ->
        parsed = Enum.map(results, fn item ->
          %{
            name: item["repo_name"] || item["name"],
            version: "latest",
            description: item["short_description"] || item["description"]
          }
        end)
        {:ok, parsed}

      {:ok, _} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a Docker image repository exists on Docker Hub.
  """
  def exists?(name) do
    {namespace, repo} = parse_image_name(name)
    url = "#{@api_url}/repositories/#{namespace}/#{repo}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Get all available tags for a Docker image.
  Returns a list of tag strings, newest first.
  """
  def versions(name) do
    {namespace, repo} = parse_image_name(name)
    url = "#{@api_url}/repositories/#{namespace}/#{repo}/tags?page_size=100&ordering=-last_updated"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"results" => tags}} when is_list(tags) ->
        version_list = Enum.map(tags, fn tag -> tag["name"] end)
        {:ok, version_list}

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

  defp parse_image_name(name) do
    case String.split(name, "/", parts: 2) do
      [repo] -> {"library", repo}
      [namespace, repo] -> {namespace, repo}
    end
  end

  defp parse_image(namespace, repo, tag_data, repo_data, tag) do
    full_name = if namespace == "library", do: repo, else: "#{namespace}/#{repo}"

    digest = tag_data["digest"] ||
      get_in(tag_data, ["images", Access.at(0), "digest"])

    manifest = %ManifestFormat{
      name: full_name,
      version: tag,
      description: repo_data["description"] || repo_data["short_description"],
      license: nil,
      homepage: "https://hub.docker.com/r/#{namespace}/#{repo}",
      repository: repo_data["source"] || repo_data["source_url"],
      authors: extract_authors(repo_data),
      keywords: [],
      dependencies: %{},
      dev_dependencies: %{},
      source_forth: :docker,
      raw_manifest: tag_data
    }

    %ResolvedPackage{
      package: full_name,
      version: tag,
      forth: :docker,
      registry_url: "https://hub.docker.com/r/#{namespace}/#{repo}",
      tarball_url: nil,
      checksum: digest,
      checksum_algo: :sha256,
      manifest: manifest,
      attestations: [],
      resolved_deps: []
    }
  end

  defp extract_authors(repo_data) do
    user = repo_data["user"] || repo_data["namespace"]
    if user && user != "", do: [user], else: []
  end
end
