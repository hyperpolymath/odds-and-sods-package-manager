# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Registries.WebJars do
  @moduledoc """
  WebJars Registry API client.
  https://www.webjars.org/api/
  Packages client-side web libraries (JS, CSS) as JARs for JVM-based
  build tools (Maven, Gradle, SBT). Includes npm, Bower, and classic WebJars.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://www.webjars.org"
  @maven_url "https://repo1.maven.org/maven2/org/webjars"

  @doc """
  Fetch WebJar metadata from the WebJars API.
  The `name` is the WebJar artifact name (e.g., "jquery", "bootstrap").
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
        url = "#{@api_url}/api/webjars/#{URI.encode(name)}/#{ver}"

        case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
          {:ok, body} when is_map(body) ->
            {:ok, parse_webjar(name, body, ver)}

          {:error, :not_found} ->
            # Fallback: build from known Maven coordinates
            {:ok, build_from_maven(name, ver)}

          {:error, %{status: 404}} ->
            {:error, :not_found}

          {:error, %{status: status}} ->
            {:error, "WebJars API returned status #{status}"}

          {:error, _reason} ->
            {:ok, build_from_maven(name, ver)}
        end
    end
  end

  defp fetch_latest_version(name) do
    url = "#{@api_url}/api/webjars/#{URI.encode(name)}/versions"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, versions} when is_list(versions) ->
        List.first(versions)

      {:ok, %{"versions" => [ver | _]}} ->
        ver

      _ ->
        nil
    end
  end

  @doc """
  Search for WebJars.
  """
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    url = "#{@api_url}/api/webjars?search=#{URI.encode_www_form(query)}&limit=#{limit}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, results} when is_list(results) ->
        entries =
          results
          |> Enum.take(limit)
          |> Enum.map(fn jar ->
            %{
              name: jar["artifactId"] || jar["name"],
              version: jar["version"] || jar["latestVersion"],
              description: jar["description"] || "WebJar: #{jar["artifactId"]}"
            }
          end)

        {:ok, entries}

      {:ok, %{"results" => results}} when is_list(results) ->
        entries =
          results
          |> Enum.take(limit)
          |> Enum.map(fn jar ->
            %{
              name: jar["artifactId"] || jar["name"],
              version: jar["version"] || jar["latestVersion"],
              description: jar["description"] || "WebJar: #{jar["artifactId"]}"
            }
          end)

        {:ok, entries}

      {:ok, _} ->
        {:ok, []}

      {:error, %{status: status}} ->
        {:error, "WebJars search returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a WebJar exists.
  """
  def exists?(name) do
    url = "#{@api_url}/api/webjars/#{URI.encode(name)}/versions"

    case VerifiedHttp.get(url, receive_timeout: 5_000) do
      {:ok, _} -> true
      _ -> false
    end
  end

  @doc """
  Get all available versions of a WebJar.
  """
  def versions(name) do
    url = "#{@api_url}/api/webjars/#{URI.encode(name)}/versions"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, versions} when is_list(versions) ->
        {:ok, versions}

      {:ok, %{"versions" => versions}} when is_list(versions) ->
        {:ok, versions}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Parsers
  # ---------------------------------------------------------------------------

  defp parse_webjar(name, json, version) do
    group_id = json["groupId"] || "org.webjars"
    artifact_id = json["artifactId"] || name

    %ResolvedPackage{
      package: name,
      version: version,
      forth: :webjars,
      registry_url: "#{@api_url}/#{artifact_id}",
      tarball_url: build_jar_url(group_id, artifact_id, version),
      checksum: json["sha1"],
      checksum_algo: if(json["sha1"], do: :sha1, else: nil),
      manifest: %ManifestFormat{
        name: artifact_id,
        version: version,
        description: json["description"] || "WebJar for #{artifact_id}",
        license: extract_license(json["licenses"]),
        homepage: json["homepage"] || json["sourceUrl"],
        repository: json["sourceUrl"],
        authors: [],
        keywords: json["keywords"] || [],
        dependencies: extract_deps(json["dependencies"]),
        dev_dependencies: %{},
        source_forth: :webjars,
        raw_manifest: json
      },
      attestations: [],
      resolved_deps: []
    }
  end

  defp build_from_maven(name, version) do
    %ResolvedPackage{
      package: name,
      version: version,
      forth: :webjars,
      registry_url: "#{@api_url}/#{name}",
      tarball_url: "#{@maven_url}/#{name}/#{version}/#{name}-#{version}.jar",
      checksum: nil,
      checksum_algo: nil,
      manifest: %ManifestFormat{
        name: name,
        version: version,
        description: "WebJar for #{name}",
        license: nil,
        homepage: "#{@api_url}/#{name}",
        repository: nil,
        authors: [],
        keywords: [],
        dependencies: %{},
        dev_dependencies: %{},
        source_forth: :webjars,
        raw_manifest: %{}
      },
      attestations: [],
      resolved_deps: []
    }
  end

  defp build_jar_url(group_id, artifact_id, version) do
    group_path = String.replace(group_id, ".", "/")

    "https://repo1.maven.org/maven2/#{group_path}/#{artifact_id}/#{version}/#{artifact_id}-#{version}.jar"
  end

  defp extract_license(nil), do: nil
  defp extract_license([%{"name" => name} | _]), do: name
  defp extract_license(license) when is_binary(license), do: license
  defp extract_license(_), do: nil

  defp extract_deps(nil), do: %{}
  defp extract_deps(deps) when is_map(deps), do: deps

  defp extract_deps(deps) when is_list(deps) do
    Enum.reduce(deps, %{}, fn
      %{"name" => name, "version" => ver}, acc -> Map.put(acc, name, ver)
      %{"artifactId" => name, "version" => ver}, acc -> Map.put(acc, name, ver)
      _, acc -> acc
    end)
  end

  defp extract_deps(_), do: %{}
end
