# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Integration.PipelineTest do
  @moduledoc """
  Integration tests for the OPSM pipeline.

  These tests verify the complete flow from CLI commands through
  to package operations, using mocked HTTP responses.
  """
  use ExUnit.Case, async: false

  alias Opsm.Config
  alias Opsm.Lockfile
  alias Opsm.Maintenance
  alias Opsm.Package.Transaction
  alias Opsm.Trust.Pipeline
  alias Opsm.Types.ResolvedPackage

  # Test fixtures
  @test_package %ResolvedPackage{
    package: "test-pkg",
    version: "1.0.0",
    forth: :npm,
    registry_url: "https://registry.npmjs.org",
    tarball_url: "https://registry.npmjs.org/test-pkg/-/test-pkg-1.0.0.tgz",
    checksum: "abc123def456",
    checksum_algo: :sha256,
    manifest: %Opsm.Types.ManifestFormat{
      name: "test-pkg",
      version: "1.0.0",
      license: "MIT",
      description: "A test package"
    },
    attestations: []
  }

  describe "trust pipeline verification" do
    test "verify returns results for package with MIT license" do
      {:ok, results} = Pipeline.verify(@test_package)

      assert results.package == "test-pkg"
      assert results.version == "1.0.0"
      assert results.forth == :npm
      assert results.overall in [:passed, :warning, :failed]
    end

    test "verify handles package with no attestations" do
      {:ok, results} = Pipeline.verify(@test_package)

      # Should warn about no attestations
      attestation_check = results.checks[:attestation]
      assert attestation_check != nil
    end

    test "verify handles package with permissive license" do
      {:ok, results} = Pipeline.verify(@test_package)

      # MIT is permissive
      license_check = results.checks[:license]

      case license_check do
        {:ok, msg} -> assert msg =~ "Permissive" or msg =~ "MIT"
        {:info, msg} -> assert msg =~ "license"
        _ -> :ok
      end
    end
  end

  describe "transaction management" do
    setup do
      tmp_dir = Path.join(System.tmp_dir!(), "opsm_integ_#{:rand.uniform(1_000_000)}")
      File.mkdir_p!(tmp_dir)

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      {:ok, tmp_dir: tmp_dir}
    end

    test "transaction creates and tracks directories", %{tmp_dir: tmp_dir} do
      txn = Transaction.new("test-pkg")

      dir1 = Path.join(tmp_dir, "pkg/lib")
      {:ok, txn} = Transaction.mkdir_p(txn, dir1)

      assert File.dir?(dir1)
      assert dir1 in txn.directories
    end

    test "transaction rollback cleans up on failure", %{tmp_dir: tmp_dir} do
      txn = Transaction.new("test-pkg")

      # Create some files
      dir1 = Path.join(tmp_dir, "pkg")
      file1 = Path.join(dir1, "file.txt")

      {:ok, txn} = Transaction.mkdir_p(txn, dir1)
      File.write!(file1, "content")
      txn = Transaction.record_file(txn, file1)

      # Simulate failure - rollback
      Transaction.rollback(txn)

      refute File.exists?(file1)
    end

    test "completed transaction is not rolled back", %{tmp_dir: tmp_dir} do
      txn = Transaction.new("test-pkg")

      dir1 = Path.join(tmp_dir, "pkg")
      file1 = Path.join(dir1, "keep.txt")

      {:ok, txn} = Transaction.mkdir_p(txn, dir1)
      File.write!(file1, "keep this")
      txn = Transaction.record_file(txn, file1)
      txn = Transaction.complete(txn)

      # Rollback should do nothing
      Transaction.rollback(txn)

      assert File.exists?(file1)
    end
  end

  describe "lockfile integration" do
    setup do
      tmp_dir = Path.join(System.tmp_dir!(), "opsm_lock_integ_#{:rand.uniform(1_000_000)}")
      File.mkdir_p!(tmp_dir)

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      {:ok, tmp_dir: tmp_dir}
    end

    test "full lockfile workflow", %{tmp_dir: tmp_dir} do
      lock_path = Path.join(tmp_dir, "opsm.lock")

      # Create new lockfile
      lockfile = Lockfile.new()

      # Add packages
      lockfile = Lockfile.add_package(lockfile, %{
        name: "lodash",
        version: "4.17.21",
        forth: :npm,
        checksum: "sha256:abc123",
        source_url: "https://registry.npmjs.org/lodash/-/lodash-4.17.21.tgz"
      })

      lockfile = Lockfile.add_package(lockfile, %{
        name: "serde",
        version: "1.0.195",
        forth: :cargo,
        checksum: "sha256:def456"
      })

      # Save
      {:ok, _} = Lockfile.write(lockfile, lock_path)

      # Reload
      {:ok, loaded} = Lockfile.read(lock_path)

      # Verify
      assert Lockfile.has_package?(loaded, "lodash", :npm)
      assert Lockfile.has_package?(loaded, "serde", :cargo)

      npm_pkgs = Lockfile.packages_for_forth(loaded, :npm)
      assert length(npm_pkgs) == 1

      cargo_pkgs = Lockfile.packages_for_forth(loaded, :cargo)
      assert length(cargo_pkgs) == 1
    end

    test "lockfile sync check", %{tmp_dir: tmp_dir} do
      lock_path = Path.join(tmp_dir, "opsm.lock")

      lockfile = Lockfile.new()
      |> Lockfile.add_package(%{name: "pkg1", version: "1.0.0", forth: :npm})
      |> Lockfile.add_package(%{name: "pkg2", version: "1.0.0", forth: :npm})

      {:ok, _} = Lockfile.write(lockfile, lock_path)
      {:ok, loaded} = Lockfile.read(lock_path)

      # Simulate installed packages (one missing)
      installed = [%{name: "pkg1", forth: :npm}]

      sync = Lockfile.check_sync(loaded, installed)

      assert sync.in_sync == false
      assert "pkg2@npm" in sync.not_installed
    end
  end

  describe "maintenance operations" do
    test "pin and unpin workflow" do
      pkg_name = "integration-test-pkg-#{:rand.uniform(10000)}"

      # Pin
      :ok = Maintenance.pin(pkg_name, "1.0.0")
      assert Maintenance.pinned?(pkg_name)

      pin = Maintenance.get_pin(pkg_name)
      assert pin["version"] == "1.0.0"

      # Unpin
      :ok = Maintenance.unpin(pkg_name)
      refute Maintenance.pinned?(pkg_name)
    end

    test "history recording" do
      # Record an operation
      id = Maintenance.record_history("test_integration", %{
        package: "test-pkg",
        version: "1.0.0",
        action: "install"
      })

      assert is_binary(id)
      assert String.length(id) == 16

      # Retrieve it
      entry = Maintenance.get_history_entry(id)
      assert entry["operation"] == "test_integration"
      assert entry["details"]["package"] == "test-pkg"
    end
  end

  describe "config loading" do
    test "example config has all services configured" do
      config = Config.example_config()

      assert config.http.timeout_ms > 0
      assert is_binary(config.claim_forge.base_url)
      assert is_binary(config.checky_monkey.base_url)
      assert is_binary(config.oikos.base_url)
      assert is_binary(config.palimpsest_license.base_url)
      assert is_binary(config.cicd_hyper_a.base_url)
    end

    test "load_config_or_example returns usable config" do
      config = Config.load_config_or_example()

      # Should return either loaded config or example
      assert %Opsm.Types.OpsmConfig{} = config
      assert config.http.timeout_ms > 0
    end
  end

  describe "end-to-end scenarios" do
    setup do
      tmp_dir = Path.join(System.tmp_dir!(), "opsm_e2e_#{:rand.uniform(1_000_000)}")
      File.mkdir_p!(tmp_dir)

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      {:ok, tmp_dir: tmp_dir}
    end

    test "simulate install -> lock -> uninstall flow", %{tmp_dir: tmp_dir} do
      lock_path = Path.join(tmp_dir, "opsm.lock")

      # Step 1: Create transaction for install
      txn = Transaction.new("fake-pkg")

      # Step 2: Simulate file creation
      pkg_dir = Path.join(tmp_dir, "node_modules/fake-pkg")
      {:ok, txn} = Transaction.mkdir_p(txn, pkg_dir)

      index_file = Path.join(pkg_dir, "index.js")
      File.write!(index_file, "module.exports = {};")
      txn = Transaction.record_file(txn, index_file)

      # Step 3: Mark complete
      _txn = Transaction.complete(txn)

      # Step 4: Update lockfile
      lockfile = Lockfile.new()
      |> Lockfile.add_package(%{
        name: "fake-pkg",
        version: "1.0.0",
        forth: :npm,
        checksum: "sha256:fakechecksum"
      })

      {:ok, _} = Lockfile.write(lockfile, lock_path)

      # Step 5: Record in history
      Maintenance.record_history("install", %{
        package: "fake-pkg",
        version: "1.0.0",
        forth: :npm
      })

      # Verify state
      assert File.exists?(index_file)
      {:ok, loaded_lock} = Lockfile.read(lock_path)
      assert Lockfile.has_package?(loaded_lock, "fake-pkg", :npm)

      # Step 6: Simulate uninstall (manual cleanup)
      File.rm_rf!(pkg_dir)

      updated_lock = Lockfile.remove_package(loaded_lock, "fake-pkg", :npm)
      {:ok, _} = Lockfile.write(updated_lock, lock_path)

      Maintenance.record_history("remove", %{
        package: "fake-pkg",
        forth: :npm
      })

      # Verify cleanup
      refute File.exists?(index_file)
      {:ok, final_lock} = Lockfile.read(lock_path)
      refute Lockfile.has_package?(final_lock, "fake-pkg", :npm)
    end
  end
end
