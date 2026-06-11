# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.ManifestFinder do
  @moduledoc """
  Locate manifests for ingestion. Shares the manifest candidate list with the
  publish pipeline so every helper resolves a manifest consistently.
  """

  alias Opsm.Validation

  @manifest_candidates [
    "opsm.toml",
    "package.json",
    "Cargo.toml",
    "mix.exs",
    "pyproject.toml",
    "pubspec.yaml",
    "go.mod",
    "Gemfile",
    "build.zig",
    "justfile",
    "requirements.txt",
    "setup.py",
    "Makefile",
    "manifest.ncl",
    "opsm.ncl",
    "project.ncl",
    "build.ncl",
    "package.ncl",
    "default.ncl"
  ]

  @spec locate(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def locate(path) do
    with {:ok, sanitized} <- Validation.sanitize_path(path) do
      expanded = Path.expand(sanitized)

      cond do
        File.exists?(expanded) and File.regular?(expanded) ->
          {:ok, expanded}

        File.exists?(expanded) and File.dir?(expanded) ->
          find_manifest_in_dir(expanded)

        true ->
          {:error, "Path not found: #{expanded}"}
      end
    end
  end

  defp find_manifest_in_dir(dir) do
    case Enum.find(@manifest_candidates, &File.exists?(Path.join(dir, &1))) do
      nil ->
        ncl_files = Path.wildcard(Path.join(dir, "*.ncl"))
        ipkg_files = Path.wildcard(Path.join(dir, "*.ipkg"))

        case ncl_files ++ ipkg_files do
          [first | _] -> {:ok, first}
          _ -> {:error, "No recognizable manifest found in #{dir}"}
        end

      candidate ->
        {:ok, Path.join(dir, candidate)}
    end
  end
end
