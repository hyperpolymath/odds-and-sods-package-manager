# SPDX-License-Identifier: PMPL-1.0
defmodule Opsm.Registries.Maven do
  @moduledoc """
  Maven Central Registry API client (Java/Kotlin/Scala).
  https://central.sonatype.com/
  Uses the Maven Central Search API.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @search_url "https://search.maven.org/solrsearch/select"
  @repo_url "https://repo1.maven.org/maven2"

  @doc """
  Fetch package metadata from Maven Central.
  Package name format: "groupId:artifactId" (e.g., "com.google.guava:guava")
  """
  def fetch_package(name, version \\ "latest") do
    {group_id, artifact_id} = parse_coordinate(name)
    url = "#{@search_url}?q=g:#{URI.encode(group_id)}+AND+a:#{URI.encode(artifact_id)}&core=gav&rows=200&wt=json"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        docs = get_in(body, ["response", "docs"]) || []

        target_version = if version == "latest" do
          case docs do
            [first | _] -> first["v"]
            [] -> nil
          end
        else
          version
        end

        if target_version do
          doc = Enum.find(docs, fn d -> d["v"] == target_version end) || %{}
          deps = fetch_pom_deps(group_id, artifact_id, target_version)
          sha1 = fetch_jar_sha1(group_id, artifact_id, target_version)
          {:ok, parse_artifact(group_id, artifact_id, target_version, doc, deps, sha1)}
        else
          {:error, :not_found}
        end

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, %{status: status}} ->
        {:error, "Maven Central returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_pom_deps(group_id, artifact_id, version) do
    group_path = String.replace(group_id, ".", "/")
    url = "#{@repo_url}/#{group_path}/#{artifact_id}/#{version}/#{artifact_id}-#{version}.pom"

    case VerifiedHttp.get(url, receive_timeout: 10_000) do
      {:ok, %{body: body}} when is_binary(body) ->
        parse_pom_dependencies(body)
      {:ok, body} when is_binary(body) ->
        parse_pom_dependencies(body)
      _ -> %{}
    end
  end

  defp parse_pom_dependencies(pom_xml) do
    # Simple regex-based POM dependency extraction
    # Matches <dependency> blocks and extracts groupId, artifactId, version
    # Skips test/provided scope dependencies
    ~r/<dependency>\s*<groupId>([^<]+)<\/groupId>\s*<artifactId>([^<]+)<\/artifactId>(?:\s*<version>([^<]*)<\/version>)?(?:\s*<scope>([^<]*)<\/scope>)?/s
    |> Regex.scan(pom_xml)
    |> Enum.reject(fn match ->
      scope = Enum.at(match, 4)
      scope in ["test", "provided", "system"]
    end)
    |> Enum.map(fn match ->
      group = Enum.at(match, 1, "")
      artifact = Enum.at(match, 2, "")
      version = Enum.at(match, 3)
      constraint = if version && not String.starts_with?(version, "${"), do: version, else: ">= 0"
      {"#{group}:#{artifact}", constraint}
    end)
    |> Map.new()
  end

  @doc """
  Search for artifacts on Maven Central.
  """
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    url = "#{@search_url}?q=#{URI.encode(query)}&rows=#{limit}&wt=json"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        docs = get_in(body, ["response", "docs"]) || []
        results = Enum.map(docs, fn doc ->
          %{
            name: "#{doc["g"]}:#{doc["a"]}",
            version: doc["latestVersion"],
            description: nil,
            downloads: 0
          }
        end)
        {:ok, results}

      {:error, %{status: status}} ->
        {:error, "Maven search returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if an artifact exists on Maven Central.
  """
  def exists?(name) do
    {group_id, artifact_id} = parse_coordinate(name)
    url = "#{@search_url}?q=g:#{URI.encode(group_id)}+AND+a:#{URI.encode(artifact_id)}&rows=1&wt=json"

    case VerifiedHttp.get_json(url, receive_timeout: 5_000) do
      {:ok, body} ->
        num_found = get_in(body, ["response", "numFound"]) || 0
        num_found > 0
      _ -> false
    end
  end

  @doc """
  Get all versions of an artifact.
  """
  def versions(name) do
    {group_id, artifact_id} = parse_coordinate(name)
    url = "#{@search_url}?q=g:#{URI.encode(group_id)}+AND+a:#{URI.encode(artifact_id)}&core=gav&rows=200&wt=json"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        docs = get_in(body, ["response", "docs"]) || []
        versions = docs |> Enum.map(& &1["v"]) |> Enum.reject(&is_nil/1)
        {:ok, versions}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get jar URL for a specific version.
  """
  def tarball_url(name, version) do
    {group_id, artifact_id} = parse_coordinate(name)
    group_path = String.replace(group_id, ".", "/")
    {:ok, "#{@repo_url}/#{group_path}/#{artifact_id}/#{version}/#{artifact_id}-#{version}.jar"}
  end

  # Parse "groupId:artifactId" format
  defp parse_coordinate(name) do
    case String.split(name, ":") do
      [group, artifact] -> {group, artifact}
      [artifact] -> {"", artifact}
      [group, artifact | _] -> {group, artifact}
    end
  end

  defp fetch_jar_sha1(group_id, artifact_id, version) do
    group_path = String.replace(group_id, ".", "/")
    url = "#{@repo_url}/#{group_path}/#{artifact_id}/#{version}/#{artifact_id}-#{version}.jar.sha1"

    case VerifiedHttp.get(url, receive_timeout: 10_000) do
      {:ok, %{body: body}} when is_binary(body) ->
        hash = body |> String.trim() |> String.split() |> List.first()
        if hash && Regex.match?(~r/^[0-9a-fA-F]{40}$/, hash), do: hash, else: nil
      {:ok, body} when is_binary(body) ->
        hash = body |> String.trim() |> String.split() |> List.first()
        if hash && Regex.match?(~r/^[0-9a-fA-F]{40}$/, hash), do: hash, else: nil
      _ -> nil
    end
  end

  # Parsers

  defp parse_artifact(group_id, artifact_id, version, doc, deps, sha1) do
    full_name = "#{group_id}:#{artifact_id}"
    group_path = String.replace(group_id, ".", "/")

    %ResolvedPackage{
      package: full_name,
      version: version,
      forth: :maven,
      registry_url: "https://central.sonatype.com/artifact/#{group_id}/#{artifact_id}",
      tarball_url: "#{@repo_url}/#{group_path}/#{artifact_id}/#{version}/#{artifact_id}-#{version}.jar",
      checksum: sha1,
      checksum_algo: if(sha1, do: :sha1, else: nil),
      manifest: %ManifestFormat{
        name: full_name,
        version: version,
        description: nil,
        license: nil,
        homepage: nil,
        repository: nil,
        authors: [],
        keywords: doc["tags"] || [],
        dependencies: deps,
        dev_dependencies: %{},
        source_forth: :maven,
        raw_manifest: doc
      },
      attestations: [],
      resolved_deps: []
    }
  end
end
