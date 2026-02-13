# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule Opsm.Registries.Pecl do
  @moduledoc """
  PHP PECL registry adapter.
  https://pecl.php.net/
  Queries the PECL REST API for PHP C-extension package metadata.

  API endpoints used:
  - GET /rest/p/:name/info.json           - Package info
  - GET /rest/r/:name/allreleases.json    - All releases
  - GET /rest/r/:name/latest.txt          - Latest stable version
  - GET /rest/p/packages.json             - Full package list

  PECL shares the same REST structure as PEAR, but hosts native PHP
  extensions written in C/C++.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @base_url "https://pecl.php.net/rest"

  @doc """
  Fetch extension metadata from the PECL registry.
  """
  def fetch_package(name, version \\ "latest") do
    with {:ok, info} <- fetch_package_info(name),
         {:ok, ver} <- resolve_version(name, version) do
      {:ok, build_resolved_package(name, info, ver)}
    end
  end

  @doc """
  Search for PECL extensions. Fetches the full list and filters locally.
  """
  def search(query, _opts \\ []) do
    url = "#{@base_url}/p/packages.json"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"packages" => packages}} when is_list(packages) ->
        q_down = String.downcase(query)

        matches =
          packages
          |> Enum.filter(fn name ->
            String.contains?(String.downcase(to_string(name)), q_down)
          end)
          |> Enum.take(20)
          |> Enum.map(fn name -> %{name: name, version: nil, description: nil} end)

        {:ok, matches}

      {:ok, packages} when is_list(packages) ->
        q_down = String.downcase(query)

        matches =
          packages
          |> Enum.filter(fn
            p when is_binary(p) -> String.contains?(String.downcase(p), q_down)
            _ -> false
          end)
          |> Enum.take(20)
          |> Enum.map(fn p -> %{name: p, version: nil, description: nil} end)

        {:ok, matches}

      {:ok, _} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if an extension exists in the PECL registry.
  """
  def exists?(name) do
    case fetch_package_info(name) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Get all available versions for a PECL extension.
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
      homepage: "https://pecl.php.net/package/#{name}",
      repository: info["repository"],
      authors: extract_authors(info),
      keywords: [],
      dependencies: %{},
      source_forth: :pecl
    }

    tarball = "https://pecl.php.net/get/#{name}-#{version}.tgz"

    %ResolvedPackage{
      package: name,
      version: version,
      forth: :pecl,
      registry_url: "https://pecl.php.net/package/#{name}",
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
