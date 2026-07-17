# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Registries.ChefSupermarket do
  @moduledoc """
  Chef Supermarket registry adapter.
  https://supermarket.chef.io/api/v1
  Queries the Chef Supermarket API for cookbook metadata, versions, and search.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://supermarket.chef.io/api/v1"

  @doc """
  Fetch cookbook metadata from Chef Supermarket.
  Returns the specified version or the latest if version is "latest".
  """
  def fetch_package(name, version \\ "latest") do
    url =
      if version == "latest" do
        "#{@api_url}/cookbooks/#{URI.encode(name)}"
      else
        "#{@api_url}/cookbooks/#{URI.encode(name)}/versions/#{URI.encode(version)}"
      end

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        ver = resolve_version(body, version)
        {:ok, parse_cookbook(name, body, ver)}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, %{status: status}} ->
        {:error, "Chef Supermarket returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp resolve_version(body, "latest") do
    get_in(body, ["latest_version"]) ||
      get_in(body, ["version"]) ||
      "0.0.0"
  end

  defp resolve_version(body, requested) do
    body["version"] || requested
  end

  @doc """
  Search for cookbooks on Chef Supermarket.
  Returns a list of matching cookbooks with name, version, and description.
  """
  def search(query, opts \\ []) do
    start = Keyword.get(opts, :start, 0)
    items = Keyword.get(opts, :items, 20)
    url = "#{@api_url}/search?q=#{URI.encode_www_form(query)}&start=#{start}&items=#{items}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"items" => items_list}} when is_list(items_list) ->
        results =
          Enum.map(items_list, fn item ->
            cookbook = item["cookbook"] || %{}

            %{
              name: cookbook["name"] || item["cookbook_name"],
              version: cookbook["latest_version"] || item["cookbook_maintained_version"],
              description: cookbook["description"] || item["cookbook_description"]
            }
          end)

        {:ok, results}

      {:ok, _} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a cookbook exists on Chef Supermarket.
  """
  def exists?(name) do
    url = "#{@api_url}/cookbooks/#{URI.encode(name)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Get all available versions of a cookbook.
  Returns a list of version strings, newest first.
  """
  def versions(name) do
    url = "#{@api_url}/cookbooks/#{URI.encode(name)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"versions" => version_urls}} when is_list(version_urls) ->
        # Chef Supermarket returns version URLs like
        # "https://supermarket.chef.io/api/v1/cookbooks/NAME/versions/1.0.0"
        version_list =
          version_urls
          |> Enum.map(fn url_str ->
            url_str
            |> String.split("/versions/")
            |> List.last()
            |> URI.decode()
          end)

        {:ok, version_list}

      {:ok, _} ->
        {:ok, []}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Internal parsers
  # ---------------------------------------------------------------------------

  defp parse_cookbook(name, body, version) do
    deps = extract_dependencies(body)

    manifest = %ManifestFormat{
      name: name,
      version: version,
      description: body["description"],
      license: body["license"],
      homepage: body["external_url"] || body["source_url"],
      repository: body["source_url"],
      authors: extract_authors(body),
      keywords: body["food_groups"] || [],
      dependencies: deps,
      dev_dependencies: %{},
      source_forth: :chef,
      raw_manifest: body
    }

    tarball = body["file"] || get_in(body, ["latest_version_url"])

    %ResolvedPackage{
      package: name,
      version: version,
      forth: :chef,
      registry_url: "https://supermarket.chef.io/cookbooks/#{name}",
      tarball_url: tarball,
      checksum: nil,
      checksum_algo: :sha256,
      manifest: manifest,
      attestations: [],
      resolved_deps: []
    }
  end

  defp extract_dependencies(body) do
    (body["dependencies"] || %{})
    |> Enum.reduce(%{}, fn {dep_name, constraint}, acc ->
      Map.put(acc, dep_name, constraint || "*")
    end)
  end

  defp extract_authors(body) do
    maintainer = body["maintainer"]
    if maintainer && maintainer != "", do: [maintainer], else: []
  end
end
