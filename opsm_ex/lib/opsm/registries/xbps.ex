# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Registries.Xbps do
  @moduledoc """
  Void Linux XBPS registry adapter.
  https://alpha.de.repo.voidlinux.org/
  Queries the Void Linux package repository index for XBPS metadata.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @repo_url "https://alpha.de.repo.voidlinux.org/current"
  @api_url "https://voidlinux.org/xbps-packages"
  @srcpkgs_url "https://github.com/void-linux/void-packages/tree/master/srcpkgs"

  @doc """
  Fetch package metadata from the Void Linux repository.
  Uses the repo index JSON endpoint for package data.
  """
  def fetch_package(name, version \\ "latest") do
    url = "#{@repo_url}/x86_64-repodata"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} when is_map(body) ->
        case Map.get(body, name) do
          nil -> fetch_from_api(name, version)
          pkg_data -> parse_xbps_entry(name, pkg_data, version)
        end

      {:ok, _} ->
        fetch_from_api(name, version)

      {:error, _} ->
        fetch_from_api(name, version)
    end
  end

  defp fetch_from_api(name, version) do
    url = "#{@api_url}/#{name}.json"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        ver =
          if version == "latest",
            do: body["version"] || body["pkgver"],
            else: version

        {:ok, build_resolved_package(name, body, ver)}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_xbps_entry(name, data, version) do
    ver =
      if version == "latest",
        do: data["pkgver"] || data["version"] || "0.0.0",
        else: version

    {:ok, build_resolved_package(name, data, ver)}
  end

  defp build_resolved_package(name, body, version) do
    deps =
      (body["run_depends"] || body["dependencies"] || [])
      |> Enum.map(fn d ->
        dep_name = String.replace(d, ~r/[><=].*/, "")
        {dep_name, "*"}
      end)
      |> Map.new()

    manifest = %ManifestFormat{
      name: name,
      version: version || "0.0.0",
      description: body["short_desc"] || body["description"],
      license: body["license"],
      homepage: body["homepage"],
      repository: "#{@srcpkgs_url}/#{name}",
      dependencies: deps
    }

    %ResolvedPackage{
      package: name,
      version: version || "0.0.0",
      forth: :xbps,
      manifest: manifest,
      tarball_url: build_tarball_url(name, version),
      checksum: body["filename-sha256"],
      checksum_algo: if(body["filename-sha256"], do: :sha256),
      attestations: []
    }
  end

  defp build_tarball_url(name, version) do
    "#{@repo_url}/#{name}-#{version || "0.0.0"}.x86_64.xbps"
  end

  @doc """
  Get available versions of a Void Linux package.
  XBPS repos typically carry a single version per branch.
  """
  def get_versions(name) do
    case fetch_package(name) do
      {:ok, pkg} -> {:ok, [pkg.version]}
      {:error, _} = err -> err
    end
  end

  @doc """
  Search for packages in the Void Linux repository.
  """
  def search(query, _opts \\ []) do
    url = "#{@api_url}/search.json?q=#{URI.encode(query)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} when is_list(body) ->
        results =
          body
          |> Enum.take(20)
          |> Enum.map(fn pkg ->
            %{
              name: pkg["pkgname"] || pkg["name"],
              version: pkg["version"],
              description: pkg["short_desc"]
            }
          end)

        {:ok, results}

      {:ok, _} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a package exists in the Void Linux repository.
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
