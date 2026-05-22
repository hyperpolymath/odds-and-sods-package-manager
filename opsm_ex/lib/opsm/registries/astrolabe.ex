# SPDX-License-Identifier: MPL-2.0
defmodule Opsm.Registries.Astrolabe do
  @moduledoc """
  Astrolabe registry adapter for Zig packages.
  https://astrolabe.pm/
  Uses the Astrolabe REST API for Zig package discovery and metadata.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://astrolabe.pm/api"

  @doc """
  Fetch Zig package metadata from Astrolabe.
  """
  def fetch_package(name, version \\ "latest") do
    url = "#{@api_url}/packages/#{URI.encode(name)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} when is_map(body) ->
        target_version = if version == "latest" do
          fetch_latest_version(body)
        else
          version
        end

        deps = extract_deps(body, target_version)
        {:ok, parse_package(name, body, target_version, deps)}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, %{status: status}} ->
        {:error, "Astrolabe returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_latest_version(body) do
    case body do
      %{"latest_version" => ver} when is_binary(ver) -> ver
      %{"versions" => [%{"version" => ver} | _]} -> ver
      %{"version" => ver} when is_binary(ver) -> ver
      _ -> nil
    end
  end

  @doc """
  Search for Zig packages on Astrolabe.
  """
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    url = "#{@api_url}/packages?q=#{URI.encode_www_form(query)}&limit=#{limit}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"packages" => packages}} when is_list(packages) ->
        results = packages
        |> Enum.take(limit)
        |> Enum.map(fn pkg ->
          %{
            name: pkg["name"],
            version: pkg["latest_version"] || pkg["version"],
            description: pkg["description"] || "",
            downloads: pkg["downloads"] || 0
          }
        end)
        {:ok, results}

      {:ok, packages} when is_list(packages) ->
        results = packages
        |> Enum.take(limit)
        |> Enum.map(fn pkg ->
          %{
            name: pkg["name"],
            version: pkg["latest_version"] || pkg["version"],
            description: pkg["description"] || "",
            downloads: pkg["downloads"] || 0
          }
        end)
        {:ok, results}

      {:ok, _} ->
        {:ok, []}

      {:error, %{status: status}} ->
        {:error, "Astrolabe search returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a Zig package exists on Astrolabe.
  """
  def exists?(name) do
    url = "#{@api_url}/packages/#{URI.encode(name)}"

    case VerifiedHttp.get(url, receive_timeout: 5_000) do
      {:ok, _} -> true
      _ -> false
    end
  end

  @doc """
  Get all versions of a Zig package.
  """
  def versions(name) do
    url = "#{@api_url}/packages/#{URI.encode(name)}/versions"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"versions" => versions}} when is_list(versions) ->
        ver_list = Enum.map(versions, fn v ->
          case v do
            %{"version" => ver} -> ver
            ver when is_binary(ver) -> ver
            _ -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)
        {:ok, ver_list}

      {:ok, versions} when is_list(versions) ->
        ver_list = Enum.map(versions, fn v ->
          case v do
            %{"version" => ver} -> ver
            ver when is_binary(ver) -> ver
            _ -> nil
          end
        end)
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
  Get tarball/archive URL for a Zig package version.
  """
  def tarball_url(name, version) do
    {:ok, "#{@api_url}/packages/#{name}/#{version}/archive.tar.gz"}
  end

  # Parsers

  defp extract_deps(body, _version) do
    case body do
      %{"dependencies" => deps} when is_map(deps) ->
        Enum.reduce(deps, %{}, fn {dep_name, constraint}, acc ->
          ver = case constraint do
            c when is_binary(c) -> c
            %{"version" => v} -> v
            _ -> ">= 0.0.0"
          end
          Map.put(acc, dep_name, ver)
        end)

      %{"deps" => deps} when is_list(deps) ->
        Enum.reduce(deps, %{}, fn dep, acc ->
          name = dep["name"] || dep["package"]
          ver = dep["version"] || ">= 0.0.0"
          if name, do: Map.put(acc, name, ver), else: acc
        end)

      _ ->
        %{}
    end
  end

  defp parse_package(name, body, version, deps) do
    description = body["description"] || body["summary"] || ""
    license = body["license"]
    homepage = body["homepage"] || body["url"]
    repository = body["repository"] || body["git_url"] || body["source"]

    %ResolvedPackage{
      package: name,
      version: version,
      forth: :zig_pkg,
      registry_url: "https://astrolabe.pm/packages/#{name}",
      tarball_url: "#{@api_url}/packages/#{name}/#{version}/archive.tar.gz",
      checksum: body["checksum"] || body["hash"],
      checksum_algo: if(body["checksum"] || body["hash"], do: :sha256, else: nil),
      manifest: %ManifestFormat{
        name: name,
        version: version,
        description: description,
        license: license,
        homepage: homepage,
        repository: repository,
        authors: extract_authors(body),
        keywords: body["tags"] || body["keywords"] || [],
        dependencies: deps,
        dev_dependencies: %{},
        source_forth: :zig_pkg,
        raw_manifest: body
      },
      attestations: [],
      resolved_deps: []
    }
  end

  defp extract_authors(body) do
    case body do
      %{"author" => author} when is_binary(author) -> [author]
      %{"authors" => authors} when is_list(authors) -> authors
      %{"maintainers" => m} when is_list(m) -> m
      _ -> []
    end
  end
end
