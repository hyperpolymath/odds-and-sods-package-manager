# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Registries.Lithoglyph do
  @moduledoc """
  Lithoglyph package registry API client.

  Lithoglyph is a narrative-first database system in nextgen-databases.
  It models data as stories — entities are characters, relationships are
  plot arcs, and queries read like natural language.  The query language
  is Glyphbase (formerly FormBD — never use that name).

  Package manager: native OPSM via `hf` registry
  Manifest format: `lithoglyph.toml` or `opsm.toml` ([package] forth = "lithoglyph")
  Registry: https://packages.lithoglyph.dev/api/v1  (planned — git fallback now)
  Language ID: lithoglyph
  Source `:forth` atom: `:lithoglyph`

  IMPORTANT: The query language is "Glyphbase", never "FormBD" or "GQL" alone.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @base_url "https://packages.lithoglyph.dev/api/v1"
  @fallback_mode :git

  @known_packages [
    %{
      name: "lithoglyph-core",
      url: "https://github.com/hyperpolymath/nextgen-databases",
      path: "lithoglyph",
      description: "Lithoglyph core — narrative data model, character/arc types, Glyphbase engine"
    },
    %{
      name: "lithoglyph-client",
      url: "https://github.com/hyperpolymath/nextgen-databases",
      path: "lithoglyph/client",
      description: "Lithoglyph client library — Glyphbase queries, narrative cursors, streaming"
    },
    %{
      name: "lithoglyph-elixir",
      url: "https://github.com/hyperpolymath/nextgen-databases",
      path: "lithoglyph/connectors/elixir",
      description: "Elixir connector for Lithoglyph — Ecto-compatible, streaming, supervision"
    },
    %{
      name: "lithoglyph-rust",
      url: "https://github.com/hyperpolymath/nextgen-databases",
      path: "lithoglyph/connectors/rust",
      description: "Rust connector for Lithoglyph — async/await, Tokio-compatible"
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

      {:error, reason} ->
        {:error, reason}
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

    results =
      Enum.filter(@known_packages, fn p ->
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
      "https://github.com/hyperpolymath/lithoglyph-#{name}"
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
      url =
        if path,
          do: "#{base}/raw/#{branch}/#{path}/#{manifest}",
          else: "#{base}/raw/#{branch}/#{manifest}"

      case VerifiedHttp.get(url, receive_timeout: 10_000) do
        {:ok, %{body: text}} -> {:ok, text}
        _ -> :not_found
      end
    end

    with :not_found <- try_url.("opsm.toml"),
         :not_found <- try_url.("lithoglyph.toml") do
      {:ok, curated_to_resolved(pkg_info, version)}
    else
      {:ok, toml_text} -> parse_lithoglyph_toml(toml_text, pkg_info, version)
    end
  end

  defp parse_lithoglyph_toml(toml_text, pkg_info, version) do
    fields = extract_toml_section(toml_text, "package")
    pkg_name = fields["name"] || pkg_info.name

    pkg = %ResolvedPackage{
      package: pkg_name,
      version: fields["version"] || version,
      forth: :lithoglyph,
      registry_url: pkg_info.url,
      tarball_url: "#{pkg_info.url}/archive/#{version}.tar.gz",
      checksum: nil,
      checksum_algo: :sha256,
      manifest: %ManifestFormat{
        name: pkg_name,
        version: fields["version"] || version,
        description: fields["description"] || pkg_info[:description],
        license: fields["license"] || "MPL-2.0",
        homepage: fields["homepage"] || pkg_info.url,
        repository: fields["repository"] || pkg_info.url,
        authors: parse_toml_array(fields["authors"]) || default_authors(),
        keywords: parse_toml_array(fields["keywords"]) || default_keywords(),
        dependencies: %{},
        dev_dependencies: %{},
        source_forth: :lithoglyph,
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
      forth: :lithoglyph,
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
        source_forth: :lithoglyph,
        raw_manifest: %{"registry" => "lithoglyph-curated"}
      },
      attestations: [],
      resolved_deps: []
    }
  end

  defp parse_registry_package(data, version) do
    %ResolvedPackage{
      package: data["name"],
      version: version,
      forth: :lithoglyph,
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
        source_forth: :lithoglyph,
        raw_manifest: data
      },
      attestations: data["attestations"] || [],
      resolved_deps: []
    }
  end

  defp parse_search_result(r) do
    %{
      name: r["name"],
      version: r["latest_version"],
      description: r["description"],
      downloads: r["downloads"] || 0
    }
  end

  defp find_curated(name) do
    case Enum.find(@known_packages, &(&1.name == name)) do
      nil -> :not_found
      pkg -> {:ok, pkg}
    end
  end

  defp extract_toml_section(toml_text, section_name) do
    {_inside, fields} =
      String.split(toml_text, "\n")
      |> Enum.reduce({false, %{}}, fn line, {inside, acc} ->
        t = String.trim(line)

        cond do
          t == "[#{section_name}]" ->
            {true, acc}

          String.starts_with?(t, "[") ->
            {false, acc}

          inside ->
            case String.split(t, " = ", parts: 2) do
              [k, v] -> {true, Map.put(acc, String.trim(k), String.trim(v, "\""))}
              _ -> {inside, acc}
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
    |> Enum.map(&(&1 |> String.trim() |> String.trim("\"")))
    |> Enum.reject(&(&1 == ""))
  end

  defp default_authors, do: ["Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>"]
  defp default_keywords, do: ["lithoglyph", "glyphbase", "narrative-database", "story-data"]
end
