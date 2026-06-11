# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Registries.Buildpacks do
  @moduledoc """
  Cloud Native Buildpacks registry adapter.
  https://registry.buildpacks.io/api/v1
  Queries the Buildpack Registry API for buildpack metadata, versions, and search.
  Supports both individual buildpacks and builder images.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://registry.buildpacks.io/api/v1"

  @doc """
  Fetch buildpack metadata from the Cloud Native Buildpacks Registry.
  Name format: "namespace/name" (e.g., "paketo-buildpacks/go").
  """
  def fetch_package(name, version \\ "latest") do
    url = "#{@api_url}/buildpacks/#{URI.encode(name, &URI.char_unreserved?/1)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        ver = resolve_version(body, version)
        {:ok, parse_buildpack(name, body, ver)}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, %{status: status}} ->
        {:error, "Buildpacks Registry returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp resolve_version(body, "latest") do
    versions_list = body["versions"] || []

    case versions_list do
      [latest | _] ->
        latest["version"] || "0.0.0"

      _ ->
        body["latest"]["version"] || "0.0.0"
    end
  end

  defp resolve_version(_body, requested), do: requested

  @doc """
  Search for buildpacks in the registry.
  Returns matching buildpacks with name, version, and description.
  """
  def search(query, _opts \\ []) do
    url = "#{@api_url}/search?matches=#{URI.encode_www_form(query)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"buildpacks" => buildpacks}} when is_list(buildpacks) ->
        results = buildpacks
        |> Enum.take(20)
        |> Enum.map(fn bp ->
          %{
            name: bp["id"] || bp["name"],
            version: get_in(bp, ["latest", "version"]),
            description: bp["description"]
          }
        end)
        {:ok, results}

      {:ok, buildpacks} when is_list(buildpacks) ->
        results = buildpacks
        |> Enum.take(20)
        |> Enum.map(fn bp ->
          %{
            name: bp["id"] || bp["name"],
            version: get_in(bp, ["latest", "version"]),
            description: bp["description"]
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
  Check if a buildpack exists in the registry.
  """
  def exists?(name) do
    url = "#{@api_url}/buildpacks/#{URI.encode(name, &URI.char_unreserved?/1)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Get all available versions of a buildpack.
  Returns version strings, newest first.
  """
  def versions(name) do
    url = "#{@api_url}/buildpacks/#{URI.encode(name, &URI.char_unreserved?/1)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"versions" => versions_list}} when is_list(versions_list) ->
        version_strs = versions_list
        |> Enum.map(fn v -> v["version"] end)
        |> Enum.reject(&is_nil/1)
        {:ok, version_strs}

      {:ok, _} ->
        {:ok, []}

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

  defp parse_buildpack(name, body, version) do
    target_version_data = find_version_data(body, version)

    stacks = extract_stacks(target_version_data || body)

    manifest = %ManifestFormat{
      name: name,
      version: version,
      description: body["description"],
      license: extract_license(target_version_data),
      homepage: body["homepage"],
      repository: body["homepage"],
      authors: extract_authors(body),
      keywords: stacks,
      dependencies: extract_order_deps(target_version_data),
      dev_dependencies: %{},
      source_forth: :buildpacks,
      raw_manifest: body
    }

    %ResolvedPackage{
      package: name,
      version: version,
      forth: :buildpacks,
      registry_url: "https://registry.buildpacks.io/buildpacks/#{name}",
      tarball_url: extract_image_uri(target_version_data, name, version),
      checksum: nil,
      checksum_algo: :sha256,
      manifest: manifest,
      attestations: [],
      resolved_deps: []
    }
  end

  defp find_version_data(body, version) do
    versions_list = body["versions"] || []

    Enum.find(versions_list, fn v ->
      v["version"] == version
    end)
  end

  defp extract_stacks(nil), do: []
  defp extract_stacks(data) do
    (data["stacks"] || [])
    |> Enum.map(fn
      s when is_binary(s) -> s
      %{"id" => id} -> id
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_license(nil), do: nil
  defp extract_license(data), do: data["license"]

  defp extract_authors(body) do
    case body["author"] || body["namespace"] do
      nil -> []
      author when is_binary(author) -> [author]
      _ -> []
    end
  end

  defp extract_order_deps(nil), do: %{}
  defp extract_order_deps(data) do
    (data["order"] || [])
    |> List.flatten()
    |> Enum.reduce(%{}, fn
      %{"id" => id, "version" => ver} -> fn acc -> Map.put(acc, id, ver) end
      %{"id" => id} -> fn acc -> Map.put(acc, id, "*") end
      _ -> fn acc -> acc end
    end)
    |> Enum.reduce(%{}, fn reducer, acc -> reducer.(acc) end)
  end

  defp extract_image_uri(nil, name, version) do
    "docker://registry.buildpacks.io/#{name}:#{version}"
  end

  defp extract_image_uri(data, name, version) do
    data["image"] || "docker://registry.buildpacks.io/#{name}:#{version}"
  end
end
