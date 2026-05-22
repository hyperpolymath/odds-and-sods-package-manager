# SPDX-License-Identifier: MPL-2.0
defmodule Opsm.Registries.EclipseMarketplace do
  @moduledoc """
  Eclipse Marketplace API client.
  https://marketplace.eclipse.org/api/p/
  Provides access to the Eclipse Marketplace for IDE plugins,
  features, and solutions. Uses the marketplace REST API.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://marketplace.eclipse.org/api/p"
  @search_url "https://marketplace.eclipse.org/api/mpc"

  @doc """
  Fetch plugin metadata from the Eclipse Marketplace.
  The `name` is the listing node name or numeric ID (e.g., "egit", "1234").
  """
  def fetch_package(name, version \\ "latest") do
    url = "#{@api_url}/#{URI.encode(name)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} when is_map(body) ->
        resolved_version = if version == "latest" do
          extract_latest_version(body)
        else
          version
        end
        {:ok, parse_listing(body, resolved_version)}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, %{status: status}} ->
        {:error, "Eclipse Marketplace returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Search for plugins on the Eclipse Marketplace.
  """
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    url = "#{@search_url}/search?query=#{URI.encode_www_form(query)}&max=#{limit}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"nodes" => nodes}} when is_list(nodes) ->
        results =
          Enum.map(nodes, fn node ->
            %{
              name: node["name"] || node["title"],
              version: node["version"] || extract_node_version(node),
              description: node["shortdescription"] || node["teaser"]
            }
          end)

        {:ok, results}

      {:ok, body} when is_list(body) ->
        results =
          body
          |> Enum.take(limit)
          |> Enum.map(fn node ->
            %{
              name: node["name"] || node["title"],
              version: node["version"] || extract_node_version(node),
              description: node["shortdescription"] || node["teaser"]
            }
          end)

        {:ok, results}

      {:ok, _} ->
        {:ok, []}

      {:error, %{status: status}} ->
        {:error, "Eclipse Marketplace search returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a plugin exists on the Eclipse Marketplace.
  """
  def exists?(name) do
    url = "#{@api_url}/#{URI.encode(name)}"

    case VerifiedHttp.get(url, receive_timeout: 5_000) do
      {:ok, _} -> true
      _ -> false
    end
  end

  @doc """
  Get available versions of an Eclipse Marketplace plugin.
  Eclipse plugins typically have one current version with update site URLs.
  Returns version history if available.
  """
  def versions(name) do
    url = "#{@api_url}/#{URI.encode(name)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} when is_map(body) ->
        version_list = extract_version_list(body)

        if version_list == [] do
          case extract_latest_version(body) do
            nil -> {:error, :not_found}
            ver -> {:ok, [ver]}
          end
        else
          {:ok, version_list}
        end

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Parsers
  # ---------------------------------------------------------------------------

  defp parse_listing(json, version) do
    node_name = json["name"] || json["title"]
    update_url = extract_update_url(json)

    %ResolvedPackage{
      package: node_name,
      version: version,
      forth: :eclipse,
      registry_url: json["url"] || "https://marketplace.eclipse.org/content/#{node_name}",
      tarball_url: update_url,
      checksum: nil,
      checksum_algo: nil,
      manifest: %ManifestFormat{
        name: node_name,
        version: version,
        description: json["shortdescription"] || json["teaser"] || json["body"],
        license: extract_license(json),
        homepage: json["homepageurl"] || json["url"],
        repository: json["sourceurl"],
        authors: extract_authors(json),
        keywords: extract_categories(json),
        dependencies: extract_eclipse_deps(json),
        dev_dependencies: %{},
        source_forth: :eclipse,
        raw_manifest: json
      },
      attestations: [],
      resolved_deps: []
    }
  end

  defp extract_latest_version(json) do
    case json do
      %{"version" => ver} when is_binary(ver) and ver != "" ->
        ver

      %{"versions" => [%{"version" => ver} | _]} ->
        ver

      %{"ius" => [%{"version" => ver} | _]} ->
        ver

      _ ->
        nil
    end
  end

  defp extract_node_version(node) do
    case node do
      %{"versions" => [%{"version" => ver} | _]} -> ver
      %{"ius" => [%{"version" => ver} | _]} -> ver
      _ -> nil
    end
  end

  defp extract_version_list(json) do
    case json do
      %{"versions" => versions} when is_list(versions) ->
        Enum.map(versions, fn
          %{"version" => ver} -> ver
          ver when is_binary(ver) -> ver
          _ -> nil
        end)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  defp extract_update_url(json) do
    case json do
      %{"updateurl" => url} when is_binary(url) and url != "" -> url
      %{"ius" => [%{"updateurl" => url} | _]} -> url
      _ -> nil
    end
  end

  defp extract_license(json) do
    case json do
      %{"license" => license} when is_binary(license) -> license
      %{"license" => %{"name" => name}} -> name
      _ -> nil
    end
  end

  defp extract_authors(json) do
    case json do
      %{"owner" => owner} when is_binary(owner) ->
        [owner]

      %{"companies" => [%{"name" => name} | _]} ->
        [name]

      %{"author" => author} when is_binary(author) ->
        [author]

      _ ->
        []
    end
  end

  defp extract_categories(json) do
    case json do
      %{"categories" => cats} when is_list(cats) ->
        Enum.map(cats, fn
          %{"name" => name} -> name
          cat when is_binary(cat) -> cat
          _ -> nil
        end)
        |> Enum.reject(&is_nil/1)

      %{"tags" => tags} when is_list(tags) ->
        tags

      _ ->
        []
    end
  end

  defp extract_eclipse_deps(json) do
    case json do
      %{"platforms" => platforms} when is_list(platforms) ->
        Enum.reduce(platforms, %{}, fn
          %{"name" => name, "version" => ver}, acc -> Map.put(acc, name, ver)
          _, acc -> acc
        end)

      _ ->
        %{}
    end
  end
end
