# SPDX-License-Identifier: MPL-2.0
defmodule Opsm.Registries.WordPress do
  @moduledoc """
  WordPress Plugins Registry API client.
  https://api.wordpress.org/plugins/info/1.2/
  Provides access to the official WordPress plugin directory via the
  plugins info REST API (JSON format).
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://api.wordpress.org/plugins/info/1.2"

  @doc """
  Fetch plugin metadata from the WordPress plugins API.
  The `name` parameter is the plugin slug (e.g., "akismet", "woocommerce").
  """
  def fetch_package(name, version \\ "latest") do
    url = "#{@api_url}/?action=plugin_information&request[slug]=#{URI.encode(name)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"error" => _}} ->
        {:error, :not_found}

      {:ok, body} when is_map(body) ->
        resolved_version = if version == "latest" do
          body["version"]
        else
          version
        end
        {:ok, parse_plugin(body, resolved_version)}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, %{status: status}} ->
        {:error, "WordPress plugins API returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Search for plugins on WordPress.org.
  """
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    url =
      "#{@api_url}/?action=query_plugins" <>
        "&request[search]=#{URI.encode_www_form(query)}" <>
        "&request[per_page]=#{limit}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"plugins" => plugins}} when is_list(plugins) ->
        results =
          Enum.map(plugins, fn plugin ->
            %{
              name: plugin["slug"] || plugin["name"],
              version: plugin["version"],
              description: plugin["short_description"] || plugin["description"]
            }
          end)

        {:ok, results}

      {:ok, _} ->
        {:ok, []}

      {:error, %{status: status}} ->
        {:error, "WordPress plugins search returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a WordPress plugin exists by slug.
  """
  def exists?(name) do
    url = "#{@api_url}/?action=plugin_information&request[slug]=#{URI.encode(name)}"

    case VerifiedHttp.get_json(url, receive_timeout: 5_000) do
      {:ok, %{"error" => _}} -> false
      {:ok, body} when is_map(body) -> Map.has_key?(body, "slug")
      _ -> false
    end
  end

  @doc """
  Get available versions of a WordPress plugin.
  The WordPress API returns versions as a map of version => download_url.
  """
  def versions(name) do
    url =
      "#{@api_url}/?action=plugin_information" <>
        "&request[slug]=#{URI.encode(name)}" <>
        "&request[fields][versions]=1"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"versions" => versions}} when is_map(versions) ->
        sorted =
          versions
          |> Map.keys()
          |> Enum.reject(&(&1 == "trunk"))
          |> Enum.sort(&version_compare/2)

        {:ok, sorted}

      {:ok, %{"error" => _}} ->
        {:error, :not_found}

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

  defp parse_plugin(json, version) do
    slug = json["slug"] || json["name"]
    download_link = json["download_link"]

    %ResolvedPackage{
      package: slug,
      version: version,
      forth: :wordpress,
      registry_url: "https://wordpress.org/plugins/#{slug}/",
      tarball_url: download_link,
      checksum: nil,
      checksum_algo: nil,
      manifest: %ManifestFormat{
        name: slug,
        version: version,
        description: json["short_description"] || json["description"],
        license: json["license"] || "GPL-2.0-or-later",
        homepage: json["homepage"],
        repository: nil,
        authors: extract_authors(json["author"], json["contributors"]),
        keywords: json["tags"] |> extract_tags(),
        dependencies: %{"wordpress" => json["requires"] || ">= 5.0"},
        dev_dependencies: %{},
        source_forth: :wordpress,
        raw_manifest: json
      },
      attestations: [],
      resolved_deps: []
    }
  end

  defp extract_authors(author, contributors) do
    author_list =
      case author do
        nil -> []
        a when is_binary(a) -> [strip_html(a)]
        _ -> []
      end

    contributor_list =
      case contributors do
        nil ->
          []

        map when is_map(map) ->
          Enum.map(map, fn {username, _info} -> username end)

        _ ->
          []
      end

    (author_list ++ contributor_list) |> Enum.uniq()
  end

  defp strip_html(str) do
    str |> String.replace(~r/<[^>]+>/, "") |> String.trim()
  end

  defp extract_tags(nil), do: []
  defp extract_tags(tags) when is_map(tags), do: Map.values(tags)
  defp extract_tags(tags) when is_list(tags), do: tags
  defp extract_tags(_), do: []

  defp version_compare(a, b) do
    Version.compare(normalize_version(a), normalize_version(b)) == :gt
  rescue
    _ -> a > b
  end

  defp normalize_version(v) do
    v
    |> String.replace(~r/^v/, "")
    |> String.split("-")
    |> List.first()
    |> ensure_three_part()
  end

  defp ensure_three_part(v) do
    parts = String.split(v, ".")

    case length(parts) do
      1 -> v <> ".0.0"
      2 -> v <> ".0"
      _ -> v
    end
  end
end
