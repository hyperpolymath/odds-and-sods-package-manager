# SPDX-License-Identifier: MPL-2.0
defmodule Opsm.Registries.Wapm do
  @moduledoc """
  WAPM (WebAssembly Package Manager) registry adapter.
  https://registry.wapm.io/
  Uses the WAPM GraphQL API for WebAssembly package metadata.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @graphql_url "https://registry.wapm.io/graphql"
  @web_url "https://wapm.io"

  @doc """
  Fetch WebAssembly package metadata from WAPM via GraphQL.
  """
  def fetch_package(name, version \\ "latest") do
    query = """
    query GetPackage($name: String!) {
      getPackage(name: $name) {
        name
        displayName
        description
        homepage
        repository
        license
        lastVersion {
          version
          description
          createdAt
          distribution {
            downloadUrl
            sha256hash
          }
          dependencies {
            name
            version
          }
          manifest
        }
        versions {
          version
        }
        maintainers {
          username
        }
      }
    }
    """

    body = Jason.encode!(%{query: query, variables: %{name: name}})

    case post_graphql(body) do
      {:ok, %{"data" => %{"getPackage" => nil}}} ->
        {:error, :not_found}

      {:ok, %{"data" => %{"getPackage" => pkg}}} when is_map(pkg) ->
        target_version = if version == "latest" do
          get_in(pkg, ["lastVersion", "version"])
        else
          version
        end

        deps = extract_deps(pkg)
        {:ok, parse_package(pkg, target_version, deps)}

      {:ok, %{"errors" => [%{"message" => msg} | _]}} ->
        {:error, msg}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, %{status: status}} ->
        {:error, "WAPM returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Search for WebAssembly packages on WAPM.
  """
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    gql = """
    query SearchPackages($query: String!, $limit: Int) {
      searchPackages(query: $query, first: $limit) {
        edges {
          node {
            name
            description
            lastVersion {
              version
            }
          }
        }
      }
    }
    """

    body = Jason.encode!(%{query: gql, variables: %{query: query, limit: limit}})

    case post_graphql(body) do
      {:ok, %{"data" => %{"searchPackages" => %{"edges" => edges}}}} when is_list(edges) ->
        results = Enum.map(edges, fn %{"node" => node} ->
          %{
            name: node["name"],
            version: get_in(node, ["lastVersion", "version"]),
            description: node["description"] || "",
            downloads: 0
          }
        end)
        {:ok, results}

      {:ok, _} ->
        {:ok, []}

      {:error, %{status: status}} ->
        {:error, "WAPM search returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a WebAssembly package exists on WAPM.
  """
  def exists?(name) do
    case fetch_package(name) do
      {:ok, _} -> true
      _ -> false
    end
  end

  @doc """
  Get all versions of a WAPM package.
  """
  def versions(name) do
    query = """
    query GetVersions($name: String!) {
      getPackage(name: $name) {
        versions {
          version
        }
      }
    }
    """

    body = Jason.encode!(%{query: query, variables: %{name: name}})

    case post_graphql(body) do
      {:ok, %{"data" => %{"getPackage" => %{"versions" => versions}}}} when is_list(versions) ->
        ver_list = versions
        |> Enum.map(fn v -> v["version"] end)
        |> Enum.reject(&is_nil/1)
        {:ok, ver_list}

      {:ok, %{"data" => %{"getPackage" => nil}}} ->
        {:error, :not_found}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get download URL for a WAPM package.
  """
  def tarball_url(name, _version) do
    # WAPM download URLs are provided in the GraphQL response distribution field
    case fetch_package(name) do
      {:ok, pkg} -> {:ok, pkg.tarball_url}
      _ -> {:error, :not_found}
    end
  end

  # GraphQL helper

  defp post_graphql(body) do
    VerifiedHttp.post_json(@graphql_url, body,
      headers: [{"content-type", "application/json"}],
      receive_timeout: 10_000
    )
  end

  # Parsers

  defp extract_deps(pkg) do
    case get_in(pkg, ["lastVersion", "dependencies"]) do
      deps when is_list(deps) ->
        Enum.reduce(deps, %{}, fn dep, acc ->
          case dep do
            %{"name" => dep_name, "version" => ver} ->
              Map.put(acc, dep_name, ver)
            %{"name" => dep_name} ->
              Map.put(acc, dep_name, ">= 0.0.0")
            _ ->
              acc
          end
        end)

      _ ->
        %{}
    end
  end

  defp parse_package(pkg, version, deps) do
    name = pkg["name"]
    last = pkg["lastVersion"] || %{}
    dist = last["distribution"] || %{}
    maintainers = pkg["maintainers"] || []

    %ResolvedPackage{
      package: name,
      version: version,
      forth: :wapm,
      registry_url: "#{@web_url}/package/#{name}",
      tarball_url: dist["downloadUrl"],
      checksum: dist["sha256hash"],
      checksum_algo: if(dist["sha256hash"], do: :sha256, else: nil),
      manifest: %ManifestFormat{
        name: name,
        version: version,
        description: pkg["description"] || last["description"] || "",
        license: pkg["license"],
        homepage: pkg["homepage"],
        repository: pkg["repository"],
        authors: Enum.map(maintainers, fn m -> m["username"] || "" end),
        keywords: [],
        dependencies: deps,
        dev_dependencies: %{},
        source_forth: :wapm,
        raw_manifest: pkg
      },
      attestations: [],
      resolved_deps: []
    }
  end
end
