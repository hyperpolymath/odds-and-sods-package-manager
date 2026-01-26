# SPDX-License-Identifier: PMPL-1.0
defmodule Opsm.Imp do
  @moduledoc """
  Internal Manifest Protocol helpers for OPSM.

  Converts the federation-unified manifest into the IMP schema described under
  `docs/imp/imp.schema.json` so the downstream HAR/nickel-config-reporter pipeline
  receives a normalized view of the package.
  """

  alias Opsm.Types.ManifestFormat

  @required_fields [:name, :version, :license, :dependencies]

  @doc """
  Normalize a `ManifestFormat` into the IMP shape and validate required fields.
  """
  @spec normalize(ManifestFormat.t(), String.t(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def normalize(%ManifestFormat{} = manifest, manifest_path, digest) do
    with :ok <- ensure_required_fields(manifest) do
      {:ok, %{
        "name" => manifest.name,
        "version" => manifest.version || "0.0.0",
        "license" => manifest.license,
        "dependencies" => format_dependencies(manifest.dependencies || %{}),
        "provenance" => build_provenance(manifest, manifest_path, digest)
      }}
    end
  end

  def normalize(_, _, _), do: {:error, "Manifest missing or invalid"}

  defp ensure_required_fields(manifest) do
    manifest
    |> Map.take(@required_fields)
    |> Enum.reduce_while(:ok, fn {field, value}, :ok ->
      cond do
        is_nil(value) ->
          {:halt, {:error, "IMP requires '#{field}'"}}

        field == :dependencies and map_size(value) == 0 ->
          {:halt, {:error, "IMP requires at least one dependency"}}

        true ->
          {:cont, :ok}
      end
    end)
  end

  defp format_dependencies(deps) when is_map(deps) do
    deps
    |> Enum.map(fn {name, version} ->
      %{
        "name" => name,
        "version" => format_dependency_version(version)
      }
    end)
  end

  defp format_dependencies(_), do: []

  defp format_dependency_version(nil), do: ""
  defp format_dependency_version(version) when is_binary(version), do: version
  defp format_dependency_version(version), do: to_string(version)

  defp build_provenance(manifest, manifest_path, digest) do
    %{
      "artifact" => Path.basename(manifest_path),
      "digest" => digest,
      "source" => manifest.source_forth || "local",
      "repository" => manifest.repository,
      "ingestedAt" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "license" => manifest.license
    }
  end
end
