# SPDX-License-Identifier: MPL-2.0
defmodule Opsm.Package.FinalizerPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Opsm.Package.Finalizer

  @moduletag :property

  # From the estate's Proven-Tests taxonomy: a property must discriminate
  # between dry-run and apply, including a negative side-effect control.
  # These are generated tests, not machine-checked proofs. The manifest
  # labels their warrant unproven until the upstream safety certificates exist.

  property "dry-run never invokes persistence over arbitrary resolved maps" do
    check all(
            names <-
              list_of(string(:alphanumeric, min_length: 1, max_length: 12),
                max_length: 15
              ),
            max_runs: 1_000
          ) do
      resolved =
        names
        |> Enum.with_index()
        |> Map.new(fn {name, index} -> {"#{name}-#{index}", {"1.0.0", name}} end)

      parent = self()
      marker = make_ref()

      persist = fn _packages ->
        send(parent, {marker, :write_attempted})
        {:error, :eacces}
      end

      assert {:ok, :dry_run} = Finalizer.finish(resolved, true, persist)
      refute_received {^marker, :write_attempted}
    end
  end

  property "applied install passes every resolved entry to persistence exactly once" do
    check all(
            names <-
              list_of(string(:alphanumeric, min_length: 1, max_length: 12),
                max_length: 15
              ),
            max_runs: 1_000
          ) do
      resolved =
        names
        |> Enum.with_index()
        |> Map.new(fn {name, index} -> {"#{name}-#{index}", {"1.0.0", name}} end)

      parent = self()
      marker = make_ref()

      persist = fn packages ->
        send(parent, {marker, packages})
        :ok
      end

      assert {:ok, :all_installed} = Finalizer.finish(resolved, false, persist)
      assert_receive {^marker, written}
      assert Enum.sort(written) == Enum.sort(Map.values(resolved))
      refute_received {^marker, _extra}
    end
  end

  property "persistence error details cannot turn into installed success" do
    check all(
            code <- integer(0..1_000),
            reason <- member_of([:eacces, :enospc, :erofs, :eperm]),
            max_runs: 1_000
          ) do
      failure = {reason, code}
      persist = fn _packages -> {:error, failure} end

      assert {:error, {:lockfile_persistence_failed, ^failure}} =
               Finalizer.finish(%{"p" => {"1.0.0", :pkg}}, false, persist)
    end
  end
end
