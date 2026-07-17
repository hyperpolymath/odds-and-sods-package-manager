# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Registries.Pypi do
  @moduledoc """
  PyPI Registry API client.
  https://pypi.org/pypi
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @base_url "https://pypi.org/pypi"

  @doc """
  Fetch package metadata from PyPI.
  """
  def fetch_package(name, version \\ "latest") do
    url =
      if version == "latest" do
        "#{@base_url}/#{URI.encode(name)}/json"
      else
        "#{@base_url}/#{URI.encode(name)}/#{version}/json"
      end

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        {:ok, parse_package(body)}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, %{status: status}} ->
        {:error, "PyPI returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Search for packages on PyPI.
  Note: PyPI deprecated XML-RPC search. Using simple API listing isn't practical.
  Falls back to warehouse search endpoint.
  """
  def search(query, opts \\ []) do
    _limit = Keyword.get(opts, :limit, 20)
    # PyPI doesn't have a proper search API anymore
    # Using the simple index isn't practical for search
    # Return a note about this limitation
    url = "https://pypi.org/search/?q=#{URI.encode(query)}"

    # For now, return a message - in production would scrape or use alternative
    {:ok,
     [
       %{
         name: query,
         description: "Search PyPI directly at #{url}",
         note: "PyPI search API deprecated - use 'pip search' or visit pypi.org"
       }
     ]}
  end

  @doc """
  Check if a package exists.
  """
  def exists?(name) do
    url = "#{@base_url}/#{URI.encode(name)}/json"

    case VerifiedHttp.get(url, receive_timeout: 5_000) do
      {:ok, _response} -> true
      _ -> false
    end
  end

  @doc """
  Get all versions of a package.
  """
  def versions(name) do
    url = "#{@base_url}/#{URI.encode(name)}/json"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        releases = body["releases"] || %{}
        versions = Map.keys(releases) |> Enum.sort(&version_compare/2)
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
  Get tarball/wheel URL for a specific version.
  """
  def tarball_url(name, version) do
    case fetch_package(name, version) do
      {:ok, pkg} -> {:ok, pkg.tarball_url}
      error -> error
    end
  end

  # Parsers

  defp parse_package(json) do
    info = json["info"] || %{}
    urls = json["urls"] || []
    version = info["version"]

    # Prefer wheel, fall back to sdist
    dist =
      Enum.find(urls, fn u -> u["packagetype"] == "bdist_wheel" end) ||
        Enum.find(urls, fn u -> u["packagetype"] == "sdist" end) ||
        List.first(urls)

    tarball = if dist, do: dist["url"], else: nil
    checksum = if dist, do: dist["digests"]["sha256"], else: nil

    %ResolvedPackage{
      package: info["name"],
      version: version,
      forth: :pypi,
      registry_url: "https://pypi.org",
      tarball_url: tarball,
      checksum: checksum,
      checksum_algo: :sha256,
      manifest: %ManifestFormat{
        name: info["name"],
        version: version,
        description: info["summary"],
        license: info["license"],
        homepage: info["home_page"] || info["project_url"],
        repository: extract_repo_url(info["project_urls"]),
        authors: extract_author(info["author"], info["author_email"]),
        keywords: parse_keywords(info["keywords"]),
        dependencies: parse_requires(info["requires_dist"]),
        dev_dependencies: %{},
        source_forth: :pypi,
        raw_manifest: json
      },
      attestations: [],
      resolved_deps: []
    }
  end

  defp extract_repo_url(nil), do: nil

  defp extract_repo_url(urls) when is_map(urls) do
    urls["Source"] || urls["Repository"] || urls["GitHub"] ||
      urls["source"] || urls["repository"] || urls["github"]
  end

  defp extract_repo_url(_), do: nil

  defp extract_author(nil, nil), do: []
  defp extract_author(name, nil), do: [name]
  defp extract_author(nil, email), do: [email]
  defp extract_author(name, email), do: ["#{name} <#{email}>"]

  defp parse_keywords(nil), do: []

  defp parse_keywords(keywords) when is_binary(keywords) do
    keywords
    |> String.split(~r/[,\s]+/)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_keywords(keywords) when is_list(keywords), do: keywords

  defp parse_requires(nil), do: %{}

  defp parse_requires(requires) when is_list(requires) do
    requires
    |> Enum.map(&parse_requirement/1)
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end

  defp parse_requirement(req) do
    # Parse "package (>=1.0)" or "package>=1.0" or "package ; extra == 'dev'"
    case Regex.run(~r/^([a-zA-Z0-9_-]+)\s*(.*)$/, req) do
      [_, name, version_spec] ->
        # Skip extras for now
        if String.contains?(version_spec, "extra ==") do
          nil
        else
          {name, String.trim(version_spec)}
        end

      _ ->
        nil
    end
  end

  defp version_compare(a, b) do
    # Basic version comparison - newer first
    Version.compare(normalize_version(a), normalize_version(b)) == :gt
  rescue
    _ -> a > b
  end

  defp normalize_version(v) do
    v
    # Remove alpha/beta/rc suffixes
    |> String.replace(~r/[a-zA-Z].*$/, "")
    |> String.split(".")
    |> Enum.take(3)
    |> Enum.map(fn part ->
      case Integer.parse(part) do
        {n, _} -> n
        :error -> 0
      end
    end)
    |> then(fn parts ->
      parts ++ List.duplicate(0, 3 - length(parts))
    end)
    |> Enum.join(".")
  end
end
