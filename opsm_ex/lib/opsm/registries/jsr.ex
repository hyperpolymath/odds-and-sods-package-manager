# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule Opsm.Registries.Jsr do
  @moduledoc """
  JSR (JavaScript Registry) API client for Deno packages.
  https://jsr.io/
  JSR uses scoped packages (e.g., @std/path, @oak/oak).
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://api.jsr.io"
  @registry_url "https://jsr.io"

  @doc """
  Fetch package metadata from JSR.
  Package names are scoped: @scope/name
  """
  def fetch_package(name, version \\ "latest") do
    case parse_scoped_name(name) do
      {:error, reason} ->
        {:error, reason}

      {:ok, {scope, pkg_name}} ->
        target_version = if version == "latest" do
          fetch_latest_version(scope, pkg_name)
        else
          version
        end

        case target_version do
          nil ->
            {:error, :not_found}

          ver ->
            url = "#{@api_url}/scopes/#{scope}/packages/#{pkg_name}/versions/#{ver}"
            case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
              {:ok, body} ->
                {:ok, parse_package(name, scope, pkg_name, body, ver)}

              {:error, :not_found} ->
                {:error, :not_found}

              {:error, %{status: 404}} ->
                {:error, :not_found}

              {:error, %{status: status}} ->
                {:error, "JSR API returned status #{status}"}

              {:error, reason} ->
                {:error, reason}
            end
        end
    end
  end

  defp fetch_latest_version(scope, pkg_name) do
    case versions_internal(scope, pkg_name) do
      {:ok, [latest | _]} -> latest
      _ -> nil
    end
  end

  @doc """
  Search for packages on JSR.
  """
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    url = "#{@api_url}/packages?search=#{URI.encode_www_form(query)}&limit=#{limit}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"items" => items}} when is_list(items) ->
        results = Enum.map(items, fn item ->
          scope = item["scope"]
          name = item["name"]
          full_name = "@#{scope}/#{name}"

          %{
            name: full_name,
            version: item["latestVersion"],
            description: item["description"] || "",
            downloads: item["score"] || 0
          }
        end)
        {:ok, results}

      {:ok, items} when is_list(items) ->
        # Alternative response format
        results = Enum.map(items, fn item ->
          scope = item["scope"]
          name = item["name"]
          full_name = "@#{scope}/#{name}"

          %{
            name: full_name,
            version: item["latestVersion"],
            description: item["description"] || "",
            downloads: item["score"] || 0
          }
        end)
        {:ok, results}

      {:ok, _} ->
        {:ok, []}

      {:error, _} ->
        {:ok, []}
    end
  end

  @doc """
  Check if a package exists on JSR.
  """
  def exists?(name) do
    case parse_scoped_name(name) do
      {:error, _} ->
        false

      {:ok, {scope, pkg_name}} ->
        url = "#{@api_url}/scopes/#{scope}/packages/#{pkg_name}/versions"
        case VerifiedHttp.get(url, receive_timeout: 5_000) do
          {:ok, _} -> true
          _ -> false
        end
    end
  end

  @doc """
  Get all versions of a package.
  """
  def versions(name) do
    case parse_scoped_name(name) do
      {:error, reason} ->
        {:error, reason}

      {:ok, {scope, pkg_name}} ->
        versions_internal(scope, pkg_name)
    end
  end

  defp versions_internal(scope, pkg_name) do
    url = "#{@api_url}/scopes/#{scope}/packages/#{pkg_name}/versions"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"versions" => versions}} when is_list(versions) ->
        # Sort versions in descending order (newest first)
        version_strings = Enum.map(versions, fn v -> v["version"] end)
        {:ok, Enum.reverse(version_strings)}

      {:ok, versions} when is_list(versions) ->
        # Alternative format: array of version strings
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
  Get tarball URL for a specific version.
  JSR uses npm-compatible tarballs.
  """
  def tarball_url(name, version) do
    case parse_scoped_name(name) do
      {:error, reason} ->
        {:error, reason}

      {:ok, {scope, pkg_name}} ->
        # JSR provides tarballs at /scopes/{scope}/packages/{name}/versions/{version}/tarball
        {:ok, "#{@api_url}/scopes/#{scope}/packages/#{pkg_name}/versions/#{version}/tarball"}
    end
  end

  # Parse scoped package name: @scope/name -> {scope, name}
  defp parse_scoped_name("@" <> rest) do
    case String.split(rest, "/", parts: 2) do
      [scope, name] when scope != "" and name != "" ->
        {:ok, {scope, name}}

      _ ->
        {:error, "Invalid scoped package name format. Expected @scope/name"}
    end
  end
  defp parse_scoped_name(_), do: {:error, "JSR packages must be scoped (start with @)"}

  # Parsers

  defp parse_package(full_name, scope, pkg_name, metadata, version) do
    # Extract dependencies from metadata
    deps = case metadata do
      %{"dependencies" => deps_map} when is_map(deps_map) ->
        Map.new(deps_map, fn {dep, ver} -> {dep, ver} end)
      _ ->
        %{}
    end

    # Extract checksum if available
    checksum = case metadata do
      %{"integrity" => integrity} when is_binary(integrity) ->
        parse_integrity_hash(integrity)
      _ ->
        nil
    end

    %ResolvedPackage{
      package: full_name,
      version: version,
      forth: :jsr,
      registry_url: "#{@registry_url}/@#{scope}/#{pkg_name}",
      tarball_url: "#{@api_url}/scopes/#{scope}/packages/#{pkg_name}/versions/#{version}/tarball",
      checksum: checksum,
      checksum_algo: if(checksum, do: :sha256, else: nil),
      manifest: %ManifestFormat{
        name: full_name,
        version: version,
        description: metadata["description"],
        license: metadata["license"],
        homepage: "#{@registry_url}/@#{scope}/#{pkg_name}",
        repository: metadata["repository"],
        authors: parse_authors(metadata),
        keywords: metadata["keywords"] || [],
        dependencies: deps,
        dev_dependencies: %{},
        source_forth: :jsr,
        raw_manifest: metadata
      },
      attestations: [],
      resolved_deps: []
    }
  end

  defp parse_authors(metadata) do
    case metadata do
      %{"author" => author} when is_binary(author) ->
        [author]
      %{"authors" => authors} when is_list(authors) ->
        authors
      _ ->
        []
    end
  end

  # Parse npm-style integrity hash (e.g., "sha256-base64hash")
  # Convert to hex-encoded SHA256
  defp parse_integrity_hash("sha256-" <> b64_hash) do
    b64_clean = String.trim_trailing(b64_hash, "=") |> pad_base64()
    case Base.decode64(b64_clean) do
      {:ok, raw_hash} -> Base.encode16(raw_hash, case: :lower)
      :error -> nil
    end
  end
  defp parse_integrity_hash(_), do: nil

  defp pad_base64(s) do
    case rem(String.length(s), 4) do
      0 -> s
      n -> s <> String.duplicate("=", 4 - n)
    end
  end
end
