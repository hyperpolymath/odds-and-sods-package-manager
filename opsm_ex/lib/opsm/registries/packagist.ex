# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule Opsm.Registries.Packagist do
  @moduledoc """
  Packagist (Composer) registry API client.
  https://packagist.org/
  Uses the Packagist Metadata v2 API for package information.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://repo.packagist.org"
  @search_url "https://packagist.org"

  @doc """
  Fetch package metadata from Packagist.
  """
  def fetch_package(name, version \\ "latest") do
    # Packagist packages use vendor/package format like "symfony/console"
    case String.split(name, "/") do
      [vendor, package] ->
        target_version = if version == "latest" do
          fetch_latest_version(vendor, package)
        else
          version
        end

        case target_version do
          nil ->
            {:error, :not_found}

          ver ->
            # Fetch package metadata
            url = "#{@api_url}/p2/#{vendor}/#{package}.json"
            case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
              {:ok, body} ->
                parse_package(name, body, ver)

              {:error, :not_found} ->
                {:error, :not_found}

              {:error, %{status: 404}} ->
                {:error, :not_found}

              {:error, %{status: status}} ->
                {:error, "Packagist returned status #{status}"}

              {:error, reason} ->
                {:error, reason}
            end
        end

      _ ->
        {:error, "Invalid package name format. Expected vendor/package"}
    end
  end

  defp fetch_latest_version(vendor, package) do
    full_name = "#{vendor}/#{package}"
    url = "#{@api_url}/p2/#{full_name}.json"
    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"packages" => %{^full_name => versions}}} when is_list(versions) ->
        # Packagist v2 returns a list of version objects, newest first
        versions
        |> Enum.map(& &1["version"])
        |> Enum.reject(&is_nil/1)
        |> Enum.reject(&String.contains?(&1, "dev"))
        |> List.first()

      {:ok, body} ->
        case get_all_versions_from_body(body) do
          [] -> nil
          [latest | _] -> latest
        end

      _ ->
        nil
    end
  end

  defp get_all_versions_from_body(%{"packages" => packages}) when is_map(packages) do
    packages
    |> Map.values()
    |> List.first()
    |> case do
      versions when is_list(versions) ->
        versions
        |> Enum.map(& &1["version"])
        |> Enum.reject(&is_nil/1)
        |> Enum.reject(&String.contains?(&1, "dev"))
      _ -> []
    end
  end
  defp get_all_versions_from_body(_), do: []

  @doc """
  Search for packages on Packagist.
  """
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    url = "#{@search_url}/search.json?q=#{URI.encode_www_form(query)}&per_page=#{limit}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"results" => results}} when is_list(results) ->
        packages = Enum.map(results, fn pkg ->
          %{
            name: Map.get(pkg, "name", ""),
            version: Map.get(pkg, "version", "unknown"),
            description: Map.get(pkg, "description", ""),
            downloads: Map.get(pkg, "downloads", 0)
          }
        end)
        {:ok, packages}

      {:ok, _} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a package exists on Packagist.
  """
  def exists?(name) do
    case String.split(name, "/") do
      [vendor, package] ->
        url = "#{@api_url}/p2/#{vendor}/#{package}.json"

        case VerifiedHttp.get(url, receive_timeout: 5_000) do
          {:ok, _} -> true
          _ -> false
        end

      _ ->
        false
    end
  end

  @doc """
  Get all versions of a package.
  """
  def versions(name) do
    case String.split(name, "/") do
      [vendor, package] ->
        url = "#{@api_url}/p2/#{vendor}/#{package}.json"

        case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
          {:ok, body} ->
            versions = get_all_versions_from_body(body)
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
        end

      _ ->
        {:error, "Invalid package name format. Expected vendor/package"}
    end
  end

  @doc """
  Get tarball URL for a specific version.
  """
  def tarball_url(name, version) do
    # Packagist doesn't provide direct tarball URLs in the v2 API
    # The dist URL is included in the package metadata
    case String.split(name, "/") do
      [vendor, package] ->
        url = "#{@api_url}/p2/#{vendor}/#{package}.json"
        case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
          {:ok, body} ->
            extract_dist_url(body, name, version)

          _ ->
            {:error, :not_found}
        end

      _ ->
        {:error, "Invalid package name format"}
    end
  end

  defp extract_dist_url(%{"packages" => packages}, name, version) when is_map(packages) do
    case Map.get(packages, name) do
      versions when is_list(versions) ->
        case Enum.find(versions, fn v -> v["version"] == version end) do
          %{"dist" => %{"url" => url}} -> {:ok, url}
          _ -> {:error, :not_found}
        end
      _ -> {:error, :not_found}
    end
  end
  defp extract_dist_url(_, _, _), do: {:error, :not_found}

  # Parsers

  defp parse_package(name, body, version) do
    case extract_version_data(body, name, version) do
      {:ok, version_data} ->
        deps = parse_composer_deps(version_data)
        {dist_url, checksum} = extract_dist_info(version_data)

        {:ok, %ResolvedPackage{
          package: name,
          version: version,
          forth: :packagist,
          registry_url: "#{@search_url}/packages/#{name}",
          tarball_url: dist_url,
          checksum: checksum,
          checksum_algo: if(checksum, do: :sha256, else: nil),
          manifest: %ManifestFormat{
            name: name,
            version: version,
            description: Map.get(version_data, "description"),
            license: parse_license(Map.get(version_data, "license")),
            homepage: Map.get(version_data, "homepage"),
            repository: extract_repo_url(version_data),
            authors: parse_authors(Map.get(version_data, "authors", [])),
            keywords: Map.get(version_data, "keywords", []),
            dependencies: deps,
            dev_dependencies: %{},
            source_forth: :packagist,
            raw_manifest: version_data
          },
          attestations: [],
          resolved_deps: []
        }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_version_data(%{"packages" => packages}, name, version) when is_map(packages) do
    case Map.get(packages, name) do
      versions when is_list(versions) ->
        case Enum.find(versions, fn v -> v["version"] == version end) do
          nil -> {:error, :version_not_found}
          version_data -> {:ok, version_data}
        end
      _ -> {:error, :not_found}
    end
  end
  defp extract_version_data(_, _, _), do: {:error, :invalid_response}

  defp parse_composer_deps(%{"require" => require}) when is_map(require) do
    require
    |> Enum.reject(fn {pkg, _} -> pkg == "php" or String.starts_with?(pkg, "ext-") end)
    |> Enum.into(%{})
  end
  defp parse_composer_deps(_), do: %{}

  defp extract_dist_info(%{"dist" => %{"url" => url, "shasum" => shasum}}) do
    {url, shasum}
  end
  defp extract_dist_info(%{"dist" => %{"url" => url}}) do
    {url, nil}
  end
  defp extract_dist_info(_), do: {nil, nil}

  defp parse_license(nil), do: nil
  defp parse_license([license | _]) when is_binary(license), do: license
  defp parse_license(license) when is_binary(license), do: license
  defp parse_license(_), do: nil

  defp parse_authors(authors) when is_list(authors) do
    Enum.map(authors, fn
      %{"name" => name, "email" => email} -> "#{name} <#{email}>"
      %{"name" => name} -> name
      _ -> "Unknown"
    end)
  end
  defp parse_authors(_), do: []

  defp extract_repo_url(%{"source" => %{"url" => url}}), do: url
  defp extract_repo_url(_), do: nil
end
