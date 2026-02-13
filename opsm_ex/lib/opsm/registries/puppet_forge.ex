# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule Opsm.Registries.PuppetForge do
  @moduledoc """
  Puppet Forge registry adapter for Puppet modules.
  https://forge.puppet.com/
  Uses the Puppet Forge v3 REST API.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://forgeapi.puppet.com/v3"
  @web_url "https://forge.puppet.com"

  @doc """
  Fetch Puppet module metadata from the Forge.
  Module names use "owner-module" format (e.g., "puppetlabs-apache").
  """
  def fetch_package(name, version \\ "latest") do
    slug = normalize_slug(name)
    url = "#{@api_url}/modules/#{slug}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} when is_map(body) ->
        target_version = if version == "latest" do
          get_in(body, ["current_release", "version"])
        else
          version
        end

        # Use current_release or fetch specific version
        release_data = if version == "latest" do
          body["current_release"] || %{}
        else
          fetch_release(slug, version)
        end

        deps = extract_deps(release_data)
        {:ok, parse_package(name, body, release_data, target_version, deps)}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, %{status: status}} ->
        {:error, "Puppet Forge returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_release(slug, version) do
    url = "#{@api_url}/releases/#{slug}-#{version}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} when is_map(body) -> body
      _ -> %{}
    end
  end

  @doc """
  Search for Puppet modules on the Forge.
  """
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    url = "#{@api_url}/modules?query=#{URI.encode_www_form(query)}&limit=#{limit}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"results" => results}} when is_list(results) ->
        packages = results
        |> Enum.take(limit)
        |> Enum.map(fn mod ->
          %{
            name: mod["slug"] || mod["name"],
            version: get_in(mod, ["current_release", "version"]),
            description: get_in(mod, ["current_release", "metadata", "summary"]) || "",
            downloads: mod["downloads"] || 0
          }
        end)
        {:ok, packages}

      {:ok, _} ->
        {:ok, []}

      {:error, %{status: status}} ->
        {:error, "Puppet Forge search returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a Puppet module exists on the Forge.
  """
  def exists?(name) do
    slug = normalize_slug(name)
    url = "#{@api_url}/modules/#{slug}"

    case VerifiedHttp.get(url, receive_timeout: 5_000) do
      {:ok, _} -> true
      _ -> false
    end
  end

  @doc """
  Get all versions of a Puppet module.
  """
  def versions(name) do
    slug = normalize_slug(name)
    url = "#{@api_url}/modules/#{slug}?include=releases"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"releases" => releases}} when is_list(releases) ->
        ver_list = releases
        |> Enum.map(fn r -> r["version"] end)
        |> Enum.reject(&is_nil/1)
        {:ok, ver_list}

      {:ok, body} when is_map(body) ->
        # Fallback: fetch releases separately
        fetch_all_versions(slug)

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_all_versions(slug) do
    url = "#{@api_url}/releases?module=#{slug}&sort_by=version&limit=100"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"results" => releases}} when is_list(releases) ->
        ver_list = releases
        |> Enum.map(fn r -> r["version"] end)
        |> Enum.reject(&is_nil/1)
        {:ok, ver_list}

      _ ->
        {:ok, []}
    end
  end

  @doc """
  Get tarball URL for a Puppet module release.
  """
  def tarball_url(name, version) do
    slug = normalize_slug(name)
    url = "#{@api_url}/releases/#{slug}-#{version}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"file_uri" => file_uri}} when is_binary(file_uri) ->
        # file_uri is relative; prepend the Forge base URL
        {:ok, "https://forgeapi.puppet.com#{file_uri}"}

      {:ok, _} ->
        {:ok, "https://forgeapi.puppet.com/v3/files/#{slug}-#{version}.tar.gz"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Helpers

  # Normalize module name: "puppetlabs/apache" -> "puppetlabs-apache"
  defp normalize_slug(name) do
    name |> String.replace("/", "-")
  end

  # Parsers

  defp extract_deps(release_data) do
    case release_data do
      %{"metadata" => %{"dependencies" => deps}} when is_list(deps) ->
        Enum.reduce(deps, %{}, fn dep, acc ->
          dep_name = dep["name"]
          constraint = dep["version_requirement"] || dep["version"] || ">= 0.0.0"
          if dep_name, do: Map.put(acc, dep_name, constraint), else: acc
        end)

      _ ->
        %{}
    end
  end

  defp parse_package(name, body, release_data, version, deps) do
    metadata = release_data["metadata"] || %{}
    description = metadata["summary"] || metadata["description"] || ""
    license = metadata["license"]
    homepage = metadata["project_page"] || body["homepage_url"]
    repository = metadata["source"] || body["source_url"]
    authors = extract_authors(metadata)
    keywords = metadata["tags"] || body["endorsement"] && [body["endorsement"]] || []

    file_uri = release_data["file_uri"]
    download_url = if file_uri, do: "https://forgeapi.puppet.com#{file_uri}", else: nil
    checksum = release_data["file_md5"] || release_data["file_sha256"]
    checksum_algo = cond do
      release_data["file_sha256"] -> :sha256
      release_data["file_md5"] -> :md5
      true -> nil
    end

    %ResolvedPackage{
      package: name,
      version: version,
      forth: :puppet,
      registry_url: "#{@web_url}/modules/#{normalize_slug(name)}",
      tarball_url: download_url,
      checksum: checksum,
      checksum_algo: checksum_algo,
      manifest: %ManifestFormat{
        name: name,
        version: version,
        description: description,
        license: license,
        homepage: homepage,
        repository: repository,
        authors: authors,
        keywords: keywords,
        dependencies: deps,
        dev_dependencies: %{},
        source_forth: :puppet,
        raw_manifest: Map.merge(body, release_data)
      },
      attestations: [],
      resolved_deps: []
    }
  end

  defp extract_authors(metadata) do
    case metadata do
      %{"author" => author} when is_binary(author) -> [author]
      %{"authors" => authors} when is_list(authors) -> authors
      _ -> []
    end
  end
end
