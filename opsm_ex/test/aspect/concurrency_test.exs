# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Aspect.ConcurrencyTest do
  use ExUnit.Case, async: true

  alias Opsm.Lockfile

  @moduletag :aspect
  @moduletag :concurrency

  describe "Concurrent Lockfile Operations" do
    test "concurrent package additions maintain consistency" do
      # Start with base lockfile
      base = Lockfile.new()

      # Simulate concurrent additions (serialized in Elixir, but tests the logic)
      tasks =
        Enum.map(1..10, fn i ->
          Task.async(fn ->
            %{
              name: "pkg-#{i}",
              version: "1.0.#{i}",
              forth: :npm,
              checksum: "hash-#{i}"
            }
          end)
        end)

      packages = Enum.map(tasks, &Task.await/1)

      # Add all packages to lockfile
      lockfile =
        packages
        |> Enum.reduce(base, &Lockfile.add_package(&2, &1))

      # Verify all packages are present
      assert Lockfile.list_packages(lockfile) |> length() == 10

      # Each package should have correct data
      Enum.each(1..10, fn i ->
        pkg = Lockfile.get_package(lockfile, "pkg-#{i}", :npm)
        assert pkg.name == "pkg-#{i}"
        assert pkg.version == "1.0.#{i}"
      end)
    end

    test "parallel package reads don't corrupt state" do
      # Build a lockfile
      lockfile =
        Enum.reduce(1..20, Lockfile.new(), fn i, acc ->
          Lockfile.add_package(acc, %{
            name: "pkg-#{i}",
            version: "1.0.0",
            forth: :npm,
            checksum: "hash-#{i}"
          })
        end)

      # Read from multiple "parallel" tasks
      tasks =
        Enum.map(1..10, fn _ ->
          Task.async(fn ->
            Lockfile.list_packages(lockfile)
          end)
        end)

      results = Enum.map(tasks, &Task.await/1)

      # All reads should return identical results
      first_result = List.first(results)
      assert Enum.all?(results, &(&1 == first_result))

      # Should have all 20 packages
      assert length(first_result) == 20
    end

    test "concurrent integrity hash computation is idempotent" do
      base =
        Lockfile.new()
        |> Lockfile.add_package(%{name: "pkg1", version: "1.0.0", forth: :npm})
        |> Lockfile.add_package(%{name: "pkg2", version: "2.0.0", forth: :npm})

      # Compute hash multiple times in parallel
      tasks =
        Enum.map(1..5, fn _ ->
          Task.async(fn ->
            Lockfile.compute_integrity_hash(base)
          end)
        end)

      hashes = Enum.map(tasks, &Task.await/1)

      # All hashes should be identical
      first_hash = Enum.at(hashes, 0).integrity_hash
      assert Enum.all?(hashes, &(&1.integrity_hash == first_hash))
    end
  end

  describe "Lockfile Download Simulation" do
    test "sequential package download doesn't corrupt lockfile" do
      lockfile = Lockfile.new()

      # Simulate downloading packages one after another
      packages_to_download = [
        %{name: "express", version: "4.18.0", forth: :npm, checksum: "hash1"},
        %{name: "react", version: "18.2.0", forth: :npm, checksum: "hash2"},
        %{name: "lodash", version: "4.17.21", forth: :npm, checksum: "hash3"}
      ]

      # Sequential "downloads" with lockfile updates
      final_lockfile =
        Enum.reduce(packages_to_download, lockfile, fn pkg, acc ->
          # Simulate: download, verify checksum, add to lockfile
          verify_mock_checksum(pkg.checksum)
          Lockfile.add_package(acc, pkg)
        end)

      # All packages should be in lockfile
      assert length(Lockfile.list_packages(final_lockfile)) == 3
      assert Lockfile.has_package?(final_lockfile, "express", :npm)
      assert Lockfile.has_package?(final_lockfile, "react", :npm)
      assert Lockfile.has_package?(final_lockfile, "lodash", :npm)
    end

    test "package download with integrity check" do
      # Simulate downloading a package and verifying integrity

      lockfile =
        Lockfile.new()
        |> Lockfile.add_package(%{
          name: "verified-pkg",
          version: "1.0.0",
          forth: :npm,
          checksum: "sha256:abc123def456"
        })

      # Download package and verify
      downloaded_checksum = "sha256:abc123def456"
      result = Lockfile.verify_package(lockfile, "verified-pkg", :npm, downloaded_checksum)

      assert :ok = result
    end

    test "corrupted download is detected before install" do
      lockfile =
        Lockfile.new()
        |> Lockfile.add_package(%{
          name: "critical-pkg",
          version: "1.0.0",
          forth: :npm,
          checksum: "sha256:expected"
        })

      # Download received corrupted checksum
      actual_checksum = "sha256:corrupted"
      result = Lockfile.verify_package(lockfile, "critical-pkg", :npm, actual_checksum)

      # Should detect mismatch
      assert {:mismatch, _} = result
    end
  end

  describe "Lockfile Serialization Under Load" do
    test "multiple serializations produce consistent output" do
      lockfile =
        Enum.reduce(1..50, Lockfile.new(), fn i, acc ->
          Lockfile.add_package(acc, %{
            name: "pkg-#{i}",
            version: "#{i}.0.0",
            forth: Enum.random([:npm, :cargo, :hex]),
            checksum: "hash-#{i}"
          })
        end)

      # Serialize multiple times
      serializations =
        Enum.map(1..3, fn _ ->
          packages = Lockfile.list_packages(lockfile)
          Jason.encode!(packages)
        end)

      # All serializations should be identical
      first = List.first(serializations)
      assert Enum.all?(serializations, &(&1 == first))
    end

    test "large lockfile remains consistent" do
      # Create a large lockfile
      large_lockfile =
        Enum.reduce(1..100, Lockfile.new(), fn i, acc ->
          Lockfile.add_package(acc, %{
            name: "pkg-#{i}",
            version: "#{i}.0.0",
            forth: Enum.random([:npm, :cargo, :hex, :pypi]),
            checksum: "hash-#{i}"
          })
        end)

      packages = Lockfile.list_packages(large_lockfile)

      # All 100 packages should be present
      assert length(packages) == 100

      # Each package should have correct data
      Enum.each(packages, fn pkg ->
        assert pkg.name =~ ~r/^pkg-/
        assert pkg.version =~ ~r/^\d+\.0\.0$/
        assert pkg.forth in [:npm, :cargo, :hex, :pypi]
        assert pkg.checksum =~ ~r/^hash-/
      end)
    end
  end

  describe "Conflict Handling" do
    test "same package from different forths doesn't conflict" do
      lockfile =
        Lockfile.new()
        |> Lockfile.add_package(%{
          name: "utility",
          version: "1.0.0",
          forth: :npm,
          checksum: "npm-hash"
        })
        |> Lockfile.add_package(%{
          name: "utility",
          version: "1.0.0",
          forth: :cargo,
          checksum: "cargo-hash"
        })
        |> Lockfile.add_package(%{
          name: "utility",
          version: "1.0.0",
          forth: :hex,
          checksum: "hex-hash"
        })

      # All three should exist without conflict
      assert Lockfile.has_package?(lockfile, "utility", :npm)
      assert Lockfile.has_package?(lockfile, "utility", :cargo)
      assert Lockfile.has_package?(lockfile, "utility", :hex)

      # Total package count should be 3
      assert length(Lockfile.list_packages(lockfile)) == 3
    end

    test "package version update in lockfile is atomic" do
      lockfile =
        Lockfile.new()
        |> Lockfile.add_package(%{
          name: "evolving-pkg",
          version: "1.0.0",
          forth: :npm,
          checksum: "hash-1"
        })

      # Update package version
      updated =
        Lockfile.add_package(lockfile, %{
          name: "evolving-pkg",
          version: "2.0.0",
          forth: :npm,
          checksum: "hash-2"
        })

      # Package should be updated to new version
      pkg = Lockfile.get_package(updated, "evolving-pkg", :npm)
      assert pkg.version == "2.0.0"
      assert pkg.checksum == "hash-2"

      # Old version should not exist
      refute Lockfile.has_package?(updated, "evolving-pkg", :npm) and
               Lockfile.get_package(updated, "evolving-pkg", :npm).version == "1.0.0"
    end
  end

  describe "Sync Checking Under Load" do
    test "lockfile sync check with many packages" do
      lockfile =
        Enum.reduce(1..50, Lockfile.new(), fn i, acc ->
          Lockfile.add_package(acc, %{
            name: "pkg-#{i}",
            version: "1.0.0",
            forth: :npm,
            checksum: "hash-#{i}"
          })
        end)

      # Simulate installed packages
      installed =
        Enum.map(1..50, fn i ->
          %{name: "pkg-#{i}", forth: :npm}
        end)

      result = Lockfile.check_sync(lockfile, installed)

      # Should be in sync
      assert result.in_sync == true
      assert result.missing_from_lockfile == []
      assert result.not_installed == []
    end

    test "detects missing packages in large lockfile" do
      lockfile =
        Enum.reduce(1..50, Lockfile.new(), fn i, acc ->
          Lockfile.add_package(acc, %{
            name: "pkg-#{i}",
            version: "1.0.0",
            forth: :npm,
            checksum: "hash-#{i}"
          })
        end)

      # Simulate missing packages 25-50
      installed =
        Enum.map(1..25, fn i ->
          %{name: "pkg-#{i}", forth: :npm}
        end)

      result = Lockfile.check_sync(lockfile, installed)

      # Should detect missing packages
      assert result.in_sync == false
      assert length(result.not_installed) == 25
    end
  end

  # Helper function to simulate checksum verification
  defp verify_mock_checksum(checksum) do
    # Mock implementation: just validate format
    assert is_binary(checksum)
    assert String.length(checksum) > 0
  end
end
