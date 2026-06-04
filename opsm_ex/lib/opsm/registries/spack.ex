# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Registries.Spack do
  @moduledoc """
  Spack HPC package manager registry adapter.
  https://packages.spack.io
  Queries the Spack packages index for HPC/scientific package metadata,
  versions, and dependency information.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://packages.spack.io/data"
  @packages_index_url "https://packages.spack.io/data/packages.json"

  @doc """
  Fetch package metadata from the Spack packages index.
  Retrieves the per-package JSON data file from packages.spack.io.
  """
  def fetch_package(name, version \\ "latest") do
    url = "#{@api_url}/packages/#{URI.encode(name)}.json"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        ver = resolve_version(body, version)
        {:ok, parse_spack_package(name, body, ver)}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, %{status: status}} ->
        {:error, "Spack registry returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp resolve_version(body, "latest") do
    # Spack packages list versions in order; take the first (newest)
    version_list = extract_version_list(body)

    case version_list do
      [latest | _] -> latest
      [] -> "0.0.0"
    end
  end

  defp resolve_version(_body, requested), do: requested

  @doc """
  Search for packages in the Spack index.
  Fetches the full package index and filters locally by name and description.
  """
  def search(query, _opts \\ []) do
    case VerifiedHttp.get_json(@packages_index_url, receive_timeout: 30_000) do
      {:ok, packages} when is_list(packages) ->
        query_lower = String.downcase(query)

        results = packages
        |> Enum.filter(fn pkg ->
          name = String.downcase(pkg["name"] || "")
          desc = String.downcase(pkg["description"] || "")
          String.contains?(name, query_lower) or String.contains?(desc, query_lower)
        end)
        |> Enum.take(20)
        |> Enum.map(fn pkg ->
          %{
            name: pkg["name"],
            version: List.first(pkg["versions"] || []),
            description: pkg["description"]
          }
        end)
        {:ok, results}

      {:ok, %{"packages" => packages}} when is_list(packages) ->
        query_lower = String.downcase(query)

        results = packages
        |> Enum.filter(fn pkg ->
          name = String.downcase(pkg["name"] || "")
          String.contains?(name, query_lower)
        end)
        |> Enum.take(20)
        |> Enum.map(fn pkg ->
          %{
            name: pkg["name"],
            version: nil,
            description: pkg["description"]
          }
        end)
        {:ok, results}

      {:ok, _} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a package exists in the Spack index.
  """
  def exists?(name) do
    url = "#{@api_url}/packages/#{URI.encode(name)}.json"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Get all available versions of a Spack package.
  Returns version strings, newest first.
  """
  def versions(name) do
    url = "#{@api_url}/packages/#{URI.encode(name)}.json"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        version_list = extract_version_list(body)
        {:ok, version_list}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  defp extract_version_list(body) do
    cond do
      is_list(body["versions"]) ->
        Enum.map(body["versions"], fn
          v when is_binary(v) -> v
          %{"name" => name} -> name
          _ -> nil
        end)
        |> Enum.reject(&is_nil/1)

      is_map(body["versions"]) ->
        body["versions"]
        |> Map.keys()
        |> Enum.sort(:desc)

      true ->
        []
    end
  end

  defp parse_spack_package(name, body, version) do
    deps = extract_dependencies(body)

    manifest = %ManifestFormat{
      name: name,
      version: version,
      description: body["description"],
      license: extract_license(body),
      homepage: body["homepage"],
      repository: body["homepage"],
      authors: extract_maintainers(body),
      keywords: body["tags"] || [],
      dependencies: deps,
      dev_dependencies: %{},
      source_forth: :spack,
      raw_manifest: body
    }

    %ResolvedPackage{
      package: name,
      version: version,
      forth: :spack,
      registry_url: "https://packages.spack.io/package.html?name=#{name}",
      tarball_url: nil,
      checksum: nil,
      checksum_algo: :sha256,
      manifest: manifest,
      attestations: [],
      resolved_deps: []
    }
  end

  defp extract_dependencies(body) do
    (body["dependencies"] || [])
    |> Enum.reduce(%{}, fn
      dep when is_binary(dep) ->
        fn acc -> Map.put(acc, dep, "*") end

      %{"name" => dep_name, "type" => _type} ->
        fn acc -> Map.put(acc, dep_name, "*") end

      %{"name" => dep_name} ->
        fn acc -> Map.put(acc, dep_name, "*") end

      _ ->
        fn acc -> acc end
    end)
    |> Enum.reduce(%{}, fn reducer, acc -> reducer.(acc) end)
  end

  defp extract_license(body) do
    case body["license"] do
      license when is_binary(license) -> license
      [license | _] when is_binary(license) -> license
      _ -> nil
    end
  end

  defp extract_maintainers(body) do
    (body["maintainers"] || [])
    |> Enum.map(fn
      m when is_binary(m) -> m
      %{"github" => gh} -> gh
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end
end
