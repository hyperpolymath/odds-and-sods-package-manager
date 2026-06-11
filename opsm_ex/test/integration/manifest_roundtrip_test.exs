# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Integration.ManifestRoundtripTest do
  use ExUnit.Case, async: true

  alias Opsm.Manifest.{Writer, OpsmToml}
  alias Opsm.Federation
  alias Opsm.Types.ManifestFormat

  @moduletag :integration

  @base_manifest %ManifestFormat{
    name: "roundtrip-test",
    version: "3.1.4",
    description: "Testing manifest roundtrip conversion",
    license: "MPL-2.0",
    homepage: "https://example.com/roundtrip",
    repository: "https://github.com/hyperpolymath/roundtrip-test",
    authors: ["Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>"],
    keywords: ["test", "roundtrip"],
    dependencies: %{"dep_a" => "1.0.0", "dep_b" => "2.3.0"},
    dev_dependencies: %{"test_dep" => "0.5.0"},
    source_forth: :hex
  }

  describe "opsm.toml roundtrip" do
    @tag :integration
    test "encode → parse preserves key fields" do
      encoded = OpsmToml.encode(@base_manifest)
      assert {:ok, decoded} = OpsmToml.parse(encoded)

      assert decoded.name == @base_manifest.name
      assert decoded.version == @base_manifest.version
      assert decoded.license == @base_manifest.license
      assert decoded.description == @base_manifest.description
      assert decoded.dependencies["dep_a"] == "1.0.0"
      assert decoded.dependencies["dep_b"] == "2.3.0"
      assert decoded.dev_dependencies["test_dep"] == "0.5.0"
    end
  end

  describe "package.json roundtrip" do
    @tag :integration
    test "write → parse via Federation.convert_manifest preserves name and version" do
      dir = Path.join(System.tmp_dir!(), "opsm_rt_npm_#{:rand.uniform(100_000)}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)

      json_str = Writer.to_package_json(@base_manifest)
      path = Path.join(dir, "package.json")
      File.write!(path, json_str)

      assert {:ok, parsed} = Federation.convert_manifest(path)
      assert parsed.name == "roundtrip-test"
      assert parsed.version == "3.1.4"
    end
  end

  describe "Cargo.toml roundtrip" do
    @tag :integration
    test "write → parse via Federation.convert_manifest preserves name and version" do
      dir = Path.join(System.tmp_dir!(), "opsm_rt_cargo_#{:rand.uniform(100_000)}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)

      toml_str = Writer.to_cargo_toml(@base_manifest)
      path = Path.join(dir, "Cargo.toml")
      File.write!(path, toml_str)

      assert {:ok, parsed} = Federation.convert_manifest(path)
      assert parsed.name == "roundtrip-test"
      assert parsed.version == "3.1.4"
    end
  end

  describe "pyproject.toml roundtrip" do
    @tag :integration
    test "write → parse via Federation.convert_manifest preserves name and version" do
      dir = Path.join(System.tmp_dir!(), "opsm_rt_py_#{:rand.uniform(100_000)}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)

      toml_str = Writer.to_pyproject_toml(@base_manifest)
      path = Path.join(dir, "pyproject.toml")
      File.write!(path, toml_str)

      assert {:ok, parsed} = Federation.convert_manifest(path)
      assert parsed.name == "roundtrip-test"
      assert parsed.version == "3.1.4"
    end
  end

  describe "cross-format conversion" do
    @tag :integration
    test "all writer targets produce non-empty output" do
      targets = [:package_json, :cargo_toml, :mix_exs, :pyproject_toml, :pubspec_yaml, :go_mod, :opsm_toml]

      for target <- targets do
        assert {:ok, output} = Writer.convert(@base_manifest, target),
               "Failed for target: #{target}"
        assert byte_size(output) > 10,
               "Output too small for target: #{target}"
      end
    end
  end
end
