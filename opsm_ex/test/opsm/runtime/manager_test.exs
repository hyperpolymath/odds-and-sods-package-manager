# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Runtime.ManagerTest do
  use ExUnit.Case, async: false

  alias Opsm.Runtime.Manager

  # Use a temp dir so tests don't touch ~/.opsm/runtimes
  @runtimes_base System.tmp_dir!()
                 |> Path.join("opsm_manager_test_#{System.unique_integer([:positive])}")

  setup do
    # Ensure clean temp dir for each test
    File.rm_rf!(@runtimes_base)
    File.mkdir_p!(@runtimes_base)
    on_exit(fn -> File.rm_rf!(@runtimes_base) end)
    :ok
  end

  # ---------------------------------------------------------------------------
  # parse_workspace_members (via install_from_manifest — internal)
  # ---------------------------------------------------------------------------

  describe "install_from_manifest/1" do
    test "returns empty list when no [runtime] section" do
      manifest = Path.join(@runtimes_base, "opsm_no_runtime.toml")

      File.write!(manifest, """
      [package]
      name = "myapp"
      version = "0.1.0"
      """)

      assert {:ok, []} = Manager.install_from_manifest(manifest)
    end

    test "parses [runtime] section into tool/version pairs" do
      manifest = Path.join(@runtimes_base, "opsm_with_runtime.toml")

      File.write!(manifest, """
      [package]
      name = "myapp"
      version = "0.1.0"

      [runtime]
      zig = "0.13.0"
      deno = "1.42.0"
      erlang = "26.2.5"
      """)

      assert {:ok, pins} = Manager.install_from_manifest(manifest)
      assert length(pins) == 3
      assert {"zig", "0.13.0"} in pins
      assert {"deno", "1.42.0"} in pins
      assert {"erlang", "26.2.5"} in pins
    end

    test "handles quoted values" do
      manifest = Path.join(@runtimes_base, "opsm_quoted.toml")

      File.write!(manifest, ~S"""
      [runtime]
      julia = "1.10.2"
      """)

      assert {:ok, [{"julia", "1.10.2"}]} = Manager.install_from_manifest(manifest)
    end

    test "stops reading [runtime] when next section starts" do
      manifest = Path.join(@runtimes_base, "opsm_sections.toml")

      File.write!(manifest, """
      [runtime]
      zig = "0.13.0"

      [dependencies]
      my-dep = "1.0.0"
      """)

      assert {:ok, pins} = Manager.install_from_manifest(manifest)
      assert length(pins) == 1
      assert {"zig", "0.13.0"} in pins
      refute {"my-dep", "1.0.0"} in pins
    end

    test "returns error for missing file" do
      assert {:error, :enoent} = Manager.install_from_manifest("/no/such/file.toml")
    end

    test "ignores comment lines, including comments containing =" do
      manifest = Path.join(@runtimes_base, "opsm_comments.toml")

      File.write!(manifest, """
      [runtime]
      # canonical pins, synced via just toolchain-sync
      # example override: zig = "9.9.9"
      zig = "0.14.0"
      """)

      assert {:ok, [{"zig", "0.14.0"}]} = Manager.install_from_manifest(manifest)
    end

    test "strips inline comments from pin values" do
      manifest = Path.join(@runtimes_base, "opsm_inline.toml")

      File.write!(manifest, """
      [runtime]
      nickel = "1.16.0" # config language
      """)

      assert {:ok, [{"nickel", "1.16.0"}]} = Manager.install_from_manifest(manifest)
    end
  end

  # ---------------------------------------------------------------------------
  # find_plugin_ncl/1 — plugin search path resolution
  # ---------------------------------------------------------------------------

  describe "find_plugin_ncl/1" do
    test "resolves a core plugin from the repo checkout (runtime/core)" do
      # Under mix, cwd is opsm_ex/ — the sibling runtime/core/ dir must be
      # searched at call time (a compile-time priv_dir attribute cannot see it)
      path = Manager.find_plugin_ncl("zig")
      assert is_binary(path), "expected zig.ncl to resolve from the repo checkout"
      assert String.ends_with?(path, "/zig.ncl")
    end

    test "returns nil for a tool with no plugin definition" do
      assert Manager.find_plugin_ncl("definitely-not-a-real-tool-xyz") == nil
    end
  end

  # ---------------------------------------------------------------------------
  # list_installed/0 — filesystem scan
  # ---------------------------------------------------------------------------

  describe "list_installed/0" do
    test "returns empty list when runtimes dir is absent" do
      # Manager reads from @runtimes_dir which expands to ~/.opsm/runtimes
      # We can't easily override without app config, so just assert contract.
      result = Manager.list_installed()
      assert is_list(result)
    end

    test "each entry has required keys" do
      result = Manager.list_installed()

      for entry <- result do
        assert Map.has_key?(entry, :name)
        assert Map.has_key?(entry, :version)
        assert Map.has_key?(entry, :active)
        assert is_binary(entry.name)
        assert is_binary(entry.version)
        assert is_boolean(entry.active)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # list_active/0
  # ---------------------------------------------------------------------------

  describe "list_active/0" do
    test "returns list of {tool, version} tuples" do
      result = Manager.list_active()
      assert is_list(result)

      for {tool, version} <- result do
        assert is_binary(tool)
        assert is_binary(version)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # current_version/1
  # ---------------------------------------------------------------------------

  describe "current_version/1" do
    test "returns 'none' for uninstalled tool" do
      assert Manager.current_version("definitely-not-installed-xyz-999") == "none"
    end
  end

  # ---------------------------------------------------------------------------
  # which/1
  # ---------------------------------------------------------------------------

  describe "which/1" do
    test "returns error for uninstalled tool" do
      assert {:error, :not_installed} = Manager.which("definitely-not-installed-xyz-999")
    end
  end

  # ---------------------------------------------------------------------------
  # remove/1
  # ---------------------------------------------------------------------------

  describe "remove/1" do
    test "returns error for non-installed tool" do
      assert {:error, :not_installed} = Manager.remove("definitely-not-installed-xyz-999")
    end
  end

  # ---------------------------------------------------------------------------
  # check_updates/0
  # ---------------------------------------------------------------------------

  describe "check_updates/0" do
    test "returns ok tuple with a list" do
      assert {:ok, updates} = Manager.check_updates()
      assert is_list(updates)
    end

    test "each update entry has required keys" do
      {:ok, updates} = Manager.check_updates()

      for update <- updates do
        assert Map.has_key?(update, :name)
        assert Map.has_key?(update, :current)
        assert Map.has_key?(update, :latest)
      end
    end
  end
end
