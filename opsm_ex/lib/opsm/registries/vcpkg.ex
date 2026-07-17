# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Registries.Vcpkg do
  @moduledoc """
  vcpkg registry adapter for C/C++ packages (Microsoft).
  https://vcpkg.io
  Uses the vcpkg.io API for package metadata.
  """

  alias Opsm.Types.{ResolvedPackage, ManifestFormat}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://vcpkg.io/output/packages"
  @web_url "https://vcpkg.io/en/package"

  def fetch_package(name, version \\ "latest") do
    url = "#{@api_url}/#{URI.encode(name)}.json"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        ver =
          if version == "latest" do
            body["Version"] || body["Version-semver"] || body["Version-string"] || "0.0.0"
          else
            version
          end

        deps = extract_deps(body)

        {:ok,
         %ResolvedPackage{
           package: name,
           version: ver,
           forth: :vcpkg,
           registry_url: "#{@web_url}/#{name}",
           tarball_url: nil,
           checksum: nil,
           checksum_algo: nil,
           manifest: %ManifestFormat{
             name: name,
             version: ver,
             description: body["Description"],
             license: body["License"],
             homepage: body["Homepage"],
             repository: nil,
             authors: [],
             keywords: [],
             dependencies: deps,
             dev_dependencies: %{},
             source_forth: :vcpkg,
             raw_manifest: body
           },
           attestations: [],
           resolved_deps: []
         }}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def search(query, _opts \\ []) do
    # vcpkg.io doesn't have a search API — check if package exists
    case fetch_package(query) do
      {:ok, pkg} ->
        {:ok, [%{name: pkg.package, version: pkg.version, description: nil, downloads: 0}]}

      _ ->
        {:ok, []}
    end
  end

  def exists?(name) do
    url = "#{@api_url}/#{URI.encode(name)}.json"

    case VerifiedHttp.get(url, receive_timeout: 5_000) do
      {:ok, _} -> true
      _ -> false
    end
  end

  def versions(name) do
    # vcpkg typically has one version per package in the registry
    case fetch_package(name) do
      {:ok, pkg} -> {:ok, [pkg.version]}
      _ -> {:error, :not_found}
    end
  end

  def tarball_url(_name, _version), do: {:ok, nil}

  defp extract_deps(body) do
    deps = body["Dependencies"] || []

    Enum.into(deps, %{}, fn
      dep when is_binary(dep) -> {dep, "*"}
      dep when is_map(dep) -> {dep["name"] || "", dep["version>="] || "*"}
      _ -> {"", "*"}
    end)
    |> Map.delete("")
  end
end
