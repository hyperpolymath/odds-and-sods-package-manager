# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Git.BuildDetectorTest do
  use ExUnit.Case, async: true

  alias Opsm.Git.BuildDetector

  setup do
    dir = Path.join(System.tmp_dir!(), "opsm_detect_test_#{:rand.uniform(100_000)}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  describe "detect/1" do
    test "detects justfile", %{dir: dir} do
      File.write!(Path.join(dir, "justfile"), "build:\n\techo hi")
      assert {:ok, [{:just, "justfile"} | _]} = BuildDetector.detect(dir)
    end

    test "detects Cargo.toml", %{dir: dir} do
      File.write!(Path.join(dir, "Cargo.toml"), "[package]\nname = \"test\"")
      assert {:ok, detected} = BuildDetector.detect(dir)
      assert Enum.any?(detected, fn {sys, _} -> sys == :cargo end)
    end

    test "detects mix.exs", %{dir: dir} do
      File.write!(Path.join(dir, "mix.exs"), "defmodule Test.MixProject do\nend")
      assert {:ok, detected} = BuildDetector.detect(dir)
      assert Enum.any?(detected, fn {sys, _} -> sys == :mix end)
    end

    test "detects package.json", %{dir: dir} do
      File.write!(Path.join(dir, "package.json"), "{}")
      assert {:ok, detected} = BuildDetector.detect(dir)
      assert Enum.any?(detected, fn {sys, _} -> sys == :npm end)
    end

    test "detects go.mod", %{dir: dir} do
      File.write!(Path.join(dir, "go.mod"), "module example.com/test\ngo 1.21")
      assert {:ok, detected} = BuildDetector.detect(dir)
      assert Enum.any?(detected, fn {sys, _} -> sys == :go end)
    end

    test "detects pyproject.toml", %{dir: dir} do
      File.write!(Path.join(dir, "pyproject.toml"), "[project]\nname = \"test\"")
      assert {:ok, detected} = BuildDetector.detect(dir)
      assert Enum.any?(detected, fn {sys, _} -> sys == :python end)
    end

    test "detects build.zig", %{dir: dir} do
      File.write!(Path.join(dir, "build.zig"), "const std = @import(\"std\");")
      assert {:ok, detected} = BuildDetector.detect(dir)
      assert Enum.any?(detected, fn {sys, _} -> sys == :zig end)
    end

    test "detects Makefile", %{dir: dir} do
      File.write!(Path.join(dir, "Makefile"), "all:\n\techo hi")
      assert {:ok, detected} = BuildDetector.detect(dir)
      assert Enum.any?(detected, fn {sys, _} -> sys == :make end)
    end

    test "detects multiple build systems with correct priority", %{dir: dir} do
      File.write!(Path.join(dir, "justfile"), "build:\n\techo hi")
      File.write!(Path.join(dir, "Makefile"), "all:\n\techo hi")
      File.write!(Path.join(dir, "Cargo.toml"), "[package]")

      assert {:ok, [{:just, "justfile"} | rest]} = BuildDetector.detect(dir)
      assert length(rest) >= 2
    end

    test "returns error for empty directory", %{dir: dir} do
      assert {:error, msg} = BuildDetector.detect(dir)
      assert msg =~ "No recognized build system"
    end

    test "returns error for non-existent directory" do
      assert {:error, msg} = BuildDetector.detect("/tmp/nonexistent_dir_#{:rand.uniform(100_000)}")
      assert msg =~ "Not a directory"
    end
  end

  describe "detect_primary/1" do
    test "returns highest priority build system", %{dir: dir} do
      File.write!(Path.join(dir, "justfile"), "build:\n\techo hi")
      File.write!(Path.join(dir, "Cargo.toml"), "[package]")

      assert {:ok, {:just, "justfile"}} = BuildDetector.detect_primary(dir)
    end
  end

  describe "has_build_system?/2" do
    test "returns true when present", %{dir: dir} do
      File.write!(Path.join(dir, "Cargo.toml"), "[package]")
      assert BuildDetector.has_build_system?(dir, :cargo)
    end

    test "returns false when absent", %{dir: dir} do
      refute BuildDetector.has_build_system?(dir, :cargo)
    end
  end
end
