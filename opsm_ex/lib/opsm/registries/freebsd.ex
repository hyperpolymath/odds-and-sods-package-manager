# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Registries.Freebsd do
  @moduledoc """
  FreeBSD Ports/Packages registry adapter.
  https://pkg.freebsd.org/
  Queries the FreeBSD package API and FreshPorts for metadata.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://pkg.freebsd.org"
  @freshports_api "https://www.freshports.org"
  @repo_branch "FreeBSD:14:amd64"

  @doc """
  Fetch package metadata from the FreeBSD package index.
  Name can be origin (e.g., "lang/python311") or package name (e.g., "python311").
  """
  def fetch_package(name, version \\ "latest") do
    url = "#{@freshports_api}/api/package/#{URI.encode(name)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        ver =
          if version == "latest",
            do: body["version"] || body["portversion"],
            else: version

        {:ok, parse_freebsd_package(name, body, ver)}

      {:error, :not_found} ->
        fetch_from_pkg_api(name, version)

      {:error, %{status: 404}} ->
        fetch_from_pkg_api(name, version)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_from_pkg_api(name, version) do
    _url = "#{@api_url}/#{@repo_branch}/latest/All/#{URI.encode(name)}.pkg"

    case VerifiedHttp.get_json(
           "#{@api_url}/#{@repo_branch}/latest/packagesite.json",
           receive_timeout: 10_000
         ) do
      {:ok, body} when is_map(body) ->
        case find_package_in_index(body, name) do
          nil ->
            {:error, :not_found}

          pkg_data ->
            ver =
              if version == "latest",
                do: pkg_data["version"] || "0.0.0",
                else: version

            {:ok, build_resolved_from_index(name, pkg_data, ver)}
        end

      {:ok, _} ->
        {:error, :not_found}

      {:error, _} ->
        {:error, :not_found}
    end
  end

  defp find_package_in_index(index, name) when is_map(index) do
    Map.get(index, name)
  end

  defp parse_freebsd_package(name, body, version) do
    deps =
      (body["run_depends"] || body["depends"] || [])
      |> Enum.map(fn
        d when is_binary(d) ->
          dep_name = d |> String.split(":") |> hd() |> String.trim()
          {dep_name, "*"}

        d when is_map(d) ->
          {d["name"] || "", "*"}

        _ ->
          nil
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(fn {n, _} -> n == "" end)
      |> Map.new()

    origin = body["origin"] || body["port_origin"] || name

    manifest = %ManifestFormat{
      name: name,
      version: version || "0.0.0",
      description: body["comment"] || body["description"],
      license: extract_license(body),
      homepage: body["www"] || body["homepage"],
      repository: "https://cgit.freebsd.org/ports/tree/#{origin}",
      dependencies: deps
    }

    %ResolvedPackage{
      package: name,
      version: version || "0.0.0",
      forth: :freebsd,
      manifest: manifest,
      tarball_url: "#{@api_url}/#{@repo_branch}/latest/All/#{name}-#{version || "0.0.0"}.pkg",
      checksum: nil,
      attestations: []
    }
  end

  defp build_resolved_from_index(name, data, version) do
    manifest = %ManifestFormat{
      name: name,
      version: version || "0.0.0",
      description: data["comment"] || data["desc"],
      license: nil,
      homepage: data["www"],
      repository: nil,
      dependencies: %{}
    }

    %ResolvedPackage{
      package: name,
      version: version || "0.0.0",
      forth: :freebsd,
      manifest: manifest,
      tarball_url: data["repopath"],
      checksum: data["sum"],
      checksum_algo: if(data["sum"], do: :sha256),
      attestations: []
    }
  end

  defp extract_license(body) do
    case body["license"] || body["licenses"] do
      l when is_binary(l) -> l
      l when is_list(l) -> Enum.join(l, " ")
      _ -> nil
    end
  end

  @doc """
  Get available versions. FreeBSD pkg repos typically carry one version.
  """
  def get_versions(name) do
    case fetch_package(name) do
      {:ok, pkg} -> {:ok, [pkg.version]}
      {:error, _} = err -> err
    end
  end

  @doc """
  Search for packages in the FreeBSD ports collection.
  """
  def search(query, _opts \\ []) do
    url = "#{@freshports_api}/api/search/?query=#{URI.encode(query)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} when is_list(body) ->
        results =
          body
          |> Enum.take(20)
          |> Enum.map(fn pkg ->
            %{
              name: pkg["name"] || pkg["package_name"],
              version: pkg["version"],
              description: pkg["comment"]
            }
          end)

        {:ok, results}

      {:ok, %{"results" => results}} when is_list(results) ->
        hits =
          results
          |> Enum.take(20)
          |> Enum.map(fn pkg ->
            %{name: pkg["name"], version: pkg["version"], description: pkg["comment"]}
          end)

        {:ok, hits}

      {:ok, _} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a package exists in the FreeBSD ports collection.
  """
  def exists?(name) do
    case fetch_package(name) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Get versions for a package.
  """
  def versions(name), do: get_versions(name)
end
