# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule Opsm.Registries.VscodeMarketplace do
  @moduledoc """
  Visual Studio Code Marketplace registry adapter.
  https://marketplace.visualstudio.com/_apis/public/gallery
  Queries the VS Marketplace Gallery API for extension metadata.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://marketplace.visualstudio.com/_apis/public/gallery"
  @api_version "7.2-preview.1"

  @doc """
  Fetch extension metadata from the VS Code Marketplace.
  Name should be in publisher.extension format (e.g., "ms-python.python").
  """
  def fetch_package(name, version \\ "latest") do
    {publisher, ext_name} = split_extension_id(name)
    url = "#{@api_url}/publishers/#{URI.encode(publisher)}/extensions/#{URI.encode(ext_name)}?api-version=#{@api_version}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        ver = if version == "latest" do
          versions_list = body["versions"] || []
          case versions_list do
            [latest | _] -> latest["version"]
            _ -> "0.0.0"
          end
        else
          version
        end
        {:ok, parse_extension(name, body, ver)}

      {:error, :not_found} -> {:error, :not_found}
      {:error, %{status: 404}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp split_extension_id(name) do
    case String.split(name, ".", parts: 2) do
      [publisher, ext] -> {publisher, ext}
      [ext] -> {"unknown", ext}
    end
  end

  defp parse_extension(name, body, version) do
    {_publisher, ext_name} = split_extension_id(name)
    display_name = body["displayName"] || ext_name
    description = body["shortDescription"] || body["description"]

    latest_version_data = case body["versions"] do
      [v | _] -> v
      _ -> %{}
    end

    properties = extract_properties(latest_version_data)
    deps = extract_extension_dependencies(properties)

    manifest = %ManifestFormat{
      name: name,
      version: version || "0.0.0",
      description: "#{display_name} - #{description}",
      license: properties["Microsoft.VisualStudio.Services.Links.License"],
      homepage: "https://marketplace.visualstudio.com/items?itemName=#{name}",
      repository: properties["Microsoft.VisualStudio.Services.Links.Source"],
      dependencies: deps
    }

    vsix_url = find_asset_url(latest_version_data, "Microsoft.VisualStudio.Services.VSIXPackage")

    %ResolvedPackage{
      package: name,
      version: version || "0.0.0",
      forth: :vscode,
      manifest: manifest,
      tarball_url: vsix_url,
      checksum: nil,
      attestations: [],
    }
  end

  defp extract_properties(version_data) do
    (version_data["properties"] || [])
    |> Enum.reduce(%{}, fn prop, acc ->
      Map.put(acc, prop["key"], prop["value"])
    end)
  end

  defp extract_extension_dependencies(properties) do
    dep_string = properties["Microsoft.VisualStudio.Code.ExtensionDependencies"] || ""

    dep_string
    |> String.split(",", trim: true)
    |> Enum.map(fn d -> {String.trim(d), "*"} end)
    |> Enum.reject(fn {n, _} -> n == "" end)
    |> Map.new()
  end

  defp find_asset_url(version_data, asset_type) do
    files = version_data["files"] || []
    case Enum.find(files, fn f -> f["assetType"] == asset_type end) do
      nil -> nil
      file -> file["source"]
    end
  end

  @doc """
  Get available versions of a VS Code extension.
  """
  def get_versions(name) do
    {publisher, ext_name} = split_extension_id(name)
    url = "#{@api_url}/publishers/#{URI.encode(publisher)}/extensions/#{URI.encode(ext_name)}?api-version=#{@api_version}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        versions_list = (body["versions"] || [])
                        |> Enum.map(fn v -> v["version"] end)
                        |> Enum.reject(&is_nil/1)
        {:ok, versions_list}

      {:error, _} = err -> err
    end
  end

  @doc """
  Search for extensions on the VS Code Marketplace.
  Uses the gallery extensionQuery API with text filter.
  """
  def search(query, _opts \\ []) do
    _url = "#{@api_url}/extensionquery?api-version=#{@api_version}"

    # The Marketplace uses POST for search queries; fall back to a GET-based search
    search_url = "https://marketplace.visualstudio.com/search?term=#{URI.encode(query)}&target=VSCode&sortBy=Relevance"

    case VerifiedHttp.get_json(search_url, receive_timeout: 10_000) do
      {:ok, body} ->
        extensions = extract_search_results(body)
        {:ok, extensions}

      {:error, _} ->
        # Fallback: direct query
        fallback_url = "#{@api_url}/extensionquery/#{URI.encode(query)}?api-version=#{@api_version}"
        case VerifiedHttp.get_json(fallback_url, receive_timeout: 10_000) do
          {:ok, body} ->
            {:ok, extract_search_results(body)}
          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp extract_search_results(body) do
    results = body["results"] || [body]
    extensions = results
    |> Enum.flat_map(fn r -> r["extensions"] || [] end)
    |> Enum.take(20)
    |> Enum.map(fn ext ->
      publisher_name = get_in(ext, ["publisher", "publisherName"]) || ""
      ext_name = ext["extensionName"] || ext["name"] || ""
      full_name = if publisher_name != "", do: "#{publisher_name}.#{ext_name}", else: ext_name
      %{
        name: full_name,
        version: get_in(ext, ["versions", Access.at(0), "version"]),
        description: ext["shortDescription"] || ext["displayName"]
      }
    end)
    extensions
  end

  @doc """
  Check if an extension exists on the VS Code Marketplace.
  """
  def exists?(name) do
    case fetch_package(name) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Get versions for an extension.
  """
  def versions(name), do: get_versions(name)
end
