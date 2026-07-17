# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Registries.Vpm do
  @moduledoc """
  VPM (V Package Manager) registry adapter for the V programming language.
  https://vpm.vlang.io/
  Uses the VPM REST API for V package metadata and search.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://vpm.vlang.io/api"
  @web_url "https://vpm.vlang.io"

  @doc """
  Fetch V package metadata from VPM.
  """
  def fetch_package(name, version \\ "latest") do
    url = "#{@api_url}/packages/#{URI.encode(name)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} when is_map(body) ->
        target_version =
          if version == "latest" do
            body["version"] || body["latest_version"] || fetch_latest_version(name)
          else
            version
          end

        deps = extract_deps(body)
        {:ok, parse_package(name, body, target_version, deps)}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, %{status: status}} ->
        {:error, "VPM returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_latest_version(name) do
    case versions(name) do
      {:ok, [latest | _]} -> latest
      _ -> nil
    end
  end

  @doc """
  Search for V packages on VPM.
  """
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    url = "#{@api_url}/packages?q=#{URI.encode_www_form(query)}&limit=#{limit}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"packages" => packages}} when is_list(packages) ->
        results =
          packages
          |> Enum.take(limit)
          |> Enum.map(&parse_search_result/1)

        {:ok, results}

      {:ok, packages} when is_list(packages) ->
        results =
          packages
          |> Enum.take(limit)
          |> Enum.map(&parse_search_result/1)

        {:ok, results}

      {:ok, _} ->
        {:ok, []}

      {:error, %{status: status}} ->
        {:error, "VPM search returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a V package exists on VPM.
  """
  def exists?(name) do
    url = "#{@api_url}/packages/#{URI.encode(name)}"

    case VerifiedHttp.get(url, receive_timeout: 5_000) do
      {:ok, _} -> true
      _ -> false
    end
  end

  @doc """
  Get all versions of a V package.
  """
  def versions(name) do
    url = "#{@api_url}/packages/#{URI.encode(name)}/versions"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"versions" => versions}} when is_list(versions) ->
        ver_list = extract_version_list(versions)
        {:ok, ver_list}

      {:ok, versions} when is_list(versions) ->
        ver_list = extract_version_list(versions)
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
  Get tarball URL for a V package.
  V packages are typically git-based; returns the archive URL.
  """
  def tarball_url(name, version) do
    {:ok, "#{@api_url}/packages/#{name}/#{version}/archive.tar.gz"}
  end

  # Parsers

  defp extract_version_list(versions) do
    Enum.map(versions, fn v ->
      case v do
        %{"version" => ver} -> ver
        %{"tag" => tag} -> tag
        ver when is_binary(ver) -> ver
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_deps(body) do
    case body do
      %{"dependencies" => deps} when is_list(deps) ->
        Enum.reduce(deps, %{}, fn dep, acc ->
          case dep do
            %{"name" => dep_name, "version" => ver} ->
              Map.put(acc, dep_name, ver)

            %{"name" => dep_name} ->
              Map.put(acc, dep_name, ">= 0.0.0")

            dep when is_binary(dep) ->
              Map.put(acc, dep, ">= 0.0.0")

            _ ->
              acc
          end
        end)

      %{"dependencies" => deps} when is_map(deps) ->
        Enum.into(deps, %{})

      _ ->
        %{}
    end
  end

  defp parse_search_result(pkg) do
    %{
      name: pkg["name"] || pkg["full_name"],
      version: pkg["version"] || pkg["latest_version"],
      description: pkg["description"] || pkg["summary"] || "",
      downloads: pkg["downloads"] || pkg["stars"] || 0
    }
  end

  defp parse_package(name, body, version, deps) do
    description = body["description"] || body["summary"] || ""
    license = body["license"]
    homepage = body["homepage"] || body["url"]
    repository = body["repository"] || body["git_url"]

    %ResolvedPackage{
      package: name,
      version: version,
      forth: :vpm,
      registry_url: "#{@web_url}/packages/#{name}",
      tarball_url:
        case tarball_url(name, version) do
          {:ok, url} -> url
          _ -> nil
        end,
      checksum: body["checksum"],
      checksum_algo: if(body["checksum"], do: :sha256, else: nil),
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
        source_forth: :vpm,
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
      %{"owner" => owner} when is_binary(owner) -> [owner]
      _ -> []
    end
  end
end
