# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Registries.Macports do
  @moduledoc """
  MacPorts registry adapter.
  https://ports.macports.org/api/v1/
  Queries the MacPorts web API for port metadata.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://ports.macports.org/api/v1"

  @doc """
  Fetch port metadata from the MacPorts API.
  """
  def fetch_package(name, version \\ "latest") do
    url = "#{@api_url}/ports/#{URI.encode(name)}/"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        ver = if version == "latest",
          do: body["version"],
          else: version
        {:ok, parse_macport(name, body, ver)}

      {:error, :not_found} -> {:error, :not_found}
      {:error, %{status: 404}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_macport(name, body, version) do
    deps = extract_dependencies(body)

    manifest = %ManifestFormat{
      name: name,
      version: version || "0.0.0",
      description: body["description"] || body["long_description"],
      license: format_license(body["license"]),
      homepage: body["homepage"],
      repository: "https://github.com/macports/macports-ports/tree/master/#{body["portdir"] || name}",
      dependencies: deps
    }

    %ResolvedPackage{
      package: name,
      version: version || "0.0.0",
      forth: :macports,
      manifest: manifest,
      tarball_url: build_distfile_url(body),
      checksum: nil,
      attestations: [],
    }
  end

  defp extract_dependencies(body) do
    dep_types = ["depends_lib", "depends_build", "depends_run", "depends_fetch"]

    dep_types
    |> Enum.flat_map(fn dep_type ->
      (body[dep_type] || [])
      |> Enum.map(fn
        d when is_binary(d) ->
          dep_name = d |> String.split(":") |> List.last() |> String.trim()
          {dep_name, "*"}
        d when is_map(d) ->
          {d["port_name"] || d["name"] || "", "*"}
        _ ->
          nil
      end)
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(fn {n, _} -> n == "" end)
    |> Map.new()
  end

  defp format_license(nil), do: nil
  defp format_license(license) when is_binary(license), do: license
  defp format_license(license) when is_list(license), do: Enum.join(license, " ")

  defp build_distfile_url(body) do
    case body["distfiles"] do
      [first | _] when is_binary(first) ->
        "https://distfiles.macports.org/#{body["name"] || "unknown"}/#{first}"
      _ -> nil
    end
  end

  @doc """
  Get available versions. MacPorts typically shows the current stable version.
  Also fetches version history if available.
  """
  def get_versions(name) do
    url = "#{@api_url}/ports/#{URI.encode(name)}/history/"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} when is_list(body) ->
        versions_list = body
        |> Enum.map(fn entry -> entry["version"] end)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
        {:ok, versions_list}

      {:ok, _} ->
        # Fallback: return just the current version
        case fetch_package(name) do
          {:ok, pkg} -> {:ok, [pkg.version]}
          {:error, _} = err -> err
        end

      {:error, _} = err -> err
    end
  end

  @doc """
  Search for ports on MacPorts.
  """
  def search(query, _opts \\ []) do
    url = "#{@api_url}/ports/?search=#{URI.encode(query)}&limit=20"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"results" => results}} when is_list(results) ->
        hits = results
        |> Enum.take(20)
        |> Enum.map(fn port ->
          %{name: port["name"], version: port["version"], description: port["description"]}
        end)
        {:ok, hits}

      {:ok, body} when is_list(body) ->
        results = body
        |> Enum.take(20)
        |> Enum.map(fn port ->
          %{name: port["name"], version: port["version"], description: port["description"]}
        end)
        {:ok, results}

      {:ok, _} -> {:ok, []}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Check if a port exists in MacPorts.
  """
  def exists?(name) do
    case fetch_package(name) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Get versions for a port.
  """
  def versions(name), do: get_versions(name)
end
