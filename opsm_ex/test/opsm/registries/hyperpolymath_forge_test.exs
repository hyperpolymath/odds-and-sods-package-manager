# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
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
  # search/2 — always returns a list (even on network failure)
  # ---------------------------------------------------------------------------

  describe "search/2" do
    test "returns a list for any query" do
      result = HyperpPolymathForge.search("opsm", [])
      assert is_list(result)
    end

    test "returns a list for empty string query" do
      result = HyperpPolymathForge.search("", [])
      assert is_list(result)
    end
  end

  # ---------------------------------------------------------------------------
  # versions/1
  # ---------------------------------------------------------------------------

  describe "versions/1" do
    test "returns ok tuple with list for any package name" do
      assert {:ok, versions} = HyperpPolymathForge.versions("opsm")
      assert is_list(versions)
    end

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
      # First call may hit the network (skippable in CI); subsequent calls use ETS
      HyperpPolymathForge.ensure_cache()
      HyperpPolymathForge.ensure_cache()
      HyperpPolymathForge.ensure_cache()
      # If we get here, idempotency is satisfied
      assert true
    end
  end
end
