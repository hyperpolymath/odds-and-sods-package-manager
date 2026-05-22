# SPDX-License-Identifier: MPL-2.0
defmodule Opsm.Git.Pipeline do
  @moduledoc """
  Orchestrates the full git clone -> detect -> build -> install pipeline.

  Provides two entry points:
  - `from_url/2` for remote repositories
  - `from_local/2` for local checkouts
  """

  alias Opsm.Git.{Clone, BuildDetector, Builder}

  @doc """
  Full pipeline from a git URL: clone -> detect -> deps -> build.

  ## Options

    * `:ref` - Git ref to checkout (tag, branch, commit SHA)
    * `:shallow` - Shallow clone (default: true for pipeline)
    * `:build_system` - Force a specific build system instead of auto-detect
    * `:recipe` - Custom build recipe
    * `:timeout` - Build timeout in ms
    * `:skip_deps` - Skip dependency installation step
    * `:cleanup_on_success` - Remove clone dir on success (default: true)

  Returns `{:ok, %{path: dir, build_system: system, output: output}}` or `{:error, reason}`.
  """
  @spec from_url(String.t(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def from_url(url, opts \\ []) do
    clone_opts = [
      shallow: Keyword.get(opts, :shallow, true),
      ref: Keyword.get(opts, :ref),
      depth: Keyword.get(opts, :depth)
    ]

    IO.puts("  Cloning #{url}...")

    case Clone.clone(url, clone_opts) do
      {:ok, %{path: repo_path, ref: ref}} ->
        IO.puts("  Cloned to #{repo_path} (ref: #{ref})")

        case build_local(repo_path, opts) do
          {:ok, result} ->
            if Keyword.get(opts, :cleanup_on_success, true) do
              Clone.cleanup(repo_path)
            end

            {:ok, Map.put(result, :clone_path, repo_path)}

          {:error, reason} ->
            # Keep clone dir on failure for debugging
            IO.puts("  Build failed. Clone preserved at: #{repo_path}")
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Build from a local checkout: detect -> deps -> build.

  ## Options

  Same as `from_url/2` except `:shallow`, `:ref`, `:depth` are ignored.

  Returns `{:ok, %{path: dir, build_system: system, output: output}}` or `{:error, reason}`.
  """
  @spec from_local(String.t(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def from_local(path, opts \\ []) do
    expanded = Path.expand(path)

    if File.dir?(expanded) do
      build_local(expanded, opts)
    else
      {:error, "Not a directory: #{expanded}"}
    end
  end

  # Internal: detect, install deps, build
  defp build_local(repo_path, opts) do
    with {:ok, {build_system, config_file}} <- detect_build_system(repo_path, opts),
         :ok <- log_detection(build_system, config_file),
         {:ok, _} <- maybe_install_deps(repo_path, build_system, opts),
         {:ok, output} <- do_build(repo_path, build_system, opts) do
      {:ok, %{
        path: repo_path,
        build_system: build_system,
        config_file: config_file,
        output: output
      }}
    end
  end

  defp detect_build_system(repo_path, opts) do
    case Keyword.get(opts, :build_system) do
      nil ->
        IO.puts("  Detecting build system...")
        BuildDetector.detect_primary(repo_path)

      system when is_atom(system) ->
        {:ok, {system, "user-specified"}}
    end
  end

  defp log_detection(build_system, config_file) do
    IO.puts("  Detected: #{build_system} (#{config_file})")
    :ok
  end

  defp maybe_install_deps(repo_path, build_system, opts) do
    if Keyword.get(opts, :skip_deps, false) do
      {:ok, "skipped"}
    else
      IO.puts("  Installing dependencies...")
      Builder.install_deps(repo_path, build_system, opts)
    end
  end

  defp do_build(repo_path, build_system, opts) do
    IO.puts("  Building with #{build_system}...")
    Builder.build(repo_path, build_system, opts)
  end
end
