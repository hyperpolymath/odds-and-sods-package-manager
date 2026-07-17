# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Registries.RubyGems do
  @moduledoc """
  RubyGems.org Registry API client.
  https://guides.rubygems.org/rubygems-org-api/
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @base_url "https://rubygems.org/api/v1"
  @v2_url "https://rubygems.org/api/v2/rubygems"

  @doc """
  Fetch gem metadata from rubygems.org.
  """
  def fetch_package(name, version \\ "latest") do
    url = "#{@base_url}/gems/#{URI.encode(name)}.json"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        target_version =
          if version == "latest" do
            body["version"]
          else
            version
          end

        deps = fetch_release_deps(name, target_version)
        {:ok, parse_gem(body, target_version, deps)}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, %{status: status}} ->
        {:error, "rubygems.org returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_release_deps(name, version) do
    # Use v2 API which includes full dependency data per version
    url = "#{@v2_url}/#{URI.encode(name)}/versions/#{version}.json"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"dependencies" => %{"runtime" => runtime_deps}}} when is_list(runtime_deps) ->
        runtime_deps
        |> Enum.map(fn d -> {d["name"], d["requirements"] || ">= 0"} end)
        |> Map.new()

      {:ok, %{"dependencies" => deps}} when is_map(deps) ->
        runtime = deps["runtime"] || []

        runtime
        |> Enum.map(fn d -> {d["name"], d["requirements"] || ">= 0"} end)
        |> Map.new()

      _ ->
        %{}
    end
  end

  @doc """
  Search for gems on rubygems.org.
  """
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    url = "#{@base_url}/search.json?query=#{URI.encode(query)}&page=1"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} when is_list(body) ->
        results =
          body
          |> Enum.take(limit)
          |> Enum.map(&parse_search_result/1)

        {:ok, results}

      {:ok, _} ->
        {:ok, []}

      {:error, %{status: status}} ->
        {:error, "rubygems.org search returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a gem exists.
  """
  def exists?(name) do
    url = "#{@base_url}/gems/#{URI.encode(name)}.json"

    case VerifiedHttp.get(url, receive_timeout: 5_000) do
      {:ok, _} -> true
      _ -> false
    end
  end

  @doc """
  Get all versions of a gem.
  """
  def versions(name) do
    url = "#{@base_url}/versions/#{URI.encode(name)}.json"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} when is_list(body) ->
        versions =
          body
          |> Enum.map(& &1["number"])
          |> Enum.reject(&is_nil/1)

        {:ok, versions}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get tarball URL for a specific version.
  """
  def tarball_url(name, version) do
    {:ok, "https://rubygems.org/gems/#{name}-#{version}.gem"}
  end

  # Parsers

  defp parse_gem(gem, version, deps) do
    licenses = gem["licenses"] || []
    license_str = if licenses == [], do: nil, else: Enum.join(licenses, " OR ")

    %ResolvedPackage{
      package: gem["name"],
      version: version,
      forth: :gem,
      registry_url: "https://rubygems.org",
      tarball_url: "https://rubygems.org/gems/#{gem["name"]}-#{version}.gem",
      checksum: gem["sha"],
      checksum_algo: :sha256,
      manifest: %ManifestFormat{
        name: gem["name"],
        version: version,
        description: gem["info"],
        license: license_str,
        homepage: gem["homepage_uri"],
        repository: gem["source_code_uri"],
        authors: parse_authors(gem["authors"]),
        keywords: [],
        dependencies: deps,
        dev_dependencies: %{},
        source_forth: :gem,
        raw_manifest: gem
      },
      attestations: [],
      resolved_deps: []
    }
  end

  defp parse_search_result(gem) do
    %{
      name: gem["name"],
      version: gem["version"],
      description: gem["info"],
      downloads: gem["downloads"]
    }
  end

  defp parse_authors(nil), do: []

  defp parse_authors(authors) when is_binary(authors) do
    String.split(authors, ",") |> Enum.map(&String.trim/1)
  end

  defp parse_authors(authors) when is_list(authors), do: authors
end
