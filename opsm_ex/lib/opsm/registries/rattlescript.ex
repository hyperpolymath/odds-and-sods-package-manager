# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Registries.RattleScript do
  @moduledoc """
  RattleScript package registry API client.

  RattleScript is the Python-syntax face of AffineScript.  Code is written
  with Python-style indentation and familiar syntax, then compiled via the
  AffineScript frontend into the same affine-typed IR and ultimately to WASM.

  The key property: RattleScript packages ARE AffineScript packages — they
  share the same manifest format (`affine.toml` with `face = "rattlescript"`),
  the same registry, and the same type-safety guarantees.  This adapter
  resolves both natively-Rattle packages and AffineScript packages that
  expose a Rattle face.

  Package manager: `rattle` CLI  (distributions/rattlescript, Rust)
  Manifest format: `affine.toml`  (face = "rattlescript")
  Registry: https://packages.affinescript.dev/api/v1  (shared with AffineScript)
  Language ID: rattlescript
  Source `:forth` atom: `:rattlescript`

  When a package is not found in the RattleScript-specific catalogue, this
  adapter transparently delegates to `Opsm.Registries.AffineScript` — any
  AffineScript package is usable from RattleScript without re-packaging.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Registries.AffineScript, as: AfsRegistry
  alias Opsm.Verified.Http, as: VerifiedHttp

  @base_url "https://packages.affinescript.dev/api/v1"
  @fallback_mode :git

  # ---------------------------------------------------------------------------
  # Curated RattleScript-native packages
  # (Packages authored specifically with the Rattle face / Python syntax)
  # ---------------------------------------------------------------------------

  @known_packages [
    %{
      name: "rattle-std",
      url: "https://github.com/hyperpolymath/rattle-std",
      description: "RattleScript standard library — Pythonic wrappers over affine-std"
    },
    %{
      name: "rattle-numpy",
      url: "https://github.com/hyperpolymath/rattle-numpy",
      description: "NumPy-compatible array operations with affine resource bounds (no aliasing)"
    },
    %{
      name: "rattle-pandas",
      url: "https://github.com/hyperpolymath/rattle-pandas",
      description: "DataFrame API with affine ownership — no surprise mutations, GC-free"
    },
    %{
      name: "rattle-asyncio",
      url: "https://github.com/hyperpolymath/rattle-asyncio",
      description: "asyncio-compatible async/await for RattleScript compiled to WASM"
    },
    %{
      name: "rattle-requests",
      url: "https://github.com/hyperpolymath/rattle-requests",
      description: "Python requests-style HTTP client backed by affine-http"
    },
    %{
      name: "rattle-pytest",
      url: "https://github.com/hyperpolymath/rattle-pytest",
      description: "pytest-style test runner for RattleScript packages"
    },
    %{
      name: "rattle-typing",
      url: "https://github.com/hyperpolymath/rattle-typing",
      description: "Python typing-module shims mapping to AffineScript's structural type system"
    },
    %{
      name: "rattle-pathlib",
      url: "https://github.com/hyperpolymath/rattle-pathlib",
      description: "pathlib-style filesystem API with affine file-handle ownership"
    },
    %{
      name: "rattle-dataclasses",
      url: "https://github.com/hyperpolymath/rattle-dataclasses",
      description: "@dataclass decorator support for RattleScript with auto-derived affine traits"
    },
    %{
      name: "rattle-groovebind",
      url: "https://github.com/hyperpolymath/groove",
      path: "bindings/rattlescript",
      description: "Groove protocol bindings for RattleScript — plug-and-play inter-service comms"
    }
  ]

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Fetch package metadata from the RattleScript catalogue.
  Falls back to the AffineScript registry if not found natively —
  any AffineScript package is usable from RattleScript.

  ## Examples

      iex> RattleScript.fetch_package("rattle-std", "latest")
      {:ok, %ResolvedPackage{forth: :rattlescript, ...}}

      iex> RattleScript.fetch_package("affine-json", "latest")
      {:ok, %ResolvedPackage{forth: :affinescript, ...}}
  """
  def fetch_package(name, version \\ "latest") do
    case @fallback_mode do
      :git -> fetch_from_git(name, version)
      :registry -> fetch_from_registry(name, version)
    end
  end

  @doc """
  Search the RattleScript catalogue, then fall through to AffineScript catalogue.

  ## Examples

      iex> RattleScript.search("http")
      {:ok, [%ResolvedPackage{...}, ...]}
  """
  def search(query, opts \\ []) do
    case @fallback_mode do
      :git -> search_combined(query, opts)
      :registry -> search_registry(query, opts)
    end
  end

  @doc """
  Check if a package exists — checks RattleScript catalogue first, then AffineScript.
  """
  def exists?(name) do
    curated_exists?(name) or AfsRegistry.exists?(name)
  end

  @doc """
  List known versions of a RattleScript package.
  """
  def versions(name) do
    case @fallback_mode do
      :git -> git_versions(name)
      :registry -> registry_versions(name)
    end
  end

  # ---------------------------------------------------------------------------
  # Registry mode (shared with AffineScript — same backend)
  # ---------------------------------------------------------------------------

  defp fetch_from_registry(name, version) do
    url = "#{@base_url}/packages/#{URI.encode(name)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        target_version = if version == "latest", do: body["latest_version"], else: version
        {:ok, parse_registry_package(body, target_version)}

      {:error, :not_found} ->
        # Transparent fallback to AffineScript registry
        AfsRegistry.fetch_package(name, version)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp search_registry(query, opts) do
    limit = Keyword.get(opts, :limit, 20)
    url = "#{@base_url}/packages?q=#{URI.encode(query)}&face=rattlescript&limit=#{limit}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} when is_list(body) ->
        {:ok, Enum.map(body, &parse_search_result/1)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp registry_versions(name) do
    url = "#{@base_url}/packages/#{URI.encode(name)}/versions"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} when is_list(body) ->
        {:ok, Enum.map(body, & &1["version"])}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Git fallback mode (current)
  # ---------------------------------------------------------------------------

  defp fetch_from_git(name, version) do
    case find_curated(name) do
      {:ok, pkg_info} ->
        fetch_git_manifest(pkg_info, version)

      :not_found ->
        # Transparent fallback: any AffineScript package works in RattleScript
        AfsRegistry.fetch_package(name, version)
    end
  end

  defp search_combined(query, opts) do
    # Search RattleScript-native catalogue
    rattle_results = search_curated(query, opts)

    # Also search AffineScript catalogue and merge (dedup by name)
    afs_results =
      case AfsRegistry.search(query, opts) do
        {:ok, pkgs} -> pkgs
        _ -> []
      end

    rattle_names = MapSet.new(rattle_results, & &1.package)

    combined =
      rattle_results ++
        Enum.reject(afs_results, fn p -> MapSet.member?(rattle_names, p.package) end)

    {:ok, combined}
  end

  defp search_curated(query, _opts) do
    query_lower = String.downcase(query)

    @known_packages
    |> Enum.filter(fn pkg ->
      text = String.downcase("#{pkg.name} #{pkg.description}")
      String.contains?(text, query_lower)
    end)
    |> Enum.map(&curated_to_resolved(&1, "latest"))
  end

  defp curated_exists?(name) do
    case find_curated(name) do
      {:ok, _} -> true
      :not_found -> false
    end
  end

  defp git_versions(name) do
    case find_curated(name) do
      {:ok, pkg_info} ->
        github_tags_url =
          pkg_info.url
          |> String.replace("https://github.com/", "https://api.github.com/repos/")
          |> Kernel.<>("/tags")

        case VerifiedHttp.get_json(github_tags_url, receive_timeout: 10_000) do
          {:ok, tags} when is_list(tags) ->
            versions = Enum.map(tags, & &1["name"]) |> Enum.reject(&is_nil/1)
            {:ok, if(versions == [], do: ["main"], else: versions)}

          _ ->
            {:ok, ["main"]}
        end

      :not_found ->
        # Delegate version lookup to AffineScript registry
        AfsRegistry.versions(name)
    end
  end

  # Fetch and parse `affine.toml` (face = "rattlescript") from a git repository.
  defp fetch_git_manifest(pkg_info, version) do
    branch = if version in ["latest", "main"], do: "main", else: version
    base_url = pkg_info.url
    path = Map.get(pkg_info, :path)

    manifest_url =
      if path do
        "#{base_url}/raw/#{branch}/#{path}/affine.toml"
      else
        "#{base_url}/raw/#{branch}/affine.toml"
      end

    case VerifiedHttp.get(manifest_url, receive_timeout: 10_000) do
      {:ok, %{body: toml_text}} ->
        parse_affine_toml(toml_text, pkg_info, version)

      _ ->
        {:ok, curated_to_resolved(pkg_info, version)}
    end
  end

  # ---------------------------------------------------------------------------
  # affine.toml parser (RattleScript face)
  # ---------------------------------------------------------------------------

  defp parse_affine_toml(toml_text, pkg_info, version) do
    fields = extract_toml_section(toml_text, "package")
    pkg_name = fields["name"] || pkg_info.name

    # Determine if this is a native Rattle package or an AffineScript package
    # exposed under the Rattle face.
    forth_atom =
      if fields["face"] == "rattlescript" or String.starts_with?(pkg_name, "rattle-") do
        :rattlescript
      else
        :affinescript
      end

    pkg = %ResolvedPackage{
      package: pkg_name,
      version: fields["version"] || version,
      forth: forth_atom,
      registry_url: pkg_info.url,
      tarball_url: "#{pkg_info.url}/archive/#{version}.tar.gz",
      checksum: nil,
      checksum_algo: :sha256,
      manifest: %ManifestFormat{
        name: pkg_name,
        version: fields["version"] || version,
        description: fields["description"] || pkg_info[:description],
        license: fields["license"],
        homepage: fields["homepage"] || pkg_info.url,
        repository: fields["repository"] || pkg_info.url,
        authors: parse_toml_array(fields["authors"]) || default_authors(),
        keywords: parse_toml_array(fields["keywords"]) || default_rattle_keywords(),
        dependencies: %{},
        dev_dependencies: %{},
        source_forth: forth_atom,
        raw_manifest: Map.put(fields, "face", fields["face"] || "rattlescript")
      },
      attestations: [],
      resolved_deps: []
    }

    {:ok, pkg}
  end

  defp curated_to_resolved(pkg_info, version) do
    %ResolvedPackage{
      package: pkg_info.name,
      version: version,
      forth: :rattlescript,
      registry_url: pkg_info.url,
      tarball_url: "#{pkg_info.url}/archive/#{version}.tar.gz",
      checksum: nil,
      checksum_algo: :sha256,
      manifest: %ManifestFormat{
        name: pkg_info.name,
        version: version,
        description: pkg_info.description,
        license: "PMPL-1.0-or-later",
        homepage: pkg_info.url,
        repository: pkg_info.url,
        authors: default_authors(),
        keywords: default_rattle_keywords(),
        dependencies: %{},
        dev_dependencies: %{},
        source_forth: :rattlescript,
        raw_manifest: %{"registry" => "rattlescript-curated", "face" => "rattlescript"}
      },
      attestations: [],
      resolved_deps: []
    }
  end

  # ---------------------------------------------------------------------------
  # Registry response parsers (future)
  # ---------------------------------------------------------------------------

  defp parse_registry_package(data, version) do
    forth_atom = if data["face"] == "rattlescript", do: :rattlescript, else: :affinescript

    %ResolvedPackage{
      package: data["name"],
      version: version,
      forth: forth_atom,
      registry_url: @base_url,
      tarball_url: "#{@base_url}/packages/#{data["name"]}/#{version}/download",
      checksum: data["checksum"],
      checksum_algo: :sha256,
      manifest: %ManifestFormat{
        name: data["name"],
        version: version,
        description: data["description"],
        license: data["license"],
        homepage: data["homepage"],
        repository: data["repository"],
        authors: data["authors"] || [],
        keywords: data["keywords"] || [],
        dependencies: data["dependencies"] || %{},
        dev_dependencies: data["dev_dependencies"] || %{},
        source_forth: forth_atom,
        raw_manifest: data
      },
      attestations: data["attestations"] || [],
      resolved_deps: []
    }
  end

  defp parse_search_result(result) do
    %{
      name: result["name"],
      version: result["latest_version"],
      description: result["description"],
      downloads: result["downloads"] || 0,
      recent_downloads: result["recent_downloads"] || 0
    }
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp find_curated(name) do
    case Enum.find(@known_packages, fn p -> p.name == name end) do
      nil -> :not_found
      pkg -> {:ok, pkg}
    end
  end

  defp extract_toml_section(toml_text, section_name) do
    lines = String.split(toml_text, "\n")

    {_in_section, fields} =
      Enum.reduce(lines, {false, %{}}, fn line, {inside, acc} ->
        trimmed = String.trim(line)

        cond do
          trimmed == "[#{section_name}]" ->
            {true, acc}

          String.starts_with?(trimmed, "[") ->
            {false, acc}

          inside ->
            case String.split(trimmed, " = ", parts: 2) do
              [key, value] ->
                {true, Map.put(acc, String.trim(key), String.trim(value, "\""))}

              _ ->
                {inside, acc}
            end

          true ->
            {inside, acc}
        end
      end)

    fields
  end

  defp parse_toml_array(nil), do: nil
  defp parse_toml_array(str) when is_binary(str) do
    str
    |> String.trim("[")
    |> String.trim("]")
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.map(&String.trim(&1, "\""))
    |> Enum.reject(&(&1 == ""))
  end

  defp default_authors, do: ["Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>"]

  defp default_rattle_keywords,
    do: ["rattlescript", "affinescript", "python-face", "affine-types", "wasm"]
end
