# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Registries.Pkgsrc do
  @moduledoc """
  NetBSD pkgsrc registry adapter.
  https://cdn.netbsd.org/pub/pkgsrc/
  Queries the pkgsrc package collection metadata for NetBSD and other platforms.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @cdn_url "https://cdn.netbsd.org/pub/pkgsrc"
  @pkgsrc_se "https://pkgsrc.se"
  @repo_url "https://github.com/NetBSD/pkgsrc"

  @doc """
  Fetch package metadata from pkgsrc.
  Name can be category/package (e.g., "lang/python311") or just the package name.
  """
  def fetch_package(name, version \\ "latest") do
    url = "#{@pkgsrc_se}/api/pkg/#{URI.encode(name)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        ver =
          if version == "latest",
            do: body["version"] || body["pkgversion"],
            else: version

        {:ok, parse_pkgsrc_package(name, body, ver)}

      {:error, :not_found} ->
        fetch_from_cdn(name, version)

      {:error, %{status: 404}} ->
        fetch_from_cdn(name, version)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_from_cdn(name, version) do
    {category, pkg_name} = split_pkgpath(name)
    _url = "#{@cdn_url}/current/#{category}/#{pkg_name}/DESCR"

    case VerifiedHttp.get_json(
           "#{@cdn_url}/packages/NetBSD/amd64/current/All/#{pkg_name}.json",
           receive_timeout: 10_000
         ) do
      {:ok, body} ->
        ver =
          if version == "latest",
            do: body["version"] || "0.0.0",
            else: version

        {:ok, build_resolved_from_cdn(name, body, ver)}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp split_pkgpath(name) do
    case String.split(name, "/", parts: 2) do
      [category, pkg] -> {category, pkg}
      [pkg] -> {"*", pkg}
    end
  end

  defp parse_pkgsrc_package(name, body, version) do
    deps =
      (body["depends"] || body["build_depends"] || [])
      |> Enum.map(fn
        d when is_binary(d) ->
          dep_name = d |> String.replace(~r/[><=\[\{].*/, "") |> String.trim()
          {dep_name, "*"}

        d when is_map(d) ->
          {d["pkgpath"] || d["name"] || "", "*"}

        _ ->
          nil
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(fn {n, _} -> n == "" end)
      |> Map.new()

    pkgpath = body["pkgpath"] || name

    manifest = %ManifestFormat{
      name: name,
      version: version || "0.0.0",
      description: body["comment"] || body["description"],
      license: body["license"],
      homepage: body["homepage"],
      repository: "#{@repo_url}/tree/trunk/#{pkgpath}",
      dependencies: deps
    }

    %ResolvedPackage{
      package: name,
      version: version || "0.0.0",
      forth: :pkgsrc,
      manifest: manifest,
      tarball_url: build_distfile_url(body),
      checksum: body["digest"] || body["sha256"],
      checksum_algo: if(body["digest"] || body["sha256"], do: :sha256),
      attestations: []
    }
  end

  defp build_resolved_from_cdn(name, body, version) do
    manifest = %ManifestFormat{
      name: name,
      version: version || "0.0.0",
      description: body["comment"] || body["description"],
      license: body["license"],
      homepage: body["homepage"],
      repository: nil,
      dependencies: %{}
    }

    %ResolvedPackage{
      package: name,
      version: version || "0.0.0",
      forth: :pkgsrc,
      manifest: manifest,
      tarball_url: body["file_name"],
      checksum: body["digest"],
      checksum_algo: if(body["digest"], do: :sha256),
      attestations: []
    }
  end

  defp build_distfile_url(body) do
    case body["distfile"] || body["distname"] do
      nil -> nil
      distfile -> "#{@cdn_url}/distfiles/#{distfile}"
    end
  end

  @doc """
  Get available versions. pkgsrc typically carries one version per branch.
  """
  def get_versions(name) do
    case fetch_package(name) do
      {:ok, pkg} -> {:ok, [pkg.version]}
      {:error, _} = err -> err
    end
  end

  @doc """
  Search for packages in pkgsrc.
  """
  def search(query, _opts \\ []) do
    url = "#{@pkgsrc_se}/api/search?q=#{URI.encode(query)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} when is_list(body) ->
        results =
          body
          |> Enum.take(20)
          |> Enum.map(fn pkg ->
            %{
              name: pkg["pkgpath"] || pkg["name"],
              version: pkg["version"],
              description: pkg["comment"] || pkg["description"]
            }
          end)

        {:ok, results}

      {:ok, %{"results" => results}} when is_list(results) ->
        hits =
          results
          |> Enum.take(20)
          |> Enum.map(fn pkg ->
            %{
              name: pkg["pkgpath"] || pkg["name"],
              version: pkg["version"],
              description: pkg["comment"]
            }
          end)

        {:ok, hits}

      {:ok, _} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a package exists in pkgsrc.
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
