# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule Opsm.Registries.TektonHub do
  @moduledoc """
  Tekton Hub registry adapter.
  https://hub.tekton.dev/resource
  Queries the Tekton Hub API for CI/CD pipeline tasks, pipelines, and
  other Tekton resources with version and catalog information.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://api.hub.tekton.dev/v1"

  @doc """
  Fetch resource metadata from Tekton Hub.
  Name can include catalog prefix: "tekton/git-clone" or just "git-clone".
  Defaults to "task" kind; pass opts for :pipeline or :stepaction.
  """
  def fetch_package(name, version \\ "latest") do
    {catalog, resource_name} = parse_resource_name(name)

    url = if version == "latest" do
      "#{@api_url}/resource/#{catalog}/#{resource_name}"
    else
      "#{@api_url}/resource/#{catalog}/#{resource_name}/#{version}"
    end

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"data" => data}} ->
        ver = resolve_version(data, version)
        {:ok, parse_tekton_resource(catalog, resource_name, data, ver)}

      {:ok, data} when is_map(data) and map_size(data) > 0 ->
        ver = resolve_version(data, version)
        {:ok, parse_tekton_resource(catalog, resource_name, data, ver)}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, %{status: status}} ->
        {:error, "Tekton Hub returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp resolve_version(data, "latest") do
    latest = data["latestVersion"] || get_in(data, ["latest", "version"])

    case latest do
      %{"version" => v} -> v
      v when is_binary(v) -> v
      _ ->
        versions = data["versions"] || []
        case versions do
          [%{"version" => v} | _] -> v
          _ -> "0.1"
        end
    end
  end

  defp resolve_version(_data, requested), do: requested

  @doc """
  Search for Tekton resources (tasks, pipelines, etc.) on Tekton Hub.
  Returns a list of matching resources with name, version, and description.
  """
  def search(query, _opts \\ []) do
    url = "#{@api_url}/query?name=#{URI.encode_www_form(query)}&limit=20"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"data" => resources}} when is_list(resources) ->
        results = Enum.map(resources, fn res ->
          latest_ver = get_in(res, ["latestVersion", "version"]) ||
            get_in(res, ["latest", "version"])

          %{
            name: "#{res["catalog"]["name"]}/#{res["name"]}",
            version: latest_ver,
            description: res["description"] || res["summary"]
          }
        end)
        {:ok, results}

      {:ok, resources} when is_list(resources) ->
        results = Enum.map(resources, fn res ->
          %{
            name: res["name"],
            version: get_in(res, ["latestVersion", "version"]),
            description: res["description"]
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
  Check if a Tekton resource exists on Tekton Hub.
  """
  def exists?(name) do
    {catalog, resource_name} = parse_resource_name(name)
    url = "#{@api_url}/resource/#{catalog}/#{resource_name}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Get all available versions of a Tekton resource.
  Returns version strings, newest first.
  """
  def versions(name) do
    {catalog, resource_name} = parse_resource_name(name)
    url = "#{@api_url}/resource/#{catalog}/#{resource_name}/versions"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"data" => %{"versions" => versions_list}}} when is_list(versions_list) ->
        ver_strs = Enum.map(versions_list, fn v -> v["version"] end)
        |> Enum.reject(&is_nil/1)
        {:ok, ver_strs}

      {:ok, %{"data" => versions_list}} when is_list(versions_list) ->
        ver_strs = Enum.map(versions_list, fn v -> v["version"] end)
        |> Enum.reject(&is_nil/1)
        {:ok, ver_strs}

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

  defp parse_resource_name(name) do
    case String.split(name, "/", parts: 2) do
      [catalog, resource] -> {catalog, resource}
      [resource] -> {"tekton", resource}
    end
  end

  defp parse_tekton_resource(catalog, resource_name, data, version) do
    full_name = "#{catalog}/#{resource_name}"
    kind = data["kind"] || "task"
    tags = extract_tags(data)

    manifest = %ManifestFormat{
      name: full_name,
      version: version,
      description: data["description"] || data["summary"],
      license: nil,
      homepage: "https://hub.tekton.dev/tekton/#{kind}/#{resource_name}",
      repository: data["github_url"] || data["repository"],
      authors: extract_authors(data),
      keywords: [kind | tags],
      dependencies: %{},
      dev_dependencies: %{},
      source_forth: :tekton,
      raw_manifest: data
    }

    %ResolvedPackage{
      package: full_name,
      version: version,
      forth: :tekton,
      registry_url: "https://hub.tekton.dev/tekton/#{kind}/#{resource_name}",
      tarball_url: data["yaml_url"] || data["rawURL"],
      checksum: nil,
      checksum_algo: :sha256,
      manifest: manifest,
      attestations: [],
      resolved_deps: []
    }
  end

  defp extract_tags(data) do
    (data["tags"] || [])
    |> Enum.map(fn
      t when is_binary(t) -> t
      %{"name" => name} -> name
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_authors(data) do
    case data["catalog"] do
      %{"name" => name} -> [name]
      _ -> []
    end
  end
end
