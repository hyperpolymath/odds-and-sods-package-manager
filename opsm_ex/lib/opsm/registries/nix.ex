# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule Opsm.Registries.Nix do
  @moduledoc """
  Nix/nixpkgs registry adapter.
  https://search.nixos.org/packages
  Queries the NixOS package search API.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @search_api "https://search.nixos.org/backend/latest-42-nixos-unstable/_search"

  @doc """
  Fetch package metadata from nixpkgs.
  """
  def fetch_package(name, version \\ "latest") do
    query = %{
      "query" => %{
        "match" => %{"package_attr_name" => name}
      },
      "size" => 1
    }

    case VerifiedHttp.post_json(@search_api, query, receive_timeout: 10_000) do
      {:ok, body} ->
        hits = get_in(body, ["hits", "hits"]) || []
        case hits do
          [hit | _] ->
            source = hit["_source"] || %{}
            ver = if version == "latest",
              do: source["package_version"],
              else: version
            {:ok, parse_nix_package(name, source, ver)}

          [] ->
            {:error, :not_found}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_nix_package(name, source, version) do
    licenses = case source["package_license"] do
      l when is_list(l) -> Enum.join(l, " AND ")
      l when is_binary(l) -> l
      _ -> nil
    end

    manifest = %ManifestFormat{
      name: name,
      version: version || "0.0.0",
      description: source["package_description"],
      license: licenses,
      homepage: case source["package_homepage"] do
        [url | _] -> url
        url when is_binary(url) -> url
        _ -> nil
      end,
      repository: nil,
      dependencies: %{}
    }

    %ResolvedPackage{
      package: name,
      version: version || "0.0.0",
      forth: :nix,
      manifest: manifest,
      tarball_url: nil,
      checksum: nil,
      attestations: [],
    }
  end

  @doc """
  Search for packages in nixpkgs.
  """
  def search(query, _opts \\ []) do
    search_query = %{
      "query" => %{
        "multi_match" => %{
          "query" => query,
          "fields" => ["package_attr_name^3", "package_pname^2", "package_description"],
          "type" => "best_fields"
        }
      },
      "size" => 20
    }

    case VerifiedHttp.post_json(@search_api, search_query, receive_timeout: 10_000) do
      {:ok, body} ->
        hits = get_in(body, ["hits", "hits"]) || []
        results = Enum.map(hits, fn hit ->
          s = hit["_source"] || %{}
          %{
            name: s["package_attr_name"],
            version: s["package_version"],
            description: s["package_description"]
          }
        end)
        {:ok, results}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get versions. Nix typically has one version per channel.
  """
  def get_versions(name) do
    case fetch_package(name) do
      {:ok, pkg} -> {:ok, [pkg.version]}
      {:error, _} = err -> err
    end
  end

  def exists?(name) do
    case fetch_package(name) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  def versions(name), do: get_versions(name)
end
