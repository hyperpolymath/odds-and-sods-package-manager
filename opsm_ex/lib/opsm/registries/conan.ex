# SPDX-License-Identifier: MPL-2.0
defmodule Opsm.Registries.Conan do
  @moduledoc """
  Conan Center Index adapter for C/C++ packages.
  https://conan.io/center
  Uses the Conan Center REST API.
  """

  alias Opsm.Types.{ResolvedPackage, ManifestFormat}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://center2.conan.io/v2/conans"
  @web_url "https://conan.io/center/recipes"

  def fetch_package(name, version \\ "latest") do
    target_version = if version == "latest" do
      case versions(name) do
        {:ok, [latest | _]} -> latest
        _ -> nil
      end
    else
      version
    end

    case target_version do
      nil -> {:error, :not_found}
      ver ->
        {:ok, %ResolvedPackage{
          package: name,
          version: ver,
          forth: :conan,
          registry_url: "#{@web_url}/#{name}",
          tarball_url: nil,
          checksum: nil,
          checksum_algo: nil,
          manifest: %ManifestFormat{
            name: name,
            version: ver,
            description: nil,
            license: nil,
            homepage: "#{@web_url}/#{name}",
            repository: nil,
            authors: [],
            keywords: [],
            dependencies: %{},
            dev_dependencies: %{},
            source_forth: :conan,
            raw_manifest: %{}
          },
          attestations: [],
          resolved_deps: []
        }}
    end
  end

  def search(query, _opts \\ []) do
    url = "https://center2.conan.io/v2/conans/search?q=#{URI.encode(query)}"
    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"results" => results}} when is_list(results) ->
        packages = Enum.map(results, fn ref ->
          name = ref |> String.split("/") |> List.first()
          %{name: name, version: nil, description: "Conan C/C++ package", downloads: 0}
        end)
        {:ok, packages}
      _ -> {:ok, []}
    end
  end

  def exists?(name) do
    case versions(name) do
      {:ok, [_ | _]} -> true
      _ -> false
    end
  end

  def versions(name) do
    url = "#{@api_url}/#{URI.encode(name)}/search"
    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"results" => results}} when is_list(results) ->
        versions = results
          |> Enum.map(fn ref ->
            ref |> String.split("/") |> Enum.at(1)
          end)
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq()
          |> Enum.reverse()
        {:ok, versions}
      _ -> {:ok, []}
    end
  end

  def tarball_url(_name, _version), do: {:ok, nil}
end
