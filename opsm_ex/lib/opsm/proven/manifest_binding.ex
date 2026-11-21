# SPDX-License-Identifier: MPL-2.0
defmodule Opsm.Proven.ManifestBinding do
  @moduledoc """
  Check that a declared test module is bound to the source that defines it.

  An existing but unrelated test file must not validate an evidence claim.
  Callers separately validate module presence, supported taxonomy coordinates
  and proof provenance; this module checks only the source-to-module binding.
  """

  @spec violations([map()], [map()]) :: [String.t()]
  def violations(manifest, observed) when is_list(manifest) and is_list(observed) do
    definitions =
      Enum.group_by(observed, & &1.module, & &1.file)

    Enum.flat_map(manifest, fn entry ->
      module = entry["module"]
      declared = entry["file"]

      case Map.get(definitions, module, []) do
        [] ->
          # The caller's separate stale-entry validator reports this case.
          []

        [^declared] ->
          []

        [actual] ->
          [
            "#{module}: manifest names #{inspect(declared)}, actual module is in #{inspect(actual)}"
          ]

        files ->
          ["#{module}: module has ambiguous source definitions #{inspect(files)}"]
      end
    end)
  end
end
