# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule Opsm.Registries.JsDelivr do
  @moduledoc """
  jsDelivr CDN and Package API client.
  https://data.jsdelivr.com/v1/
  Provides access to jsDelivr package metadata, version listings,
  and CDN statistics. Supports npm, GitHub, and WordPress packages.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://data.jsdelivr.com/v1"
  @cdn_url "https://cdn.jsdelivr.net"

  @doc """
  Fetch package metadata from jsDelivr.
  The `name` is an npm package name by default (e.g., "lodash").
  Prefix with "gh/" for GitHub repos or "wp/" for WordPress plugins.
  """
  def fetch_package(name, version \\ "latest") do
    {source, pkg_name} = parse_source(name)

    target_version = if version == "latest" do
      fetch_latest_version(source, pkg_name)
    else
      version
    end

    case target_version do
      nil ->
        {:error, :not_found}

      ver ->
        url = "#{@api_url}/package/#{source}/#{pkg_name}@#{ver}"

        case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
          {:ok, body} when is_map(body) ->
            {:ok, parse_package(source, pkg_name, body, ver)}

          {:error, :not_found} ->
            {:error, :not_found}

          {:error, %{status: 404}} ->
            {:error, :not_found}

          {:error, %{status: status}} ->
            {:error, "jsDelivr API returned status #{status}"}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp fetch_latest_version(source, pkg_name) do
    url = "#{@api_url}/package/#{source}/#{pkg_name}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"tags" => %{"latest" => ver}}} -> ver
      {:ok, %{"versions" => [%{"version" => ver} | _]}} -> ver
      {:ok, %{"versions" => [ver | _]}} when is_binary(ver) -> ver
      _ -> nil
    end
  end

  @doc """
  Search for packages via jsDelivr stats.
  Uses the jsDelivr stats API to find popular packages matching the query.
  """
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    # jsDelivr does not have a native search API; proxy through npm search
    # and augment with jsDelivr stats
    url = "https://registry.npmjs.org/-/v1/search?text=#{URI.encode_www_form(query)}&size=#{limit}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"objects" => objects}} when is_list(objects) ->
        results =
          Enum.map(objects, fn obj ->
            pkg = obj["package"] || %{}

            %{
              name: pkg["name"],
              version: pkg["version"],
              description: pkg["description"]
            }
          end)

        {:ok, results}

      {:ok, _} ->
        {:ok, []}

      {:error, %{status: status}} ->
        {:error, "jsDelivr search returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a package exists on jsDelivr.
  """
  def exists?(name) do
    {source, pkg_name} = parse_source(name)
    url = "#{@api_url}/package/#{source}/#{pkg_name}"

    case VerifiedHttp.get(url, receive_timeout: 5_000) do
      {:ok, _} -> true
      _ -> false
    end
  end

  @doc """
  Get all available versions of a package on jsDelivr.
  """
  def versions(name) do
    {source, pkg_name} = parse_source(name)
    url = "#{@api_url}/package/#{source}/#{pkg_name}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"versions" => versions}} when is_list(versions) ->
        version_list =
          Enum.map(versions, fn
            %{"version" => v} -> v
            v when is_binary(v) -> v
            _ -> nil
          end)
          |> Enum.reject(&is_nil/1)

        {:ok, version_list}

      {:ok, %{"tags" => tags}} when is_map(tags) ->
        {:ok, Map.values(tags) |> Enum.uniq()}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Source parsing
  # ---------------------------------------------------------------------------

  defp parse_source("gh/" <> rest), do: {"gh", rest}
  defp parse_source("wp/" <> rest), do: {"wp", rest}
  defp parse_source(name), do: {"npm", name}

  # ---------------------------------------------------------------------------
  # Parsers
  # ---------------------------------------------------------------------------

  defp parse_package(source, pkg_name, json, version) do
    default_file = json["default"] || "/dist/index.min.js"

    %ResolvedPackage{
      package: pkg_name,
      version: version,
      forth: :jsdelivr,
      registry_url: "https://www.jsdelivr.com/package/#{source}/#{pkg_name}",
      tarball_url: "#{@cdn_url}/#{source}/#{pkg_name}@#{version}#{default_file}",
      checksum: nil,
      checksum_algo: nil,
      manifest: %ManifestFormat{
        name: pkg_name,
        version: version,
        description: json["description"],
        license: json["license"],
        homepage: "https://www.jsdelivr.com/package/#{source}/#{pkg_name}",
        repository: json["repository"],
        authors: [],
        keywords: json["keywords"] || [],
        dependencies: %{},
        dev_dependencies: %{},
        source_forth: :jsdelivr,
        raw_manifest: json
      },
      attestations: [],
      resolved_deps: []
    }
  end
end
