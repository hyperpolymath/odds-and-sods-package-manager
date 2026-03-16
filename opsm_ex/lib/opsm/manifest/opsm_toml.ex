# SPDX-License-Identifier: PMPL-1.0
defmodule Opsm.Manifest.OpsmToml do
  @moduledoc """
  Native OPSM manifest format (opsm.toml) parser and writer.

  Format:
  ```toml
  [package]
  name = "my-tool"
  version = "1.0.0"
  license = "PMPL-1.0-or-later"
  description = "A useful tool"
  authors = ["Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>"]
  keywords = ["tool", "utility"]

  [dependencies]
  req = ">= 0.5.0"
  jason = "~> 1.4"

  [dev-dependencies]
  stream_data = "~> 0.6"

  [build]
  system = "mix"
  command = "mix release"

  [run]
  binary = "bin/my-tool"
  ```
  """

  alias Opsm.Types.ManifestFormat

  @doc """
  Parse an opsm.toml string into a ManifestFormat struct.

  Returns `{:ok, %ManifestFormat{}}` or `{:error, reason}`.
  """
  @spec parse(String.t()) :: {:ok, ManifestFormat.t()} | {:error, String.t()}
  def parse(toml_string) when is_binary(toml_string) do
    case Toml.decode(toml_string) do
      {:ok, toml} ->
        pkg = toml["package"] || %{}

        manifest = %ManifestFormat{
          name: pkg["name"] || "unknown",
          version: pkg["version"] || "0.0.0",
          description: pkg["description"],
          license: pkg["license"],
          homepage: pkg["homepage"],
          repository: pkg["repository"],
          authors: pkg["authors"] || [],
          keywords: pkg["keywords"] || [],
          dependencies: toml["dependencies"] || %{},
          dev_dependencies: toml["dev-dependencies"] || %{},
          bin: extract_bin(toml),
          scripts: extract_scripts(toml),
          source_forth: safe_to_forth(pkg["source_forth"]),
          raw_manifest: toml
        }

        {:ok, manifest}

      {:error, reason} ->
        {:error, "Failed to parse opsm.toml: #{inspect(reason)}"}
    end
  end

  def parse(_), do: {:error, "Expected a string"}

  @doc """
  Parse an opsm.toml file from disk.

  Returns `{:ok, %ManifestFormat{}}` or `{:error, reason}`.
  """
  @spec parse_file(String.t()) :: {:ok, ManifestFormat.t()} | {:error, String.t()}
  def parse_file(path) do
    case File.read(path) do
      {:ok, content} -> parse(content)
      {:error, reason} -> {:error, "Failed to read #{path}: #{reason}"}
    end
  end

  @doc """
  Encode a ManifestFormat struct to opsm.toml string.

  Delegates to `Opsm.Manifest.Writer.to_opsm_toml/1`.
  """
  @spec encode(ManifestFormat.t()) :: String.t()
  def encode(%ManifestFormat{} = manifest) do
    Opsm.Manifest.Writer.to_opsm_toml(manifest)
  end

  @doc """
  Get the build configuration from a parsed opsm.toml.

  Returns `%{system: atom, command: string}` or `nil`.
  """
  @spec build_config(ManifestFormat.t()) :: map() | nil
  def build_config(%ManifestFormat{raw_manifest: raw}) when is_map(raw) do
    case raw["build"] do
      nil -> nil
      build ->
        %{
          system: safe_to_build_system(build["system"]),
          command: build["command"]
        }
    end
  end

  def build_config(_), do: nil

  @doc """
  Get the run configuration from a parsed opsm.toml.

  Returns `%{binary: string}` or `nil`.
  """
  @spec run_config(ManifestFormat.t()) :: map() | nil
  def run_config(%ManifestFormat{raw_manifest: raw}) when is_map(raw) do
    case raw["run"] do
      nil -> nil
      run -> %{binary: run["binary"], args: run["args"]}
    end
  end

  def run_config(_), do: nil

  # Extract bin entries from [bin] table
  defp extract_bin(toml) do
    toml["bin"] || %{}
  end

  # Extract script entries from [scripts] table
  defp extract_scripts(toml) do
    toml["scripts"] || %{}
  end

  defp safe_to_forth(nil), do: nil
  defp safe_to_forth(s) when is_binary(s), do: Opsm.Validation.safe_to_forth(s)
  defp safe_to_forth(a) when is_atom(a), do: a

  @known_build_systems ~w(just make cargo mix npm python go zig bundler pub gradle maven cabal stack dune)a

  defp safe_to_build_system(nil), do: nil
  defp safe_to_build_system(s) when is_binary(s) do
    atom = String.to_existing_atom(s)
    if atom in @known_build_systems, do: atom, else: nil
  rescue
    ArgumentError -> nil
  end
end
