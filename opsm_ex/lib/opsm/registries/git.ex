# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Registries.Git do
  @moduledoc """
  Generic git repository adapter for package fetching.

  This adapter is used by language-specific adapters (like Idris2, Agda, Mercury)
  that distribute packages as git repositories without a central registry.

  Features:
  - Clone repositories at specific tags/branches/commits
  - List available tags (versions)
  - Handle subpaths within monorepos
  - Parse manifest files from repository
  - Cache cloned repositories locally

  ## Examples

      # Fetch package from git at specific tag
      Git.fetch_package("https://github.com/org/repo", "v1.0.0")

      # Fetch from subpath in monorepo
      Git.fetch_package(
        "https://github.com/idris-lang/Idris2",
        "v0.6.0",
        subpath: "libs/contrib"
      )

      # List available tags
      Git.list_tags("https://github.com/org/repo")
  """

  alias Opsm.Types.{ResolvedPackage, ManifestFormat}

  require Logger

  @cache_dir "/tmp/opsm-cache/git"

  @doc """
  Fetch package metadata from a git repository.

  ## Parameters

  - `url` - Git repository URL (https or ssh)
  - `version` - Git ref (tag, branch, commit SHA) or "latest" for default branch
  - `opts` - Options:
    - `:subpath` - Path within repository for monorepo support
    - `:manifest_file` - Expected manifest filename (auto-detected if omitted)
    - `:shallow` - Use shallow clone (default: true)

  ## Examples

      iex> Git.fetch_package("https://github.com/org/package", "v1.0.0")
      {:ok, %ResolvedPackage{...}}

      iex> Git.fetch_package("https://github.com/org/mono", "main",
      ...>   subpath: "packages/lib1")
      {:ok, %ResolvedPackage{...}}
  """
  @spec fetch_package(String.t(), String.t(), keyword()) ::
    {:ok, ResolvedPackage.t()} | {:error, term()}
  def fetch_package(url, version \\ "latest", opts \\ []) do
    Logger.debug("Fetching package from git: #{url}@#{version}")

    with {:ok, cache_path} <- ensure_cloned(url, opts),
         {:ok, ref} <- resolve_ref(cache_path, version),
         :ok <- checkout_ref(cache_path, ref),
         {:ok, manifest} <- find_manifest(cache_path, opts) do
      parse_manifest(manifest, url, ref, opts)
    else
      {:error, reason} ->
        Logger.error("Git fetch failed for #{url}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  List all tags (versions) available in a git repository.

  Returns tags in descending order (newest first) based on semver if applicable.

  ## Examples

      iex> Git.list_tags("https://github.com/org/repo")
      {:ok, ["v1.2.0", "v1.1.0", "v1.0.0"]}
  """
  @spec list_tags(String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def list_tags(url) do
    Logger.debug("Listing tags for git repo: #{url}")

    with {:ok, cache_path} <- ensure_cloned(url, shallow: false) do
      case Opsm.SafeExec.cmd("git", ["tag", "--sort=-v:refname"], cd: cache_path) do
        {output, 0} ->
          tags = output
          |> String.split("\n", trim: true)
          |> Enum.map(&String.trim/1)

          {:ok, tags}

        {error, _code} ->
          {:error, "Failed to list tags: #{error}"}
      end
    end
  end

  @doc """
  Get the default branch name for a repository.

  ## Examples

      iex> Git.default_branch("https://github.com/org/repo")
      {:ok, "main"}
  """
  @spec default_branch(String.t()) :: {:ok, String.t()} | {:error, term()}
  def default_branch(url) do
    with {:ok, cache_path} <- ensure_cloned(url, []) do
      case Opsm.SafeExec.cmd("git", ["symbolic-ref", "refs/remotes/origin/HEAD"], cd: cache_path) do
        {output, 0} ->
          branch = output
          |> String.trim()
          |> String.replace("refs/remotes/origin/", "")

          {:ok, branch}

        {_, _} ->
          # Fallback: try common default branches
          {:ok, "main"}
      end
    end
  end

  @doc """
  Check if a git URL is accessible.

  ## Examples

      iex> Git.accessible?("https://github.com/org/repo")
      true
  """
  @spec accessible?(String.t()) :: boolean()
  def accessible?(url) do
    case Opsm.SafeExec.cmd("git", ["ls-remote", "--exit-code", "--heads", url]) do
      {_, 0} -> true
      _ -> false
    end
  end

  # Private functions

  defp ensure_cloned(url, opts) do
    cache_path = cache_path_for_url(url)
    shallow = Keyword.get(opts, :shallow, true)

    cond do
      File.dir?(cache_path) ->
        # Already cloned, just fetch updates
        Logger.debug("Using cached git repo: #{cache_path}")
        update_cache(cache_path)
        {:ok, cache_path}

      true ->
        # Clone fresh
        Logger.debug("Cloning git repo to cache: #{url} -> #{cache_path}")
        clone_repo(url, cache_path, shallow)
    end
  end

  defp cache_path_for_url(url) do
    # Create a stable cache path from URL hash
    hash = :crypto.hash(:sha256, url) |> Base.encode16(case: :lower)
    Path.join(@cache_dir, hash)
  end

  defp clone_repo(url, dest, shallow) do
    File.mkdir_p!(Path.dirname(dest))

    args = if shallow do
      ["clone", "--depth", "1", url, dest]
    else
      ["clone", url, dest]
    end

    case Opsm.SafeExec.cmd("git", args, stderr_to_stdout: true) do
      {_, 0} ->
        Logger.info("Successfully cloned: #{url}")
        {:ok, dest}

      {error, _code} ->
        File.rm_rf(dest)  # Clean up partial clone
        {:error, "Git clone failed: #{error}"}
    end
  end

  defp update_cache(cache_path) do
    case Opsm.SafeExec.cmd("git", ["fetch", "--all"], cd: cache_path, stderr_to_stdout: true) do
      {_, 0} ->
        :ok

      {error, _code} ->
        Logger.warning("Failed to update git cache: #{error}")
        :ok  # Non-fatal, use existing cache
    end
  end

  defp resolve_ref(cache_path, "latest") do
    # Get default branch HEAD
    case Opsm.SafeExec.cmd("git", ["rev-parse", "origin/HEAD"], cd: cache_path) do
      {output, 0} ->
        {:ok, String.trim(output)}

      {_, _} ->
        # Fallback to main/master
        case Opsm.SafeExec.cmd("git", ["rev-parse", "origin/main"], cd: cache_path) do
          {output, 0} -> {:ok, String.trim(output)}
          {_, _} ->
            case Opsm.SafeExec.cmd("git", ["rev-parse", "origin/master"], cd: cache_path) do
              {output, 0} -> {:ok, String.trim(output)}
              {_, _} -> {:error, "Could not resolve default branch"}
            end
        end
    end
  end

  defp resolve_ref(cache_path, ref) do
    # Try to resolve ref (tag, branch, or commit SHA)
    case Opsm.SafeExec.cmd("git", ["rev-parse", ref], cd: cache_path) do
      {output, 0} ->
        {:ok, String.trim(output)}

      {_, _} ->
        # Try with origin/ prefix for branches
        case Opsm.SafeExec.cmd("git", ["rev-parse", "origin/#{ref}"], cd: cache_path) do
          {output, 0} ->
            {:ok, String.trim(output)}

          {_, _} ->
            {:error, "Could not resolve ref: #{ref}"}
        end
    end
  end

  defp checkout_ref(cache_path, ref) do
    case Opsm.SafeExec.cmd("git", ["checkout", ref], cd: cache_path, stderr_to_stdout: true) do
      {_, 0} ->
        :ok

      {error, _code} ->
        {:error, "Git checkout failed: #{error}"}
    end
  end

  defp find_manifest(cache_path, opts) do
    subpath = Keyword.get(opts, :subpath)
    search_path = if subpath do
      Path.join(cache_path, subpath)
    else
      cache_path
    end

    manifest_file = Keyword.get(opts, :manifest_file)

    cond do
      manifest_file && File.exists?(Path.join(search_path, manifest_file)) ->
        {:ok, Path.join(search_path, manifest_file)}

      true ->
        # Auto-detect manifest file
        detect_manifest(search_path)
    end
  end

  defp detect_manifest(search_path) do
    # Common manifest filenames by ecosystem
    candidates = [
      "package.json",      # npm
      "Cargo.toml",        # Rust
      "mix.exs",           # Elixir
      "*.nimble",          # Nim
      "*.ipkg",            # Idris2
      "*.cabal",           # Haskell
      "dune-project",      # OCaml
      "*.gpr",             # Ada
      "_CoqProject",       # Coq
      "lakefile.lean",     # Lean 4
      "META.json",         # Mercury
      "*.asd",             # Common Lisp
      "shard.yml"          # Crystal
    ]

    found = Enum.find_value(candidates, fn pattern ->
      matches = Path.wildcard(Path.join(search_path, pattern))
      if matches != [], do: List.first(matches)
    end)

    case found do
      nil -> {:error, "No manifest file found in repository"}
      path -> {:ok, path}
    end
  end

  defp parse_manifest(manifest_path, url, ref, opts) do
    # Read manifest and extract metadata
    # This is simplified - real implementation would parse each format
    Logger.debug("Parsing manifest: #{manifest_path}")

    manifest_type = detect_manifest_type(manifest_path)
    name = extract_name(manifest_path, manifest_type)
    version = extract_version(manifest_path, manifest_type, ref)

    # Create manifest format
    manifest = %ManifestFormat{
      name: name,
      version: version,
      repository: url,
      source_forth: :git,
      description: "Git repository package",
      license: nil,
      dependencies: %{},
      dev_dependencies: %{},
      raw_manifest: %{
        "registry" => "git",
        "location_type" => "git",
        "commit_sha" => ref,
        "manifest_file" => Path.basename(manifest_path),
        "manifest_type" => manifest_type,
        "subpath" => Keyword.get(opts, :subpath)
      }
    }

    package = %ResolvedPackage{
      package: name,
      version: version,
      forth: :git,
      registry_url: url,
      tarball_url: "#{url}/archive/#{ref}.tar.gz",
      checksum: nil,
      checksum_algo: :sha256,
      manifest: manifest,
      attestations: [],
      resolved_deps: []
    }

    {:ok, package}
  end

  defp detect_manifest_type(path) do
    name = Path.basename(path)

    cond do
      name == "package.json" -> :npm
      name == "Cargo.toml" -> :cargo
      name == "mix.exs" -> :hex
      String.ends_with?(name, ".nimble") -> :nimble
      String.ends_with?(name, ".ipkg") -> :idris2
      String.ends_with?(name, ".cabal") -> :cabal
      name == "dune-project" -> :dune
      String.ends_with?(name, ".gpr") -> :ada
      name == "_CoqProject" -> :coq
      name == "lakefile.lean" -> :lean
      name == "META.json" -> :mercury
      String.ends_with?(name, ".asd") -> :common_lisp
      name == "shard.yml" -> :crystal
      true -> :unknown
    end
  end

  defp extract_name(manifest_path, _manifest_type) do
    # Simplified: use directory name
    # Real implementation would parse manifest file
    manifest_path
    |> Path.dirname()
    |> Path.basename()
  end

  defp extract_version(_manifest_path, _manifest_type, ref) do
    # Simplified: use git ref as version
    # Real implementation would parse manifest file
    ref
    |> String.replace("refs/tags/", "")
    |> String.replace("refs/heads/", "")
    |> String.slice(0..10)  # Truncate SHA if needed
  end
end
