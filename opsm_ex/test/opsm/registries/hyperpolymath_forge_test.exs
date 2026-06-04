# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Registries.HyperpPolymathForgeTest do
  use ExUnit.Case, async: false

  alias Opsm.Registries.HyperpPolymathForge

  # ---------------------------------------------------------------------------
  # Module interface contract
  # ---------------------------------------------------------------------------

  describe "module exports" do
    test "ensure_cache/0 is defined" do
      assert function_exported?(HyperpPolymathForge, :ensure_cache, 0)
    end

    test "search/2 is defined" do
      assert function_exported?(HyperpPolymathForge, :search, 2)
    end

    test "fetch_package/2 is defined" do
      assert function_exported?(HyperpPolymathForge, :fetch_package, 2)
    end

    test "versions/1 is defined" do
      assert function_exported?(HyperpPolymathForge, :versions, 1)
    end

    test "exists?/1 is defined" do
      assert function_exported?(HyperpPolymathForge, :exists?, 1)
    end
  end

  # ---------------------------------------------------------------------------
  # search/2 — hits the GitHub API (unauthenticated), so these tests require
  # network access and an un-rate-limited IP. Tagged :external_api.
  # ---------------------------------------------------------------------------

  describe "search/2" do
    @tag :external_api
    test "returns a list for any query" do
      result = HyperpPolymathForge.search("opsm", [])
      assert is_list(result)
    end

    @tag :external_api
    test "returns a list for empty string query" do
      result = HyperpPolymathForge.search("", [])
      assert is_list(result)
    end
  end

  # ---------------------------------------------------------------------------
  # versions/1 — hits GitHub API for tag list. Tagged :external_api.
  # ---------------------------------------------------------------------------

  describe "versions/1" do
    @tag :external_api
    test "returns ok tuple with list for any package name" do
      assert {:ok, versions} = HyperpPolymathForge.versions("opsm")
      assert is_list(versions)
    end

    @tag :external_api
    test "returns ok tuple with list for non-existent package" do
      assert {:ok, versions} = HyperpPolymathForge.versions("xyz-definitely-not-a-package-999")
      assert is_list(versions)
    end
  end

  # ---------------------------------------------------------------------------
  # exists?/1
  # ---------------------------------------------------------------------------

  describe "exists?/1" do
    test "returns boolean for any query" do
      result = HyperpPolymathForge.exists?("opsm")
      assert is_boolean(result)
    end

    test "returns false for obviously non-existent package" do
      result = HyperpPolymathForge.exists?("xyz-definitely-not-a-hp-package-abc-999")
      assert result == false
    end
  end

  # ---------------------------------------------------------------------------
  # fetch_package/2
  # ---------------------------------------------------------------------------

  describe "fetch_package/2" do
    test "returns error tuple for non-existent package" do
      result = HyperpPolymathForge.fetch_package("xyz-definitely-not-a-hp-package-abc-999", "latest")
      assert match?({:error, _}, result)
    end

    @tag :external_api
    test "returns ok or not_found for opsm itself" do
      case HyperpPolymathForge.fetch_package("opsm", "latest") do
        {:ok, pkg} ->
          assert is_map(pkg)
          assert pkg.forth == :hf
        {:error, :not_found} ->
          # Acceptable if GitHub API unavailable in CI or cache miss
          :ok
        {:error, _} ->
          :ok
      end
    end
  end

  # ---------------------------------------------------------------------------
  # ensure_cache/0 — idempotent, non-crashing
  # ---------------------------------------------------------------------------

  describe "ensure_cache/0" do
    test "does not raise when called multiple times" do
      HyperpPolymathForge.ensure_cache()
      HyperpPolymathForge.ensure_cache()
      HyperpPolymathForge.ensure_cache()
      assert true
    end
  end

  # ---------------------------------------------------------------------------
  # ETS-seeded tests — no network required
  #
  # We seed the :hfr_cache ETS table directly before each test and clear it
  # after.  This exercises search/2, exists?/1, and fetch_package/2 logic
  # without touching the GitHub API.
  # ---------------------------------------------------------------------------

  describe "search/2 — ETS-seeded (no network)" do
    setup do
      HyperpPolymathForge.ensure_cache()
      now = System.monotonic_time(:millisecond)
      expiry = now + 60_000

      entries = [
        {"opsm", %{
          type: :package,
          pkg_name: "opsm",
          repo_name: "odds-and-sods-package-manager",
          default_branch: "main",
          version: "2.0.0",
          description: "Universal package manager",
          license: "MPL-2.0",
          authors: ["Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>"],
          keywords: ["package", "manager"],
          forth: :hyperpolymath,
          repo_url: "https://github.com/hyperpolymath/odds-and-sods-package-manager",
          raw_toml: %{}
        }, expiry},
        {"affinescript-vite", %{
          type: :package,
          pkg_name: "affinescript-vite",
          repo_name: "affinescript-vite",
          default_branch: "main",
          version: "0.1.0",
          description: "Vite plugin for AffineScript",
          license: "MPL-2.0",
          authors: ["Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>"],
          keywords: ["vite", "affinescript", "bundler"],
          forth: :affinescript,
          repo_url: "https://github.com/hyperpolymath/affinescript-vite",
          raw_toml: %{}
        }, expiry},
        {"ephapax-core", %{
          type: :package,
          pkg_name: "ephapax-core",
          repo_name: "ephapax",
          default_branch: "main",
          version: "0.3.0",
          description: "Linear type system for Elixir",
          license: "MPL-2.0",
          authors: ["Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>"],
          keywords: ["types", "linear", "ephapax"],
          forth: :ephapax,
          repo_url: "https://github.com/hyperpolymath/ephapax",
          raw_toml: %{}
        }, expiry}
      ]

      Enum.each(entries, fn {name, entry, exp} ->
        :ets.insert(:hfr_cache, {name, entry, exp})
      end)

      on_exit(fn ->
        if :ets.info(:hfr_cache) != :undefined do
          :ets.delete_all_objects(:hfr_cache)
        end
      end)

      :ok
    end

    test "returns all packages for empty query" do
      {:ok, results} = HyperpPolymathForge.search("", [])
      assert length(results) >= 3
    end

    test "filters by keyword in package name" do
      {:ok, results} = HyperpPolymathForge.search("opsm", [])
      names = Enum.map(results, & &1.package)
      assert "opsm" in names
    end

    test "filters by keyword in description" do
      {:ok, results} = HyperpPolymathForge.search("universal", [])
      names = Enum.map(results, & &1.package)
      assert "opsm" in names
    end

    test "filters by keyword in keywords list" do
      {:ok, results} = HyperpPolymathForge.search("bundler", [])
      names = Enum.map(results, & &1.package)
      assert "affinescript-vite" in names
    end

    test "returns empty list for unmatched query" do
      {:ok, results} = HyperpPolymathForge.search("zzz-definitely-no-match-xyz", [])
      assert results == []
    end

    test "forth: option restricts to matching ecosystem" do
      {:ok, results} = HyperpPolymathForge.search("", forth: :affinescript)
      names = Enum.map(results, & &1.package)
      assert "affinescript-vite" in names
      refute "opsm" in names
      refute "ephapax-core" in names
    end

    test "forth: :ephapax finds only ephapax packages" do
      {:ok, results} = HyperpPolymathForge.search("", forth: :ephapax)
      names = Enum.map(results, & &1.package)
      assert "ephapax-core" in names
      refute "opsm" in names
    end

    test "limit: option caps result count" do
      {:ok, results} = HyperpPolymathForge.search("", limit: 1)
      assert length(results) == 1
    end

    test "each result has required ResolvedPackage fields" do
      {:ok, results} = HyperpPolymathForge.search("", [])
      for pkg <- results do
        assert is_binary(pkg.package)
        assert is_binary(pkg.version)
        assert is_atom(pkg.forth)
        assert is_binary(pkg.tarball_url)
        assert is_map(pkg.manifest)
      end
    end
  end

  describe "exists?/1 — ETS-seeded (no network)" do
    setup do
      HyperpPolymathForge.ensure_cache()
      now = System.monotonic_time(:millisecond)
      expiry = now + 60_000

      :ets.insert(:hfr_cache, {"seed-pkg", %{
        type: :package, pkg_name: "seed-pkg", repo_name: "seed-repo",
        default_branch: "main", version: "1.0.0", description: "seeded",
        license: "MPL-2.0", authors: [], keywords: [],
        forth: :hyperpolymath, repo_url: "https://github.com/hyperpolymath/seed-repo",
        raw_toml: %{}
      }, expiry})

      on_exit(fn ->
        if :ets.info(:hfr_cache) != :undefined do
          :ets.delete_all_objects(:hfr_cache)
        end
      end)

      :ok
    end

    test "returns true for seeded package" do
      assert HyperpPolymathForge.exists?("seed-pkg") == true
    end

    test "returns false for absent package" do
      assert HyperpPolymathForge.exists?("xyz-not-in-cache-abc-999") == false
    end
  end

  describe "fetch_package/2 — ETS-seeded (no network)" do
    setup do
      HyperpPolymathForge.ensure_cache()
      now = System.monotonic_time(:millisecond)
      expiry = now + 60_000

      :ets.insert(:hfr_cache, {"my-seeded-pkg", %{
        type: :package, pkg_name: "my-seeded-pkg", repo_name: "my-seeded-repo",
        default_branch: "main", version: "1.2.3", description: "a test package",
        license: "MPL-2.0",
        authors: ["Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>"],
        keywords: ["test"], forth: :hyperpolymath,
        repo_url: "https://github.com/hyperpolymath/my-seeded-repo",
        raw_toml: %{"dependencies" => %{}, "dev-dependencies" => %{}}
      }, expiry})

      on_exit(fn ->
        if :ets.info(:hfr_cache) != :undefined do
          :ets.delete_all_objects(:hfr_cache)
        end
      end)

      :ok
    end

    test "returns {:ok, pkg} for a seeded package" do
      assert {:ok, pkg} = HyperpPolymathForge.fetch_package("my-seeded-pkg", "latest")
      assert pkg.package == "my-seeded-pkg"
      assert pkg.forth == :hyperpolymath
      assert String.contains?(pkg.tarball_url, "my-seeded-repo")
    end

    test "returns {:error, :not_found} for absent package (no network fallback)" do
      # Cache is non-empty (seed-pkg is there), so refresh_index won't fire
      assert {:error, :not_found} = HyperpPolymathForge.fetch_package("xyz-not-seeded-abc-999", "latest")
    end

    test "resolved manifest has correct fields" do
      {:ok, pkg} = HyperpPolymathForge.fetch_package("my-seeded-pkg", "latest")
      assert pkg.manifest.name == "my-seeded-pkg"
      assert pkg.manifest.version == "1.2.3"
      assert pkg.manifest.description == "a test package"
      assert pkg.manifest.license == "MPL-2.0"
    end
  end
end
