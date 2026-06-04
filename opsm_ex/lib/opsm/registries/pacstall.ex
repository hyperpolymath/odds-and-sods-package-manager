# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Registries.Pacstall do
  @moduledoc """
  Pacstall registry adapter.
  https://pacstall.dev/
  Queries the Pacstall API for Ubuntu community-maintained packages
  (pacscripts) that compile from source or install prebuilt binaries.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://pacstall.dev/api"
  @github_raw "https://raw.githubusercontent.com/pacstall/pacstall-programs/master/packages"

  @doc """
  Fetch package metadata from Pacstall.
  """
  def fetch_package(name, version \\ "latest") do
    url = "#{@api_url}/packages/#{URI.encode(name)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        ver = if version == "latest" do
          body["version"] || body["latestVersion"] || "0.0.0"
        else
          version
        end

        {:ok, parse_pacstall(name, body, ver)}

      {:error, :not_found} -> {:error, :not_found}
      {:error, %{status: 404}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_pacstall(name, body, version) do
    # Pacstall packages declare dependencies as space-separated strings
    raw_deps = body["dependencies"] || body["depends"] || []
    deps = case raw_deps do
      d when is_binary(d) ->
        d |> String.split() |> Enum.map(fn dep -> {dep, "*"} end) |> Map.new()
      d when is_list(d) ->
        d |> Enum.map(fn dep -> {dep, "*"} end) |> Map.new()
      _ -> %{}
    end

    manifest = %ManifestFormat{
      name: name,
      version: version,
      description: body["description"] || body["pkgdesc"],
      license: body["license"],
      homepage: body["url"] || body["homepage"],
      repository: "#{@github_raw}/#{name}",
      keywords: body["repology"] || [],
      dependencies: deps,
      source_forth: :pacstall,
      raw_manifest: body
    }

    # Pacstall packages are built from source via pacscripts
    source_url = body["source"] || body["url"]

    %ResolvedPackage{
      package: name,
      version: version,
      forth: :pacstall,
      registry_url: "https://pacstall.dev",
      manifest: manifest,
      tarball_url: source_url,
      checksum: body["hash"] || body["sha256"],
      checksum_algo: if(body["hash"] || body["sha256"], do: :sha256),
      attestations: [],
      resolved_deps: []
    }
  end

  @doc """
  Search for packages in the Pacstall repository.
  """
  def search(query, _opts \\ []) do
    url = "#{@api_url}/packages?search=#{URI.encode(query)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} when is_list(body) ->
        results = body
        |> Enum.take(20)
        |> Enum.map(fn pkg ->
          %{
            name: pkg["name"] || pkg["packageName"],
            version: pkg["version"] || pkg["latestVersion"],
            description: pkg["description"] || pkg["pkgdesc"]
          }
        end)
        {:ok, results}

      {:ok, %{"packages" => packages}} when is_list(packages) ->
        results = packages
        |> Enum.take(20)
        |> Enum.map(fn pkg ->
          %{
            name: pkg["name"] || pkg["packageName"],
            version: pkg["version"] || pkg["latestVersion"],
            description: pkg["description"] || pkg["pkgdesc"]
          }
        end)
        {:ok, results}

      {:ok, _} -> {:ok, []}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Check if a package exists in the Pacstall repository.
  """
  def exists?(name) do
    case fetch_package(name) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Get available versions of a Pacstall package.
  Pacstall typically has one version per pacscript.
  """
  def versions(name) do
    case fetch_package(name) do
      {:ok, pkg} -> {:ok, [pkg.version]}
      {:error, _} = err -> err
    end
  end
end
