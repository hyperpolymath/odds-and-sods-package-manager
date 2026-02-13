# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule Opsm.Registries.Zypper do
  @moduledoc """
  openSUSE Zypper registry adapter.
  https://api.opensuse.org/
  Queries the openSUSE Build Service (OBS) API for package metadata.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://api.opensuse.org"
  @software_url "https://software.opensuse.org"
  @default_project "openSUSE:Tumbleweed"

  @doc """
  Fetch package metadata from the openSUSE Build Service.
  """
  def fetch_package(name, version \\ "latest") do
    project = URI.encode(@default_project)
    url = "#{@api_url}/source/#{project}/#{URI.encode(name)}/_meta"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        ver = if version == "latest",
          do: extract_version(body),
          else: version
        {:ok, build_resolved_package(name, body, ver)}

      {:error, :not_found} -> fetch_from_factory(name, version)
      {:error, %{status: 404}} -> fetch_from_factory(name, version)
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_from_factory(name, version) do
    url = "#{@api_url}/search/published/binary/id?match=@name='#{URI.encode(name)}'"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        binaries = body["binary"] || body["collection"] || []
        case extract_binary_info(binaries, name) do
          nil -> {:error, :not_found}
          info ->
            ver = if version == "latest",
              do: info["version"] || "0.0.0",
              else: version
            {:ok, build_resolved_from_binary(name, info, ver)}
        end

      {:error, :not_found} -> {:error, :not_found}
      {:error, %{status: 404}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp extract_binary_info(binaries, name) when is_list(binaries) do
    Enum.find(binaries, fn b ->
      (b["name"] || b["@name"] || "") == name
    end)
  end

  defp extract_binary_info(binaries, _name) when is_map(binaries), do: binaries
  defp extract_binary_info(_, _), do: nil

  defp extract_version(body) do
    body["version"] || body["ver"] || "0.0.0"
  end

  defp build_resolved_package(name, body, version) do
    manifest = %ManifestFormat{
      name: name,
      version: version || "0.0.0",
      description: body["description"] || body["title"],
      license: body["license"],
      homepage: body["url"] || "#{@software_url}/package/show/#{@default_project}/#{name}",
      repository: "#{@api_url}/source/#{URI.encode(@default_project)}/#{name}",
      dependencies: extract_dependencies(body)
    }

    %ResolvedPackage{
      package: name,
      version: version || "0.0.0",
      forth: :zypper,
      manifest: manifest,
      tarball_url: nil,
      checksum: nil,
      attestations: [],
    }
  end

  defp build_resolved_from_binary(name, info, version) do
    manifest = %ManifestFormat{
      name: name,
      version: version || "0.0.0",
      description: info["description"] || info["summary"],
      license: info["license"],
      homepage: "#{@software_url}/package/show/#{@default_project}/#{name}",
      repository: nil,
      dependencies: %{}
    }

    %ResolvedPackage{
      package: name,
      version: version || "0.0.0",
      forth: :zypper,
      manifest: manifest,
      tarball_url: info["filepath"],
      checksum: nil,
      attestations: [],
    }
  end

  defp extract_dependencies(body) do
    (body["requires"] || body["buildrequires"] || [])
    |> Enum.map(fn d when is_binary(d) -> {d, "*"}; d when is_map(d) -> {d["name"] || "", "*"}; _ -> nil end)
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(fn {n, _} -> n == "" end)
    |> Map.new()
  end

  @doc """
  Get available versions from OBS.
  """
  def get_versions(name) do
    project = URI.encode(@default_project)
    url = "#{@api_url}/source/#{project}/#{URI.encode(name)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        ver = extract_version(body)
        {:ok, [ver]}

      {:error, _} = err -> err
    end
  end

  @doc """
  Search for packages in the openSUSE Build Service.
  """
  def search(query, _opts \\ []) do
    url = "#{@api_url}/search/published/binary/id?match=contains(@name,'#{URI.encode(query)}')"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        binaries = body["binary"] || body["collection"] || []
        results = binaries
        |> List.wrap()
        |> Enum.take(20)
        |> Enum.map(fn b ->
          %{
            name: b["name"] || b["@name"],
            version: b["version"],
            description: b["description"] || b["summary"]
          }
        end)
        {:ok, results}

      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Check if a package exists in the openSUSE repositories.
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
