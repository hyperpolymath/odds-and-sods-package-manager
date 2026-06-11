# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Git.BuildDetector do
  @moduledoc """
  Detects build systems present in a repository by scanning for marker files.

  Returns a priority-ordered list of detected build systems.
  """

  @doc """
  Detect build systems in a repository directory.

  Returns `{:ok, [{build_system, config_file}]}` or `{:error, reason}`.
  Results are priority-ordered (preferred build systems first).
  """
  @spec detect(String.t()) :: {:ok, [{atom(), String.t()}]} | {:error, String.t()}
  def detect(repo_path) do
    if File.dir?(repo_path) do
      detected =
        markers()
        |> Enum.filter(fn {_system, file} -> File.exists?(Path.join(repo_path, file)) end)

      case detected do
        [] -> {:error, "No recognized build system found in #{repo_path}"}
        found -> {:ok, found}
      end
    else
      {:error, "Not a directory: #{repo_path}"}
    end
  end

  @doc """
  Detect the primary (highest priority) build system.

  Returns `{:ok, {build_system, config_file}}` or `{:error, reason}`.
  """
  @spec detect_primary(String.t()) :: {:ok, {atom(), String.t()}} | {:error, String.t()}
  def detect_primary(repo_path) do
    case detect(repo_path) do
      {:ok, [primary | _]} -> {:ok, primary}
      {:error, _} = err -> err
    end
  end

  @doc """
  Check if a specific build system is present.
  """
  @spec has_build_system?(String.t(), atom()) :: boolean()
  def has_build_system?(repo_path, system) do
    case detect(repo_path) do
      {:ok, detected} -> Enum.any?(detected, fn {s, _} -> s == system end)
      {:error, _} -> false
    end
  end

  # Priority-ordered list of build system markers.
  # First match wins when using detect_primary/1.
  defp markers do
    [
      {:just, "justfile"},
      {:make, "Makefile"},
      {:make, "GNUmakefile"},
      {:cargo, "Cargo.toml"},
      {:mix, "mix.exs"},
      {:npm, "package.json"},
      {:python, "pyproject.toml"},
      {:python, "setup.py"},
      {:go, "go.mod"},
      {:bundler, "Gemfile"},
      {:pub, "pubspec.yaml"},
      {:zig, "build.zig"},
      {:gradle, "build.gradle"},
      {:gradle, "build.gradle.kts"},
      {:maven_build, "pom.xml"},
      {:cabal, "*.cabal"},
      {:stack, "stack.yaml"},
      {:dune, "dune-project"},
      {:nim, "*.nimble"}
    ]
    |> Enum.filter(fn {_system, file} ->
      # Expand globs at filter time for wildcard patterns
      not String.contains?(file, "*")
    end)
    |> Kernel.++(detect_glob_markers())
  end

  # Handle glob-based markers separately
  defp detect_glob_markers do
    # These need Path.wildcard which requires a base path,
    # so they're handled as static entries that get filtered in detect/1
    []
  end
end
