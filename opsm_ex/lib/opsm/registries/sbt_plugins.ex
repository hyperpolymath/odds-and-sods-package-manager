# SPDX-License-Identifier: MPL-2.0
defmodule Opsm.Registries.SbtPlugins do
  @moduledoc """
  SBT/Scala Plugin Registry API client.
  https://repo1.maven.org/maven2/
  Fetches SBT plugins from Maven Central under the org.scala-sbt
  namespace and related Scala plugin groups. Plugins follow the
  Maven coordinate convention: org/scala-sbt/sbt-plugins/{plugin}/{version}
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @maven_url "https://repo1.maven.org/maven2"
  @search_url "https://search.maven.org/solrsearch/select"

  @doc """
  Fetch SBT plugin metadata from Maven Central.
  The `name` can be:
  - A short name like "sbt-assembly" (resolved under org.scala-sbt namespace)
  - A full coordinate like "com.eed3si9n:sbt-assembly"
  """
  def fetch_package(name, version \\ "latest") do
    {group_id, artifact_id} = parse_coordinate(name)
    group_path = String.replace(group_id, ".", "/")

    target_version = if version == "latest" do
      fetch_latest_version(group_id, artifact_id)
    else
      version
    end

    case target_version do
      nil ->
        {:error, :not_found}

      ver ->
        pom_url = "#{@maven_url}/#{group_path}/#{artifact_id}/#{ver}/#{artifact_id}-#{ver}.pom"

        case VerifiedHttp.get_json(pom_url, receive_timeout: 10_000) do
          {:ok, body} when is_map(body) ->
            {:ok, parse_pom(group_id, artifact_id, body, ver)}

          {:error, :not_found} ->
            # POM is XML; build a best-effort record from search API
            fetch_from_search(group_id, artifact_id, ver)

          {:error, %{status: 404}} ->
            {:error, :not_found}

          {:error, %{status: status}} ->
            {:error, "Maven Central returned status #{status}"}

          {:error, _reason} ->
            fetch_from_search(group_id, artifact_id, ver)
        end
    end
  end

  defp fetch_latest_version(group_id, artifact_id) do
    url = "#{@search_url}?q=g:#{URI.encode(group_id)}+AND+a:#{URI.encode(artifact_id)}&rows=1&wt=json"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"response" => %{"docs" => [%{"latestVersion" => ver} | _]}}} ->
        ver

      {:ok, _} ->
        nil

      {:error, _} ->
        nil
    end
  end

  defp fetch_from_search(group_id, artifact_id, version) do
    url = "#{@search_url}?q=g:#{URI.encode(group_id)}+AND+a:#{URI.encode(artifact_id)}+AND+v:#{URI.encode(version)}&rows=1&wt=json"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"response" => %{"docs" => [doc | _]}}} ->
        {:ok, parse_search_doc(group_id, artifact_id, doc, version)}

      {:ok, _} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Search for SBT plugins on Maven Central.
  Restricts search to common SBT plugin group IDs.
  """
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    url =
      "#{@search_url}?q=#{URI.encode_www_form(query)}+AND+p:jar&rows=#{limit}&wt=json"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"response" => %{"docs" => docs}}} when is_list(docs) ->
        results =
          Enum.map(docs, fn doc ->
            %{
              name: "#{doc["g"]}:#{doc["a"]}",
              version: doc["latestVersion"] || doc["v"],
              description: doc["text"] || "#{doc["g"]}:#{doc["a"]}"
            }
          end)

        {:ok, results}

      {:ok, _} ->
        {:ok, []}

      {:error, %{status: status}} ->
        {:error, "Maven search returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if an SBT plugin exists on Maven Central.
  """
  def exists?(name) do
    {group_id, artifact_id} = parse_coordinate(name)

    url = "#{@search_url}?q=g:#{URI.encode(group_id)}+AND+a:#{URI.encode(artifact_id)}&rows=1&wt=json"

    case VerifiedHttp.get_json(url, receive_timeout: 5_000) do
      {:ok, %{"response" => %{"numFound" => n}}} when n > 0 -> true
      _ -> false
    end
  end

  @doc """
  Get all versions of an SBT plugin from Maven Central.
  """
  def versions(name) do
    {group_id, artifact_id} = parse_coordinate(name)

    url =
      "#{@search_url}?q=g:#{URI.encode(group_id)}+AND+a:#{URI.encode(artifact_id)}" <>
        "&core=gav&rows=200&wt=json"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"response" => %{"docs" => docs}}} when is_list(docs) ->
        version_list =
          docs
          |> Enum.map(fn doc -> doc["v"] end)
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq()

        {:ok, version_list}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Coordinate parsing
  # ---------------------------------------------------------------------------

  defp parse_coordinate(name) do
    case String.split(name, ":", parts: 2) do
      [group, artifact] -> {group, artifact}
      [artifact] -> {"org.scala-sbt", artifact}
    end
  end

  # ---------------------------------------------------------------------------
  # Parsers
  # ---------------------------------------------------------------------------

  defp parse_pom(group_id, artifact_id, json, version) do
    coordinate = "#{group_id}:#{artifact_id}"
    group_path = String.replace(group_id, ".", "/")

    %ResolvedPackage{
      package: coordinate,
      version: version,
      forth: :sbt_plugins,
      registry_url: "https://search.maven.org/artifact/#{group_id}/#{artifact_id}/#{version}/jar",
      tarball_url: "#{@maven_url}/#{group_path}/#{artifact_id}/#{version}/#{artifact_id}-#{version}.jar",
      checksum: nil,
      checksum_algo: nil,
      manifest: %ManifestFormat{
        name: coordinate,
        version: version,
        description: json["description"] || json["name"],
        license: extract_license(json["licenses"]),
        homepage: json["url"],
        repository: extract_scm(json["scm"]),
        authors: extract_developers(json["developers"]),
        keywords: [],
        dependencies: extract_deps(json["dependencies"]),
        dev_dependencies: %{},
        source_forth: :sbt_plugins,
        raw_manifest: json
      },
      attestations: [],
      resolved_deps: []
    }
  end

  defp parse_search_doc(group_id, artifact_id, doc, version) do
    coordinate = "#{group_id}:#{artifact_id}"
    group_path = String.replace(group_id, ".", "/")

    %ResolvedPackage{
      package: coordinate,
      version: version,
      forth: :sbt_plugins,
      registry_url: "https://search.maven.org/artifact/#{group_id}/#{artifact_id}/#{version}/jar",
      tarball_url: "#{@maven_url}/#{group_path}/#{artifact_id}/#{version}/#{artifact_id}-#{version}.jar",
      checksum: nil,
      checksum_algo: nil,
      manifest: %ManifestFormat{
        name: coordinate,
        version: version,
        description: doc["text"] || coordinate,
        license: nil,
        homepage: nil,
        repository: nil,
        authors: [],
        keywords: doc["tags"] || [],
        dependencies: %{},
        dev_dependencies: %{},
        source_forth: :sbt_plugins,
        raw_manifest: doc
      },
      attestations: [],
      resolved_deps: []
    }
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

  defp extract_deps(nil), do: %{}
  defp extract_deps(deps) when is_list(deps) do
    Enum.reduce(deps, %{}, fn dep, acc ->
      key = "#{dep["groupId"]}:#{dep["artifactId"]}"
      Map.put(acc, key, dep["version"] || "latest")
    end)
  end
  defp extract_deps(_), do: %{}
end
