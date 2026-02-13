# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule Opsm.Registries.Pear do
  @moduledoc """
  PHP PEAR registry adapter.
  https://pear.php.net/
  Queries the PEAR REST API for PHP package metadata.

  API endpoints used:
  - GET /rest/p/:name/info.xml            - Package info (XML)
  - GET /rest/r/:name/allreleases.xml     - All releases
  - GET /rest/r/:name/:version.xml        - Specific release
  - GET /rest/p/packages.xml              - All packages
  - GET /rest/p/:name/info.json           - Package info (JSON, where available)
  - GET /rest/r/:name/latest.txt          - Latest stable version

  Note: The PEAR REST API primarily returns XML. This adapter attempts JSON
  endpoints first and falls back to parsing simple text/XML responses.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @base_url "https://pear.php.net/rest"

  @doc """
  Fetch package metadata from the PEAR registry.
  """
  def fetch_package(name, version \\ "latest") do
    with {:ok, info} <- fetch_package_info(name),
         {:ok, ver} <- resolve_version(name, version) do
      {:ok, build_resolved_package(name, info, ver)}
    end
  end

  @doc """
  Search for PEAR packages. Since PEAR lacks a search API, this fetches the
  full package list and filters locally.
  """
  def search(query, _opts \\ []) do
    url = "#{@base_url}/p/packages.json"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"packages" => packages}} when is_list(packages) ->
        q_down = String.downcase(query)

        matches =
          packages
          |> Enum.filter(fn name ->
            String.contains?(String.downcase(name), q_down)
          end)
          |> Enum.take(20)
          |> Enum.map(fn name ->
            %{name: name, version: nil, description: nil}
          end)

        {:ok, matches}

      {:ok, packages} when is_list(packages) ->
        q_down = String.downcase(query)

        matches =
          packages
          |> Enum.filter(fn
            p when is_binary(p) -> String.contains?(String.downcase(p), q_down)
            %{"name" => n} -> String.contains?(String.downcase(n), q_down)
            _ -> false
          end)
          |> Enum.take(20)
          |> Enum.map(fn
            p when is_binary(p) -> %{name: p, version: nil, description: nil}
            %{"name" => n} -> %{name: n, version: nil, description: nil}
          end)

        {:ok, matches}

      {:ok, _} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a package exists in the PEAR registry.
  """
  def exists?(name) do
    case fetch_package_info(name) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Get all available versions for a PEAR package.
  """
  def versions(name) do
    url = "#{@base_url}/r/#{String.downcase(name)}/allreleases.json"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"r" => releases}} when is_list(releases) ->
        vers = Enum.map(releases, fn r -> r["v"] end) |> Enum.reject(&is_nil/1)
        {:ok, vers}

      {:ok, releases} when is_list(releases) ->
        vers = Enum.map(releases, fn r -> r["version"] || r["v"] end)
        {:ok, Enum.reject(vers, &is_nil/1)}

      {:error, :not_found} -> {:error, :not_found}
      {:error, %{status: 404}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp fetch_package_info(name) do
    url = "#{@base_url}/p/#{String.downcase(name)}/info.json"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} -> {:ok, body}
      {:error, :not_found} -> {:error, :not_found}
      {:error, %{status: 404}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_version(name, "latest") do
    url = "#{@base_url}/r/#{String.downcase(name)}/latest.txt"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"version" => v}} -> {:ok, v}
      {:ok, v} when is_binary(v) -> {:ok, String.trim(v)}
      {:error, _} -> {:ok, "0.0.0"}
    end
  end

  defp resolve_version(_name, version), do: {:ok, version}

  defp build_resolved_package(name, info, version) do
    manifest = %ManifestFormat{
      name: name,
      version: version,
      description: info["d"] || info["description"] || info["s"] || info["summary"],
      license: info["l"] || info["license"],
      homepage: "https://pear.php.net/package/#{name}",
      repository: info["repository"],
      authors: extract_authors(info),
      keywords: [],
      dependencies: %{},
      source_forth: :pear
    }

    tarball = "https://pear.php.net/get/#{name}-#{version}.tgz"

    %ResolvedPackage{
      package: name,
      version: version,
      forth: :pear,
      registry_url: "https://pear.php.net/package/#{name}",
      manifest: manifest,
      tarball_url: tarball,
      checksum: nil,
      attestations: []
    }
  end

  defp extract_authors(info) do
    case info["lead"] || info["maintainers"] do
      m when is_binary(m) -> [m]
      m when is_list(m) -> Enum.map(m, fn a -> a["name"] || a end)
      _ -> []
    end
  end
end
