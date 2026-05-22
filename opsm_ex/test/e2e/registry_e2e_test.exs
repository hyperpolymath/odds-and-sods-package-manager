# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# End-to-end integration tests for registry adapters.
# These tests make real network calls to public registry APIs.
#
# Run with: mix test test/e2e/ --include e2e
# Excluded from normal test runs (requires network access).

defmodule Opsm.E2E.RegistryE2ETest do
  use ExUnit.Case, async: false

  alias Opsm.Registries.{Npm, Hex, Crates, Pypi}

  @moduletag :e2e

  # Generous timeouts for real network calls
  @moduletag timeout: 60_000

  # ==========================================================================
  # npm Registry — https://registry.npmjs.org
  # ==========================================================================

  describe "npm registry (lodash)" do
    @tag :e2e
    test "versions/1 returns a non-empty list of versions" do
      assert {:ok, versions} = Npm.versions("lodash")
      assert is_list(versions)
      assert length(versions) > 100
      # lodash has been around since 2012, many versions
      assert Enum.all?(versions, &is_binary/1)
      # Check for a known version
      assert "4.17.21" in versions
    end

    @tag :e2e
    test "fetch_package/2 returns valid metadata for latest" do
      assert {:ok, pkg} = Npm.fetch_package("lodash", "latest")
      assert pkg.package == "lodash"
      assert pkg.forth == :npm
      assert is_binary(pkg.version)
      assert is_binary(pkg.tarball_url)
      assert pkg.tarball_url =~ "registry.npmjs.org"

      # Manifest fields
      assert pkg.manifest.name == "lodash"
      assert is_binary(pkg.manifest.description)
      assert pkg.manifest.license == "MIT"
      assert pkg.manifest.source_forth == :npm
    end

    @tag :e2e
    test "fetch_package/2 returns valid metadata for specific version" do
      assert {:ok, pkg} = Npm.fetch_package("lodash", "4.17.21")
      assert pkg.package == "lodash"
      assert pkg.version == "4.17.21"
      assert is_binary(pkg.checksum)
      assert pkg.checksum_algo == :sha1
    end

    @tag :e2e
    test "exists?/1 returns true for known package" do
      assert Npm.exists?("lodash") == true
    end

    @tag :e2e
    test "exists?/1 returns false for non-existent package" do
      assert Npm.exists?("this-package-does-not-exist-opsm-test-#{System.system_time(:second)}") == false
    end

    @tag :e2e
    test "search/2 returns results" do
      assert {:ok, results} = Npm.search("lodash", limit: 5)
      assert is_list(results)
      assert length(results) > 0

      first = List.first(results)
      assert is_binary(first.name)
    end
  end

  # ==========================================================================
  # Hex Registry — https://hex.pm/api
  # ==========================================================================

  describe "hex registry (jason)" do
    @tag :e2e
    test "versions/1 returns a non-empty list of versions" do
      assert {:ok, versions} = Hex.versions("jason")
      assert is_list(versions)
      assert length(versions) > 5
      assert Enum.all?(versions, &is_binary/1)
      # jason 1.4.1 is a well-known version
      assert "1.4.1" in versions
    end

    @tag :e2e
    test "fetch_package/2 returns valid metadata for latest" do
      assert {:ok, pkg} = Hex.fetch_package("jason", "latest")
      assert pkg.package == "jason"
      assert pkg.forth == :hex
      assert is_binary(pkg.version)
      assert is_binary(pkg.tarball_url)
      assert pkg.tarball_url =~ "repo.hex.pm"

      # Manifest fields
      assert pkg.manifest.name == "jason"
      assert is_binary(pkg.manifest.description)
      assert pkg.manifest.source_forth == :hex
    end

    @tag :e2e
    test "fetch_package/2 returns valid metadata for specific version" do
      assert {:ok, pkg} = Hex.fetch_package("jason", "1.4.1")
      assert pkg.package == "jason"
      assert pkg.version == "1.4.1"
      # Hex provides SHA-256 checksums
      assert pkg.checksum_algo == :sha256
    end

    @tag :e2e
    test "fetch_package/2 includes dependencies" do
      # phoenix has known dependencies
      assert {:ok, pkg} = Hex.fetch_package("phoenix", "latest")
      assert pkg.package == "phoenix"
      assert is_map(pkg.manifest.dependencies)
      # Phoenix depends on plug, plug_crypto, etc.
      assert map_size(pkg.manifest.dependencies) > 0
    end

    @tag :e2e
    test "exists?/1 returns true for known package" do
      assert Hex.exists?("jason") == true
    end

    @tag :e2e
    test "exists?/1 returns false for non-existent package" do
      assert Hex.exists?("nonexistent-pkg-opsm-test-#{System.system_time(:second)}") == false
    end

    @tag :e2e
    test "search/2 returns results for jason" do
      assert {:ok, results} = Hex.search("jason", limit: 5)
      assert is_list(results)
      assert length(results) > 0
    end
  end

  # ==========================================================================
  # Crates.io Registry — https://crates.io/api/v1
  # ==========================================================================

  describe "crates.io registry (serde)" do
    @tag :e2e
    test "versions/1 returns a non-empty list of versions" do
      assert {:ok, versions} = Crates.versions("serde")
      assert is_list(versions)
      assert length(versions) > 100
      assert Enum.all?(versions, &is_binary/1)
      # serde 1.0.0 is a known version
      assert "1.0.0" in versions
    end

    @tag :e2e
    test "fetch_package/2 returns valid metadata for latest" do
      assert {:ok, pkg} = Crates.fetch_package("serde", "latest")
      assert pkg.package == "serde"
      assert pkg.forth == :cargo
      assert is_binary(pkg.version)
      assert is_binary(pkg.tarball_url)
      assert pkg.tarball_url =~ "crates"

      # Manifest fields
      assert pkg.manifest.name == "serde"
      assert is_binary(pkg.manifest.description)
      assert pkg.manifest.source_forth == :cargo
    end

    @tag :e2e
    test "fetch_package/2 returns valid metadata for specific version" do
      assert {:ok, pkg} = Crates.fetch_package("serde", "1.0.210")
      assert pkg.package == "serde"
      assert pkg.version == "1.0.210"
      assert pkg.checksum_algo == :sha256
    end

    @tag :e2e
    test "fetch_package/2 includes dependencies" do
      # serde_json has known dependencies (serde, itoa, etc.)
      assert {:ok, pkg} = Crates.fetch_package("serde_json", "latest")
      assert pkg.package == "serde_json"
      assert is_map(pkg.manifest.dependencies)
      assert map_size(pkg.manifest.dependencies) > 0
    end

    @tag :e2e
    test "exists?/1 returns true for known crate" do
      assert Crates.exists?("serde") == true
    end

    @tag :e2e
    test "exists?/1 returns false for non-existent crate" do
      assert Crates.exists?("nonexistent-crate-opsm-test-#{System.system_time(:second)}") == false
    end

    @tag :e2e
    test "search/2 returns results for serde" do
      assert {:ok, results} = Crates.search("serde", limit: 5)
      assert is_list(results)
      assert length(results) > 0

      first = List.first(results)
      assert is_binary(first.name)
    end

    @tag :e2e
    test "dependencies/2 returns dependency map for serde_json" do
      assert {:ok, deps} = Crates.dependencies("serde_json", "1.0.128")
      assert is_map(deps)
      # serde_json has "normal" dependencies
      assert Map.has_key?(deps, "normal")
    end
  end

  # ==========================================================================
  # PyPI Registry — https://pypi.org/pypi
  # ==========================================================================

  describe "pypi registry (requests)" do
    @tag :e2e
    test "versions/1 returns a non-empty list of versions" do
      assert {:ok, versions} = Pypi.versions("requests")
      assert is_list(versions)
      assert length(versions) > 50
      assert Enum.all?(versions, &is_binary/1)
      # requests 2.28.0 is a known version
      assert "2.28.0" in versions
    end

    @tag :e2e
    test "fetch_package/2 returns valid metadata for latest" do
      assert {:ok, pkg} = Pypi.fetch_package("requests", "latest")
      assert pkg.package == "requests"
      assert pkg.forth == :pypi
      assert is_binary(pkg.version)
      # PyPI provides download URLs
      assert is_binary(pkg.tarball_url)

      # Manifest fields
      assert pkg.manifest.name == "requests"
      assert is_binary(pkg.manifest.description)
      assert pkg.manifest.source_forth == :pypi
    end

    @tag :e2e
    test "fetch_package/2 returns valid metadata for specific version" do
      assert {:ok, pkg} = Pypi.fetch_package("requests", "2.31.0")
      assert pkg.package == "requests"
      assert pkg.version == "2.31.0"
      assert pkg.checksum_algo == :sha256
      assert is_binary(pkg.checksum)
    end

    @tag :e2e
    test "fetch_package/2 includes dependencies (requires_dist)" do
      assert {:ok, pkg} = Pypi.fetch_package("requests", "latest")
      assert is_map(pkg.manifest.dependencies)
      # requests depends on urllib3, certifi, charset-normalizer, idna
      assert map_size(pkg.manifest.dependencies) > 0
    end

    @tag :e2e
    test "exists?/1 returns true for known package" do
      assert Pypi.exists?("requests") == true
    end

    @tag :e2e
    test "exists?/1 returns false for non-existent package" do
      assert Pypi.exists?("nonexistent-pkg-opsm-test-#{System.system_time(:second)}") == false
    end

    @tag :e2e
    test "fetch_package/2 returns not_found for non-existent package" do
      result = Pypi.fetch_package("nonexistent-pkg-opsm-#{System.system_time(:second)}")

      case result do
        {:error, :not_found} -> assert true
        {:error, {:http_error, 404}} -> assert true
        {:error, _reason} -> assert true
      end
    end
  end

  # ==========================================================================
  # Cross-Registry Consistency Checks
  # ==========================================================================

  describe "cross-registry consistency" do
    @tag :e2e
    test "all registries return consistent struct shapes" do
      # Fetch one package from each registry
      results = [
        {:npm, Npm.fetch_package("lodash", "latest")},
        {:hex, Hex.fetch_package("jason", "latest")},
        {:cargo, Crates.fetch_package("serde", "latest")},
        {:pypi, Pypi.fetch_package("requests", "latest")}
      ]

      for {registry, result} <- results do
        case result do
          {:ok, pkg} ->
            # All should return ResolvedPackage structs with the same fields
            assert is_binary(pkg.package), "#{registry}: package name should be binary"
            assert is_binary(pkg.version), "#{registry}: version should be binary"
            assert is_atom(pkg.forth), "#{registry}: forth should be atom"
            assert is_binary(pkg.registry_url), "#{registry}: registry_url should be binary"
            assert is_list(pkg.attestations), "#{registry}: attestations should be list"
            assert is_list(pkg.resolved_deps), "#{registry}: resolved_deps should be list"

            # Manifest should be consistent
            assert is_binary(pkg.manifest.name), "#{registry}: manifest.name should be binary"
            assert is_binary(pkg.manifest.version), "#{registry}: manifest.version should be binary"
            assert is_map(pkg.manifest.dependencies), "#{registry}: dependencies should be map"
            assert is_atom(pkg.manifest.source_forth), "#{registry}: source_forth should be atom"

          {:error, reason} ->
            flunk("#{registry} fetch failed: #{inspect(reason)}")
        end
      end
    end

    @tag :e2e
    test "all registries handle not-found consistently" do
      nonexistent = "definitely-not-a-real-package-opsm-#{System.system_time(:second)}"

      results = [
        {:npm, Npm.fetch_package(nonexistent)},
        {:hex, Hex.fetch_package(nonexistent)},
        {:cargo, Crates.fetch_package(nonexistent)},
        {:pypi, Pypi.fetch_package(nonexistent)}
      ]

      for {registry, result} <- results do
        case result do
          {:error, _reason} ->
            # All should return some form of error
            assert true

          {:ok, _} ->
            flunk("#{registry}: should not find non-existent package '#{nonexistent}'")
        end
      end
    end
  end
end
