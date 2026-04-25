# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Registries.Ephapax do
  @moduledoc """
  Ephapax package registry API client.

  Ephapax is a dyadic linear/affine type system language targeting WasmGC,
  with formally verified memory safety (Coq proofs) and first-class linear
  resource management.  It is the formal verification backbone of the
  hyperpolymath type theory stack.

  Package manager: `epx` CLI  (nextgen-languages/ephapax/tools/epx-pkg, OCaml)
  Manifest format: `ephapax.toml` or `opsm.toml` ([package] forth = "ephapax")
  Registry: https://packages.ephapax.dev/api/v1  (planned — git fallback now)
  Language ID: ephapax
  Source `:forth` atom: `:ephapax`
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Manifest.OpsmToml
  alias Opsm.Verified.Http, as: VerifiedHttp

  @base_url "https://packages.ephapax.dev/api/v1"
  @fallback_mode :git

  @known_packages [
    %{
      name: "ephapax-std",
      url: "https://github.com/hyperpolymath/ephapax",
      path: "stdlib",
      description: "Ephapax standard library — linear collections, safe I/O, effect primitives"
    },
    %{
      name: "ephapax-wasm",
      url: "https://github.com/hyperpolymath/ephapax",
      path: "target/wasmgc",
      description: "WasmGC compilation target for Ephapax — linear heap, GC integration"
    },
    %{
      name: "ephapax-linear",
      url: "https://github.com/hyperpolymath/ephapax",
      path: "linear",
      description: "Linear type utilities — borrows, moves, uniqueness, fractional permissions"
    },
    %{
      name: "ephapax-proofs",
      url: "https://github.com/hyperpolymath/ephapax",
      path: "proofs",
      description: "Coq/Rocq proof library — preservation, progress, linear metatheory"
    },
    %{
      name: "ephapax-test",
      url: "https://github.com/hyperpolymath/ephapax",
      path: "test",
      description: "Property-based testing for Ephapax — linear-safe generator framework"
    },
    %{
      name: "ephapax-effects",
      url: "https://github.com/hyperpolymath/ephapax",
      path: "effects",
      description: "Algebraic effects with linear resources for Ephapax"
    },
    %{
      name: "ephapax-pipewire",
      url: "https://github.com/hyperpolymath/ephapax",
      path: "examples/pipewire",
      description: "PipeWire filter-node proving ground — linear audio buffer management"
    },
    %{
      name: "groovebind-ephapax",
      url: "https://github.com/hyperpolymath/groove",
      path: "bindings/ephapax",
      description: "Groove protocol bindings for Ephapax — linear inter-service comms"
    }
  ]

  def fetch_package(name, version \\ "latest") do
    case @fallback_mode do
      :git -> fetch_from_git(name, version)
      :registry -> fetch_from_registry(name, version)
    end
  end

  def search(query, opts \\ []) do
    case @fallback_mode do
      :git -> search_curated(query, opts)
      :registry -> search_registry(query, opts)
    end
  end

  def exists?(name) do
    case @fallback_mode do
      :git -> curated_exists?(name)
      :registry -> registry_exists?(name)
    end
  end

  def versions(name) do
    case @fallback_mode do
      :git -> git_versions(name)
      :registry -> registry_versions(name)
    end
  end

  defp fetch_from_registry(name, version) do
    url = "#{@base_url}/packages/#{URI.encode(name)}"
    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        target = if version == "latest", do: body["latest_version"], else: version
        {:ok, parse_registry_package(body, target)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp search_registry(query, opts) do
    limit = Keyword.get(opts, :limit, 20)
    url = "#{@base_url}/packages?q=#{URI.encode(query)}&limit=#{limit}"
    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} when is_list(body) -> {:ok, Enum.map(body, &parse_search_result/1)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp registry_exists?(name) do
    case VerifiedHttp.get("#{@base_url}/packages/#{URI.encode(name)}", receive_timeout: 5_000) do
      {:ok, _} -> true
      _ -> false
    end
  end

  defp registry_versions(name) do
    url = "#{@base_url}/packages/#{URI.encode(name)}/versions"
    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} when is_list(body) -> {:ok, Enum.map(body, & &1["version"])}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_from_git(name, version) do
    case find_curated(name) do
      {:ok, pkg_info} -> fetch_git_manifest(pkg_info, version)
      :not_found -> try_github_locations(name, version)
    end
  end

  defp search_curated(query, _opts) do
    q = String.downcase(query)
    results = Enum.filter(@known_packages, fn p ->
      String.contains?(String.downcase("#{p.name} #{p.description}"), q)
    end)
    {:ok, Enum.map(results, &curated_to_resolved(&1, "latest"))}
  end

  defp curated_exists?(name), do: match?({:ok, _}, find_curated(name))

  defp git_versions(name) do
    case find_curated(name) do
      {:ok, pkg_info} ->
        tags_url =
          pkg_info.url
          |> String.replace("https://github.com/", "https://api.github.com/repos/")
          |> Kernel.<>("/tags")
        case VerifiedHttp.get_json(tags_url, receive_timeout: 10_000) do
          {:ok, tags} when is_list(tags) ->
            versions = Enum.map(tags, & &1["name"]) |> Enum.reject(&is_nil/1)
            {:ok, if(versions == [], do: ["main"], else: versions)}
          _ -> {:ok, ["main"]}
        end
      :not_found -> {:error, :not_found}
    end
  end

  defp try_github_locations(name, version) do
    urls = [
      "https://github.com/hyperpolymath/#{name}",
      "https://github.com/hyperpolymath/ephapax-#{name}"
    ]
    Enum.find_value(urls, {:error, :not_found}, fn url ->
      case fetch_git_manifest(%{name: name, url: url, description: nil}, version) do
        {:ok, pkg} -> {:ok, pkg}
        _ -> nil
      end
    end)
  end

  defp fetch_git_manifest(pkg_info, version) do
    branch = if version in ["latest", "main"], do: "main", else: version
    path = Map.get(pkg_info, :path)
    base = pkg_info.url

    try_url = fn manifest ->
      url = if path, do: "#{base}/raw/#{branch}/#{path}/#{manifest}",
                    else: "#{base}/raw/#{branch}/#{manifest}"
      case VerifiedHttp.get(url, receive_timeout: 10_000) do
        {:ok, %{body: text}} -> {:ok, text}
        _ -> :not_found
      end
    end

    with :not_found <- try_url.("opsm.toml"),
         :not_found <- try_url.("ephapax.toml") do
      {:ok, curated_to_resolved(pkg_info, version)}
    else
      {:ok, toml_text} -> parse_ephapax_toml(toml_text, pkg_info, version)
    end
  end

  defp parse_ephapax_toml(toml_text, pkg_info, version) do
    # Use canonical OpsmToml parser; fall back to pkg_info fields on parse failure.
    manifest =
      case OpsmToml.parse(toml_text) do
        {:ok, m} ->
          %{m | source_forth: :ephapax}

        {:error, _} ->
          %ManifestFormat{
            name: pkg_info.name,
            version: version,
            description: pkg_info[:description],
            license: "PMPL-1.0-or-later",
            homepage: pkg_info.url,
            repository: pkg_info.url,
            authors: default_authors(),
            keywords: default_keywords(),
            dependencies: %{},
            dev_dependencies: %{},
            source_forth: :ephapax,
            raw_manifest: %{}
          }
      end

    pkg_name = manifest.name || pkg_info.name
    resolved_version = manifest.version || version

    pkg = %ResolvedPackage{
      package: pkg_name,
      version: resolved_version,
      forth: :ephapax,
      registry_url: pkg_info.url,
      tarball_url: "#{pkg_info.url}/archive/#{version}.tar.gz",
      checksum: nil,
      checksum_algo: :sha256,
      manifest: manifest,
      attestations: [],
      resolved_deps: []
    }
    {:ok, pkg}
  end

  defp curated_to_resolved(pkg_info, version) do
    %ResolvedPackage{
      package: pkg_info.name,
      version: version,
      forth: :ephapax,
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
        keywords: default_keywords(),
        dependencies: %{},
        dev_dependencies: %{},
        source_forth: :ephapax,
        raw_manifest: %{"registry" => "ephapax-curated"}
      },
      attestations: [],
      resolved_deps: []
    }
  end

  defp parse_registry_package(data, version) do
    %ResolvedPackage{
      package: data["name"],
      version: version,
      forth: :ephapax,
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
        source_forth: :ephapax,
        raw_manifest: data
      },
      attestations: data["attestations"] || [],
      resolved_deps: []
    }
  end

  defp parse_search_result(r) do
    %{name: r["name"], version: r["latest_version"],
      description: r["description"], downloads: r["downloads"] || 0}
  end

  defp find_curated(name) do
    case Enum.find(@known_packages, &(&1.name == name)) do
      nil -> :not_found
      pkg -> {:ok, pkg}
    end
  end

  defp default_authors, do: ["Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>"]
  defp default_keywords, do: ["ephapax", "linear-types", "affine", "wasmgc", "formal-verification"]
end
