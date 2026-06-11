# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Registries.AffineScript do
  @moduledoc """
  AffineScript package registry API client.

  AffineScript is an affine-typed, WASM-first functional language with
  resource guarantees (no use-after-move, bounded memory, effect tracking).

  Package manager: `affine` CLI  (tools/affine-pkg, Rust)
  Manifest format: `affine.toml`  ([package] section, Cargo.toml-style)
  Registry: https://packages.affinescript.dev/api/v1  (planned — git fallback now)
  Language ID: affinescript
  Source `:forth` atom: `:affinescript`

  Packages are hosted on GitHub under the hyperpolymath org until the
  central registry is deployed.  The curated list below covers the standard
  library and the first wave of community packages.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @base_url "https://packages.affinescript.dev/api/v1"
  @fallback_mode :git  # Switch to :registry once packages.affinescript.dev is live

  # ---------------------------------------------------------------------------
  # Curated package catalogue
  # Entries: name, url, path (optional sub-directory), description
  # ---------------------------------------------------------------------------

  @known_packages [
    %{
      name: "affinescript-std",
      url: "https://github.com/hyperpolymath/affinescript-std",
      description: "AffineScript standard library — core types, IO, effects, resources"
    },
    %{
      name: "affine-wasm",
      url: "https://github.com/hyperpolymath/affine-wasm",
      description: "WASM host bindings and memory-safe foreign-function bridge for AffineScript"
    },
    %{
      name: "affine-effects",
      url: "https://github.com/hyperpolymath/affine-effects",
      description: "Effect-handler combinators and algebraic-effect primitives for AffineScript"
    },
    %{
      name: "affine-resources",
      url: "https://github.com/hyperpolymath/affine-resources",
      description: "Resource-budget types: time, memory, energy, carbon (shadow-price API)"
    },
    %{
      name: "affine-test",
      url: "https://github.com/hyperpolymath/affine-test",
      description: "Property-based testing framework for AffineScript (QuickCheck-style)"
    },
    %{
      name: "affine-json",
      url: "https://github.com/hyperpolymath/affine-json",
      description: "Resource-safe JSON parsing and encoding for AffineScript"
    },
    %{
      name: "affine-http",
      url: "https://github.com/hyperpolymath/affine-http",
      description: "HTTP client/server with linear connection handles for AffineScript"
    },
    %{
      name: "affine-fmt",
      url: "https://github.com/hyperpolymath/affine-fmt",
      description: "Formatting utilities: string interpolation, pretty-printing, ANSI colour"
    },
    %{
      name: "affine-row",
      url: "https://github.com/hyperpolymath/affine-row",
      description: "Row-polymorphism extensions: structural records, open unions, row variables"
    },
    %{
      name: "affine-crypto",
      url: "https://github.com/hyperpolymath/affine-crypto",
      description: "Post-quantum cryptographic primitives (Dilithium5, Kyber-1024) for AffineScript"
    },
    %{
      name: "typed-wasm-rt",
      url: "https://github.com/hyperpolymath/typed-wasm",
      path: "runtime",
      description: "Typed-WASM runtime embeddings for AffineScript compiled modules"
    },
    %{
      name: "groovebind",
      url: "https://github.com/hyperpolymath/groove",
      path: "bindings/affinescript",
      description: "Groove protocol bindings for AffineScript — plug-and-play inter-service comms"
    }
  ]

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Fetch package metadata from the AffineScript registry (or git fallback).

  ## Examples

      iex> AffineScript.fetch_package("affine-std", "latest")
      {:ok, %ResolvedPackage{name: "affine-std", ...}}

      iex> AffineScript.fetch_package("unknown-pkg")
      {:error, :not_found}
  """
  def fetch_package(name, version \\ "latest") do
    case @fallback_mode do
      :git -> fetch_from_git(name, version)
      :registry -> fetch_from_registry(name, version)
    end
  end

  @doc """
  Search the curated AffineScript package catalogue.

  ## Examples

      iex> AffineScript.search("wasm")
      {:ok, [%ResolvedPackage{...}]}
  """
  def search(query, opts \\ []) do
    case @fallback_mode do
      :git -> search_curated(query, opts)
      :registry -> search_registry(query, opts)
    end
  end

  @doc """
  Check whether a package exists in the curated catalogue.
  """
  def exists?(name) do
    case @fallback_mode do
      :git -> curated_exists?(name)
      :registry -> registry_exists?(name)
    end
  end

  @doc """
  List known versions of an AffineScript package.
  In git mode, queries the repository for git tags via the GitHub API.
  """
  def versions(name) do
    case @fallback_mode do
      :git -> git_versions(name)
      :registry -> registry_versions(name)
    end
  end

  # ---------------------------------------------------------------------------
  # Registry mode (future — once packages.affinescript.dev is deployed)
  # ---------------------------------------------------------------------------

  defp fetch_from_registry(name, version) do
    url = "#{@base_url}/packages/#{URI.encode(name)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        target_version = if version == "latest", do: body["latest_version"], else: version
        {:ok, parse_registry_package(body, target_version)}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp search_registry(query, opts) do
    limit = Keyword.get(opts, :limit, 20)
    url = "#{@base_url}/packages?q=#{URI.encode(query)}&limit=#{limit}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} when is_list(body) ->
        {:ok, Enum.map(body, &parse_search_result/1)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp registry_exists?(name) do
    url = "#{@base_url}/packages/#{URI.encode(name)}"
    case VerifiedHttp.get(url, receive_timeout: 5_000) do
      {:ok, _} -> true
      _ -> false
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
        # Try standard GitHub locations before giving up
        try_github_locations(name, version)
    end
  end

  defp search_curated(query, _opts) do
    query_lower = String.downcase(query)

    results =
      Enum.filter(@known_packages, fn pkg ->
        text = String.downcase("#{pkg.name} #{pkg.description}")
        String.contains?(text, query_lower)
      end)

    packages = Enum.map(results, &curated_to_resolved(&1, "latest"))
    {:ok, packages}
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
        # Query GitHub tags API
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
        {:error, :not_found}
    end
  end

  defp try_github_locations(name, version) do
    urls = [
      "https://github.com/hyperpolymath/#{name}",
      "https://github.com/hyperpolymath/affinescript-#{name}",
      "https://github.com/affinescript/#{name}"
    ]

    Enum.find_value(urls, {:error, :not_found}, fn url ->
      case fetch_git_manifest(%{name: name, url: url, description: nil}, version) do
        {:ok, pkg} -> {:ok, pkg}
        _ -> nil
      end
    end)
  end

  # Fetch and parse `affine.toml` from a git repository.
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
        # No affine.toml — synthesise from curated metadata
        {:ok, curated_to_resolved(pkg_info, version)}
    end
  end

  # ---------------------------------------------------------------------------
  # affine.toml parser
  # Handles the [package] section of AffineScript's Cargo.toml-style manifest.
  # ---------------------------------------------------------------------------

  defp parse_affine_toml(toml_text, pkg_info, version) do
    fields = extract_toml_section(toml_text, "package")
    pkg_name = fields["name"] || pkg_info.name

    pkg = %ResolvedPackage{
      package: pkg_name,
      version: fields["version"] || version,
      forth: :affinescript,
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
        keywords: parse_toml_array(fields["keywords"]) || default_keywords(),
        dependencies: %{},
        dev_dependencies: %{},
        source_forth: :affinescript,
        raw_manifest: fields
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
      forth: :affinescript,
      registry_url: pkg_info.url,
      tarball_url: "#{pkg_info.url}/archive/#{version}.tar.gz",
      checksum: nil,
      checksum_algo: :sha256,
      manifest: %ManifestFormat{
        name: pkg_info.name,
        version: version,
        description: pkg_info.description,
        license: "MPL-2.0",
        homepage: pkg_info.url,
        repository: pkg_info.url,
        authors: default_authors(),
        keywords: default_keywords(),
        dependencies: %{},
        dev_dependencies: %{},
        source_forth: :affinescript,
        raw_manifest: %{"registry" => "affinescript-curated"}
      },
      attestations: [],
      resolved_deps: []
    }
  end

  # ---------------------------------------------------------------------------
  # Registry response parsers (future)
  # ---------------------------------------------------------------------------

  defp parse_registry_package(data, version) do
    %ResolvedPackage{
      package: data["name"],
      version: version,
      forth: :affinescript,
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
        source_forth: :affinescript,
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

  # Minimal TOML [section] extractor — handles key = "value" and key = ["a","b"] lines.
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

  # Parse a TOML inline array string ["a", "b", "c"] into a list.
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
  defp default_keywords, do: ["affinescript", "affine-types", "wasm", "resource-safety"]
end
