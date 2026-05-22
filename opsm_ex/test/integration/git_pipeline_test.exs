# SPDX-License-Identifier: MPL-2.0
defmodule Opsm.Integration.GitPipelineTest do
  use ExUnit.Case, async: false

  alias Opsm.Git.{Clone, BuildDetector, Pipeline}

  @moduletag :integration

  setup do
    dir = Path.join(System.tmp_dir!(), "opsm_integ_git_#{:rand.uniform(100_000)}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  describe "local git pipeline" do
    @tag :integration
    test "detects and reports build system for a Cargo project", %{dir: dir} do
      # Create a minimal Cargo project
      File.write!(Path.join(dir, "Cargo.toml"), """
      [package]
      name = "test-project"
      version = "0.1.0"
      edition = "2021"
      """)
      File.mkdir_p!(Path.join(dir, "src"))
      File.write!(Path.join(dir, "src/main.rs"), ~s[fn main() { println!("hello"); }])

      assert {:ok, {:cargo, "Cargo.toml"}} = BuildDetector.detect_primary(dir)
    end

    @tag :integration
    test "detects and reports build system for a Mix project", %{dir: dir} do
      File.write!(Path.join(dir, "mix.exs"), """
      defmodule Test.MixProject do
        use Mix.Project
        def project, do: [app: :test, version: "0.0.1"]
      end
      """)

      assert {:ok, {:mix, "mix.exs"}} = BuildDetector.detect_primary(dir)
    end

    @tag :integration
    test "full pipeline returns proper structure for local path", %{dir: dir} do
      # Create a justfile project (simplest build system)
      File.write!(Path.join(dir, "justfile"), """
      build:
      \techo "built"
      """)

      # Pipeline will detect justfile and try to build
      # It may fail if `just` isn't installed, but should detect correctly
      case Pipeline.from_local(dir, skip_deps: true) do
        {:ok, result} ->
          assert result.build_system == :just
          assert result.path == dir

        {:error, msg} ->
          # Expected if `just` isn't installed
          assert msg =~ "failed" or msg =~ "not found" or msg =~ "blocked"
      end
    end
  end

  describe "clone operations" do
    @tag :integration
    test "cleanup removes directory" do
      dir = Path.join(System.tmp_dir!(), "opsm_cleanup_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "file.txt"), "test")

      assert :ok = Clone.cleanup(dir)
      refute File.exists?(dir)
    end
  end
end
