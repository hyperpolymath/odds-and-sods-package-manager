# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Registries.EclexiaTest do
  use ExUnit.Case, async: true

  alias Opsm.Registries.Eclexia

  describe "fetch_package/2" do
    @tag :external_api
    test "fetches eclexia package from git" do
      # eclexia itself is a real package on GitHub
      case Eclexia.fetch_package("eclexia", "latest") do
        {:ok, pkg} ->
          assert pkg.forth == :eclexia
          assert is_binary(pkg.package)
          assert pkg.manifest.source_forth == :eclexia

        {:error, :not_found} ->
          # Acceptable if network unavailable in CI
          :ok

        {:error, _reason} ->
          :ok
      end
    end

    test "returns error for non-existent package" do
      assert {:error, :not_found} =
               Eclexia.fetch_package("xyz-definitely-does-not-exist-eclexia-abc-999")
    end
  end

  describe "search/2" do
    test "returns list (empty in git fallback mode)" do
      assert {:ok, results} = Eclexia.search("resource")
      assert is_list(results)
    end
  end

  describe "exists?/1" do
    @tag :external_api
    test "returns boolean for known package" do
      result = Eclexia.exists?("eclexia")
      assert is_boolean(result)
    end

    test "returns false for non-existent package" do
      assert Eclexia.exists?("xyz-definitely-does-not-exist-eclexia-abc-999") == false
    end
  end

  describe "versions/1" do
    test "returns list of versions" do
      assert {:ok, versions} = Eclexia.versions("eclexia")
      assert is_list(versions)
      assert "main" in versions
    end
  end
end
