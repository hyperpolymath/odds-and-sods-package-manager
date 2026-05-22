# SPDX-License-Identifier: MPL-2.0
defmodule Opsm.Registries.NixDarwin do
  @moduledoc """
  Nix-Darwin / Home Manager registry adapter.
  https://nix-community.github.io/home-manager/
  Queries the nix-darwin and Home Manager option search for macOS
  system-level and user-level Nix configuration options and packages.
  Falls back to nixpkgs search for package resolution.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @home_manager_api "https://mipmip.github.io/home-manager-option-search/data"
  @nixpkgs_search_api "https://search.nixos.org/backend/latest-42-nixos-unstable/_search"
  @nix_darwin_options "https://daiderd.com/nix-darwin/manual/index.html"

  @doc """
  Fetch a package or option from the Nix-Darwin/Home Manager ecosystem.
  Searches Home Manager options first, then falls back to nixpkgs.
  """
  def fetch_package(name, version \\ "latest") do
    case fetch_home_manager_option(name) do
      {:ok, _} = result -> result
      {:error, :not_found} -> fetch_nixpkgs_package(name, version)
      {:error, _} -> fetch_nixpkgs_package(name, version)
    end
  end

  defp fetch_home_manager_option(name) do
    # Home Manager options are exposed as a JSON index
    url = "#{@home_manager_api}/options.json"

    case VerifiedHttp.get_json(url, receive_timeout: 15_000) do
      {:ok, options} when is_map(options) ->
        # Options keyed by dot-separated paths (e.g., "programs.git.enable")
        case Map.get(options, name) do
          nil ->
            # Try partial match
            matches = options
                      |> Enum.filter(fn {k, _v} -> String.contains?(k, name) end)
                      |> Enum.take(1)
            case matches do
              [{key, opt} | _] -> {:ok, parse_hm_option(key, opt)}
              [] -> {:error, :not_found}
            end

          opt ->
            {:ok, parse_hm_option(name, opt)}
        end

      {:ok, options} when is_list(options) ->
        match = Enum.find(options, fn opt ->
          (opt["name"] || opt["option"]) == name
        end)
        case match do
          nil -> {:error, :not_found}
          opt -> {:ok, parse_hm_option(name, opt)}
        end

      {:error, _} = err -> err
    end
  end

  defp parse_hm_option(name, opt) do
    description = case opt do
      o when is_map(o) -> o["description"] || o["type"] || "Home Manager option"
      o when is_binary(o) -> o
      _ -> "Home Manager option"
    end

    option_type = if is_map(opt), do: opt["type"], else: nil
    default_val = if is_map(opt), do: opt["default"], else: nil

    manifest = %ManifestFormat{
      name: name,
      version: "home-manager",
      description: description,
      license: "MIT",
      homepage: "https://nix-community.github.io/home-manager/",
      repository: "https://github.com/nix-community/home-manager",
      keywords: ["nix-darwin", "home-manager", "nix-option", option_type] |> Enum.reject(&is_nil/1),
      dependencies: %{},
      source_forth: :nix_darwin,
      raw_manifest: %{
        "option" => name,
        "type" => option_type,
        "default" => default_val,
        "description" => description
      }
    }

    %ResolvedPackage{
      package: name,
      version: "home-manager",
      forth: :nix_darwin,
      registry_url: "https://nix-community.github.io/home-manager/",
      manifest: manifest,
      tarball_url: nil,
      checksum: nil,
      attestations: [],
      resolved_deps: []
    }
  end

  defp fetch_nixpkgs_package(name, version) do
    query = %{
      "query" => %{
        "bool" => %{
          "should" => [
            %{"match" => %{"package_attr_name" => name}},
            %{"match" => %{"package_pname" => name}}
          ]
        }
      },
      "size" => 1
    }

    case VerifiedHttp.post_json(@nixpkgs_search_api, query, receive_timeout: 10_000) do
      {:ok, body} ->
        hits = get_in(body, ["hits", "hits"]) || []
        case hits do
          [hit | _] ->
            source = hit["_source"] || %{}
            ver = if version == "latest",
              do: source["package_version"] || "0.0.0",
              else: version
            {:ok, parse_nixpkgs(name, source, ver)}

          [] -> {:error, :not_found}
        end

      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_nixpkgs(name, source, version) do
    licenses = case source["package_license"] do
      l when is_list(l) -> Enum.join(l, " AND ")
      l when is_binary(l) -> l
      _ -> nil
    end

    homepage = case source["package_homepage"] do
      [url | _] -> url
      url when is_binary(url) -> url
      _ -> nil
    end

    manifest = %ManifestFormat{
      name: name,
      version: version,
      description: source["package_description"],
      license: licenses,
      homepage: homepage,
      repository: "https://github.com/NixOS/nixpkgs",
      keywords: ["nix-darwin", "nixpkgs", source["package_system"]] |> Enum.reject(&is_nil/1),
      dependencies: %{},
      source_forth: :nix_darwin,
      raw_manifest: source
    }

    %ResolvedPackage{
      package: name,
      version: version,
      forth: :nix_darwin,
      registry_url: @nix_darwin_options,
      manifest: manifest,
      tarball_url: nil,
      checksum: nil,
      attestations: [],
      resolved_deps: []
    }
  end

  @doc """
  Search for options and packages in the Nix-Darwin/Home Manager ecosystem.
  """
  def search(query, _opts \\ []) do
    # Search nixpkgs for darwin-compatible packages
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

    case VerifiedHttp.post_json(@nixpkgs_search_api, search_query, receive_timeout: 10_000) do
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

      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Check if a package or option exists.
  """
  def exists?(name) do
    case fetch_package(name) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Get versions. Home Manager options have a single 'version' per flake ref.
  Nixpkgs packages typically have one version per channel.
  """
  def versions(name) do
    case fetch_package(name) do
      {:ok, pkg} -> {:ok, [pkg.version]}
      {:error, _} = err -> err
    end
  end
end
