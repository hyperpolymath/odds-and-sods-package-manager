# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Registries.WingetApi do
  @moduledoc """
  WinGet manifest search adapter.
  https://winget.run/
  Queries the winget.run API for Windows Package Manager manifests,
  providing searchable access to the WinGet community repository
  (microsoft/winget-pkgs).
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://winget.run/api"
  @github_manifest_base "https://raw.githubusercontent.com/microsoft/winget-pkgs/master/manifests"

  @doc """
  Fetch package metadata from winget.run.
  Name should be the package identifier (e.g., "Mozilla.Firefox").
  """
  def fetch_package(name, version \\ "latest") do
    url = "#{@api_url}/pkg/#{URI.encode(name)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        pkg = body["package"] || body
        versions_list = pkg["versions"] || body["versions"] || []

        ver =
          if version == "latest" do
            case versions_list do
              [latest | _] ->
                if is_map(latest), do: latest["version"], else: latest

              _ ->
                pkg["version"] || pkg["latestVersion"] || "0.0.0"
            end
          else
            version
          end

        {:ok, parse_winget(name, pkg, ver)}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_winget(name, pkg, version) do
    # WinGet manifests include installer URLs and hashes
    installers = pkg["installers"] || []
    primary_installer = List.first(installers)

    installer_url =
      if primary_installer do
        primary_installer["url"] || primary_installer["installerUrl"]
      end

    installer_hash =
      if primary_installer do
        primary_installer["sha256"] || primary_installer["installerSha256"]
      end

    manifest = %ManifestFormat{
      name: name,
      version: version || "0.0.0",
      description: pkg["description"] || pkg["shortDescription"],
      license: pkg["license"] || pkg["licenseIdentifier"],
      homepage: pkg["homepage"] || pkg["publisherUrl"],
      repository: pkg["publisherSupportUrl"] || build_manifest_url(name),
      authors: if(pkg["publisher"], do: [pkg["publisher"]], else: []),
      keywords: pkg["tags"] || [],
      dependencies: parse_dependencies(pkg["dependencies"]),
      source_forth: :winget_api,
      raw_manifest: pkg
    }

    %ResolvedPackage{
      package: name,
      version: version || "0.0.0",
      forth: :winget_api,
      registry_url: "https://winget.run",
      manifest: manifest,
      tarball_url: installer_url,
      checksum: installer_hash,
      checksum_algo: if(installer_hash, do: :sha256),
      attestations: [],
      resolved_deps: []
    }
  end

  defp build_manifest_url(name) do
    # WinGet manifests are stored by first letter / Publisher.App / version
    first_letter = String.first(name) |> String.downcase()
    path = String.replace(name, ".", "/")
    "#{@github_manifest_base}/#{first_letter}/#{path}"
  end

  defp parse_dependencies(nil), do: %{}

  defp parse_dependencies(deps) when is_list(deps) do
    deps
    |> Enum.map(fn
      d when is_map(d) -> {d["packageIdentifier"] || d["id"], d["minimumVersion"] || "*"}
      d when is_binary(d) -> {d, "*"}
    end)
    |> Map.new()
  end

  defp parse_dependencies(deps) when is_map(deps), do: deps
  defp parse_dependencies(_), do: %{}

  @doc """
  Search for packages on winget.run.
  """
  def search(query, _opts \\ []) do
    url = "#{@api_url}/search?q=#{URI.encode(query)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, items} when is_list(items) ->
        results =
          items
          |> Enum.take(20)
          |> Enum.map(fn pkg ->
            %{
              name: pkg["id"] || pkg["packageIdentifier"],
              version: pkg["version"],
              description: pkg["description"]
            }
          end)

        {:ok, results}

      {:ok, body} ->
        packages = body["packages"] || body["results"] || []

        results =
          packages
          |> Enum.take(20)
          |> Enum.map(fn pkg ->
            %{
              name: pkg["id"] || pkg["packageIdentifier"] || pkg["name"],
              version: pkg["version"] || pkg["latestVersion"],
              description: pkg["description"] || pkg["shortDescription"]
            }
          end)

        {:ok, results}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a package exists in the WinGet repository.
  """
  def exists?(name) do
    case fetch_package(name) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Get available versions of a WinGet package.
  """
  def versions(name) do
    url = "#{@api_url}/pkg/#{URI.encode(name)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        pkg = body["package"] || body
        versions_list = pkg["versions"] || body["versions"] || []

        vers =
          versions_list
          |> Enum.map(fn
            v when is_map(v) -> v["version"]
            v when is_binary(v) -> v
            _ -> nil
          end)
          |> Enum.reject(&is_nil/1)

        {:ok, vers}

      {:error, _} = err ->
        err
    end
  end
end
