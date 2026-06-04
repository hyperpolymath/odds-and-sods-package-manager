# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Registries.Portage do
  @moduledoc """
  Gentoo Portage registry adapter.
  https://packages.gentoo.org/api/
  Queries the Gentoo Packages API for ebuild metadata.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://packages.gentoo.org"

  @doc """
  Fetch package metadata from the Gentoo Packages API.
  Name can be category/package (e.g., "dezig/python") or just the package name.
  """
  def fetch_package(name, version \\ "latest") do
    {category, pkg_name} = split_atom(name)
    url = "#{@api_url}/packages/#{category}/#{pkg_name}.json"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        ver = if version == "latest" do
          versions_list = body["versions"] || []
          case Enum.find(versions_list, fn v -> v["arch"] == "amd64" end) do
            nil ->
              case versions_list do
                [latest | _] -> latest["version"]
                _ -> "0.0.0"
              end
            stable -> stable["version"]
          end
        else
          version
        end
        {:ok, parse_portage_package(name, body, ver)}

      {:error, :not_found} -> {:error, :not_found}
      {:error, %{status: 404}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp split_atom(name) do
    case String.split(name, "/", parts: 2) do
      [category, pkg] -> {category, pkg}
      [pkg] -> {"*", pkg}
    end
  end

  defp parse_portage_package(name, body, version) do
    deps = (body["dependencies"] || [])
           |> Enum.map(fn d ->
             dep_atom = d["atom"] || d["name"] || ""
             {dep_atom, d["condition"] || "*"}
           end)
           |> Enum.reject(fn {n, _} -> n == "" end)
           |> Map.new()

    manifest = %ManifestFormat{
      name: name,
      version: version || "0.0.0",
      description: body["description"] || body["longdescription"],
      license: body["license"],
      homepage: body["homepage"],
      repository: "https://gitweb.gentoo.org/repo/gentoo.git/tree/#{name}",
      dependencies: deps
    }

    %ResolvedPackage{
      package: name,
      version: version || "0.0.0",
      forth: :portage,
      manifest: manifest,
      tarball_url: nil,
      checksum: nil,
      attestations: [],
    }
  end

  @doc """
  Get all available versions of a Gentoo package.
  """
  def get_versions(name) do
    {category, pkg_name} = split_atom(name)
    url = "#{@api_url}/packages/#{category}/#{pkg_name}.json"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        versions_list = (body["versions"] || [])
                        |> Enum.map(fn v -> v["version"] end)
                        |> Enum.reject(&is_nil/1)
                        |> Enum.uniq()
        {:ok, versions_list}

      {:error, _} = err -> err
    end
  end

  @doc """
  Search for packages on packages.gentoo.org.
  """
  def search(query, _opts \\ []) do
    url = "#{@api_url}/packages/search.json?q=#{URI.encode(query)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} when is_list(body) ->
        results = body
        |> Enum.take(20)
        |> Enum.map(fn pkg ->
          %{
            name: "#{pkg["category"]}/#{pkg["name"]}",
            version: get_in(pkg, ["versions", Access.at(0), "version"]),
            description: pkg["description"]
          }
        end)
        {:ok, results}

      {:ok, %{"results" => results}} when is_list(results) ->
        hits = results
        |> Enum.take(20)
        |> Enum.map(fn pkg ->
          %{
            name: "#{pkg["category"]}/#{pkg["name"]}",
            version: nil,
            description: pkg["description"]
          }
        end)
        {:ok, hits}

      {:ok, _} -> {:ok, []}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Check if a package exists in the Gentoo repository.
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
