# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Registries.HyperpPolymathForge do
  @moduledoc """
  Hyperpolymath Forge Registry (HFR) — first-class discovery for every
  package authored by hyperpolymath.

  Any GitHub repository under the `hyperpolymath` organisation that ships
  an `opsm.toml` at its root is automatically a first-class OPSM package.
  No curated list maintenance required.

  ## Discovery strategy

  1. List all repositories under `github.com/hyperpolymath` via the
     GitHub REST API (paginated, public + private with token).
  2. For each repo, fetch `opsm.toml` from the default branch.
  3. If `opsm.toml` is present, index the package into an ETS cache
     with a 30-minute TTL.
  4. Serve `search/2`, `fetch_package/2`, `exists?/1`, and `versions/1`
     from the cache, refreshing lazily on miss.

  ## Environment

  - `GITHUB_TOKEN` — personal access token for higher rate limits and
    private repository access.  Optional but strongly recommended.

  ## Filtering

  `search(query, forth: :affinescript)` restricts to a specific language
  ecosystem.  The `:forth` value matches the `forth` field in `opsm.toml`.

  ## Self-inclusion

  `odds-and-sods-package-manager` ships its own `opsm.toml`, so OPSM
  is itself a first-class HFR package and can be updated with
  `opsm update opsm --registry hf`.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @github_org "hyperpolymath"
  @github_api "https://api.github.com"
  @cache_table :hfr_cache
  @cache_ttl_ms 30 * 60 * 1_000  # 30 minutes
  @per_page 100
  @opsm_manifest_name "opsm.toml"

  # ---------------------------------------------------------------------------
  # ETS cache initialisation — called once by Opsm.Application
  # ---------------------------------------------------------------------------

  @doc """
  Ensure the HFR ETS cache table exists.
  Idempotent — safe to call multiple times.
  """
  def ensure_cache do
    case :ets.info(@cache_table) do
      :undefined ->
        :ets.new(@cache_table, [:named_table, :public, :set, read_concurrency: true])
      _ ->
        :ok
    end
  end

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Fetch a package from the Hyperpolymath Forge Registry.

  The package name must match the `[package] name` field in `opsm.toml`.
  On cache miss, refreshes the full org index before looking up.

  ## Examples

      iex> HyperpPolymathForge.fetch_package("odds-and-sods-package-manager", "latest")
      {:ok, %ResolvedPackage{name: "odds-and-sods-package-manager", ...}}
  """
  def fetch_package(name, version \\ "latest") do
    case lookup_cached(name) do
      {:hit, pkg_info} ->
        resolve_package(pkg_info, version)

      :miss ->
        with :ok <- refresh_index() do
          case lookup_cached(name) do
            {:hit, pkg_info} -> resolve_package(pkg_info, version)
            :miss -> {:error, :not_found}
          end
        end
    end
  end

  @doc """
  Search hyperpolymath packages by keyword.

  Accepts an optional `forth:` filter to restrict to a language ecosystem.

  ## Options

  - `:forth` — atom, e.g. `:affinescript`, `:ephapax`.  Filters by the
    `forth` field in each package's `opsm.toml`.
  - `:limit` — integer, default 50.

  ## Examples

      iex> HyperpPolymathForge.search("wasm")
      {:ok, [%ResolvedPackage{...}]}

      iex> HyperpPolymathForge.search("types", forth: :ephapax)
      {:ok, [%ResolvedPackage{...}]}
  """
  def search(query, opts \\ []) do
    ensure_index()

    forth_filter = Keyword.get(opts, :forth)
    limit = Keyword.get(opts, :limit, 50)
    query_lower = String.downcase(query)

    results =
      :ets.tab2list(@cache_table)
      |> Enum.filter(fn {_name, entry, _exp} ->
        is_map(entry) and
          entry[:type] == :package and
          entry_matches_query?(entry, query_lower) and
          (forth_filter == nil or entry[:forth] == forth_filter)
      end)
      |> Enum.take(limit)
      |> Enum.map(fn {_name, entry, _exp} ->
        curated_to_resolved(entry, "latest")
      end)

    {:ok, results}
  end

  @doc """
  Check whether a repository with the given package name exists in the
  hyperpolymath org and ships `opsm.toml`.
  """
  def exists?(name) do
    ensure_index()
    case lookup_cached(name) do
      {:hit, _} -> true
      :miss -> false
    end
  end

  @doc """
  List all git tags for a hyperpolymath package.

  In practice this returns GitHub release tag names.  Falls back to
  `["main"]` when no tags are present.
  """
  def versions(name) do
    case lookup_cached(name) do
      {:hit, pkg_info} ->
        fetch_github_tags(pkg_info[:repo_name] || name)

      :miss ->
        with :ok <- refresh_index() do
          case lookup_cached(name) do
            {:hit, pkg_info} -> fetch_github_tags(pkg_info[:repo_name] || name)
            :miss -> {:error, :not_found}
          end
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Index management
  # ---------------------------------------------------------------------------

  defp ensure_index do
    ensure_cache()
    # Trigger refresh if cache is empty or stale
    if :ets.info(@cache_table, :size) == 0 do
      refresh_index()
    end
    :ok
  end

  @doc """
  Crawl the hyperpolymath GitHub organisation and index all repos that
  contain `opsm.toml`.  Stores results in the ETS cache.
  """
  def refresh_index do
    ensure_cache()

    case fetch_org_repos() do
      {:ok, repos} ->
        # Fetch opsm.toml in parallel (bounded concurrency — max 5 at a time)
        repos
        |> Task.async_stream(
          fn repo -> index_repo(repo) end,
          max_concurrency: 5,
          timeout: 10_000,
          on_timeout: :kill_task
        )
        |> Stream.run()

        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # GitHub API helpers
  # ---------------------------------------------------------------------------

  defp fetch_org_repos do
    collect_pages("#{@github_api}/orgs/#{@github_org}/repos", [])
  end

  defp collect_pages(url, acc) do
    params = "?per_page=#{@per_page}&type=all"
    target = if String.contains?(url, "?"), do: url, else: url <> params

    case VerifiedHttp.get_json(target, headers: github_headers(), receive_timeout: 15_000) do
      {:ok, repos} when is_list(repos) ->
        {:ok, acc ++ repos}

      {:error, reason} ->
        {:error, reason}

      _ ->
        {:ok, acc}
    end
  end

  defp index_repo(repo) do
    repo_name = repo["name"]
    default_branch = repo["default_branch"] || "main"
    raw_url = "https://raw.githubusercontent.com/#{@github_org}/#{repo_name}/#{default_branch}/#{@opsm_manifest_name}"

    case VerifiedHttp.get(raw_url, headers: github_headers(), receive_timeout: 5_000) do
      {:ok, %{status: 200, body: toml_text}} ->
        parsed = parse_opsm_toml(toml_text)
        pkg_name = parsed["name"] || repo_name
        expiry = System.monotonic_time(:millisecond) + @cache_ttl_ms

        entry = %{
          type: :package,
          pkg_name: pkg_name,
          repo_name: repo_name,
          default_branch: default_branch,
          version: parsed["version"] || "0.0.0",
          description: parsed["description"] || repo["description"] || "",
          license: parsed["license"] || "PMPL-1.0-or-later",
          authors: parsed["authors"] || default_authors(),
          keywords: parsed["keywords"] || [],
          forth: safe_to_atom(parsed["forth"]),
          repo_url: repo["html_url"],
          raw_toml: parsed
        }

        :ets.insert(@cache_table, {pkg_name, entry, expiry})

      _ ->
        # No opsm.toml — not a managed package, skip silently
        :ok
    end
  end

  defp fetch_github_tags(repo_name) do
    url = "#{@github_api}/repos/#{@github_org}/#{repo_name}/tags"

    case VerifiedHttp.get_json(url, headers: github_headers(), receive_timeout: 10_000) do
      {:ok, tags} when is_list(tags) ->
        versions = tags |> Enum.map(& &1["name"]) |> Enum.reject(&is_nil/1)
        {:ok, if(versions == [], do: ["main"], else: versions)}

      _ ->
        {:ok, ["main"]}
    end
  end

  defp github_headers do
    token = System.get_env("GITHUB_TOKEN") || Application.get_env(:opsm, :github_token, nil)

    base = [{"Accept", "application/vnd.github+json"},
            {"X-GitHub-Api-Version", "2022-11-28"}]

    if token do
      [{"Authorization", "Bearer #{token}"} | base]
    else
      base
    end
  end

  # ---------------------------------------------------------------------------
  # Cache helpers
  # ---------------------------------------------------------------------------

  defp lookup_cached(name) do
    ensure_cache()
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@cache_table, name) do
      [{^name, entry, expiry}] when expiry > now ->
        {:hit, entry}

      [{^name, _entry, _expired}] ->
        :ets.delete(@cache_table, name)
        :miss

      [] ->
        :miss
    end
  end

  # ---------------------------------------------------------------------------
  # Resolution helpers
  # ---------------------------------------------------------------------------

  defp resolve_package(pkg_info, version) do
    repo_name = pkg_info[:repo_name]
    branch = if version in ["latest", "main"], do: pkg_info[:default_branch] || "main", else: version

    pkg = %ResolvedPackage{
      package: pkg_info[:pkg_name],
      version: version,
      forth: pkg_info[:forth] || :hyperpolymath,
      registry_url: pkg_info[:repo_url],
      tarball_url: "https://github.com/#{@github_org}/#{repo_name}/archive/refs/heads/#{branch}.tar.gz",
      checksum: nil,
      checksum_algo: :sha256,
      manifest: %ManifestFormat{
        name: pkg_info[:pkg_name],
        version: pkg_info[:version],
        description: pkg_info[:description],
        license: pkg_info[:license],
        homepage: pkg_info[:repo_url],
        repository: pkg_info[:repo_url],
        authors: pkg_info[:authors] || default_authors(),
        keywords: pkg_info[:keywords] || [],
        dependencies: pkg_info[:raw_toml]["dependencies"] || %{},
        dev_dependencies: pkg_info[:raw_toml]["dev-dependencies"] || %{},
        source_forth: pkg_info[:forth] || :hyperpolymath,
        raw_manifest: pkg_info[:raw_toml]
      },
      attestations: [],
      resolved_deps: []
    }

    {:ok, pkg}
  end

  defp curated_to_resolved(entry, version) do
    %ResolvedPackage{
      package: entry[:pkg_name],
      version: entry[:version] || version,
      forth: entry[:forth] || :hyperpolymath,
      registry_url: entry[:repo_url],
      tarball_url: "https://github.com/#{@github_org}/#{entry[:repo_name]}/archive/refs/heads/main.tar.gz",
      checksum: nil,
      checksum_algo: :sha256,
      manifest: %ManifestFormat{
        name: entry[:pkg_name],
        version: entry[:version] || version,
        description: entry[:description],
        license: entry[:license] || "PMPL-1.0-or-later",
        homepage: entry[:repo_url],
        repository: entry[:repo_url],
        authors: entry[:authors] || default_authors(),
        keywords: entry[:keywords] || [],
        dependencies: %{},
        dev_dependencies: %{},
        source_forth: entry[:forth] || :hyperpolymath,
        raw_manifest: entry[:raw_toml] || %{}
      },
      attestations: [],
      resolved_deps: []
    }
  end

  # ---------------------------------------------------------------------------
  # opsm.toml parser
  # ---------------------------------------------------------------------------

  # Parses [package] and [dependencies] sections from an opsm.toml file.
  defp parse_opsm_toml(toml_text) do
    pkg_fields = extract_toml_section(toml_text, "package")
    deps_fields = extract_toml_section(toml_text, "dependencies")
    dev_deps_fields = extract_toml_section(toml_text, "dev-dependencies")

    pkg_fields
    |> Map.put("dependencies", deps_fields)
    |> Map.put("dev-dependencies", dev_deps_fields)
  end

  defp extract_toml_section(toml_text, section_name) do
    lines = String.split(toml_text, "\n")

    {_inside, fields} =
      Enum.reduce(lines, {false, %{}}, fn line, {inside, acc} ->
        trimmed = String.trim(line)

        cond do
          trimmed == "[#{section_name}]" ->
            {true, acc}

          String.starts_with?(trimmed, "[") and trimmed != "[#{section_name}]" ->
            {false, acc}

          inside and String.contains?(trimmed, " = ") ->
            [key | rest] = String.split(trimmed, " = ", parts: 2)
            raw_value = Enum.join(rest, " = ")
            value = strip_toml_string(raw_value)
            {true, Map.put(acc, String.trim(key), value)}

          true ->
            {inside, acc}
        end
      end)

    fields
  end

  defp strip_toml_string(val) do
    val = String.trim(val)

    cond do
      String.starts_with?(val, "\"\"\"") ->
        val |> String.trim_leading("\"\"\"") |> String.trim_trailing("\"\"\"") |> String.trim()

      String.starts_with?(val, "\"") and String.ends_with?(val, "\"") ->
        val |> String.trim_leading("\"") |> String.trim_trailing("\"")

      String.starts_with?(val, "[") ->
        # Inline array — parse quoted strings
        val
        |> String.trim("[")
        |> String.trim("]")
        |> String.split(",")
        |> Enum.map(&(&1 |> String.trim() |> String.trim("\"")))
        |> Enum.reject(&(&1 == ""))

      true ->
        val
    end
  end

  # ---------------------------------------------------------------------------
  # Search helpers
  # ---------------------------------------------------------------------------

  defp entry_matches_query?(entry, query_lower) do
    text =
      [entry[:pkg_name], entry[:description] | List.wrap(entry[:keywords])]
      |> Enum.map(&to_string/1)
      |> Enum.join(" ")
      |> String.downcase()

    String.contains?(text, query_lower)
  end

  # ---------------------------------------------------------------------------
  # Defaults
  # ---------------------------------------------------------------------------

  defp default_authors, do: ["Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>"]

  defp safe_to_atom(nil), do: nil
  defp safe_to_atom(str) when is_binary(str) do
    try do
      String.to_existing_atom(str)
    rescue
      ArgumentError -> String.to_atom(str)
    end
  end
  defp safe_to_atom(atom) when is_atom(atom), do: atom
end
