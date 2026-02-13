# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule Opsm.Registries.Alire do
  @moduledoc """
  Ada/SPARK Alire registry adapter.
  https://alire.ada.dev/
  Queries the Alire crate index for Ada/SPARK package metadata.

  API endpoints used:
  - GET /crates/:name.json              - Crate metadata
  - GET /crates.json                    - Full crate listing
  - GET /search.json?q=:query           - Search crates

  The Alire index is backed by a GitHub repository
  (alire-project/alire-index). The JSON API at alire.ada.dev provides
  a web-friendly view of the index data.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @base_url "https://alire.ada.dev"
  @index_api "https://raw.githubusercontent.com/alire-project/alire-index/stable/index"

  @doc """
  Fetch crate metadata from the Alire registry.
  Tries the web API first, falls back to the raw GitHub index.
  """
  def fetch_package(name, version \\ "latest") do
    url = "#{@base_url}/crates/#{String.downcase(name)}.json"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        ver = resolve_version(body, version)
        {:ok, build_resolved_package(name, body, ver)}

      {:error, :not_found} ->
        fetch_from_index(name, version)

      {:error, %{status: 404}} ->
        fetch_from_index(name, version)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Search for Ada/SPARK crates matching a query string.
  """
  def search(query, _opts \\ []) do
    url = "#{@base_url}/search.json?q=#{URI.encode_www_form(query)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, results} when is_list(results) ->
        matches =
          results
          |> Enum.take(20)
          |> Enum.map(fn c ->
            %{
              name: c["name"],
              version: c["version"] || c["latest_version"],
              description: c["description"]
            }
          end)

        {:ok, matches}

      {:ok, %{"crates" => crates}} when is_list(crates) ->
        matches =
          crates
          |> Enum.take(20)
          |> Enum.map(fn c ->
            %{
              name: c["name"],
              version: c["version"],
              description: c["description"]
            }
          end)

        {:ok, matches}

      {:ok, _} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a crate exists in the Alire index.
  """
  def exists?(name) do
    case fetch_package(name) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Get all available versions for an Alire crate.
  """
  def versions(name) do
    url = "#{@base_url}/crates/#{String.downcase(name)}.json"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"releases" => releases}} when is_list(releases) ->
        vers = Enum.map(releases, fn r -> r["version"] end) |> Enum.reject(&is_nil/1)
        {:ok, vers}

      {:ok, body} ->
        case body["version"] || body["latest_version"] do
          nil -> {:ok, []}
          v -> {:ok, [v]}
        end

      {:error, :not_found} -> {:error, :not_found}
      {:error, %{status: 404}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp fetch_from_index(name, version) do
    # Alire index uses first two chars of lowercase name as directory prefix
    lower = String.downcase(name)
    prefix = String.slice(lower, 0, 2)
    url = "#{@index_api}/#{prefix}/#{lower}/#{lower}.toml"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        ver = if version == "latest", do: body["version"] || "0.0.0", else: version
        {:ok, build_resolved_package(name, body, ver)}

      {:error, :not_found} -> {:error, :not_found}
      {:error, %{status: 404}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_version(body, "latest") do
    body["version"] || body["latest_version"] || "0.0.0"
  end

  defp resolve_version(_body, version), do: version

  defp build_resolved_package(name, body, version) do
    deps =
      (body["depends-on"] || body["dependencies"] || [])
      |> normalise_deps()

    manifest = %ManifestFormat{
      name: name,
      version: version,
      description: body["description"] || body["long-description"],
      license: extract_license(body),
      homepage: body["website"] || body["homepage"],
      repository: body["origin"] || body["repository"],
      authors: extract_authors(body),
      keywords: body["tags"] || [],
      dependencies: deps,
      source_forth: :alire
    }

    %ResolvedPackage{
      package: name,
      version: version,
      forth: :alire,
      registry_url: "#{@base_url}/crates/#{String.downcase(name)}",
      manifest: manifest,
      tarball_url: body["origin"],
      checksum: nil,
      attestations: []
    }
  end

  defp normalise_deps(deps) when is_list(deps) do
    deps
    |> Enum.map(fn
      %{"crate" => n, "version" => v} -> {n, v}
      %{"name" => n, "version" => v} -> {n, v}
      d when is_binary(d) -> {d, "*"}
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end

  defp normalise_deps(deps) when is_map(deps), do: deps
  defp normalise_deps(_), do: %{}

  defp extract_license(body) do
    case body["licenses"] || body["license"] do
      l when is_binary(l) -> l
      l when is_list(l) -> Enum.join(l, " AND ")
      _ -> nil
    end
  end

  defp extract_authors(body) do
    case body["authors"] || body["maintainers"] || body["maintainers-logins"] do
      a when is_list(a) -> Enum.map(a, &to_string/1)
      a when is_binary(a) -> [a]
      _ -> []
    end
  end
end
