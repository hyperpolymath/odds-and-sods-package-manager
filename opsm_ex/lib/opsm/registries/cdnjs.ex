# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Registries.Cdnjs do
  @moduledoc """
  cdnjs Registry API client.
  https://api.cdnjs.com/libraries
  Provides access to the cdnjs open-source CDN library index.
  Libraries are served from cdnjs.cloudflare.com.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://api.cdnjs.com/libraries"

  @doc """
  Fetch library metadata from cdnjs.
  The `name` is the library name (e.g., "jquery", "lodash").
  """
  def fetch_package(name, version \\ "latest") do
    url =
      "#{@api_url}/#{URI.encode(name)}?fields=name,version,description,homepage,repository,license,author,keywords,versions,filename,sri"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"error" => true}} ->
        {:error, :not_found}

      {:ok, %{"name" => _} = body} ->
        resolved_version =
          if version == "latest" do
            body["version"]
          else
            version
          end

        {:ok, parse_library(body, resolved_version)}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, %{status: status}} ->
        {:error, "cdnjs API returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Search for libraries on cdnjs.
  """
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    url =
      "#{@api_url}?search=#{URI.encode_www_form(query)}&fields=name,version,description&limit=#{limit}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"results" => results}} when is_list(results) ->
        entries =
          Enum.map(results, fn lib ->
            %{
              name: lib["name"],
              version: lib["version"],
              description: lib["description"]
            }
          end)

        {:ok, entries}

      {:ok, _} ->
        {:ok, []}

      {:error, %{status: status}} ->
        {:error, "cdnjs search returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a library exists on cdnjs.
  """
  def exists?(name) do
    url = "#{@api_url}/#{URI.encode(name)}?fields=name"

    case VerifiedHttp.get_json(url, receive_timeout: 5_000) do
      {:ok, %{"name" => _}} -> true
      _ -> false
    end
  end

  @doc """
  Get all available versions of a cdnjs library.
  """
  def versions(name) do
    url = "#{@api_url}/#{URI.encode(name)}?fields=versions"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"versions" => versions}} when is_list(versions) ->
        {:ok, Enum.reverse(versions)}

      {:ok, %{"error" => true}} ->
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

  defp parse_library(json, version) do
    lib_name = json["name"]
    filename = json["filename"] || "#{lib_name}.min.js"
    cdn_url = "https://cdnjs.cloudflare.com/ajax/libs/#{lib_name}/#{version}/#{filename}"

    %ResolvedPackage{
      package: lib_name,
      version: version,
      forth: :cdnjs,
      registry_url: "https://cdnjs.com/libraries/#{lib_name}",
      tarball_url: cdn_url,
      checksum: extract_sri(json["sri"], version, filename),
      checksum_algo: :sha256,
      manifest: %ManifestFormat{
        name: lib_name,
        version: version,
        description: json["description"],
        license: json["license"],
        homepage: json["homepage"],
        repository: extract_repo(json["repository"]),
        authors: extract_author(json["author"]),
        keywords: json["keywords"] || [],
        dependencies: %{},
        dev_dependencies: %{},
        source_forth: :cdnjs,
        raw_manifest: json
      },
      attestations: [],
      resolved_deps: []
    }
  end

  defp extract_repo(nil), do: nil
  defp extract_repo(%{"url" => url}), do: clean_git_url(url)
  defp extract_repo(url) when is_binary(url), do: clean_git_url(url)
  defp extract_repo(_), do: nil

  defp clean_git_url(url) do
    url
    |> String.replace(~r/^git\+/, "")
    |> String.replace(~r/\.git$/, "")
  end

  defp extract_author(nil), do: []
  defp extract_author(author) when is_binary(author), do: [author]
  defp extract_author(%{"name" => name}), do: [name]
  defp extract_author(_), do: []

  defp extract_sri(nil, _version, _filename), do: nil

  defp extract_sri(sri_map, version, filename) when is_map(sri_map) do
    case get_in(sri_map, [version, filename]) do
      "sha256-" <> hash -> hash
      _ -> nil
    end
  end

  defp extract_sri(_, _, _), do: nil
end
