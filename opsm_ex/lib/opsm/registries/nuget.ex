# SPDX-License-Identifier: PMPL-1.0
defmodule Opsm.Registries.NuGet do
  @moduledoc """
  NuGet (.NET) Registry API client.
  https://api.nuget.org/v3/index.json
  Uses the NuGet V3 API protocol.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @registration_url "https://api.nuget.org/v3/registration5-gz-semver2"
  @search_url "https://azuresearch-usnc.nuget.org/query"
  @download_base "https://api.nuget.org/v3-flatcontainer"

  @doc """
  Fetch package metadata from NuGet.
  """
  def fetch_package(name, version \\ "latest") do
    lower_name = String.downcase(name)
    url = "#{@registration_url}/#{lower_name}/index.json"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        # Registration pages contain version catalogs
        items = body["items"] || []
        all_entries = items
          |> Enum.flat_map(fn page ->
            # Some pages inline items, others need fetching
            page["items"] || []
          end)

        target_version = if version == "latest" do
          # Find the latest non-prerelease version
          all_entries
          |> Enum.map(fn entry ->
            catalog = entry["catalogEntry"] || %{}
            catalog["version"]
          end)
          |> Enum.reject(&is_nil/1)
          |> Enum.reject(fn v -> String.contains?(v, "-") end)
          |> List.last()
        else
          version
        end

        entry = Enum.find(all_entries, fn e ->
          catalog = e["catalogEntry"] || %{}
          catalog["version"] == target_version
        end)

        catalog = if entry, do: entry["catalogEntry"] || %{}, else: %{}
        deps = extract_nuget_deps(catalog)
        {hash, hash_algo} = extract_nuget_hash(catalog)

        {:ok, parse_nuget_package(name, target_version, catalog, deps, hash, hash_algo)}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, %{status: status}} ->
        {:error, "NuGet returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_nuget_deps(catalog) do
    groups = catalog["dependencyGroups"] || []

    groups
    |> Enum.flat_map(fn group ->
      deps = group["dependencies"] || []
      Enum.map(deps, fn dep ->
        {dep["id"], dep["range"] || ">= 0.0.0"}
      end)
    end)
    |> Enum.uniq_by(fn {name, _} -> String.downcase(name) end)
    |> Map.new()
  end

  @doc """
  Search for packages on NuGet.
  """
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    url = "#{@search_url}?q=#{URI.encode(query)}&take=#{limit}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        data = body["data"] || []
        results = Enum.map(data, fn pkg ->
          %{
            name: pkg["id"],
            version: pkg["version"],
            description: pkg["description"],
            downloads: pkg["totalDownloads"] || 0
          }
        end)
        {:ok, results}

      {:error, %{status: status}} ->
        {:error, "NuGet search returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a package exists on NuGet.
  """
  def exists?(name) do
    lower_name = String.downcase(name)
    url = "#{@registration_url}/#{lower_name}/index.json"

    case VerifiedHttp.get(url, receive_timeout: 5_000) do
      {:ok, _} -> true
      _ -> false
    end
  end

  @doc """
  Get all versions of a package.
  """
  def versions(name) do
    lower_name = String.downcase(name)
    url = "#{@download_base}/#{lower_name}/index.json"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"versions" => versions}} when is_list(versions) ->
        {:ok, Enum.reverse(versions)}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get nupkg URL for a specific version.
  """
  def tarball_url(name, version) do
    lower_name = String.downcase(name)
    lower_version = String.downcase(version)
    {:ok, "#{@download_base}/#{lower_name}/#{lower_version}/#{lower_name}.#{lower_version}.nupkg"}
  end

  defp extract_nuget_hash(catalog) do
    hash = catalog["packageHash"]
    algo_str = catalog["packageHashAlgorithm"]

    if hash do
      # NuGet provides base64-encoded hashes; convert to hex
      hex_hash = case Base.decode64(hash) do
        {:ok, raw} -> Base.encode16(raw, case: :lower)
        :error -> hash
      end

      algo = case algo_str do
        "SHA512" -> :sha512
        "SHA256" -> :sha256
        "SHA1" -> :sha1
        _ -> :sha512
      end

      {hex_hash, algo}
    else
      {nil, nil}
    end
  end

  # Parsers

  defp parse_nuget_package(name, version, catalog, deps, hash, hash_algo) do
    %ResolvedPackage{
      package: name,
      version: version,
      forth: :nuget,
      registry_url: "https://www.nuget.org/packages/#{name}",
      tarball_url: "#{@download_base}/#{String.downcase(name)}/#{String.downcase(version)}/#{String.downcase(name)}.#{String.downcase(version)}.nupkg",
      checksum: hash,
      checksum_algo: hash_algo,
      manifest: %ManifestFormat{
        name: name,
        version: version,
        description: catalog["description"],
        license: catalog["licenseExpression"],
        homepage: catalog["projectUrl"],
        repository: nil,
        authors: parse_authors(catalog["authors"]),
        keywords: catalog["tags"] || [],
        dependencies: deps,
        dev_dependencies: %{},
        source_forth: :nuget,
        raw_manifest: catalog
      },
      attestations: [],
      resolved_deps: []
    }
  end

  defp parse_authors(nil), do: []
  defp parse_authors(authors) when is_binary(authors) do
    String.split(authors, ",") |> Enum.map(&String.trim/1)
  end
  defp parse_authors(authors) when is_list(authors), do: authors
end
