# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule Opsm.Registries.Alpine do
  @moduledoc """
  Alpine Linux (apk) package registry adapter.
  Queries the Alpine package database API.
  https://pkgs.alpinelinux.org/packages
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://pkgs.alpinelinux.org"

  @doc """
  Fetch package metadata from Alpine packages.
  """
  def fetch_package(name, version \\ "latest") do
    url = "#{@api_url}/package/edge/main/x86_64/#{name}"
    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        ver = if version == "latest",
          do: body["version"] || body["pkgver"],
          else: version
        {:ok, parse_alpine_package(name, body, ver)}

      {:error, :not_found} ->
        # Try community repo
        fetch_community(name, version)

      {:error, %{status: 404}} ->
        fetch_community(name, version)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_community(name, version) do
    url = "#{@api_url}/package/edge/community/x86_64/#{name}"
    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        ver = if version == "latest",
          do: body["version"] || body["pkgver"],
          else: version
        {:ok, parse_alpine_package(name, body, ver)}

      {:error, :not_found} -> {:error, :not_found}
      {:error, %{status: 404}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_alpine_package(name, body, version) do
    deps = (body["depends"] || [])
           |> Enum.map(fn d ->
             dep_name = String.replace(d, ~r/[><=].*/, "")
             {dep_name, "*"}
           end)
           |> Map.new()

    manifest = %ManifestFormat{
      name: name,
      version: version || "0.0.0",
      description: body["description"] || body["pkgdesc"],
      license: body["license"],
      homepage: body["url"],
      repository: "https://gitlab.alpinelinux.org/alpine/aports/-/tree/master/main/#{name}",
      dependencies: deps
    }

    %ResolvedPackage{
      package: name,
      version: version || "0.0.0",
      forth: :alpine,
      manifest: manifest,
      tarball_url: nil,
      checksum: nil,
      attestations: [],
    }
  end

  @doc """
  Get versions — Alpine typically has one version per branch.
  """
  def get_versions(name) do
    case fetch_package(name) do
      {:ok, pkg} -> {:ok, [pkg.version]}
      {:error, _} = err -> err
    end
  end

  @doc """
  Search for packages.
  """
  def search(query, _opts \\ []) do
    url = "#{@api_url}/packages?name=#{URI.encode(query)}*&branch=edge&arch=x86_64"
    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} when is_list(body) ->
        results = body
        |> Enum.take(20)
        |> Enum.map(fn p ->
          %{name: p["name"], version: p["version"], description: p["description"]}
        end)
        {:ok, results}

      {:ok, _} -> {:ok, []}
      {:error, reason} -> {:error, reason}
    end
  end

  def exists?(name) do
    case fetch_package(name) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  def versions(name), do: get_versions(name)
end
