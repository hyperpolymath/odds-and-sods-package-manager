# SPDX-License-Identifier: MPL-2.0
defmodule Opsm.Registries.Melpa do
  @moduledoc """
  MELPA (Milkypostman's Emacs Lisp Package Archive) registry adapter.
  https://melpa.org/
  Uses the MELPA JSON archive API for Emacs package metadata.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://melpa.org"
  @archive_url "https://melpa.org/archive.json"
  @download_url "https://melpa.org/packages"

  @doc """
  Fetch Emacs package metadata from MELPA.
  MELPA archive.json contains all packages in a single JSON blob.
  """
  def fetch_package(name, version \\ "latest") do
    case VerifiedHttp.get_json(@archive_url, receive_timeout: 10_000) do
      {:ok, archive} when is_map(archive) ->
        case Map.get(archive, name) do
          nil ->
            {:error, :not_found}

          pkg_data ->
            target_version = if version == "latest" do
              extract_version(pkg_data)
            else
              version
            end

            deps = extract_deps(pkg_data)
            {:ok, parse_package(name, pkg_data, target_version, deps)}
        end

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, %{status: status}} ->
        {:error, "MELPA returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Search for packages on MELPA.
  Fetches the full archive and filters client-side (MELPA has no search endpoint).
  """
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    case VerifiedHttp.get_json(@archive_url, receive_timeout: 10_000) do
      {:ok, archive} when is_map(archive) ->
        downcased = String.downcase(query)

        results = archive
        |> Enum.filter(fn {name, data} ->
          desc = Map.get(data, "desc", "") || ""
          String.contains?(String.downcase(name), downcased) ||
            String.contains?(String.downcase(desc), downcased)
        end)
        |> Enum.take(limit)
        |> Enum.map(fn {name, data} ->
          %{
            name: name,
            version: extract_version(data),
            description: Map.get(data, "desc", ""),
            downloads: 0
          }
        end)

        {:ok, results}

      {:error, %{status: status}} ->
        {:error, "MELPA search returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if an Emacs package exists on MELPA.
  """
  def exists?(name) do
    case VerifiedHttp.get_json(@archive_url, receive_timeout: 10_000) do
      {:ok, archive} when is_map(archive) ->
        Map.has_key?(archive, name)

      _ ->
        false
    end
  end

  @doc """
  Get all versions of a MELPA package.
  MELPA is a rolling-release archive, so typically only the latest version exists.
  """
  def versions(name) do
    case VerifiedHttp.get_json(@archive_url, receive_timeout: 10_000) do
      {:ok, archive} when is_map(archive) ->
        case Map.get(archive, name) do
          nil -> {:error, :not_found}
          data -> {:ok, [extract_version(data)]}
        end

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get tarball URL for a MELPA package.
  """
  def tarball_url(name, version) do
    {:ok, "#{@download_url}/#{name}-#{version}.tar"}
  end

  # Parsers

  defp extract_version(data) do
    case Map.get(data, "ver") do
      ver when is_list(ver) -> Enum.join(ver, ".")
      _ -> "0.0.0"
    end
  end

  defp extract_deps(data) do
    case Map.get(data, "deps") do
      deps when is_map(deps) ->
        Enum.reduce(deps, %{}, fn {dep_name, ver_list}, acc ->
          constraint = case ver_list do
            ver when is_list(ver) -> ">= #{Enum.join(ver, ".")}"
            _ -> ">= 0.0.0"
          end
          Map.put(acc, dep_name, constraint)
        end)

      _ ->
        %{}
    end
  end

  defp parse_package(name, data, version, deps) do
    description = Map.get(data, "desc", "")

    %ResolvedPackage{
      package: name,
      version: version,
      forth: :melpa,
      registry_url: "#{@api_url}/#/#{name}",
      tarball_url: "#{@download_url}/#{name}-#{version}.tar",
      checksum: nil,
      checksum_algo: nil,
      manifest: %ManifestFormat{
        name: name,
        version: version,
        description: description,
        license: nil,
        homepage: "#{@api_url}/#/#{name}",
        repository: nil,
        authors: [],
        keywords: Map.get(data, "keywords") || [],
        dependencies: deps,
        dev_dependencies: %{},
        source_forth: :melpa,
        raw_manifest: data
      },
      attestations: [],
      resolved_deps: []
    }
  end
end
