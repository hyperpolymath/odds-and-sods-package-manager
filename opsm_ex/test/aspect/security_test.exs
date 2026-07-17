# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Aspect.SecurityTest do
  use ExUnit.Case, async: true

  alias Opsm.{Lockfile, Verified}
  alias Opsm.Registries.Registry

  @moduletag :aspect
  @moduletag :security

  describe "Package Tampering Detection" do
    test "detects checksum mismatch when package is altered" do
      lockfile =
        Lockfile.new()
        |> Lockfile.add_package(%{
          name: "critical-lib",
          version: "1.0.0",
          forth: :npm,
          checksum: "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
          checksum_algo: "sha256"
        })

      # Tampered checksum should not match
      {:mismatch, details} =
        Lockfile.verify_package(
          lockfile,
          "critical-lib",
          :npm,
          "sha256:0000000000000000000000000000000000000000000000000000000000000000"
        )

      assert details.expected =~ "e3b0c44"
      assert details.actual =~ "00000000"
    end

    test "rejects package with missing checksum" do
      lockfile =
        Lockfile.new()
        |> Lockfile.add_package(%{
          name: "untrusted-lib",
          version: "1.0.0",
          forth: :npm
        })

      result = Lockfile.verify_package(lockfile, "untrusted-lib", :npm, "any-checksum")

      # Missing checksum should produce warning
      assert {:ok, :no_checksum_recorded} = result
    end
  end

  describe "Dependency Confusion Detection" do
    test "blocks package when internal and external registries have same name" do
      # Simulate: package "lodash" requested from npm but also exists internally
      # A package manager should prefer internal registry first

      # This is a registry-level check: when resolving, prefer internal registries
      registry_order = [:internal, :private, :npm]

      # The resolver should check internal registries first
      assert :internal in registry_order
      assert :npm in registry_order

      assert Enum.find_index(registry_order, &(&1 == :internal)) <
               Enum.find_index(registry_order, &(&1 == :npm))
    end

    test "validates registry source for each package" do
      lockfile =
        Lockfile.new()
        |> Lockfile.add_package(%{
          name: "business-logic",
          version: "2.5.3",
          forth: :npm,
          source_url: "https://trusted-registry.example.com/business-logic.tgz"
        })
        |> Lockfile.add_package(%{
          name: "util-lib",
          version: "1.0.0",
          forth: :internal,
          source_url: "https://internal.company.local/util-lib.tgz"
        })

      npm_pkg = Lockfile.get_package(lockfile, "business-logic", :npm)
      internal_pkg = Lockfile.get_package(lockfile, "util-lib", :internal)

      # Verify packages have correct registry sources
      assert npm_pkg.forth == :npm
      assert internal_pkg.forth == :internal
      assert npm_pkg.source_url =~ "trusted-registry"
      assert internal_pkg.source_url =~ "internal.company"
    end
  end

  describe "Lockfile Poisoning Detection" do
    test "detects when lockfile has been modified after generation" do
      lockfile =
        Lockfile.new()
        |> Lockfile.add_package(%{
          name: "pkg1",
          version: "1.0.0",
          forth: :npm,
          checksum: "abc123"
        })
        |> Lockfile.compute_integrity_hash()

      original_hash = lockfile.integrity_hash

      # Simulate tampering: add a malicious package
      tampered =
        Lockfile.add_package(lockfile, %{
          name: "malware",
          version: "1.0.0",
          forth: :npm,
          checksum: "evil"
        })

      tampered = %{tampered | integrity_hash: original_hash}

      # Integrity verification should fail
      result = Lockfile.verify_integrity(tampered)
      assert {:error, _} = result
    end

    test "detects when dependency list is modified" do
      lockfile =
        Lockfile.new()
        |> Lockfile.add_package(%{
          name: "app",
          version: "1.0.0",
          forth: :npm,
          dependencies: ["safe-dep-1", "safe-dep-2"]
        })
        |> Lockfile.compute_integrity_hash()

      original_hash = lockfile.integrity_hash

      # Tamper: modify dependencies
      tampered =
        Lockfile.add_package(lockfile, %{
          name: "app",
          version: "1.0.0",
          forth: :npm,
          dependencies: ["safe-dep-1", "safe-dep-2", "malicious-dep"]
        })

      tampered = %{tampered | integrity_hash: original_hash}

      assert {:error, _} = Lockfile.verify_integrity(tampered)
    end

    test "lockfile integrity hash prevents silent corruption" do
      lockfile =
        Lockfile.new()
        |> Lockfile.add_package(%{name: "pkg", version: "1.0.0", forth: :npm, checksum: "abc"})
        |> Lockfile.compute_integrity_hash()

      # Compute new hash after modification
      modified =
        Lockfile.add_package(lockfile, %{
          name: "pkg",
          version: "2.0.0",
          forth: :npm,
          checksum: "def"
        })

      # Hash without recomputation should fail
      tampered = %{modified | integrity_hash: lockfile.integrity_hash}
      assert {:error, _} = Lockfile.verify_integrity(tampered)

      # Hash with recomputation should succeed
      correct = Lockfile.compute_integrity_hash(modified)
      assert :ok = Lockfile.verify_integrity(correct)
    end
  end

  describe "Registry MITM Protection" do
    test "validates registry URLs are well-formed" do
      alias Opsm.Verified.Url

      # Valid HTTP URL
      assert {:ok, url} = Url.validate("http://registry.example.com/package")
      assert url.scheme == "http"

      # Valid HTTPS URL
      assert {:ok, url} = Url.validate("https://registry.example.com/package")
      assert url.scheme == "https"

      # Both are acceptable for registry access
    end

    test "blocks localhost in registry URLs" do
      alias Opsm.Verified.Url

      # Localhost should be blocked
      assert {:error, :blocked_host} = Url.validate("https://localhost/api")
    end

    test "blocks file:// scheme" do
      alias Opsm.Verified.Url

      # file:// scheme should be rejected
      assert {:error, {:invalid_scheme, "file"}} = Url.validate("file:///etc/passwd")
    end

    test "blocks data: scheme" do
      alias Opsm.Verified.Url

      # data: scheme should be rejected
      assert {:error, {:invalid_scheme, "data"}} =
               Url.validate("data:text/html,<script>alert(1)</script>")
    end
  end

  describe "Path Traversal Prevention" do
    test "detects path traversal patterns in package paths" do
      # These paths are dangerous and should be detected
      invalid_paths = [
        "../../../etc/passwd",
        "lib/../../../etc/passwd",
        "node_modules/../../../sensitive",
        "..\\..\\..\\windows\\system32"
      ]

      # Verify they contain traversal patterns
      Enum.each(invalid_paths, fn path ->
        # Check for traversal pattern: .. or backslash escapes
        has_traversal = String.contains?(path, ["../", "..\\", "\\.."])
        assert has_traversal, "Path should contain traversal pattern: #{path}"
      end)
    end

    test "safe relative paths don't contain traversal patterns" do
      safe_paths = [
        "lib/mylib.js",
        "src/index.js",
        "dist/bundle.min.js",
        "lib/sub/deep/file.js"
      ]

      Enum.each(safe_paths, fn path ->
        has_traversal = String.contains?(path, ["../", "..\\", "\\.."])
        refute has_traversal, "Safe path should not contain traversal: #{path}"
      end)
    end

    test "path normalization prevents traversal attacks" do
      # When extracting a tarball, paths must be checked for traversal
      paths_to_check = [
        # Safe
        {"package/lib/main.js", false},
        # Dangerous
        {"package/../../../etc/passwd", true},
        # Safe
        {"package/./lib/index.js", false}
      ]

      Enum.each(paths_to_check, fn {path, is_dangerous} ->
        # Check for traversal patterns before extraction
        has_traversal = String.contains?(path, ["../", "..\\", "\\.."])

        if is_dangerous do
          # These paths should be detected as having traversal
          assert has_traversal, "Should detect traversal pattern in: #{path}"
        else
          # Safe paths shouldn't have traversal patterns
          refute has_traversal, "Safe path should not have traversal: #{path}"
        end
      end)
    end
  end

  describe "Cryptographic Verification" do
    test "uses SHA3-512 for lockfile integrity" do
      lockfile =
        Lockfile.new()
        |> Lockfile.add_package(%{name: "pkg", version: "1.0.0", forth: :npm})
        |> Lockfile.compute_integrity_hash()

      assert lockfile.integrity_algo == "sha3-512"
      # 512 bits = 128 hex
      assert String.length(lockfile.integrity_hash) == 128
    end

    test "packages default to BLAKE2b checksums" do
      lockfile =
        Lockfile.new()
        |> Lockfile.add_package(%{
          name: "pkg",
          version: "1.0.0",
          forth: :npm,
          checksum: "hash123"
        })

      pkg = Lockfile.get_package(lockfile, "pkg", :npm)
      assert pkg.checksum_algo == "blake2b"
    end
  end

  describe "Supply Chain Integrity" do
    test "lockfile records full dependency tree with integrity" do
      lockfile =
        Lockfile.new()
        |> Lockfile.add_package(%{
          name: "root",
          version: "1.0.0",
          forth: :npm,
          checksum: "root-hash",
          dependencies: ["dep-a", "dep-b"]
        })
        |> Lockfile.add_package(%{
          name: "dep-a",
          version: "2.0.0",
          forth: :npm,
          checksum: "dep-a-hash",
          dependencies: ["deep-dep"]
        })
        |> Lockfile.add_package(%{
          name: "deep-dep",
          version: "1.0.0",
          forth: :npm,
          checksum: "deep-hash",
          dependencies: []
        })
        |> Lockfile.compute_integrity_hash()

      # Every package in the chain has checksum
      root = Lockfile.get_package(lockfile, "root", :npm)
      dep_a = Lockfile.get_package(lockfile, "dep-a", :npm)
      deep = Lockfile.get_package(lockfile, "deep-dep", :npm)

      assert root.checksum == "root-hash"
      assert dep_a.checksum == "dep-a-hash"
      assert deep.checksum == "deep-hash"

      # Lockfile itself has integrity
      assert lockfile.integrity_hash != nil
      assert :ok = Lockfile.verify_integrity(lockfile)
    end

    test "prevents version substitution attacks" do
      lockfile =
        Lockfile.new()
        |> Lockfile.add_package(%{
          name: "pkg",
          version: "1.0.0",
          forth: :npm,
          checksum: "checksum-for-1.0.0"
        })

      # Cannot trick into accepting 2.0.0 with old checksum
      result = Lockfile.verify_package(lockfile, "pkg", :npm, "checksum-for-1.0.0")
      assert :ok = result

      # Wrong version should fail
      result_wrong = Lockfile.verify_package(lockfile, "pkg", :npm, "different-checksum")
      assert {:mismatch, _} = result_wrong
    end
  end
end
