# SPDX-License-Identifier: MPL-2.0
defmodule Opsm.Registries.Dub do
  @moduledoc """
  D language (DUB) registry adapter.
  https://code.dlang.org/api/v1/
  Queries the DUB package registry for D language packages.

  API endpoints used:
  - GET /api/v1/packages/:name           - Package metadata
  - GET /api/v1/packages/:name/:version  - Specific version info
  - GET /api/v1/packages/search?q=:query - Search packages
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @base_url "https://code.dlang.org/api/v1"

  @doc """
  Fetch package metadata from the DUB registry.
  """
  def fetch_package(name, version \\ "latest") do
    url = "#{@base_url}/packages/#{name}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        ver = resolve_version(body, version)
        {:ok, build_resolved_package(name, body, ver)}

      {:error, :not_found} -> {:error, :not_found}
      {:error, %{status: 404}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Search for D packages matching a query string.
  """
  def search(query, _opts \\ []) do
    url = "#{@base_url}/packages/search?q=#{URI.encode_www_form(query)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, results} when is_list(results) ->
        matches =
          results
          |> Enum.take(20)
          |> Enum.map(fn pkg ->
            %{
              name: pkg["name"],
              version: get_in(pkg, ["version"]) || latest_version_from_list(pkg),
              description: pkg["description"]
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
  Check if a package exists in the DUB registry.
  """
  def exists?(name) do
    case fetch_package(name) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Get all available versions for a package.
  """
  def versions(name) do
    url = "#{@base_url}/packages/#{name}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        vers =
          (body["versions"] || [])
          |> Enum.map(fn v -> v["version"] end)
          |> Enum.reject(&is_nil/1)

        {:ok, vers}

      {:error, :not_found} -> {:error, :not_found}
      {:error, %{status: 404}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp resolve_version(body, "latest") do
    case body["versions"] do
      [latest | _] -> latest["version"] || "0.0.0"
      _ -> "0.0.0"
    end
  end

  defp resolve_version(_body, version), do: version

  defp latest_version_from_list(pkg) do
    case pkg["versions"] do
      [latest | _] -> latest["version"]
      _ -> nil
    end
  end

  defp build_resolved_package(name, body, version) do
    deps =
      (get_in(body, ["versions"]) || [])
      |> List.first(%{})
      |> Map.get("dependencies", %{})
      |> Enum.map(fn {k, v} -> {k, extract_dep_version(v)} end)
      |> Map.new()

    manifest = %ManifestFormat{
      name: name,
      version: version,
      description: body["description"],
      license: body["license"],
      homepage: body["homepage"],
      repository: body["repository"],
      dependencies: deps,
      source_forth: :dub
    }

    %ResolvedPackage{
      package: name,
      version: version,
      forth: :dub,
      registry_url: "https://code.dlang.org/packages/#{name}",
      manifest: manifest,
      tarball_url: nil,
      checksum: nil,
      attestations: []
    }
  end

  defp extract_dep_version(v) when is_binary(v), do: v
  defp extract_dep_version(%{"version" => v}), do: v
  defp extract_dep_version(_), do: "*"
end
