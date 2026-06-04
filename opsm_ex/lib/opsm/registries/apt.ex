# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Registries.Apt do
  @moduledoc """
  APT/dpkg (Debian/Ubuntu) package registry adapter.
  Queries the Debian Sources/Packages API and Ubuntu Launchpad.
  https://sources.debian.org/api/
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @debian_api "https://sources.debian.org/api"
  # Ubuntu Launchpad API for future use
  # @ubuntu_api "https://api.launchpad.net/1.0/ubuntu/+archive/primary"

  @doc """
  Fetch package metadata from Debian sources API.
  """
  def fetch_package(name, version \\ "latest") do
    url = "#{@debian_api}/src/#{name}/"
    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        versions = body["versions"] || []
        case versions do
          [] -> {:error, :not_found}
          _ ->
            ver = if version == "latest" do
              latest = List.first(versions)
              latest["version"]
            else
              version
            end
            {:ok, parse_debian_package(name, body, ver, versions)}
        end

      {:error, :not_found} -> {:error, :not_found}
      {:error, %{status: 404}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_debian_package(name, _body, version, _versions) do
    manifest = %ManifestFormat{
      name: name,
      version: version || "0.0.0",
      description: nil,
      license: nil,
      homepage: "https://packages.debian.org/#{name}",
      repository: "https://salsa.debian.org/debian/#{name}",
      dependencies: %{}
    }

    %ResolvedPackage{
      package: name,
      version: version || "0.0.0",
      forth: :apt,
      manifest: manifest,
      tarball_url: nil,
      checksum: nil,
      attestations: [],
    }
  end

  @doc """
  Get all available versions from Debian.
  """
  def get_versions(name) do
    url = "#{@debian_api}/src/#{name}/"
    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        versions = (body["versions"] || [])
                   |> Enum.map(fn v -> v["version"] end)
                   |> Enum.reject(&is_nil/1)
        {:ok, versions}

      {:error, _} = err -> err
    end
  end

  @doc """
  Search for packages in Debian.
  """
  def search(query, _opts \\ []) do
    url = "#{@debian_api}/search/#{URI.encode(query)}/"
    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} when is_map(body) ->
        results = (body["results"] || %{})
        |> then(fn r when is_map(r) -> r; _ -> %{} end)
        |> Map.get("exact", %{})
        |> then(fn r when is_map(r) -> r; _ -> %{} end)
        |> Map.get("source", [])
        |> then(fn r when is_list(r) -> r; _ -> [] end)
        |> Enum.take(20)
        |> Enum.map(fn pkg when is_map(pkg) ->
          %{name: pkg["name"], version: nil, description: nil}
        end)
        {:ok, results}

      {:ok, _} ->
        {:ok, []}

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
