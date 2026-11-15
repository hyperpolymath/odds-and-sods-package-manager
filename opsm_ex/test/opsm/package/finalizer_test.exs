# SPDX-License-Identifier: MPL-2.0
defmodule Opsm.Package.FinalizerTest do
  use ExUnit.Case, async: true

  alias Opsm.Package.Finalizer

  test "dry-run does not invoke the lockfile writer" do
    parent = self()
    persist = fn _packages ->
      send(parent, :lockfile_written)
      :ok
    end

    assert {:ok, :dry_run} =
             Finalizer.finish(%{"example" => {"1.0.0", :example_package}}, true, persist)

    refute_received :lockfile_written
  end

  test "dry-run preserves an existing lockfile" do
    dir = Path.join(System.tmp_dir!(), "opsm-finalizer-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "opsm.lock")

    try do
      File.write!(path, "original lockfile")

      persist = fn _packages ->
        File.write!(path, "modified lockfile")
        :ok
      end

      assert {:ok, :dry_run} = Finalizer.finish(%{}, true, persist)
      assert File.read!(path) == "original lockfile"
    after
      File.rm_rf!(dir)
    end
  end

  test "applied install persists resolved packages once" do
    parent = self()

    persist = fn packages ->
      send(parent, {:persist, packages})
      :ok
    end

    resolved = %{"example" => {"1.0.0", :example_package}}

    assert {:ok, :all_installed} = Finalizer.finish(resolved, false, persist)
    assert_receive {:persist, [{"1.0.0", :example_package}]}
    refute_received {:persist, _}
  end

  test "applied install reports a lockfile persistence error" do
    persist = fn _packages -> {:error, :eacces} end

    assert {:error, {:lockfile_persistence_failed, :eacces}} =
             Finalizer.finish(%{}, false, persist)
  end
end
