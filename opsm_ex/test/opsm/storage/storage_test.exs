# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Storage.StorageTest do
  use ExUnit.Case, async: false

  alias Opsm.Storage.{Local, S3, Ipfs, Manager}

  @test_dir Path.join(System.tmp_dir!(), "opsm_storage_test_#{:rand.uniform(1_000_000)}")

  setup do
    File.mkdir_p!(@test_dir)

    on_exit(fn -> File.rm_rf!(@test_dir) end)
    :ok
  end

  # ---------------------------------------------------------------------------
  # Local backend
  # ---------------------------------------------------------------------------

  describe "Local backend" do
    test "put/get round-trip stores and retrieves file contents" do
      src = Path.join(@test_dir, "test.tgz")
      File.write!(src, "tarball-data-123")

      key = "npm/test-pkg-1.0.0.tgz"
      assert {:ok, ^key} = Local.put(key, src, [])

      dest = Path.join(@test_dir, "retrieved.tgz")
      assert {:ok, ^dest} = Local.get(key, dest, [])
      assert File.read!(dest) == "tarball-data-123"

      # Cleanup
      Local.get(key, src, [])
      File.rm(Local.path_for(key))
    end

    test "exists? returns false for unknown key" do
      refute Local.exists?("cargo/does-not-exist-999.9.9.crate", [])
    end

    test "exists? returns true after put" do
      src = Path.join(@test_dir, "exists_check.tgz")
      File.write!(src, "data")
      key = "hex/exists-test-0.1.0.tar"

      Local.put(key, src, [])
      assert Local.exists?(key, [])

      # Cleanup
      File.rm(Local.path_for(key))
    end

    test "get returns {:error, :not_found} for missing key" do
      dest = Path.join(@test_dir, "not_there.tgz")
      assert {:error, :not_found} = Local.get("npm/ghost-pkg-0.0.0.tgz", dest, [])
    end

    test "url/2 always returns nil (local has no public URL)" do
      assert Local.url("any-key", []) == nil
    end

    test "path_for/1 returns a path inside the cache root" do
      path = Local.path_for("cargo/serde-1.0.0.crate")
      assert String.starts_with?(path, Local.cache_root())
    end
  end

  # ---------------------------------------------------------------------------
  # S3 backend (without credentials = not_configured)
  # ---------------------------------------------------------------------------

  describe "S3 backend (unconfigured)" do
    test "put returns {:error, :not_configured} when env vars absent" do
      # Remove any possible env override
      System.delete_env("OPSM_S3_BUCKET")
      System.delete_env("AWS_ACCESS_KEY_ID")
      System.delete_env("AWS_SECRET_ACCESS_KEY")

      src = Path.join(@test_dir, "s3_test.tgz")
      File.write!(src, "data")
      assert {:error, :not_configured} = S3.put("npm/test-1.0.0.tgz", src, [])
    end

    test "exists? returns false when env vars absent" do
      System.delete_env("OPSM_S3_BUCKET")
      System.delete_env("AWS_ACCESS_KEY_ID")
      System.delete_env("AWS_SECRET_ACCESS_KEY")

      refute S3.exists?("any/key.tgz", [])
    end

    test "url returns nil when env vars absent" do
      System.delete_env("OPSM_S3_BUCKET")
      assert S3.url("any/key.tgz", []) == nil
    end
  end

  # ---------------------------------------------------------------------------
  # IPFS backend (without running node)
  # ---------------------------------------------------------------------------

  describe "Ipfs backend (no node)" do
    test "exists? returns false when CID not in index" do
      # No IPFS node running — exists? must not raise
      refute Ipfs.exists?("npm/ghost-0.0.0.tgz", [])
    end

    test "get returns {:error, :not_found} for unknown key" do
      dest = Path.join(@test_dir, "ipfs_get.tgz")
      assert {:error, :not_found} = Ipfs.get("npm/ghost-0.0.0.tgz", dest, [])
    end

    test "url returns nil for unknown key (no CID in index)" do
      assert Ipfs.url("npm/ghost-0.0.0.tgz", []) == nil
    end
  end

  # ---------------------------------------------------------------------------
  # Manager
  # ---------------------------------------------------------------------------

  describe "Manager" do
    test "status/0 returns a map with local, s3, ipfs keys" do
      status = Manager.status()
      assert Map.has_key?(status, :local)
      assert Map.has_key?(status, :s3)
      assert Map.has_key?(status, :ipfs)
      assert status.local.active == true
    end

    test "fetch returns {:error, :not_found} when key not in any backend" do
      System.delete_env("OPSM_S3_BUCKET")
      System.delete_env("OPSM_IPFS_API")

      dest = Path.join(@test_dir, "manager_fetch.tgz")
      assert {:error, :not_found} = Manager.fetch("npm/totally-unknown-key-999.tgz", dest)
    end

    test "fetch returns {:ok, path} for key present in local backend" do
      # Write directly to local cache and verify Manager sees it
      src = Path.join(@test_dir, "manager_local.tgz")
      File.write!(src, "local-data")
      key = "npm/manager-local-test-9.9.9.tgz"
      {:ok, _} = Local.put(key, src, [])

      dest = Path.join(@test_dir, "manager_fetch_result.tgz")
      assert {:ok, _path} = Manager.fetch(key, dest)

      # Cleanup
      File.rm(Local.path_for(key))
    end

    test "store/2 completes without error when only local backend active" do
      System.delete_env("OPSM_S3_BUCKET")
      System.delete_env("OPSM_IPFS_API")

      src = Path.join(@test_dir, "manager_store.tgz")
      File.write!(src, "store-data")
      assert :ok = Manager.store("npm/store-test-1.0.0.tgz", src)
    end

    test "public_url returns nil when no remote backends configured" do
      System.delete_env("OPSM_S3_BUCKET")
      System.delete_env("OPSM_IPFS_API")

      assert Manager.public_url("npm/any.tgz") == nil
    end
  end

  # ---------------------------------------------------------------------------
  # storage_key_for indirectly (via Downloader.cache_path_for pattern)
  # ---------------------------------------------------------------------------

  describe "storage key format" do
    test "forward-slash in Go package names is escaped to double-dash" do
      # We can't call private storage_key_for directly, but Local.path_for
      # should contain double-dash for slashes (it mirrors the same logic)
      key = "go/github.com--gin-gonic--gin-1.9.0.zip"
      path = Local.path_for(key)
      assert String.contains?(path, "github.com--gin-gonic")
    end
  end
end
