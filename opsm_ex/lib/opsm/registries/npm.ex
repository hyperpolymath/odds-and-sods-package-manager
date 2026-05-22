# SPDX-License-Identifier: MPL-2.0
defmodule Opsm.Registries.Npm do
  @moduledoc """
  NPM Registry API client.
  https://registry.npmjs.org
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @base_url "https://registry.npmjs.org"

  @doc """
  Fetch package metadata from npm registry.
  """
  def fetch_package(name, version \\ "latest") do
    url = if version == "latest" do
      "#{@base_url}/#{URI.encode(name)}/latest"
    else
      "#{@base_url}/#{URI.encode(name)}/#{version}"
    end

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        {:ok, parse_package(body, version)}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, %{status: status}} ->
        {:error, "npm returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Search for packages on npm.
  """
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    url = "#{@base_url}/-/v1/search?text=#{URI.encode(query)}&size=#{limit}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        results = body["objects"] || []
        {:ok, Enum.map(results, &parse_search_result/1)}

      {:error, %{status: status}} ->
        {:error, "npm search returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a package exists.
  """
  def exists?(name) do
    url = "#{@base_url}/#{URI.encode(name)}"

    case VerifiedHttp.get(url, receive_timeout: 5_000) do
      {:ok, _response} -> true
      _ -> false
    end
  end

  @doc """
  Get all versions of a package.
  """
  def versions(name) do
    url = "#{@base_url}/#{URI.encode(name)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        versions = body["versions"] || %{}
        {:ok, Map.keys(versions) |> Enum.sort(&version_compare/2)}

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
    case fetch_package(name, version) do
      {:ok, pkg} -> {:ok, pkg.tarball_url}
      error -> error
    end
  end

  # Parsers

  defp parse_package(json, requested_version) do
    version = json["version"] || requested_version
    dist = json["dist"] || %{}

    %ResolvedPackage{
      package: json["name"],
      version: version,
      forth: :npm,
      registry_url: @base_url,
      tarball_url: dist["tarball"],
      checksum: dist["shasum"],
      checksum_algo: :sha1,
      manifest: %ManifestFormat{
        name: json["name"],
        version: version,
        description: json["description"],
        license: extract_license(json["license"]),
        homepage: json["homepage"],
        repository: extract_repo(json["repository"]),
        authors: extract_authors(json["author"], json["maintainers"]),
        keywords: json["keywords"] || [],
        dependencies: json["dependencies"] || %{},
        dev_dependencies: json["devDependencies"] || %{},
        optional_dependencies: json["optionalDependencies"] || %{},
        peer_dependencies: json["peerDependencies"] || %{},
        bin: json["bin"] || %{},
        scripts: json["scripts"] || %{},
        source_forth: :npm,
        raw_manifest: json
      },
      attestations: [],
      resolved_deps: []
    }
  end

  defp parse_search_result(obj) do
    pkg = obj["package"] || %{}
    %{
      name: pkg["name"],
      version: pkg["version"],
      description: pkg["description"],
      keywords: pkg["keywords"] || [],
      score: obj["score"]["final"] || 0,
      publisher: get_in(pkg, ["publisher", "username"])
    }
  end

  defp extract_license(nil), do: nil
  defp extract_license(license) when is_binary(license), do: license
  defp extract_license(%{"type" => type}), do: type
  defp extract_license(_), do: nil

  defp extract_repo(nil), do: nil
  defp extract_repo(url) when is_binary(url), do: url
  defp extract_repo(%{"url" => url}), do: clean_repo_url(url)
  defp extract_repo(_), do: nil

  defp clean_repo_url(url) do
    url
    |> String.replace(~r/^git\+/, "")
    |> String.replace(~r/\.git$/, "")
  end

  defp extract_authors(author, maintainers) do
    author_list = case author do
      nil -> []
      a when is_binary(a) -> [a]
      %{"name" => name} -> [name]
      _ -> []
    end

    maintainer_list = case maintainers do
      nil -> []
      list when is_list(list) ->
        Enum.map(list, fn
          %{"name" => name} -> name
          name when is_binary(name) -> name
          _ -> nil
        end)
        |> Enum.reject(&is_nil/1)
      _ -> []
    end

    (author_list ++ maintainer_list) |> Enum.uniq()
  end

  defp version_compare(a, b) do
    # Simple semver comparison - newer versions first
    Version.compare(normalize_version(a), normalize_version(b)) == :gt
  rescue
    _ -> a > b
  end

  defp normalize_version(v) do
    v
    |> String.replace(~r/^v/, "")
    |> String.split("-")
    |> List.first()
  end
end
