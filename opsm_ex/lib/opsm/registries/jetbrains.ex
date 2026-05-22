# SPDX-License-Identifier: MPL-2.0
defmodule Opsm.Registries.Jetbrains do
  @moduledoc """
  JetBrains Plugin Marketplace registry adapter.
  https://plugins.jetbrains.com/api/
  Queries the JetBrains Plugin Repository API for IDE plugin metadata.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://plugins.jetbrains.com/api"
  @marketplace_url "https://plugins.jetbrains.com"

  @doc """
  Fetch plugin metadata from the JetBrains Plugin Marketplace.
  Name can be a numeric plugin ID or the plugin XML ID string.
  """
  def fetch_package(name, version \\ "latest") do
    url = "#{@api_url}/plugins/#{URI.encode(to_string(name))}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        ver = if version == "latest" do
          extract_latest_version(body)
        else
          version
        end
        {:ok, parse_plugin(name, body, ver)}

      {:error, :not_found} -> {:error, :not_found}
      {:error, %{status: 404}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp extract_latest_version(body) do
    case body["updates"] || body["releases"] do
      [latest | _] -> latest["version"] || "0.0.0"
      _ ->
        case body["version"] do
          nil -> "0.0.0"
          v -> v
        end
    end
  end

  defp parse_plugin(name, body, version) do
    plugin_id = body["id"] || name
    xml_id = body["xmlId"] || body["pluginId"] || to_string(name)

    deps = (body["dependencies"] || [])
           |> Enum.map(fn
             d when is_binary(d) -> {d, "*"}
             d when is_map(d) -> {d["xmlId"] || d["id"] || "", d["version"] || "*"}
             _ -> nil
           end)
           |> Enum.reject(&is_nil/1)
           |> Enum.reject(fn {n, _} -> n == "" end)
           |> Map.new()

    compatible_products = (body["compatibleProducts"] || body["products"] || [])
                          |> Enum.map(fn
                            p when is_binary(p) -> p
                            p when is_map(p) -> p["code"] || p["name"]
                            _ -> nil
                          end)
                          |> Enum.reject(&is_nil/1)

    description = build_description(body, compatible_products)

    manifest = %ManifestFormat{
      name: xml_id,
      version: version || "0.0.0",
      description: description,
      license: body["license"],
      homepage: "#{@marketplace_url}/plugin/#{plugin_id}",
      repository: body["sourceCodeUrl"] || body["urls"] |> extract_source_url(),
      dependencies: deps
    }

    download_url = case body["updates"] || body["releases"] do
      [_latest | _] -> "#{@marketplace_url}/plugin/download?pluginId=#{plugin_id}&version=#{version}"
      _ -> nil
    end

    %ResolvedPackage{
      package: to_string(name),
      version: version || "0.0.0",
      forth: :jetbrains,
      manifest: manifest,
      tarball_url: download_url,
      checksum: nil,
      attestations: [],
    }
  end

  defp build_description(body, compatible_products) do
    base = body["description"] || body["preview"] || body["name"]
    products_str = if compatible_products != [] do
      " (#{Enum.join(compatible_products, ", ")})"
    else
      ""
    end
    "#{base}#{products_str}"
  end

  defp extract_source_url(nil), do: nil
  defp extract_source_url(urls) when is_map(urls), do: urls["sourceCode"] || urls["github"]
  defp extract_source_url(_), do: nil

  @doc """
  Get available versions of a JetBrains plugin.
  """
  def get_versions(name) do
    url = "#{@api_url}/plugins/#{URI.encode(to_string(name))}/updates"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} when is_list(body) ->
        versions_list = body
                        |> Enum.map(fn u -> u["version"] end)
                        |> Enum.reject(&is_nil/1)
                        |> Enum.uniq()
        {:ok, versions_list}

      {:ok, _} ->
        case fetch_package(name) do
          {:ok, pkg} -> {:ok, [pkg.version]}
          {:error, _} = err -> err
        end

      {:error, _} = err -> err
    end
  end

  @doc """
  Search for plugins on the JetBrains Marketplace.
  """
  def search(query, _opts \\ []) do
    url = "#{@api_url}/searchPlugins?search=#{URI.encode(query)}&max=20"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} when is_list(body) ->
        results = body
        |> Enum.take(20)
        |> Enum.map(fn plugin ->
          %{
            name: plugin["xmlId"] || plugin["name"] || to_string(plugin["id"]),
            version: extract_latest_version(plugin),
            description: plugin["preview"] || plugin["name"]
          }
        end)
        {:ok, results}

      {:ok, %{"plugins" => plugins}} when is_list(plugins) ->
        results = plugins
        |> Enum.take(20)
        |> Enum.map(fn plugin ->
          %{
            name: plugin["xmlId"] || plugin["name"] || to_string(plugin["id"]),
            version: nil,
            description: plugin["preview"] || plugin["name"]
          }
        end)
        {:ok, results}

      {:ok, _} -> {:ok, []}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Check if a plugin exists on the JetBrains Marketplace.
  """
  def exists?(name) do
    case fetch_package(name) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Get versions for a plugin.
  """
  def versions(name), do: get_versions(name)
end
