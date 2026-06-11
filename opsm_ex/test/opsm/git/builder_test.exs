# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Git.BuilderTest do
  use ExUnit.Case, async: true

  alias Opsm.Git.Builder

  describe "build/3" do
    test "returns error when command not found" do
      dir = System.tmp_dir!()

      # just is likely not installed in test env, or the build will fail
      # Either way we get an error (not a crash)
      result = Builder.build(dir, :just)
      assert {:error, _} = result
    end

    test "accepts custom recipe" do
      dir = System.tmp_dir!()
      # echo is not in the SafeExec allowlist, so this tests the safety boundary
      result = Builder.build(dir, :just, recipe: "echo hello")
      # Should be blocked by SafeExec
      assert {:error, msg} = result
      assert msg =~ "failed" or msg =~ "blocked"
    end
  end

  describe "install_deps/3" do
    test "returns ok for systems with no deps step" do
      dir = System.tmp_dir!()
      assert {:ok, msg} = Builder.install_deps(dir, :just)
      assert msg =~ "no dependency step"
    end
  end
end
