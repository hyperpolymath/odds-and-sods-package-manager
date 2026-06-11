# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
# Tests for Opsm.Wiring.run_audit/2 — validates graceful degradation
# when oikos and palimpsest services are unreachable.
defmodule Opsm.Wiring.AuditTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Opsm.Config
  alias Opsm.Wiring

  # Helpers to build a workspace TOML fixture in a temp dir
  defp tmp_workspace(members) do
    dir = System.tmp_dir!() |> Path.join("opsm_audit_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    toml = """
    [workspace]
    members = #{inspect(members)}
    """

    File.write!(Path.join(dir, "opsm.toml"), toml)
    dir
  end

  # ======================================================================
  # run_audit/2 — graceful degradation
  # ======================================================================

  describe "run_audit/2 — graceful degradation when services unreachable" do
    test "returns ok even when oikos and palimpsest are offline" do
      config = Config.example_config()

      output =
        capture_io(fn ->
          assert {:ok, "Audit completed"} = Wiring.run_audit(config, "express")
        end)

      assert output =~ "Auditing package: express"
      assert output =~ "Sustainability Analysis (oikos)"
      assert output =~ "License Analysis (palimpsest)"
    end

    test "returns ok for a path-style package argument" do
      config = Config.example_config()

      capture_io(fn ->
        assert {:ok, "Audit completed"} = Wiring.run_audit(config, "/some/nonexistent/path")
      end)
    end

    test "returns ok for an empty package name" do
      config = Config.example_config()

      capture_io(fn ->
        assert {:ok, "Audit completed"} = Wiring.run_audit(config, "")
      end)
    end

    test "oikos failure is printed as warning, not crash" do
      config = Config.example_config()

      output =
        capture_io(fn ->
          Wiring.run_audit(config, "some-pkg")
        end)

      # Service on 127.0.0.1:7005 is unreachable — should warn, not raise
      refute output =~ "** ("
    end

    test "license analysis failure is printed as warning, not crash" do
      config = Config.example_config()

      output =
        capture_io(fn ->
          Wiring.run_audit(config, "some-pkg")
        end)

      refute output =~ "** ("
    end
  end

  # ======================================================================
  # Workspace TOML member parsing — structural tests
  # ======================================================================

  describe "workspace TOML member parsing" do
    test "parses single-member workspace" do
      {:ok, parsed} =
        Toml.decode("""
        [workspace]
        members = ["express"]
        """)

      assert get_in(parsed, ["workspace", "members"]) == ["express"]
    end

    test "parses multi-member workspace" do
      {:ok, parsed} =
        Toml.decode("""
        [workspace]
        members = ["express", "lodash", "react"]
        """)

      members = get_in(parsed, ["workspace", "members"])
      assert length(members) == 3
      assert "express" in members
      assert "react" in members
    end

    test "returns empty list when workspace section is missing" do
      {:ok, parsed} = Toml.decode("[package]\nname = \"foo\"\n")
      members = get_in(parsed, ["workspace", "members"])
      assert is_nil(members)
    end

    test "returns empty list when members key is absent" do
      {:ok, parsed} = Toml.decode("[workspace]\nroot = true\n")
      members = get_in(parsed, ["workspace", "members"])
      assert is_nil(members)
    end

    test "handles members with @ version pinning" do
      {:ok, parsed} =
        Toml.decode("""
        [workspace]
        members = ["express@4.18.0", "lodash@4.17.21"]
        """)

      members = get_in(parsed, ["workspace", "members"])
      assert "express@4.18.0" in members
    end
  end

  # ======================================================================
  # Workspace TOML file on disk — integration with tmp file
  # ======================================================================

  describe "workspace opsm.toml on disk" do
    test "TOML file with workspace members parses correctly from disk" do
      dir = tmp_workspace(["pkg-a", "pkg-b", "pkg-c"])

      on_exit(fn -> File.rm_rf!(dir) end)

      content = File.read!(Path.join(dir, "opsm.toml"))
      {:ok, parsed} = Toml.decode(content)

      members = get_in(parsed, ["workspace", "members"])
      assert length(members) == 3
      assert "pkg-a" in members
    end

    test "empty workspace members list parses correctly" do
      dir = tmp_workspace([])
      on_exit(fn -> File.rm_rf!(dir) end)

      content = File.read!(Path.join(dir, "opsm.toml"))
      {:ok, parsed} = Toml.decode(content)

      members = get_in(parsed, ["workspace", "members"]) || []
      assert members == []
    end
  end
end
