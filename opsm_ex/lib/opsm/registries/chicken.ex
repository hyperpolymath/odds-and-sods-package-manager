# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule Opsm.Registries.Chicken do
  @moduledoc """
  CHICKEN Scheme egg registry adapter.
  https://eggs.call-cc.org/
  Queries the CHICKEN egg repository for Scheme extension metadata.

  API endpoints used:
  - GET /5/:name.json                   - Egg metadata (CHICKEN 5)
  - GET /5/                             - Egg listing (HTML, parsed)
  - GET /5/:name/tags                   - Available versions/tags

  CHICKEN Scheme eggs are hosted at eggs.call-cc.org. The registry does not
  expose a formal JSON API; this adapter targets known endpoints and the
  henrietta egg server. For version listings, the adapter queries the
  egg's release-info file from the svn/git repository.

  Alternate data source: https://api.call-cc.org/5/egg/:name (wiki API).
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @base_url "https://eggs.call-cc.org/5"
  @wiki_api "https://api.call-cc.org/5"

  @doc """
  Fetch egg metadata from the CHICKEN registry.
  """
  def fetch_package(name, version \\ "latest") do
    url = "#{@wiki_api}/egg/#{URI.encode(name)}.json"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        ver = resolve_version(body, version)
        {:ok, build_resolved_package(name, body, ver)}

      {:error, :not_found} ->
        fetch_from_eggs_server(name, version)

      {:error, %{status: 404}} ->
        fetch_from_eggs_server(name, version)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Search for CHICKEN eggs matching a query string.
  Uses the wiki API egg listing endpoint.
  """
  def search(query, _opts \\ []) do
    url = "#{@wiki_api}/egg.json"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, eggs} when is_list(eggs) ->
        q_down = String.downcase(query)

        matches =
          eggs
          |> Enum.filter(fn egg ->
            name = String.downcase(egg["name"] || "")
            desc = String.downcase(egg["synopsis"] || egg["description"] || "")
            String.contains?(name, q_down) or String.contains?(desc, q_down)
          end)
          |> Enum.take(20)
          |> Enum.map(fn egg ->
            %{
              name: egg["name"],
              version: egg["version"],
              description: egg["synopsis"] || egg["description"]
            }
          end)

        {:ok, matches}

      {:ok, eggs} when is_map(eggs) ->
        q_down = String.downcase(query)

        matches =
          eggs
          |> Enum.filter(fn {name, _info} ->
            String.contains?(String.downcase(name), q_down)
          end)
          |> Enum.take(20)
          |> Enum.map(fn {name, info} ->
            %{
              name: name,
              version: info["version"],
              description: info["synopsis"] || info["description"]
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
  Check if an egg exists in the CHICKEN registry.
  """
  def exists?(name) do
    case fetch_package(name) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Get all available versions for a CHICKEN egg.
  """
  def versions(name) do
    url = "#{@wiki_api}/egg/#{URI.encode(name)}.json"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"versions" => vers}} when is_list(vers) ->
        {:ok, Enum.map(vers, fn v -> v["version"] || v end) |> Enum.reject(&is_nil/1)}

      {:ok, body} ->
        case body["version"] do
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

  defp fetch_from_eggs_server(name, version) do
    url = "#{@base_url}/#{URI.encode(name)}/release-info"

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
    body["version"] || body["latest-version"] || "0.0.0"
  end

  defp resolve_version(_body, version), do: version

  defp build_resolved_package(name, body, version) do
    deps =
      (body["dependencies"] || body["depends"] || body["needs"] || [])
      |> normalise_deps()

    manifest = %ManifestFormat{
      name: name,
      version: version,
      description: body["synopsis"] || body["description"],
      license: extract_license(body),
      homepage: "https://wiki.call-cc.org/egg/#{name}",
      repository: body["repository"] || body["git-url"],
      authors: extract_authors(body),
      keywords: body["category"] |> List.wrap(),
      dependencies: deps,
      source_forth: :chicken
    }

    tarball = "#{@base_url}/#{name}/#{name}-#{version}.tar.gz"

    %ResolvedPackage{
      package: name,
      version: version,
      forth: :chicken,
      registry_url: "#{@base_url}/#{name}",
      manifest: manifest,
      tarball_url: tarball,
      checksum: nil,
      attestations: []
    }
  end

  defp normalise_deps(deps) when is_list(deps) do
    deps
    |> Enum.map(fn
      d when is_binary(d) -> {d, "*"}
      d when is_atom(d) -> {Atom.to_string(d), "*"}
      %{"name" => n, "version" => v} -> {n, v}
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end

  defp normalise_deps(deps) when is_map(deps), do: deps
  defp normalise_deps(_), do: %{}

  defp extract_license(body) do
    case body["license"] do
      l when is_binary(l) -> l
      l when is_list(l) -> Enum.join(l, " AND ")
      _ -> nil
    end
  end

  defp extract_authors(body) do
    case body["author"] || body["maintainer"] do
      a when is_binary(a) -> [a]
      a when is_list(a) -> Enum.map(a, &to_string/1)
      _ -> []
    end
  end
end
