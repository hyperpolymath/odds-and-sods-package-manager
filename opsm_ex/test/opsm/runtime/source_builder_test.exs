# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Runtime.SourceBuilderTest do
  use ExUnit.Case, async: true

  alias Opsm.Runtime.SourceBuilder

  # ---------------------------------------------------------------------------
  # check_system_dependencies/1
  # ---------------------------------------------------------------------------

  describe "check_system_dependencies/1" do
    test "returns :ok when system_dependencies is empty" do
      plugin = %{"system_dependencies" => []}
      assert :ok = SourceBuilder.check_system_dependencies(plugin)
    end

    test "returns :ok when system_dependencies is absent" do
      plugin = %{}
      assert :ok = SourceBuilder.check_system_dependencies(plugin)
    end

    test "returns missing dependencies for unavailable tools" do
      plugin = %{
        "system_dependencies" => [
          %{"name" => "definitely-nonexistent-tool-xyz-999", "check_command" => "definitely-nonexistent-tool-xyz-999 --version"}
        ]
      }
      result = SourceBuilder.check_system_dependencies(plugin)
      assert {:error, {:missing_system_dependencies, missing}} = result
      assert "definitely-nonexistent-tool-xyz-999" in missing
    end

    test "passes for tools that are actually available" do
      plugin = %{
        "system_dependencies" => [
          %{"name" => "bash", "check_command" => "bash --version"}
        ]
      }
      # bash is available on any system running these tests
      assert :ok = SourceBuilder.check_system_dependencies(plugin)
    end
  end

  # ---------------------------------------------------------------------------
  # install/2 — strategy dispatch (dry smoke, no actual builds)
  # ---------------------------------------------------------------------------

  describe "install/2 — delegate strategy" do
    test "returns error when delegate manager is not found" do
      plugin = %{
        "name" => "haskell",
        "install" => %{
          "strategy" => "DelegateToManager",
          "delegate_to" => "ghcup-definitely-not-installed-xyz",
          "delegate_install_command" => "ghcup-definitely-not-installed-xyz install ghc {{version}} --set"
        },
        "system_dependencies" => []
      }
      result = SourceBuilder.install(plugin, "9.6.4")
      # Should fail because the delegate tool doesn't exist
      assert match?({:error, _}, result)
    end
  end

  describe "install/2 — build_from_source strategy" do
    test "returns error when build steps reference unavailable tools" do
      plugin = %{
        "name" => "test-tool",
        "install" => %{
          "strategy" => "BuildFromSource",
          "build_steps" => [
            "definitely-nonexistent-configure-xyz --prefix={{install_dir}}",
            "make -j$(nproc)",
            "make install"
          ]
        },
        "system_dependencies" => []
      }
      result = SourceBuilder.install(plugin, "1.0.0")
      assert match?({:error, _}, result)
    end
  end
end
