# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Benchmark do
  alias Opsm.{Lockfile, VersionConstraint}

  # Helper to generate test packages
  defp generate_packages(count) do
    Enum.map(1..count, fn i ->
      %{
        name: "pkg-#{i}",
        version: "1.#{i}.0",
        forth: Enum.random([:npm, :cargo, :hex, :pypi]),
        checksum: "hash-#{i}",
        checksum_algo: "blake2b"
      }
    end)
  end

  # Helper to create lockfile with packages
  defp create_lockfile(packages) do
    Enum.reduce(packages, Lockfile.new(), &Lockfile.add_package(&2, &1))
  end

  def suite do
    [
      # Version Constraint Benchmarks
      {"Version Constraint: Parse caret constraint", fn ->
        VersionConstraint.parse("^1.2.3", :semver)
      end},

      {"Version Constraint: Parse tilde constraint", fn ->
        VersionConstraint.parse("~1.2.3", :semver)
      end},

      {"Version Constraint: Parse python constraint", fn ->
        VersionConstraint.parse(">=1.0,<2.0", :python)
      end},

      {"Version Constraint: Satisfies? (match)", fn ->
        {:ok, constraint} = VersionConstraint.parse("^1.2.3", :semver)
        VersionConstraint.satisfies?("1.2.5", constraint)
      end},

      {"Version Constraint: Satisfies? (no match)", fn ->
        {:ok, constraint} = VersionConstraint.parse("^1.2.3", :semver)
        VersionConstraint.satisfies?("2.0.0", constraint)
      end},

      # Lockfile Operations - Small Scale (10 packages)
      {"Lockfile: Create new (empty)", fn ->
        Lockfile.new()
      end},

      {"Lockfile: Add single package", fn ->
        Lockfile.new()
        |> Lockfile.add_package(%{
          name: "test-pkg",
          version: "1.0.0",
          forth: :npm,
          checksum: "hash"
        })
      end},

      {"Lockfile: Add 10 packages", fn ->
        packages = generate_packages(10)
        create_lockfile(packages)
      end},

      {"Lockfile: List 10 packages", fn ->
        packages = generate_packages(10)
        lockfile = create_lockfile(packages)
        Lockfile.list_packages(lockfile)
      end},

      {"Lockfile: Filter by forth (10 packages)", fn ->
        packages = generate_packages(10)
        lockfile = create_lockfile(packages)
        Lockfile.packages_for_forth(lockfile, :npm)
      end},

      # Lockfile Operations - Medium Scale (50 packages)
      {"Lockfile: Add 50 packages", fn ->
        packages = generate_packages(50)
        create_lockfile(packages)
      end},

      {"Lockfile: List 50 packages", fn ->
        packages = generate_packages(50)
        lockfile = create_lockfile(packages)
        Lockfile.list_packages(lockfile)
      end},

      {"Lockfile: Compute integrity hash (50 packages)", fn ->
        packages = generate_packages(50)
        lockfile = create_lockfile(packages)
        Lockfile.compute_integrity_hash(lockfile)
      end},

      {"Lockfile: Verify package (hit, 50 packages)", fn ->
        packages = generate_packages(50)
        lockfile = create_lockfile(packages)
        Lockfile.verify_package(lockfile, "pkg-25", Enum.random([:npm, :cargo, :hex]), "hash-25")
      end},

      # Lockfile Operations - Large Scale (100 packages)
      {"Lockfile: Add 100 packages", fn ->
        packages = generate_packages(100)
        create_lockfile(packages)
      end},

      {"Lockfile: List 100 packages", fn ->
        packages = generate_packages(100)
        lockfile = create_lockfile(packages)
        Lockfile.list_packages(lockfile)
      end},

      {"Lockfile: Compute integrity hash (100 packages)", fn ->
        packages = generate_packages(100)
        lockfile = create_lockfile(packages)
        Lockfile.compute_integrity_hash(lockfile)
      end},

      {"Lockfile: Check sync (100 packages, all in sync)", fn ->
        packages = generate_packages(100)
        lockfile = create_lockfile(packages)
        installed = Enum.map(packages, fn p -> %{name: p.name, forth: p.forth} end)
        Lockfile.check_sync(lockfile, installed)
      end},

      # Trust Pipeline Benchmarks
      {"Trust Pipeline: Verify signature (mock)", fn ->
        # Mock signature verification
        :crypto.hash(:sha256, "test-data")
      end},

      # Integrity Operations
      {"Integrity: Hash 10-package lockfile", fn ->
        packages = generate_packages(10)
        lockfile = create_lockfile(packages)
        Lockfile.compute_integrity_hash(lockfile)
      end},

      {"Integrity: Verify integrity (valid)", fn ->
        packages = generate_packages(10)
        lockfile = create_lockfile(packages)
        |> Lockfile.compute_integrity_hash()
        Lockfile.verify_integrity(lockfile)
      end},

      {"Integrity: Hash 500-package lockfile", fn ->
        packages = generate_packages(500)
        lockfile = create_lockfile(packages)
        Lockfile.compute_integrity_hash(lockfile)
      end},

      # Package Operations
      {"Package: Get package by name (hit)", fn ->
        packages = generate_packages(50)
        lockfile = create_lockfile(packages)
        Lockfile.get_package(lockfile, "pkg-25", Enum.random([:npm, :cargo, :hex]))
      end},

      {"Package: Remove package", fn ->
        packages = generate_packages(50)
        lockfile = create_lockfile(packages)
        Lockfile.remove_package(lockfile, "pkg-1", Enum.random([:npm, :cargo, :hex]))
      end},

      # Mixed Workload
      {"Mixed: Add, get, verify on 50-package lockfile", fn ->
        packages = generate_packages(50)
        lockfile = Lockfile.new()

        lockfile = Enum.reduce(packages, lockfile, fn pkg, acc ->
          Lockfile.add_package(acc, pkg)
        end)

        Lockfile.get_package(lockfile, "pkg-25", Enum.random([:npm, :cargo, :hex]))
        Lockfile.verify_package(lockfile, "pkg-25", Enum.random([:npm, :cargo, :hex]), "hash-25")
        Lockfile.list_packages(lockfile)
      end},
    ]
  end
end

# Run with: mix run -r bench/opsm_bench.exs
# Or: benchee (if installed)
# For now, we can use Enum.each to run tests

Opsm.Benchmark.suite()
|> Enum.each(fn {label, fun} ->
  IO.write("#{label}... ")
  start_time = System.monotonic_time(:microsecond)

  # Run 1000 times for faster benchmarks
  Enum.each(1..1000, fn _ -> fun.() end)

  end_time = System.monotonic_time(:microsecond)
  duration = (end_time - start_time) / 1000.0

  IO.puts("~#{round(duration)} μs (average over 1000 runs)")
end)

IO.puts("\nBenchmark complete!")
