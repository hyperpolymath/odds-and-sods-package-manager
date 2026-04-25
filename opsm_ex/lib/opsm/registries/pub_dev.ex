# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule Opsm.Registries.PubDev do
  @moduledoc """
  pub.dev Registry API client (Dart/Flutter packages).
  https://pub.dev/help/api
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @base_url "https://pub.dev/api"

  @doc """
  Fetch package metadata from pub.dev.
  """
  def fetch_package(name, version \\ "latest") do
    url = "#{@base_url}/packages/#{URI.encode(name)}"
    headers = [{"accept", "application/vnd.pub.v2+json"}]

    case VerifiedHttp.get_json(url, headers: headers, receive_timeout: 10_000) do
      {:ok, body} ->
        versions_list = body["versions"] || []
        latest_info = body["latest"] || %{}

        target_version = if version == "latest" do
          latest_info["version"]
        else
          version
        end

        version_info = Enum.find(versions_list, fn v -> v["version"] == target_version end)
        pubspec = if version_info, do: version_info["pubspec"] || %{}, else: latest_info["pubspec"] || %{}

        deps = parse_pubspec_deps(pubspec["dependencies"])
        dev_deps = parse_pubspec_deps(pubspec["dev_dependencies"])

        {:ok, parse_package(body, pubspec, target_version, version_info, deps, dev_deps)}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, %{status: status}} ->
        {:error, "pub.dev returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_pubspec_deps(nil), do: %{}
  defp parse_pubspec_deps(deps) when is_map(deps) do
    deps
    |> Enum.reject(fn {_name, constraint} ->
      # Skip SDK dependencies and path dependencies
      is_map(constraint) and (Map.has_key?(constraint, "sdk") or Map.has_key?(constraint, "path"))
    end)
    |> Enum.map(fn
      {name, constraint} when is_binary(constraint) -> {name, constraint}
      {name, %{"hosted" => _} = spec} -> {name, spec["version"] || "any"}
      {name, _} -> {name, "any"}
    end)
    |> Map.new()
  end

  @doc """
  Search for packages on pub.dev.
  """
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    url = "#{@base_url}/search?q=#{URI.encode(query)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"packages" => packages}} when is_list(packages) ->
        results = packages
          |> Enum.take(limit)
          |> Enum.map(fn pkg ->
            %{
              name: pkg["package"],
              version: nil,
              description: nil,
              downloads: 0
            }
          end)
        {:ok, results}

      {:ok, _} ->
        {:ok, []}

      {:error, %{status: status}} ->
        {:error, "pub.dev search returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a package exists on pub.dev.
  """
  def exists?(name) do
    url = "#{@base_url}/packages/#{URI.encode(name)}"
    headers = [{"accept", "application/vnd.pub.v2+json"}]

    case VerifiedHttp.get(url, headers: headers, receive_timeout: 5_000) do
      {:ok, _} -> true
      _ -> false
    end
  end

  @doc """
  Get all versions of a package.
  """
  def versions(name) do
    url = "#{@base_url}/packages/#{URI.encode(name)}"
    headers = [{"accept", "application/vnd.pub.v2+json"}]

    case VerifiedHttp.get_json(url, headers: headers, receive_timeout: 10_000) do
      {:ok, body} ->
        versions_list = body["versions"] || []
        versions = versions_list
          |> Enum.map(& &1["version"])
          |> Enum.reject(&is_nil/1)
          |> Enum.reverse()  # Newest first
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
  Get archive URL for a specific version.
  """
  def tarball_url(name, version) do
    {:ok, "#{@base_url}/archives/#{name}-#{version}.tar.gz"}
  end

  # Parsers

  defp parse_package(body, pubspec, version, version_info, deps, dev_deps) do
    checksum = if version_info, do: version_info["archive_sha256"], else: nil

    %ResolvedPackage{
      package: body["name"],
      version: version,
      forth: :pub,
      registry_url: "https://pub.dev/packages/#{body["name"]}",
      tarball_url: "#{@base_url}/archives/#{body["name"]}-#{version}.tar.gz",
      checksum: checksum,
      checksum_algo: if(checksum, do: :sha256, else: nil),
      manifest: %ManifestFormat{
        name: body["name"],
        version: version,
        description: pubspec["description"],
        license: nil,
        homepage: pubspec["homepage"],
        repository: pubspec["repository"],
        authors: pubspec["authors"] || [],
        keywords: [],
        dependencies: deps,
        dev_dependencies: dev_deps,
        source_forth: :pub,
        raw_manifest: pubspec
      },
      attestations: [],
      resolved_deps: []
    }
  end
end
