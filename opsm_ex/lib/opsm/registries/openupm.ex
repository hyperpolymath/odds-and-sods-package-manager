# SPDX-License-Identifier: MPL-2.0
defmodule Opsm.Registries.OpenUpm do
  @moduledoc """
  OpenUPM registry adapter for Unity packages.
  https://openupm.com/
  Uses the OpenUPM npm-compatible registry API at package.openupm.com.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @registry_url "https://package.openupm.com"
  @api_url "https://api.openupm.com"
  @web_url "https://openupm.com"

  @doc """
  Fetch Unity package metadata from OpenUPM.
  OpenUPM follows the npm registry protocol.
  """
  def fetch_package(name, version \\ "latest") do
    url = "#{@registry_url}/#{URI.encode(name)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} when is_map(body) ->
        target_version = if version == "latest" do
          get_in(body, ["dist-tags", "latest"])
        else
          version
        end

        version_data = get_in(body, ["versions", target_version]) || %{}
        deps = extract_deps(version_data)
        {:ok, parse_package(name, body, version_data, target_version, deps)}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, %{status: status}} ->
        {:error, "OpenUPM returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Search for Unity packages on OpenUPM.
  Uses the OpenUPM search API.
  """
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    url = "#{@registry_url}/-/v1/search?text=#{URI.encode_www_form(query)}&size=#{limit}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"objects" => objects}} when is_list(objects) ->
        results = objects
        |> Enum.take(limit)
        |> Enum.map(fn obj ->
          pkg = obj["package"] || %{}
          %{
            name: pkg["name"],
            version: pkg["version"],
            description: pkg["description"] || "",
            downloads: get_in(obj, ["score", "detail", "popularity"]) || 0
          }
        end)
        {:ok, results}

      {:ok, _} ->
        # Fallback: try the OpenUPM API endpoint
        search_via_api(query, limit)

      {:error, %{status: status}} ->
        {:error, "OpenUPM search returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp search_via_api(query, limit) do
    url = "#{@api_url}/packages?q=#{URI.encode_www_form(query)}&limit=#{limit}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, packages} when is_list(packages) ->
        results = packages
        |> Enum.take(limit)
        |> Enum.map(fn pkg ->
          %{
            name: pkg["name"],
            version: pkg["version"] || pkg["ver"],
            description: pkg["description"] || pkg["displayName"] || "",
            downloads: pkg["downloads"] || 0
          }
        end)
        {:ok, results}

      _ ->
        {:ok, []}
    end
  end

  @doc """
  Check if a Unity package exists on OpenUPM.
  """
  def exists?(name) do
    url = "#{@registry_url}/#{URI.encode(name)}"

    case VerifiedHttp.get(url, receive_timeout: 5_000) do
      {:ok, _} -> true
      _ -> false
    end
  end

  @doc """
  Get all versions of a Unity package.
  """
  def versions(name) do
    url = "#{@registry_url}/#{URI.encode(name)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"versions" => versions}} when is_map(versions) ->
        ver_list = versions
        |> Map.keys()
        |> Enum.sort(:desc)
        {:ok, ver_list}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get tarball URL for a Unity package.
  OpenUPM follows npm tarball conventions.
  """
  def tarball_url(name, version) do
    {:ok, "#{@registry_url}/#{name}/-/#{name}-#{version}.tgz"}
  end

  # Parsers

  defp extract_deps(version_data) do
    case version_data do
      %{"dependencies" => deps} when is_map(deps) ->
        Enum.into(deps, %{})

      _ ->
        %{}
    end
  end

  defp parse_package(name, body, version_data, version, deps) do
    description = version_data["description"] || body["description"] || ""
    license = extract_license(version_data["license"] || body["license"])
    homepage = version_data["homepage"] || body["homepage"]
    repository = extract_repository(version_data["repository"] || body["repository"])
    authors = extract_authors(version_data["author"] || body["author"])
    keywords = version_data["keywords"] || body["keywords"] || []

    dist = version_data["dist"] || %{}

    %ResolvedPackage{
      package: name,
      version: version,
      forth: :openupm,
      registry_url: "#{@web_url}/packages/#{name}",
      tarball_url: dist["tarball"] || "#{@registry_url}/#{name}/-/#{name}-#{version}.tgz",
      checksum: dist["shasum"],
      checksum_algo: if(dist["shasum"], do: :sha1, else: nil),
      manifest: %ManifestFormat{
        name: name,
        version: version,
        description: description,
        license: license,
        homepage: homepage,
        repository: repository,
        authors: authors,
        keywords: keywords,
        dependencies: deps,
        dev_dependencies: version_data["devDependencies"] || %{},
        source_forth: :openupm,
        raw_manifest: version_data
      },
      attestations: [],
      resolved_deps: []
    }
  end

  defp extract_license(nil), do: nil
  defp extract_license(license) when is_binary(license), do: license
  defp extract_license(%{"type" => type}), do: type
  defp extract_license(_), do: nil

  defp extract_repository(nil), do: nil
  defp extract_repository(repo) when is_binary(repo), do: repo
  defp extract_repository(%{"url" => url}), do: url
  defp extract_repository(_), do: nil

  defp extract_authors(nil), do: []
  defp extract_authors(author) when is_binary(author), do: [author]
  defp extract_authors(%{"name" => name}), do: [name]
  defp extract_authors(authors) when is_list(authors) do
    Enum.map(authors, fn
      a when is_binary(a) -> a
      %{"name" => n} -> n
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end
  defp extract_authors(_), do: []
end
