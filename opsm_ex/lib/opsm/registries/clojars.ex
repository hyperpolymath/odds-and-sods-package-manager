# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Registries.Clojars do
  @moduledoc """
  Clojars registry API client.
  https://clojars.org/
  Clojars is the community-driven Clojure library repository.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://clojars.org/api"
  @repo_url "https://repo.clojars.org"
  @web_url "https://clojars.org"

  @doc """
  Fetch artifact metadata from Clojars.
  """
  def fetch_package(name, version \\ "latest") do
    # Clojars artifacts can be grouped (e.g., "org.clojure/clojure") or simple (e.g., "compojure")
    {group_id, artifact_id} = parse_artifact_name(name)

    target_version =
      if version == "latest" do
        fetch_latest_version(group_id, artifact_id)
      else
        version
      end

    case target_version do
      nil ->
        {:error, :not_found}

      ver ->
        # Fetch artifact metadata
        url = build_artifact_url(group_id, artifact_id)

        case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
          {:ok, body} ->
            {:ok, parse_artifact(name, body, ver)}

          {:error, :not_found} ->
            {:error, :not_found}

          {:error, %{status: 404}} ->
            {:error, :not_found}

          {:error, %{status: status}} ->
            {:error, "Clojars API returned status #{status}"}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp fetch_latest_version(group_id, artifact_id) do
    url = build_artifact_url(group_id, artifact_id)

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"latest_version" => version}} -> version
      {:ok, %{"versions" => [latest | _]}} -> latest
      _ -> nil
    end
  end

  defp parse_artifact_name(name) do
    case String.split(name, "/", parts: 2) do
      [group, artifact] -> {group, artifact}
      # Simple artifact name uses itself as group
      [artifact] -> {artifact, artifact}
    end
  end

  defp build_artifact_url(group_id, artifact_id) do
    if group_id == artifact_id do
      "#{@api_url}/artifacts/#{artifact_id}"
    else
      "#{@api_url}/artifacts/#{group_id}/#{artifact_id}"
    end
  end

  @doc """
  Search for Clojars artifacts.
  """
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    url = "#{@api_url}/search?q=#{URI.encode_www_form(query)}&format=json"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"results" => results}} when is_list(results) ->
        packages =
          results
          |> Enum.take(limit)
          |> Enum.map(&parse_search_result/1)

        {:ok, packages}

      {:ok, results} when is_list(results) ->
        packages =
          results
          |> Enum.take(limit)
          |> Enum.map(&parse_search_result/1)

        {:ok, packages}

      {:error, :not_found} ->
        {:ok, []}

      {:error, %{status: 404}} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_search_result(result) do
    %{
      name: build_full_name(result),
      version: Map.get(result, "version") || Map.get(result, "latest_version"),
      description: Map.get(result, "description") || "",
      downloads: Map.get(result, "downloads", 0)
    }
  end

  defp build_full_name(%{"group_name" => group, "jar_name" => artifact}) when group != artifact do
    "#{group}/#{artifact}"
  end

  defp build_full_name(%{"jar_name" => artifact}), do: artifact
  defp build_full_name(%{"artifact_id" => artifact}), do: artifact
  defp build_full_name(_), do: "unknown"

  @doc """
  Check if a Clojars artifact exists.
  """
  def exists?(name) do
    {group_id, artifact_id} = parse_artifact_name(name)
    url = build_artifact_url(group_id, artifact_id)

    case VerifiedHttp.get(url, receive_timeout: 5_000) do
      {:ok, _} -> true
      _ -> false
    end
  end

  @doc """
  Get all versions of a Clojars artifact.
  """
  def versions(name) do
    {group_id, artifact_id} = parse_artifact_name(name)
    url = build_artifact_url(group_id, artifact_id)

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"versions" => versions}} when is_list(versions) ->
        # Reverse to get newest first
        {:ok, Enum.reverse(versions)}

      {:ok, %{"recent_versions" => versions}} when is_list(versions) ->
        # Some endpoints might only return recent versions
        versions_list =
          versions
          |> Enum.map(fn
            %{"version" => v} -> v
            v when is_binary(v) -> v
            _ -> nil
          end)
          |> Enum.reject(&is_nil/1)

        {:ok, Enum.reverse(versions_list)}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}

      _ ->
        {:ok, []}
    end
  end

  @doc """
  Get JAR URL for a specific version.
  Clojars uses Maven repository layout.
  """
  def tarball_url(name, version) do
    {group_id, artifact_id} = parse_artifact_name(name)
    # Convert group_id dots to slashes for Maven path
    group_path = String.replace(group_id, ".", "/")
    jar_url = "#{@repo_url}/#{group_path}/#{artifact_id}/#{version}/#{artifact_id}-#{version}.jar"
    {:ok, jar_url}
  end

  # Parsers

  defp parse_artifact(name, metadata, version) do
    {group_id, artifact_id} = parse_artifact_name(name)

    # Extract dependencies from the version metadata if available
    deps = extract_dependencies(metadata, version)

    # Get JAR URL
    {:ok, jar_url} = tarball_url(name, version)

    # Build web URL for the artifact
    web_url =
      if group_id == artifact_id do
        "#{@web_url}/#{artifact_id}"
      else
        "#{@web_url}/#{group_id}/#{artifact_id}"
      end

    # Repository URL (often hosted on GitHub)
    repo_url =
      case metadata do
        %{"scm" => %{"url" => url}} -> url
        %{"homepage" => url} when is_binary(url) -> url
        _ -> nil
      end

    %ResolvedPackage{
      package: name,
      version: version,
      forth: :clojars,
      registry_url: web_url,
      tarball_url: jar_url,
      # Clojars API doesn't provide checksums directly
      checksum: nil,
      checksum_algo: nil,
      manifest: %ManifestFormat{
        name: name,
        version: version,
        description: Map.get(metadata, "description"),
        license: extract_license(metadata),
        homepage: Map.get(metadata, "homepage") || web_url,
        repository: repo_url,
        authors: extract_authors(metadata),
        keywords: [],
        dependencies: deps,
        dev_dependencies: %{},
        source_forth: :clojars,
        raw_manifest: metadata
      },
      attestations: [],
      resolved_deps: []
    }
  end

  defp extract_dependencies(metadata, version) do
    # Try to find version-specific dependencies
    case metadata do
      %{"recent_versions" => versions} when is_list(versions) ->
        versions
        |> Enum.find(%{}, fn v ->
          Map.get(v, "version") == version
        end)
        |> Map.get("dependencies", %{})
        |> normalize_deps()

      %{"dependencies" => deps} ->
        normalize_deps(deps)

      _ ->
        %{}
    end
  end

  defp normalize_deps(deps) when is_map(deps) do
    # Dependencies might be in format: {"group/artifact" => "version"}
    # or [{"group/artifact", "version"}]
    deps
  end

  defp normalize_deps(deps) when is_list(deps) do
    # Convert list of tuples to map
    Enum.into(deps, %{})
  end

  defp normalize_deps(_), do: %{}

  defp extract_license(metadata) do
    case metadata do
      %{"licenses" => [license | _]} when is_binary(license) -> license
      %{"licenses" => [%{"name" => name} | _]} -> name
      %{"license" => license} when is_binary(license) -> license
      _ -> nil
    end
  end

  defp extract_authors(metadata) do
    case metadata do
      %{"authors" => authors} when is_list(authors) -> authors
      %{"author" => author} when is_binary(author) -> [author]
      _ -> []
    end
  end
end
