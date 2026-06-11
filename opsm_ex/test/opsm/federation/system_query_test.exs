# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Federation.SystemQueryTest do
  use ExUnit.Case, async: true

  alias Opsm.Federation.SystemQuery

  describe "query_installed/1" do
    test "returns error for unknown port" do
      assert {:error, msg} = SystemQuery.query_installed(:nonexistent_pm)
      assert msg =~ "No query command"
    end

    # These tests depend on what's installed on the test system
    # They're designed to not fail on CI where these tools aren't available
    test "queries rpm if available" do
      if System.find_executable("rpm") do
        assert {:ok, packages} = SystemQuery.query_installed(:rpm)
        assert is_list(packages)

        if packages != [] do
          assert %{name: _, version: _} = hd(packages)
        end
      end
    end

    test "queries dpkg if available" do
      if System.find_executable("dpkg-query") do
        assert {:ok, packages} = SystemQuery.query_installed(:deb)
        assert is_list(packages)
      end
    end

    test "queries flatpak if available" do
      if System.find_executable("flatpak") do
        assert {:ok, packages} = SystemQuery.query_installed(:flatpak)
        assert is_list(packages)
      end
    end

    test "queries snap if available" do
      if System.find_executable("snap") do
        assert {:ok, packages} = SystemQuery.query_installed(:snap)
        assert is_list(packages)
      end
    end
  end

  describe "query_version/2" do
    test "returns :not_installed for unknown package" do
      if System.find_executable("rpm") do
        assert {:error, :not_installed} = SystemQuery.query_version(:rpm, "nonexistent-package-xyz-#{:rand.uniform(100_000)}")
      end
    end
  end

  describe "detect_system_pm/0" do
    test "returns a known system PM or :none_found" do
      case SystemQuery.detect_system_pm() do
        {:ok, pm} -> assert pm in [:rpm, :deb, :pacman, :homebrew, :nix, :flatpak, :snap]
        {:error, :none_found} -> assert true
      end
    end
  end
end
