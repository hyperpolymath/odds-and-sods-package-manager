# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Registries.Godot do
  @moduledoc """
  Godot Asset Library registry adapter.
  https://godotengine.org/asset-library/api
  Queries the official Godot Asset Library API for plugins, tools,
  templates, and other assets for the Godot game engine.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://godotengine.org/asset-library/api"

  @doc """
  Fetch asset metadata from the Godot Asset Library.
  Name can be the asset title or numeric asset ID.
  """
  def fetch_package(name, version \\ "latest") do
    case fetch_by_id_or_search(name) do
      {:ok, body} ->
        ver = if version == "latest" do
          body["version_string"] || body["version"] || "0.0.0"
        else
          version
        end

        {:ok, parse_godot_asset(name, body, ver)}

      {:error, _} = err -> err
    end
  end

  defp fetch_by_id_or_search(name) do
    # Try as numeric ID first
    case Integer.parse(to_string(name)) do
      {id, ""} -> fetch_by_id(id)
      _ -> fetch_by_name(name)
    end
  end

  defp fetch_by_id(id) do
    url = "#{@api_url}/asset/#{id}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} -> {:ok, body}
      {:error, :not_found} -> {:error, :not_found}
      {:error, %{status: 404}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_by_name(name) do
    url = "#{@api_url}/asset?filter=#{URI.encode(name)}&max_results=1"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        results = body["result"] || []
        case results do
          [asset | _] ->
            # Fetch full asset details by ID
            asset_id = asset["asset_id"]
            if asset_id, do: fetch_by_id(asset_id), else: {:ok, asset}

          [] -> {:error, :not_found}
        end

      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_godot_asset(name, body, version) do
    # Map Godot category IDs to human-readable strings
    category = body["category"] || body["category_id"]

    # The download URL points to the asset archive
    download_url = body["download_url"] || body["browse_url"]
    download_hash = body["download_hash"]

    manifest = %ManifestFormat{
      name: body["title"] || to_string(name),
      version: version,
      description: body["description"],
      license: map_godot_license(body["cost"]),
      homepage: body["browse_url"],
      repository: body["browse_url"],
      authors: if(body["author"], do: [body["author"]], else: []),
      keywords: [
        "godot",
        "godot-#{body["godot_version"] || "unknown"}",
        category_label(category)
      ] |> Enum.reject(&is_nil/1),
      dependencies: %{},
      source_forth: :godot,
      raw_manifest: body
    }

    %ResolvedPackage{
      package: body["title"] || to_string(name),
      version: version,
      forth: :godot,
      registry_url: "https://godotengine.org/asset-library",
      manifest: manifest,
      tarball_url: download_url,
      checksum: download_hash,
      checksum_algo: if(download_hash, do: :sha256),
      attestations: [],
      resolved_deps: []
    }
  end

  # Godot Asset Library uses "cost" field for license info
  defp map_godot_license("MIT"), do: "MIT"
  defp map_godot_license("Apache 2.0"), do: "Apache-2.0"
  defp map_godot_license("GPL v3"), do: "GPL-3.0-only"
  defp map_godot_license("MPL 2.0"), do: "MPL-2.0"
  defp map_godot_license("CC BY 4.0"), do: "CC-BY-4.0"
  defp map_godot_license("CC0"), do: "CC0-1.0"
  defp map_godot_license("Unlicense"), do: "Unlicense"
  defp map_godot_license(other) when is_binary(other), do: other
  defp map_godot_license(_), do: nil

  defp category_label(0), do: "2d-tools"
  defp category_label(1), do: "3d-tools"
  defp category_label(2), do: "shaders"
  defp category_label(3), do: "materials"
  defp category_label(4), do: "tools"
  defp category_label(5), do: "scripts"
  defp category_label(6), do: "misc"
  defp category_label(c) when is_binary(c), do: c
  defp category_label(_), do: nil

  @doc """
  Search for assets in the Godot Asset Library.
  """
  def search(query, opts \\ []) do
    max_results = Keyword.get(opts, :limit, 20)
    godot_version = Keyword.get(opts, :godot_version)

    params = "filter=#{URI.encode(query)}&max_results=#{max_results}"
    params = if godot_version, do: "#{params}&godot_version=#{godot_version}", else: params
    url = "#{@api_url}/asset?#{params}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        results = (body["result"] || [])
        |> Enum.map(fn asset ->
          %{
            name: asset["title"],
            version: asset["version_string"] || asset["version"],
            description: asset["description"] || asset["blurb"]
          }
        end)
        {:ok, results}

      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Check if an asset exists in the Godot Asset Library.
  """
  def exists?(name) do
    case fetch_package(name) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Get available versions. Godot assets typically have one published version.
  """
  def versions(name) do
    case fetch_package(name) do
      {:ok, pkg} -> {:ok, [pkg.version]}
      {:error, _} = err -> err
    end
  end
end
