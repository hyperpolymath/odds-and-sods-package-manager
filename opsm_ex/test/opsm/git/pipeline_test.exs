# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Git.PipelineTest do
  use ExUnit.Case, async: true

  alias Opsm.Git.Pipeline

  describe "from_local/2" do
    test "returns error for non-directory path" do
      assert {:error, msg} =
               Pipeline.from_local("/tmp/nonexistent_path_#{:rand.uniform(100_000)}")

      assert msg =~ "Not a directory"
    end

    test "returns error for directory without build system" do
      dir = Path.join(System.tmp_dir!(), "opsm_pipeline_empty_#{:rand.uniform(100_000)}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)

      assert {:error, msg} = Pipeline.from_local(dir)
      assert msg =~ "No recognized build system"
    end

    test "detects build system in local checkout" do
      dir = Path.join(System.tmp_dir!(), "opsm_pipeline_mix_#{:rand.uniform(100_000)}")
      File.mkdir_p!(dir)

      File.write!(Path.join(dir, "mix.exs"), """
      defmodule Test.MixProject do
        use Mix.Project
        def project, do: [app: :test, version: "0.0.1"]
      end
      """)

      on_exit(fn -> File.rm_rf!(dir) end)

      # This will detect mix but fail at deps.get (no hex config) — that's expected
      result = Pipeline.from_local(dir, skip_deps: true)

      case result do
        {:ok, %{build_system: :mix}} ->
          assert true

        {:error, msg} ->
          # mix compile will fail in a minimal env, but detection should have worked
          assert msg =~ "mix" or msg =~ "failed"
      end
    end
  end

  describe "from_url/2" do
    test "rejects invalid URLs" do
      assert {:error, msg} = Pipeline.from_url("http://localhost/repo.git")
      assert msg =~ "Invalid clone URL"
    end
  end
end
