# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Registries.Solus do
  @moduledoc """
  Solus eopkg registry adapter.
  https://packages.getsol.us/
  Queries the Solus package repository API for eopkg packages.
  Solus is an independently developed Linux distribution using
  the eopkg package manager and ypkg build system.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://packages.getsol.us/api"
  @repo_url "https://packages.getsol.us"

  @doc """
  Fetch package metadata from the Solus repository.
  """
  def fetch_package(name, version \\ "latest") do
    url = "#{@api_url}/packages/#{URI.encode(name)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        pkg = body["package"] || body

        ver = if version == "latest" do
          pkg["version"] || get_latest_version(pkg) || "0.0.0"
        else
          version
        end

        {:ok, parse_solus_package(name, pkg, ver)}

      {:error, :not_found} -> {:error, :not_found}
      {:error, %{status: 404}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_latest_version(pkg) do
    history = pkg["history"] || pkg["releases"] || []
    case history do
      [latest | _] -> latest["version"]
      _ -> nil
    end
  end

  defp parse_solus_package(name, pkg, version) do
    # eopkg packages declare runtime and build dependencies
    runtime_deps = (pkg["rundeps"] || pkg["runtimeDependencies"] || [])
                   |> normalize_deps()

    source = pkg["source"] || %{}

    manifest = %ManifestFormat{
      name: name,
      version: version,
      description: pkg["description"] || pkg["summary"],
      license: normalize_license(pkg["license"] || pkg["licenses"]),
      homepage: source["homepage"] || pkg["homepage"],
      repository: source["url"] || pkg["sourceUrl"],
      authors: extract_packager(pkg),
      keywords: [pkg["component"] || pkg["partOf"]] |> Enum.reject(&is_nil/1),
      dependencies: runtime_deps,
      source_forth: :solus,
      raw_manifest: pkg
    }

    # eopkg packages are distributed as .eopkg archives
    release = (pkg["history"] || pkg["releases"] || []) |> List.first() || %{}
    release_num = release["release"] || pkg["release"]

    download_url = if release_num do
      "#{@repo_url}/shannon/#{name}-#{version}-#{release_num}-1-x86_64.eopkg"
    end

    %ResolvedPackage{
      package: name,
      version: version,
      forth: :solus,
      registry_url: @repo_url,
      manifest: manifest,
      tarball_url: download_url,
      checksum: release["sha256"] || pkg["sha256sum"],
      checksum_algo: if(release["sha256"] || pkg["sha256sum"], do: :sha256),
      attestations: [],
      resolved_deps: []
    }
  end

  defp normalize_deps(deps) when is_list(deps) do
    deps
    |> Enum.map(fn
      d when is_map(d) -> {d["name"] || d["package"], d["version"] || "*"}
      d when is_binary(d) -> {d, "*"}
    end)
    |> Map.new()
  end

  defp normalize_deps(_), do: %{}

  defp normalize_license(license) when is_binary(license), do: license
  defp normalize_license(licenses) when is_list(licenses), do: Enum.join(licenses, " AND ")
  defp normalize_license(_), do: nil

  defp extract_packager(pkg) do
    packager = pkg["packager"] || pkg["maintainer"]
    case packager do
      p when is_binary(p) -> [p]
      %{"name" => name} -> [name]
      _ -> []
    end
  end

  @doc """
  Search for packages in the Solus repository.
  """
  def search(query, _opts \\ []) do
    url = "#{@api_url}/packages?search=#{URI.encode(query)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} when is_map(body) ->
        packages = body["packages"] || body["results"] || []
        results = packages
        |> Enum.take(20)
        |> Enum.map(fn pkg ->
          %{
            name: pkg["name"],
            version: pkg["version"],
            description: pkg["description"] || pkg["summary"]
          }
        end)
        {:ok, results}

      {:ok, items} when is_list(items) ->
        results = items
        |> Enum.take(20)
        |> Enum.map(fn pkg ->
          %{
            name: pkg["name"],
            version: pkg["version"],
            description: pkg["description"] || pkg["summary"]
          }
        end)
        {:ok, results}

      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Check if a package exists in the Solus repository.
  """
  def exists?(name) do
    case fetch_package(name) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Get available versions from the package release history.
  """
  def versions(name) do
    url = "#{@api_url}/packages/#{URI.encode(name)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        pkg = body["package"] || body
        history = pkg["history"] || pkg["releases"] || []
        vers = history
               |> Enum.map(fn r -> r["version"] end)
               |> Enum.reject(&is_nil/1)
               |> Enum.uniq()

        # Fall back to single version if no history
        vers = if vers == [] do
          v = pkg["version"]
          if v, do: [v], else: []
        else
          vers
        end

        {:ok, vers}

      {:error, _} = err -> err
    end
  end
end
