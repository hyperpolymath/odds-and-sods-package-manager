# SPDX-License-Identifier: MPL-2.0
defmodule Opsm.Registries.Cpan do
  @moduledoc """
  CPAN (Comprehensive Perl Archive Network) registry API client.
  https://fastapi.metacpan.org/
  Uses the MetaCPAN API to fetch Perl distribution metadata.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://fastapi.metacpan.org/v1"

  @doc """
  Fetch distribution metadata from MetaCPAN.
  """
  def fetch_package(name, version \\ "latest") do
    target_version = if version == "latest" do
      fetch_latest_version(name)
    else
      version
    end

    case target_version do
      nil ->
        {:error, :not_found}

      ver ->
        # Fetch release info
        url = "#{@api_url}/release/#{name}"
        case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
          {:ok, body} ->
            # Verify version matches if specific version requested
            if version != "latest" and Map.get(body, "version") != ver do
              # Try author/name format for specific version
              fetch_specific_version(name, ver)
            else
              deps = extract_dependencies(body)
              {:ok, parse_distribution(name, body, ver, deps)}
            end

          {:error, :not_found} ->
            {:error, :not_found}

          {:error, %{status: 404}} ->
            {:error, :not_found}

          {:error, %{status: status}} ->
            {:error, "MetaCPAN returned status #{status}"}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp fetch_specific_version(name, version) do
    # Try searching for exact version
    search_url = "#{@api_url}/release/_search?q=distribution:#{name}+AND+version:#{version}&size=1"
    case VerifiedHttp.get_json(search_url, receive_timeout: 10_000) do
      {:ok, %{"hits" => %{"hits" => [%{"_source" => body} | _]}}} ->
        deps = extract_dependencies(body)
        {:ok, parse_distribution(name, body, version, deps)}

      _ ->
        {:error, :not_found}
    end
  end

  defp fetch_latest_version(name) do
    url = "#{@api_url}/release/#{name}"
    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"version" => version}} -> version
      _ ->
        # Fallback: get version list
        case versions_internal(name) do
          {:ok, [latest | _]} -> latest
          _ -> nil
        end
    end
  end

  defp extract_dependencies(body) do
    # Extract runtime dependencies from metadata
    # MetaCPAN stores dependencies in the "dependency" field
    body
    |> Map.get("dependency", [])
    |> Enum.filter(fn dep ->
      # Only runtime dependencies, not test/build/configure
      Map.get(dep, "phase") == "runtime" and
      Map.get(dep, "relationship") == "requires"
    end)
    |> Enum.reduce(%{}, fn dep, acc ->
      module = Map.get(dep, "module")
      version = Map.get(dep, "version", "0")
      if module do
        Map.put(acc, module, ">= #{version}")
      else
        acc
      end
    end)
  end

  @doc """
  Search for Perl distributions on CPAN.
  """
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    url = "#{@api_url}/release/_search?q=#{URI.encode(query)}&size=#{limit}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"hits" => %{"hits" => hits}}} ->
        results = Enum.map(hits, fn %{"_source" => release} ->
          %{
            name: Map.get(release, "distribution"),
            version: Map.get(release, "version"),
            description: Map.get(release, "abstract", ""),
            downloads: 0
          }
        end)
        {:ok, results}

      {:error, reason} ->
        {:error, reason}

      _ ->
        {:ok, []}
    end
  end

  @doc """
  Check if a Perl distribution exists on CPAN.
  """
  def exists?(name) do
    url = "#{@api_url}/release/#{name}"

    case VerifiedHttp.get(url, receive_timeout: 5_000) do
      {:ok, _} -> true
      _ -> false
    end
  end

  @doc """
  Get all versions of a Perl distribution.
  """
  def versions(name) do
    versions_internal(name)
  end

  defp versions_internal(name) do
    url = "#{@api_url}/release/_search?q=distribution:#{name}&size=100&fields=version"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"hits" => %{"hits" => hits}}} ->
        versions =
          hits
          |> Enum.map(fn hit ->
            case hit do
              %{"fields" => %{"version" => [version]}} -> version
              %{"_source" => %{"version" => version}} -> version
              _ -> nil
            end
          end)
          |> Enum.filter(&(&1 != nil))
          |> Enum.reverse()

        if versions == [] do
          {:error, :not_found}
        else
          {:ok, versions}
        end

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}

      _ ->
        {:ok, []}
    end
  end

  @doc """
  Get tarball URL for a specific version.
  """
  def tarball_url(name, _version) do
    # Fetch release info to get download URL
    url = "#{@api_url}/release/#{name}"
    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        case Map.get(body, "download_url") do
          nil -> {:error, :no_download_url}
          download_url -> {:ok, download_url}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Parsers

  defp parse_distribution(name, release, version, deps) do
    author = Map.get(release, "author")
    download_url = Map.get(release, "download_url")
    checksum = Map.get(release, "checksum_sha256")

    %ResolvedPackage{
      package: name,
      version: version,
      forth: :cpan,
      registry_url: "https://metacpan.org/release/#{name}",
      tarball_url: download_url,
      checksum: checksum,
      checksum_algo: if(checksum, do: :sha256, else: nil),
      manifest: %ManifestFormat{
        name: name,
        version: version,
        description: Map.get(release, "abstract"),
        license: Map.get(release, "license") |> format_license(),
        homepage: "https://metacpan.org/release/#{name}",
        repository: Map.get(release, "resources.repository.url"),
        authors: if(author, do: [author], else: []),
        keywords: [],
        dependencies: deps,
        dev_dependencies: %{},
        source_forth: :cpan,
        raw_manifest: release
      },
      attestations: [],
      resolved_deps: []
    }
  end

  defp format_license(license) when is_list(license), do: Enum.join(license, ", ")
  defp format_license(license) when is_binary(license), do: license
  defp format_license(_), do: nil
end
