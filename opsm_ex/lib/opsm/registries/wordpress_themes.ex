# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Registries.WordPressThemes do
  @moduledoc """
  WordPress Themes Registry API client.
  https://api.wordpress.org/themes/info/1.2/
  Provides access to the official WordPress theme directory via the
  themes info REST API (JSON format).
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://api.wordpress.org/themes/info/1.2"

  @doc """
  Fetch theme metadata from the WordPress themes API.
  The `name` parameter is the theme slug (e.g., "twentytwentyfour").
  """
  def fetch_package(name, version \\ "latest") do
    url = "#{@api_url}/?action=theme_information&request[slug]=#{URI.encode(name)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"error" => _}} ->
        {:error, :not_found}

      {:ok, body} when is_map(body) ->
        resolved_version =
          if version == "latest" do
            body["version"]
          else
            version
          end

        {:ok, parse_theme(body, resolved_version)}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, %{status: status}} ->
        {:error, "WordPress themes API returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Search for themes on WordPress.org.
  """
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    url =
      "#{@api_url}/?action=query_themes" <>
        "&request[search]=#{URI.encode_www_form(query)}" <>
        "&request[per_page]=#{limit}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"themes" => themes}} when is_list(themes) ->
        results =
          Enum.map(themes, fn theme ->
            %{
              name: theme["slug"] || theme["name"],
              version: theme["version"],
              description: theme["description"]
            }
          end)

        {:ok, results}

      {:ok, _} ->
        {:ok, []}

      {:error, %{status: status}} ->
        {:error, "WordPress themes search returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a WordPress theme exists by slug.
  """
  def exists?(name) do
    url = "#{@api_url}/?action=theme_information&request[slug]=#{URI.encode(name)}"

    case VerifiedHttp.get_json(url, receive_timeout: 5_000) do
      {:ok, %{"error" => _}} -> false
      {:ok, body} when is_map(body) -> Map.has_key?(body, "slug")
      _ -> false
    end
  end

  @doc """
  Get available versions of a WordPress theme.
  The WordPress themes API returns versions as a map of version => download_url.
  """
  def versions(name) do
    url =
      "#{@api_url}/?action=theme_information" <>
        "&request[slug]=#{URI.encode(name)}" <>
        "&request[fields][versions]=1"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"versions" => versions}} when is_map(versions) ->
        sorted =
          versions
          |> Map.keys()
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

  defp parse_theme(json, version) do
    slug = json["slug"] || json["name"]
    download_link = json["download_link"]

    %ResolvedPackage{
      package: slug,
      version: version,
      forth: :wordpress_themes,
      registry_url: "https://wordpress.org/themes/#{slug}/",
      tarball_url: download_link,
      checksum: nil,
      checksum_algo: nil,
      manifest: %ManifestFormat{
        name: slug,
        version: version,
        description: json["description"],
        license: "GPL-2.0-or-later",
        homepage: json["homepage"] || "https://wordpress.org/themes/#{slug}/",
        repository: nil,
        authors: extract_author(json["author"]),
        keywords: extract_tags(json["tags"]),
        dependencies: %{"wordpress" => json["requires"] || ">= 5.0"},
        dev_dependencies: %{},
        source_forth: :wordpress_themes,
        raw_manifest: json
      },
      attestations: [],
      resolved_deps: []
    }
  end

  defp extract_author(nil), do: []
  defp extract_author(author) when is_binary(author), do: [strip_html(author)]

  defp extract_author(author) when is_map(author) do
    case author do
      %{"display_name" => name} -> [name]
      %{"user_nicename" => name} -> [name]
      _ -> []
    end
  end

  defp extract_author(_), do: []

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
    parts =
      v |> String.replace(~r/^v/, "") |> String.split("-") |> List.first() |> String.split(".")

    case length(parts) do
      1 -> Enum.at(parts, 0) <> ".0.0"
      2 -> Enum.join(parts, ".") <> ".0"
      _ -> Enum.join(parts, ".")
    end
  end
end
