# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Registries.Guix do
  @moduledoc """
  GNU Guix package registry adapter.
  https://guix.gnu.org/packages/
  Queries the Guix Data Service API.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://data.guix.gnu.org/api/v1"

  @doc """
  Fetch package metadata from the Guix Data Service.
  """
  def fetch_package(name, version \\ "latest") do
    url = "#{@api_url}/packages?name=#{URI.encode(name)}"
    case VerifiedHttp.get_json(url, receive_timeout: 15_000) do
      {:ok, body} when is_list(body) ->
        case body do
          [] -> {:error, :not_found}
          packages ->
            pkg = if version == "latest" do
              List.first(packages)
            else
              Enum.find(packages, fn p -> p["version"] == version end) ||
              List.first(packages)
            end
            ver = if version == "latest", do: pkg["version"], else: version
            {:ok, parse_guix_package(name, pkg, ver)}
        end

      {:ok, %{"error" => _}} -> {:error, :not_found}
      {:error, :not_found} -> {:error, :not_found}
      {:error, %{status: 404}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_guix_package(name, pkg, version) do
    manifest = %ManifestFormat{
      name: name,
      version: version || "0.0.0",
      description: pkg["description"] || pkg["synopsis"],
      license: pkg["license"],
      homepage: pkg["home-page"] || pkg["homepage"],
      repository: "https://git.savannah.gnu.org/cgit/guix.git",
      dependencies: %{}
    }

    %ResolvedPackage{
      package: name,
      version: version || "0.0.0",
      forth: :guix,
      manifest: manifest,
      tarball_url: nil,
      checksum: nil,
      attestations: [],
    }
  end

  @doc """
  Get available versions.
  """
  def get_versions(name) do
    url = "#{@api_url}/packages?name=#{URI.encode(name)}"
    case VerifiedHttp.get_json(url, receive_timeout: 15_000) do
      {:ok, body} when is_list(body) ->
        versions = body
        |> Enum.map(fn p -> p["version"] end)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
        {:ok, versions}

      {:error, _} = err -> err
    end
  end

  @doc """
  Search for packages.
  """
  def search(query, _opts \\ []) do
    url = "#{@api_url}/packages?search=#{URI.encode(query)}"
    case VerifiedHttp.get_json(url, receive_timeout: 15_000) do
      {:ok, body} when is_list(body) ->
        results = body
        |> Enum.take(20)
        |> Enum.map(fn p ->
          %{name: p["name"], version: p["version"], description: p["synopsis"]}
        end)
        {:ok, results}

      {:ok, _} -> {:ok, []}
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
