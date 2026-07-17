# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.LockfileTest do
  use ExUnit.Case, async: true

  alias Opsm.Lockfile

  describe "new/0" do
    test "creates an empty lockfile" do
      lockfile = Lockfile.new()

      # v2: Added crypto integration
      assert lockfile.version == "2"
      assert lockfile.packages == %{}
      assert lockfile.generated_at != nil
      # Not computed until write
      assert lockfile.integrity_hash == nil
      assert lockfile.integrity_algo == "sha3-512"
    end
  end

  describe "add_package/2" do
    test "adds a package to the lockfile" do
      lockfile = Lockfile.new()

      package = %{
        name: "lodash",
        version: "4.17.21",
        forth: :npm,
        checksum: "abc123",
        source_url: "https://registry.npmjs.org/lodash/-/lodash-4.17.21.tgz"
      }

      updated = Lockfile.add_package(lockfile, package)

      assert Lockfile.has_package?(updated, "lodash", :npm)

      entry = Lockfile.get_package(updated, "lodash", :npm)
      assert entry.name == "lodash"
      assert entry.version == "4.17.21"
      assert entry.forth == :npm
      assert entry.checksum == "abc123"
    end

    test "updates existing package" do
      lockfile = Lockfile.new()

      package1 = %{name: "pkg", version: "1.0.0", forth: :npm}
      package2 = %{name: "pkg", version: "2.0.0", forth: :npm}

      updated =
        lockfile
        |> Lockfile.add_package(package1)
        |> Lockfile.add_package(package2)

      entry = Lockfile.get_package(updated, "pkg", :npm)
      assert entry.version == "2.0.0"
    end

    test "handles packages from different forths" do
      lockfile = Lockfile.new()

      npm_pkg = %{name: "chalk", version: "5.0.0", forth: :npm}
      cargo_pkg = %{name: "serde", version: "1.0.0", forth: :cargo}

      updated =
        lockfile
        |> Lockfile.add_package(npm_pkg)
        |> Lockfile.add_package(cargo_pkg)

      assert Lockfile.has_package?(updated, "chalk", :npm)
      assert Lockfile.has_package?(updated, "serde", :cargo)
      refute Lockfile.has_package?(updated, "chalk", :cargo)
    end
  end

  describe "remove_package/3" do
    test "removes a package from the lockfile" do
      lockfile =
        Lockfile.new()
        |> Lockfile.add_package(%{name: "pkg", version: "1.0.0", forth: :npm})

      assert Lockfile.has_package?(lockfile, "pkg", :npm)

      updated = Lockfile.remove_package(lockfile, "pkg", :npm)

      refute Lockfile.has_package?(updated, "pkg", :npm)
    end

    test "does nothing for non-existent package" do
      lockfile = Lockfile.new()
      updated = Lockfile.remove_package(lockfile, "nonexistent", :npm)

      assert updated.packages == %{}
    end
  end

  describe "list_packages/1" do
    test "returns sorted list of packages" do
      lockfile =
        Lockfile.new()
        |> Lockfile.add_package(%{name: "zebra", version: "1.0.0", forth: :npm})
        |> Lockfile.add_package(%{name: "alpha", version: "1.0.0", forth: :npm})
        |> Lockfile.add_package(%{name: "beta", version: "1.0.0", forth: :npm})

      packages = Lockfile.list_packages(lockfile)

      assert length(packages) == 3
      assert Enum.at(packages, 0).name == "alpha"
      assert Enum.at(packages, 1).name == "beta"
      assert Enum.at(packages, 2).name == "zebra"
    end
  end

  describe "packages_for_forth/2" do
    test "filters packages by forth" do
      lockfile =
        Lockfile.new()
        |> Lockfile.add_package(%{name: "lodash", version: "4.0.0", forth: :npm})
        |> Lockfile.add_package(%{name: "serde", version: "1.0.0", forth: :cargo})
        |> Lockfile.add_package(%{name: "chalk", version: "5.0.0", forth: :npm})

      npm_packages = Lockfile.packages_for_forth(lockfile, :npm)

      assert length(npm_packages) == 2
      assert Enum.all?(npm_packages, fn p -> p.forth == :npm end)
    end
  end

  describe "verify_package/4" do
    test "returns :ok when checksum matches" do
      lockfile =
        Lockfile.new()
        |> Lockfile.add_package(%{name: "pkg", version: "1.0.0", forth: :npm, checksum: "abc123"})

      assert :ok = Lockfile.verify_package(lockfile, "pkg", :npm, "abc123")
    end

    test "returns mismatch when checksum differs" do
      lockfile =
        Lockfile.new()
        |> Lockfile.add_package(%{name: "pkg", version: "1.0.0", forth: :npm, checksum: "abc123"})

      assert {:mismatch, details} = Lockfile.verify_package(lockfile, "pkg", :npm, "xyz789")
      assert details.expected == "abc123"
      assert details.actual == "xyz789"
    end

    test "returns ok with warning when no checksum recorded" do
      lockfile =
        Lockfile.new()
        |> Lockfile.add_package(%{name: "pkg", version: "1.0.0", forth: :npm})

      assert {:ok, :no_checksum_recorded} = Lockfile.verify_package(lockfile, "pkg", :npm, "any")
    end

    test "returns error for package not in lockfile" do
      lockfile = Lockfile.new()

      assert {:error, :not_in_lockfile} = Lockfile.verify_package(lockfile, "pkg", :npm, "any")
    end
  end

  describe "check_sync/2" do
    test "reports in sync when matching" do
      lockfile =
        Lockfile.new()
        |> Lockfile.add_package(%{name: "pkg1", version: "1.0.0", forth: :npm})
        |> Lockfile.add_package(%{name: "pkg2", version: "1.0.0", forth: :npm})

      installed = [
        %{name: "pkg1", forth: :npm},
        %{name: "pkg2", forth: :npm}
      ]

      result = Lockfile.check_sync(lockfile, installed)

      assert result.in_sync == true
      assert result.missing_from_lockfile == []
      assert result.not_installed == []
    end

    test "reports packages missing from lockfile" do
      lockfile =
        Lockfile.new()
        |> Lockfile.add_package(%{name: "pkg1", version: "1.0.0", forth: :npm})

      installed = [
        %{name: "pkg1", forth: :npm},
        %{name: "pkg2", forth: :npm}
      ]

      result = Lockfile.check_sync(lockfile, installed)

      assert result.in_sync == false
      assert "pkg2@npm" in result.missing_from_lockfile
    end

    test "reports packages not installed" do
      lockfile =
        Lockfile.new()
        |> Lockfile.add_package(%{name: "pkg1", version: "1.0.0", forth: :npm})
        |> Lockfile.add_package(%{name: "pkg2", version: "1.0.0", forth: :npm})

      installed = [
        %{name: "pkg1", forth: :npm}
      ]

      result = Lockfile.check_sync(lockfile, installed)

      assert result.in_sync == false
      assert "pkg2@npm" in result.not_installed
    end
  end

  describe "read/1 and write/2" do
    setup do
      tmp_dir = Path.join(System.tmp_dir!(), "opsm_lockfile_test_#{:rand.uniform(1_000_000)}")
      File.mkdir_p!(tmp_dir)

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      {:ok, tmp_dir: tmp_dir}
    end

    test "roundtrip write and read", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "opsm.lock")

      original =
        Lockfile.new()
        |> Lockfile.add_package(%{
          name: "lodash",
          version: "4.17.21",
          forth: :npm,
          checksum: "abc123",
          source_url: "https://example.com/lodash.tgz",
          dependencies: ["dep1", "dep2"]
        })

      {:ok, ^path} = Lockfile.write(original, path)
      {:ok, loaded} = Lockfile.read(path)

      assert loaded.version == original.version

      entry = Lockfile.get_package(loaded, "lodash", :npm)
      assert entry.name == "lodash"
      assert entry.version == "4.17.21"
      assert entry.checksum == "abc123"
      assert entry.dependencies == ["dep1", "dep2"]
    end

    test "returns error for missing file", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "nonexistent.lock")

      assert {:error, :not_found} = Lockfile.read(path)
    end
  end

  describe "find_lockfile/1" do
    setup do
      tmp_dir = Path.join(System.tmp_dir!(), "opsm_lockfile_find_#{:rand.uniform(1_000_000)}")
      File.mkdir_p!(tmp_dir)

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      {:ok, tmp_dir: tmp_dir}
    end

    test "finds lockfile in current directory", %{tmp_dir: tmp_dir} do
      lock_path = Path.join(tmp_dir, "opsm.lock")
      File.write!(lock_path, "{}")

      {:ok, found} = Lockfile.find_lockfile(tmp_dir)
      assert found == lock_path
    end

    test "finds lockfile in parent directory", %{tmp_dir: tmp_dir} do
      lock_path = Path.join(tmp_dir, "opsm.lock")
      File.write!(lock_path, "{}")

      subdir = Path.join(tmp_dir, "src/lib")
      File.mkdir_p!(subdir)

      {:ok, found} = Lockfile.find_lockfile(subdir)
      assert found == lock_path
    end

    test "returns error when not found", %{tmp_dir: tmp_dir} do
      # No lock file created
      subdir = Path.join(tmp_dir, "src")
      File.mkdir_p!(subdir)

      {:error, :not_found} = Lockfile.find_lockfile(subdir)
    end
  end

  describe "compute_integrity_hash/1" do
    test "computes SHA3-512 integrity hash for lockfile" do
      lockfile =
        Lockfile.new()
        |> Lockfile.add_package(%{name: "pkg", version: "1.0.0", forth: :npm, checksum: "abc123"})

      lockfile_with_hash = Lockfile.compute_integrity_hash(lockfile)

      assert lockfile_with_hash.integrity_hash != nil
      # 512 bits = 128 hex chars
      assert String.length(lockfile_with_hash.integrity_hash) == 128
      assert lockfile_with_hash.integrity_algo == "sha3-512"
    end

    test "produces different hashes for different lockfiles" do
      lockfile1 =
        Lockfile.new()
        |> Lockfile.add_package(%{name: "pkg1", version: "1.0.0", forth: :npm})
        |> Lockfile.compute_integrity_hash()

      lockfile2 =
        Lockfile.new()
        |> Lockfile.add_package(%{name: "pkg2", version: "1.0.0", forth: :npm})
        |> Lockfile.compute_integrity_hash()

      assert lockfile1.integrity_hash != lockfile2.integrity_hash
    end

    test "produces same hash for same lockfile" do
      lockfile =
        Lockfile.new()
        |> Lockfile.add_package(%{name: "pkg", version: "1.0.0", forth: :npm})

      hash1 = Lockfile.compute_integrity_hash(lockfile).integrity_hash
      hash2 = Lockfile.compute_integrity_hash(lockfile).integrity_hash

      assert hash1 == hash2
    end
  end

  describe "verify_integrity/1" do
    test "verifies valid integrity hash" do
      lockfile =
        Lockfile.new()
        |> Lockfile.add_package(%{name: "pkg", version: "1.0.0", forth: :npm})
        |> Lockfile.compute_integrity_hash()

      assert :ok = Lockfile.verify_integrity(lockfile)
    end

    test "detects tampering (modified packages)" do
      lockfile =
        Lockfile.new()
        |> Lockfile.add_package(%{name: "pkg", version: "1.0.0", forth: :npm})
        |> Lockfile.compute_integrity_hash()

      # Tamper with the lockfile (change version)
      tampered = Lockfile.add_package(lockfile, %{name: "pkg", version: "2.0.0", forth: :npm})
      # Keep the old integrity hash (simulating tampering)
      tampered = %{tampered | integrity_hash: lockfile.integrity_hash}

      assert {:error, _} = Lockfile.verify_integrity(tampered)
    end

    test "allows lockfiles without integrity hash (backward compatibility)" do
      lockfile =
        Lockfile.new()
        |> Lockfile.add_package(%{name: "pkg", version: "1.0.0", forth: :npm})

      # No integrity hash computed

      assert {:ok, :no_integrity_hash} = Lockfile.verify_integrity(lockfile)
    end
  end

  describe "encryption and decryption" do
    setup do
      tmp_dir = Path.join(System.tmp_dir!(), "opsm_lockfile_crypto_#{:rand.uniform(1_000_000)}")
      File.mkdir_p!(tmp_dir)

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      {:ok, tmp_dir: tmp_dir}
    end

    test "encrypts and decrypts lockfile", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "opsm.lock")
      key = Opsm.Crypto.Symmetric.generate_key()

      original =
        Lockfile.new()
        |> Lockfile.add_package(%{name: "secret-pkg", version: "1.0.0", forth: :npm})

      {:ok, ^path} = Lockfile.write(original, path, encrypt: true, key: key)
      {:ok, loaded} = Lockfile.read(path, decrypt: true, key: key, verify_integrity: false)

      assert loaded.version == original.version
      entry = Lockfile.get_package(loaded, "secret-pkg", :npm)
      assert entry.name == "secret-pkg"
    end

    test "encrypted file cannot be read without decryption", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "opsm.lock")
      key = Opsm.Crypto.Symmetric.generate_key()

      lockfile =
        Lockfile.new()
        |> Lockfile.add_package(%{name: "pkg", version: "1.0.0", forth: :npm})

      {:ok, ^path} = Lockfile.write(lockfile, path, encrypt: true, key: key)

      # Try to read without decryption - should fail
      assert {:error, _} = Lockfile.read(path)
    end

    test "decryption fails with wrong key", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "opsm.lock")
      correct_key = Opsm.Crypto.Symmetric.generate_key()
      wrong_key = Opsm.Crypto.Symmetric.generate_key()

      lockfile =
        Lockfile.new()
        |> Lockfile.add_package(%{name: "pkg", version: "1.0.0", forth: :npm})

      {:ok, ^path} = Lockfile.write(lockfile, path, encrypt: true, key: correct_key)

      # Try to decrypt with wrong key
      assert {:error, _} = Lockfile.read(path, decrypt: true, key: wrong_key)
    end
  end

  describe "write with integrity hash" do
    setup do
      tmp_dir =
        Path.join(System.tmp_dir!(), "opsm_lockfile_integrity_#{:rand.uniform(1_000_000)}")

      File.mkdir_p!(tmp_dir)

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      {:ok, tmp_dir: tmp_dir}
    end

    test "write automatically computes integrity hash", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "opsm.lock")

      lockfile =
        Lockfile.new()
        |> Lockfile.add_package(%{name: "pkg", version: "1.0.0", forth: :npm})

      {:ok, ^path} = Lockfile.write(lockfile, path)
      {:ok, loaded} = Lockfile.read(path)

      assert loaded.integrity_hash != nil
      assert loaded.integrity_algo == "sha3-512"
      assert :ok = Lockfile.verify_integrity(loaded)
    end

    test "read detects tampered lockfile", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "opsm.lock")

      lockfile =
        Lockfile.new()
        |> Lockfile.add_package(%{name: "pkg", version: "1.0.0", forth: :npm})

      {:ok, ^path} = Lockfile.write(lockfile, path)

      # Manually tamper with the file
      {:ok, content} = File.read(path)
      tampered = String.replace(content, "1.0.0", "2.0.0")
      File.write!(path, tampered)

      # Should fail integrity check
      assert {:error, _} = Lockfile.read(path)
    end
  end

  describe "BLAKE2b package checksums" do
    test "new packages default to BLAKE2b checksums" do
      lockfile =
        Lockfile.new()
        |> Lockfile.add_package(%{name: "pkg", version: "1.0.0", forth: :npm, checksum: "abc123"})

      entry = Lockfile.get_package(lockfile, "pkg", :npm)
      # v1.0.1: Default to BLAKE2b
      assert entry.checksum_algo == "blake2b"
    end

    test "can specify custom checksum algorithm" do
      lockfile =
        Lockfile.new()
        |> Lockfile.add_package(%{
          name: "pkg",
          version: "1.0.0",
          forth: :npm,
          checksum: "xyz789",
          checksum_algo: "sha3-512"
        })

      entry = Lockfile.get_package(lockfile, "pkg", :npm)
      assert entry.checksum_algo == "sha3-512"
    end
  end
end
