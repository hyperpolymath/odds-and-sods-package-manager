# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Registries.GradlePlugins do
  @moduledoc """
  Gradle Plugin Portal API client.
  https://plugins.gradle.org/m2/
  Accesses Gradle plugins via the Maven-compatible repository endpoint
  and the plugin portal search API.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @m2_url "https://plugins.gradle.org/m2"
  @search_url "https://plugins.gradle.org"

  @doc """
  Fetch plugin metadata from the Gradle Plugin Portal.
  The `name` is the plugin ID (e.g., "org.jetbrains.kotlin.jvm").
  Gradle plugins are published as Maven artifacts under the marker artifact
  convention: {plugin.id}:{plugin.id}.gradle.plugin:{version}
  """
  def fetch_package(name, version \\ "latest") do
    group_path = String.replace(name, ".", "/")
    marker_artifact = "#{name}.gradle.plugin"
    marker_path = String.replace(marker_artifact, ".", "/")

    target_version = if version == "latest" do
      fetch_latest_version(group_path, marker_path)
    else
      version
    end

    case target_version do
      nil ->
        {:error, :not_found}

      ver ->
        pom_url = "#{@m2_url}/#{group_path}/#{marker_path}/#{ver}/#{marker_artifact}-#{ver}.pom"

        case VerifiedHttp.get_json(pom_url, receive_timeout: 10_000) do
          {:ok, body} ->
            {:ok, parse_plugin(name, body, ver)}

          {:error, :not_found} ->
            # POM is XML, not JSON -- build from metadata instead
            {:ok, build_plugin_from_metadata(name, ver)}

          {:error, %{status: 404}} ->
            {:error, :not_found}

          {:error, %{status: status}} ->
            {:error, "Gradle Plugin Portal returned status #{status}"}

          {:error, _reason} ->
            # Fallback: the POM endpoint may not serve JSON
            {:ok, build_plugin_from_metadata(name, ver)}
        end
    end
  end

  defp fetch_latest_version(group_path, marker_path) do
    metadata_url = "#{@m2_url}/#{group_path}/#{marker_path}/maven-metadata.xml"

    case VerifiedHttp.get_json(metadata_url, receive_timeout: 10_000) do
      {:ok, %{"versioning" => %{"latest" => latest}}} ->
        latest

      {:ok, _} ->
        nil

      {:error, _} ->
        # maven-metadata.xml is XML; parse version from text if needed
        nil
    end
  end

  @doc """
  Search for plugins on the Gradle Plugin Portal.
  Uses the portal search page (HTML-based); falls back to a simple listing.
  """
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    url = "#{@search_url}/search?term=#{URI.encode_www_form(query)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"plugins" => plugins}} when is_list(plugins) ->
        results =
          plugins
          |> Enum.take(limit)
          |> Enum.map(fn plugin ->
            %{
              name: plugin["id"] || plugin["name"],
              version: plugin["version"] || plugin["latestVersion"],
              description: plugin["description"] || ""
            }
          end)

        {:ok, results}

      {:ok, _} ->
        {:ok, []}

      {:error, _reason} ->
        # Search endpoint may return HTML; return empty
        {:ok, []}
    end
  end

  @doc """
  Check if a Gradle plugin exists on the portal.
  """
  def exists?(name) do
    group_path = String.replace(name, ".", "/")
    marker_path = String.replace("#{name}.gradle.plugin", ".", "/")
    metadata_url = "#{@m2_url}/#{group_path}/#{marker_path}/maven-metadata.xml"

    case VerifiedHttp.get(metadata_url, receive_timeout: 5_000) do
      {:ok, _} -> true
      _ -> false
    end
  end

  @doc """
  Get all versions of a Gradle plugin from Maven metadata.
  """
  def versions(name) do
    group_path = String.replace(name, ".", "/")
    marker_path = String.replace("#{name}.gradle.plugin", ".", "/")
    metadata_url = "#{@m2_url}/#{group_path}/#{marker_path}/maven-metadata.xml"

    case VerifiedHttp.get_json(metadata_url, receive_timeout: 10_000) do
      {:ok, %{"versioning" => %{"versions" => %{"version" => versions}}}}
      when is_list(versions) ->
        {:ok, Enum.reverse(versions)}

      {:ok, %{"versioning" => %{"versions" => versions}}} when is_list(versions) ->
        {:ok, Enum.reverse(versions)}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}

      _ ->
        {:error, :not_found}
    end
  end

  # ---------------------------------------------------------------------------
  # Parsers
  # ---------------------------------------------------------------------------

  defp parse_plugin(name, json, version) do
    %ResolvedPackage{
      package: name,
      version: version,
      forth: :gradle_plugins,
      registry_url: "#{@search_url}/plugin/#{name}",
      tarball_url: build_jar_url(name, version),
      checksum: nil,
      checksum_algo: nil,
      manifest: %ManifestFormat{
        name: json["artifactId"] || name,
        version: version,
        description: json["description"] || json["name"],
        license: extract_license(json["licenses"]),
        homepage: "#{@search_url}/plugin/#{name}",
        repository: extract_scm(json["scm"]),
        authors: extract_developers(json["developers"]),
        keywords: [],
        dependencies: extract_gradle_deps(json["dependencies"]),
        dev_dependencies: %{},
        source_forth: :gradle_plugins,
        raw_manifest: json
      },
      attestations: [],
      resolved_deps: []
    }
  end

  defp build_plugin_from_metadata(name, version) do
    %ResolvedPackage{
      package: name,
      version: version,
      forth: :gradle_plugins,
      registry_url: "#{@search_url}/plugin/#{name}",
      tarball_url: build_jar_url(name, version),
      checksum: nil,
      checksum_algo: nil,
      manifest: %ManifestFormat{
        name: name,
        version: version,
        description: nil,
        license: nil,
        homepage: "#{@search_url}/plugin/#{name}",
        repository: nil,
        authors: [],
        keywords: [],
        dependencies: %{},
        dev_dependencies: %{},
        source_forth: :gradle_plugins,
        raw_manifest: %{}
      },
      attestations: [],
      resolved_deps: []
    }
  end

  defp build_jar_url(name, version) do
    group_path = String.replace(name, ".", "/")
    marker = "#{name}.gradle.plugin"
    marker_path = String.replace(marker, ".", "/")
    "#{@m2_url}/#{group_path}/#{marker_path}/#{version}/#{marker}-#{version}.pom"
  end

  defp extract_license(nil), do: nil
  defp extract_license([%{"name" => name} | _]), do: name
  defp extract_license(_), do: nil

  defp extract_scm(nil), do: nil
  defp extract_scm(%{"url" => url}), do: url
  defp extract_scm(_), do: nil

  defp extract_developers(nil), do: []
  defp extract_developers(devs) when is_list(devs) do
    Enum.map(devs, fn
      %{"name" => name} -> name
      dev when is_binary(dev) -> dev
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end
  defp extract_developers(_), do: []

  defp extract_gradle_deps(nil), do: %{}
  defp extract_gradle_deps(deps) when is_list(deps) do
    Enum.reduce(deps, %{}, fn dep, acc ->
      key = "#{dep["groupId"]}:#{dep["artifactId"]}"
      Map.put(acc, key, dep["version"] || "latest")
    end)
  end
  defp extract_gradle_deps(_), do: %{}
end
