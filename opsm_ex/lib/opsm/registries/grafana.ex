# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Registries.Grafana do
  @moduledoc """
  Grafana Plugins registry adapter.
  https://grafana.com/api/plugins
  Queries the Grafana plugin catalog API for datasource, panel, and app
  plugin metadata with version history and dependency information.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://grafana.com/api/plugins"

  @doc """
  Fetch plugin metadata from the Grafana plugin catalog.
  Name is the plugin slug/id (e.g., "grafana-clock-panel").
  """
  def fetch_package(name, version \\ "latest") do
    url = "#{@api_url}/#{URI.encode(name)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        ver = resolve_version(body, version)
        {:ok, parse_grafana_plugin(name, body, ver)}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, %{status: status}} ->
        {:error, "Grafana registry returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp resolve_version(body, "latest") do
    case body["version"] do
      v when is_binary(v) -> v
      _ ->
        versions_list = body["versions"] || []
        case versions_list do
          [%{"version" => v} | _] -> v
          _ -> "0.0.0"
        end
    end
  end

  defp resolve_version(_body, requested), do: requested

  @doc """
  Search for plugins in the Grafana catalog.
  Returns matching plugins with name, version, and description.
  """
  def search(query, opts \\ []) do
    page_size = Keyword.get(opts, :limit, 20)
    type_filter = Keyword.get(opts, :type, nil)

    url = "#{@api_url}?q=#{URI.encode_www_form(query)}&pageSize=#{page_size}" <>
      if(type_filter, do: "&type=#{type_filter}", else: "")

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"items" => plugins}} when is_list(plugins) ->
        results = Enum.map(plugins, fn plugin ->
          %{
            name: plugin["slug"] || plugin["id"],
            version: plugin["version"],
            description: plugin["description"]
          }
        end)
        {:ok, results}

      {:ok, plugins} when is_list(plugins) ->
        results = plugins
        |> Enum.take(page_size)
        |> Enum.map(fn plugin ->
          %{
            name: plugin["slug"] || plugin["id"],
            version: plugin["version"],
            description: plugin["description"]
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
  Check if a plugin exists in the Grafana catalog.
  """
  def exists?(name) do
    url = "#{@api_url}/#{URI.encode(name)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Get all available versions of a Grafana plugin.
  Returns version strings, newest first.
  """
  def versions(name) do
    url = "#{@api_url}/#{URI.encode(name)}/versions"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"items" => versions_list}} when is_list(versions_list) ->
        ver_strs = versions_list
        |> Enum.map(fn v -> v["version"] end)
        |> Enum.reject(&is_nil/1)
        {:ok, ver_strs}

      {:ok, versions_list} when is_list(versions_list) ->
        ver_strs = versions_list
        |> Enum.map(fn v -> v["version"] end)
        |> Enum.reject(&is_nil/1)
        {:ok, ver_strs}

      {:ok, _} ->
        # Fallback: fetch the main plugin info and extract versions from there
        fetch_versions_from_plugin(name)

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_versions_from_plugin(name) do
    url = "#{@api_url}/#{URI.encode(name)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"versions" => versions_list}} when is_list(versions_list) ->
        ver_strs = versions_list
        |> Enum.map(fn v -> v["version"] end)
        |> Enum.reject(&is_nil/1)
        {:ok, ver_strs}

      {:ok, body} ->
        case body["version"] do
          v when is_binary(v) -> {:ok, [v]}
          _ -> {:ok, []}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  defp parse_grafana_plugin(name, body, version) do
    plugin_type = body["type"] || body["typeCode"] || "panel"
    deps = extract_dependencies(body)

    manifest = %ManifestFormat{
      name: name,
      version: version,
      description: body["description"],
      license: body["license"],
      homepage: body["url"] || "https://grafana.com/grafana/plugins/#{name}",
      repository: body["links"]["source"] || body["sourceUrl"],
      authors: extract_authors(body),
      keywords: [plugin_type | (body["keywords"] || [])],
      dependencies: deps,
      dev_dependencies: %{},
      source_forth: :grafana,
      raw_manifest: body
    }

    download_url = body["downloadUrl"] ||
      "https://grafana.com/api/plugins/#{name}/versions/#{version}/download"

    %ResolvedPackage{
      package: name,
      version: version,
      forth: :grafana,
      registry_url: "https://grafana.com/grafana/plugins/#{name}",
      tarball_url: download_url,
      checksum: body["sha256"],
      checksum_algo: :sha256,
      manifest: manifest,
      attestations: [],
      resolved_deps: []
    }
  end

  defp extract_dependencies(body) do
    grafana_dep = case body["grafanaDependency"] || body["grafanaVersion"] do
      nil -> %{}
      constraint -> %{"grafana" => constraint}
    end

    plugin_deps = (body["dependencies"] || body["pluginDependencies"] || [])
    |> Enum.reduce(grafana_dep, fn
      %{"id" => id, "version" => ver}, acc -> Map.put(acc, id, ver)
      %{"id" => id}, acc -> Map.put(acc, id, "*")
      _, acc -> acc
    end)

    plugin_deps
  end

  defp extract_authors(body) do
    org = body["orgName"] || body["orgSlug"]
    if org && org != "", do: [org], else: []
  end
end
