# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule Opsm.Registries.Rpm do
  @moduledoc """
  RPM/DNF (Fedora/RHEL) package registry adapter.
  Queries the Fedora Bodhi and MDAPI endpoints.
  https://bodhi.fedoraproject.org/docs/
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @bodhi_api "https://bodhi.fedoraproject.org"
  @mdapi "https://mdapi.fedoraproject.org"

  @doc """
  Fetch package metadata from Fedora MDAPI.
  """
  def fetch_package(name, version \\ "latest") do
    url = "#{@mdapi}/rawhide/pkg/#{name}"
    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        ver = if version == "latest",
          do: "#{body["version"]}-#{body["release"]}",
          else: version
        {:ok, parse_rpm_package(name, body, ver)}

      {:error, :not_found} -> {:error, :not_found}
      {:error, %{status: 404}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_rpm_package(name, body, version) do
    requires = (body["requires"] || [])
               |> Enum.filter(&is_map/1)
               |> Enum.map(fn r -> {r["name"] || "", "*"} end)
               |> Enum.reject(fn {n, _} -> n == "" end)
               |> Map.new()

    manifest = %ManifestFormat{
      name: name,
      version: version || "0.0.0",
      description: body["summary"] || body["description"],
      license: body["rpm_license"],
      homepage: body["url"],
      repository: "https://src.fedoraproject.org/rpms/#{name}",
      dependencies: requires
    }

    %ResolvedPackage{
      package: name,
      version: version || "0.0.0",
      forth: :rpm,
      manifest: manifest,
      tarball_url: nil,
      checksum: nil,
      attestations: [],
    }
  end

  @doc """
  Get versions from Bodhi updates.
  """
  def get_versions(name) do
    url = "#{@bodhi_api}/updates/?packages=#{name}&rows_per_page=20"
    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        versions = (body["updates"] || [])
                   |> Enum.flat_map(fn u ->
                     (u["builds"] || [])
                     |> Enum.map(fn b -> b["nvr"] end)
                   end)
                   |> Enum.reject(&is_nil/1)
        {:ok, versions}

      {:error, _} = err -> err
    end
  end

  @doc """
  Search for packages.
  """
  def search(query, _opts \\ []) do
    url = "#{@mdapi}/rawhide/srcpkg/#{URI.encode(query)}"
    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} when is_list(body) ->
        results = body
        |> Enum.take(20)
        |> Enum.map(fn pkg ->
          %{name: pkg["name"], version: pkg["version"], description: pkg["summary"]}
        end)
        {:ok, results}

      {:ok, body} when is_map(body) ->
        {:ok, [%{name: body["name"], version: body["version"], description: body["summary"]}]}

      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Check if a package exists.
  """
  def exists?(name) do
    case fetch_package(name) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Get versions.
  """
  def versions(name), do: get_versions(name)
end
