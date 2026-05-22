# SPDX-License-Identifier: MPL-2.0
defmodule Opsm.Registries.AnsibleGalaxy do
  @moduledoc """
  Ansible Galaxy registry adapter for Ansible collections and roles.
  https://galaxy.ansible.com/
  Uses the Galaxy v3 REST API for collection and role metadata.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://galaxy.ansible.com/api/v3"
  @api_v2_url "https://galaxy.ansible.com/api/v2"
  @web_url "https://galaxy.ansible.com"

  @doc """
  Fetch Ansible collection metadata from Galaxy.
  Collection names use the "namespace.name" format (e.g., "ansible.builtin").
  """
  def fetch_package(name, version \\ "latest") do
    {namespace, collection} = split_collection_name(name)
    url = "#{@api_url}/plugin/ansible/content/published/collections/index/#{namespace}/#{collection}/"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} when is_map(body) ->
        target_version = if version == "latest" do
          body["highest_version"] && body["highest_version"]["version"]
        else
          version
        end

        # Fetch version-specific metadata for dependencies
        {deps, version_meta} = fetch_version_metadata(namespace, collection, target_version)
        {:ok, parse_package(name, body, version_meta, target_version, deps)}

      {:error, :not_found} ->
        # Fallback: try v2 API for roles
        fetch_role(name, version)

      {:error, %{status: 404}} ->
        fetch_role(name, version)

      {:error, %{status: status}} ->
        {:error, "Ansible Galaxy returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_role(name, version) do
    url = "#{@api_v2_url}/roles/?search=#{URI.encode_www_form(name)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"results" => [role | _]}} ->
        ver = if version == "latest" do
          get_in(role, ["summary_fields", "versions", Access.at(0), "name"]) ||
            role["version"]
        else
          version
        end
        {:ok, parse_role(name, role, ver)}

      {:ok, _} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_version_metadata(namespace, collection, version) do
    url = "#{@api_url}/plugin/ansible/content/published/collections/index/#{namespace}/#{collection}/versions/#{version}/"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} when is_map(body) ->
        deps = extract_collection_deps(body)
        {deps, body}

      _ ->
        {%{}, %{}}
    end
  end

  @doc """
  Search for Ansible collections and roles on Galaxy.
  """
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    # Search collections via v3 API
    url = "#{@api_url}/plugin/ansible/search/collection-versions/?q=#{URI.encode_www_form(query)}&limit=#{limit}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"data" => results}} when is_list(results) ->
        packages = results
        |> Enum.take(limit)
        |> Enum.map(fn r ->
          %{
            name: "#{r["namespace"]}.#{r["name"]}",
            version: r["version"],
            description: r["description"] || "",
            downloads: r["download_count"] || 0
          }
        end)
        {:ok, packages}

      {:ok, %{"results" => results}} when is_list(results) ->
        packages = results
        |> Enum.take(limit)
        |> Enum.map(fn r ->
          %{
            name: r["namespace"] && r["name"] && "#{r["namespace"]}.#{r["name"]}" || r["name"],
            version: r["version"] || get_in(r, ["latest_version", "version"]),
            description: r["description"] || "",
            downloads: r["download_count"] || 0
          }
        end)
        {:ok, packages}

      {:ok, _} ->
        {:ok, []}

      {:error, %{status: status}} ->
        {:error, "Ansible Galaxy search returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if an Ansible collection or role exists on Galaxy.
  """
  def exists?(name) do
    {namespace, collection} = split_collection_name(name)
    url = "#{@api_url}/plugin/ansible/content/published/collections/index/#{namespace}/#{collection}/"

    case VerifiedHttp.get(url, receive_timeout: 5_000) do
      {:ok, _} -> true
      _ ->
        # Fallback: check v2 roles API
        role_url = "#{@api_v2_url}/roles/?search=#{URI.encode_www_form(name)}"
        case VerifiedHttp.get_json(role_url, receive_timeout: 5_000) do
          {:ok, %{"count" => count}} when count > 0 -> true
          _ -> false
        end
    end
  end

  @doc """
  Get all versions of an Ansible collection.
  """
  def versions(name) do
    {namespace, collection} = split_collection_name(name)
    url = "#{@api_url}/plugin/ansible/content/published/collections/index/#{namespace}/#{collection}/versions/"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"data" => versions}} when is_list(versions) ->
        ver_list = Enum.map(versions, fn v -> v["version"] end)
        |> Enum.reject(&is_nil/1)
        {:ok, ver_list}

      {:ok, %{"results" => versions}} when is_list(versions) ->
        ver_list = Enum.map(versions, fn v -> v["version"] end)
        |> Enum.reject(&is_nil/1)
        {:ok, ver_list}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get download URL for an Ansible collection tarball.
  """
  def tarball_url(name, version) do
    {namespace, collection} = split_collection_name(name)
    url = "#{@api_url}/plugin/ansible/content/published/collections/index/#{namespace}/#{collection}/versions/#{version}/"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"download_url" => dl_url}} when is_binary(dl_url) ->
        {:ok, dl_url}

      {:ok, %{"href" => href}} when is_binary(href) ->
        {:ok, href}

      _ ->
        {:error, :not_found}
    end
  end

  # Helpers

  defp split_collection_name(name) do
    case String.split(name, ".", parts: 2) do
      [namespace, collection] -> {namespace, collection}
      [name_only] -> {name_only, name_only}
    end
  end

  # Parsers

  defp extract_collection_deps(version_data) do
    case version_data do
      %{"metadata" => %{"dependencies" => deps}} when is_map(deps) ->
        Enum.into(deps, %{})

      %{"dependencies" => deps} when is_map(deps) ->
        Enum.into(deps, %{})

      _ ->
        %{}
    end
  end

  defp parse_package(name, body, version_meta, version, deps) do
    description = body["description"] || get_in(version_meta, ["metadata", "description"]) || ""
    license = get_in(version_meta, ["metadata", "license"]) || body["license"]
    homepage = get_in(version_meta, ["metadata", "homepage"]) || body["homepage"]
    repository = get_in(version_meta, ["metadata", "repository"]) || body["repository"]
    authors = extract_authors(body, version_meta)
    download_url = version_meta["download_url"]

    %ResolvedPackage{
      package: name,
      version: version,
      forth: :ansible,
      registry_url: "#{@web_url}/ui/repo/published/#{String.replace(name, ".", "/")}",
      tarball_url: download_url,
      checksum: version_meta["artifact"] && version_meta["artifact"]["sha256"],
      checksum_algo: if(version_meta["artifact"], do: :sha256, else: nil),
      manifest: %ManifestFormat{
        name: name,
        version: version,
        description: description,
        license: license,
        homepage: homepage,
        repository: repository,
        authors: authors,
        keywords: get_in(version_meta, ["metadata", "tags"]) || body["tags"] || [],
        dependencies: deps,
        dev_dependencies: %{},
        source_forth: :ansible,
        raw_manifest: Map.merge(body, version_meta)
      },
      attestations: [],
      resolved_deps: []
    }
  end

  defp parse_role(name, role, version) do
    %ResolvedPackage{
      package: name,
      version: version,
      forth: :ansible,
      registry_url: "#{@web_url}/ui/standalone/roles/#{role["namespace"]}/#{role["name"]}",
      tarball_url: nil,
      checksum: nil,
      checksum_algo: nil,
      manifest: %ManifestFormat{
        name: name,
        version: version,
        description: role["description"] || "",
        license: role["license"],
        homepage: role["github_repo"] && "https://github.com/#{role["github_repo"]}",
        repository: role["github_repo"] && "https://github.com/#{role["github_repo"]}.git",
        authors: [role["github_user"] || ""],
        keywords: role["tags"] || [],
        dependencies: %{},
        dev_dependencies: %{},
        source_forth: :ansible,
        raw_manifest: role
      },
      attestations: [],
      resolved_deps: []
    }
  end

  defp extract_authors(body, version_meta) do
    cond do
      get_in(version_meta, ["metadata", "authors"]) ->
        version_meta["metadata"]["authors"]

      body["namespace"] ->
        [body["namespace"]["name"] || body["namespace"]]

      true ->
        []
    end
  end
end
