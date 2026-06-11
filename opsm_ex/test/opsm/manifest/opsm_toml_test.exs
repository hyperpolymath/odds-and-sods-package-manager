# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Manifest.OpsmTomlTest do
  use ExUnit.Case, async: true

  alias Opsm.Manifest.OpsmToml
  alias Opsm.Types.ManifestFormat

  @sample_toml """
  [package]
  name = "my-tool"
  version = "1.0.0"
  license = "MPL-2.0"
  description = "A useful tool"
  authors = ["Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>"]
  keywords = ["tool", "utility"]

  [dependencies]
  req = ">= 0.5.0"
  jason = "~> 1.4"

  [dev-dependencies]
  stream_data = "~> 0.6"

  [build]
  system = "mix"
  command = "mix release"

  [run]
  binary = "bin/my-tool"
  """

  describe "parse/1" do
    test "parses valid opsm.toml" do
      assert {:ok, manifest} = OpsmToml.parse(@sample_toml)
      assert manifest.name == "my-tool"
      assert manifest.version == "1.0.0"
      assert manifest.license == "MPL-2.0"
      assert manifest.description == "A useful tool"
      assert "Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>" in manifest.authors
      assert "tool" in manifest.keywords
    end

    test "parses dependencies" do
      assert {:ok, manifest} = OpsmToml.parse(@sample_toml)
      assert manifest.dependencies["req"] == ">= 0.5.0"
      assert manifest.dependencies["jason"] == "~> 1.4"
    end

    test "parses dev-dependencies" do
      assert {:ok, manifest} = OpsmToml.parse(@sample_toml)
      assert manifest.dev_dependencies["stream_data"] == "~> 0.6"
    end

    test "returns error for invalid TOML" do
      assert {:error, msg} = OpsmToml.parse("not [valid toml {{")
      assert msg =~ "Failed to parse"
    end

    test "returns error for non-string input" do
      assert {:error, _} = OpsmToml.parse(123)
    end

    test "handles minimal manifest" do
      minimal = """
      [package]
      name = "minimal"
      version = "0.1.0"
      """

      assert {:ok, manifest} = OpsmToml.parse(minimal)
      assert manifest.name == "minimal"
      assert manifest.dependencies == %{}
    end
  end

  describe "build_config/1" do
    test "extracts build configuration" do
      {:ok, manifest} = OpsmToml.parse(@sample_toml)
      config = OpsmToml.build_config(manifest)
      assert config.system == :mix
      assert config.command == "mix release"
    end

    test "returns nil when no build section" do
      {:ok, manifest} = OpsmToml.parse("[package]\nname = \"test\"\nversion = \"0.0.1\"")
      assert is_nil(OpsmToml.build_config(manifest))
    end
  end

  describe "run_config/1" do
    test "extracts run configuration" do
      {:ok, manifest} = OpsmToml.parse(@sample_toml)
      config = OpsmToml.run_config(manifest)
      assert config.binary == "bin/my-tool"
    end
  end

  describe "encode/1 roundtrip" do
    test "encode then parse produces equivalent manifest" do
      original = %ManifestFormat{
        name: "roundtrip-test",
        version: "2.0.0",
        description: "Testing roundtrip",
        license: "MPL-2.0",
        authors: ["Test Author"],
        keywords: ["test"],
        dependencies: %{"dep_a" => "1.0.0"},
        dev_dependencies: %{"test_dep" => "0.1.0"},
        source_forth: :hex
      }

      encoded = OpsmToml.encode(original)
      assert {:ok, decoded} = OpsmToml.parse(encoded)

      assert decoded.name == original.name
      assert decoded.version == original.version
      assert decoded.license == original.license
      assert decoded.dependencies["dep_a"] == "1.0.0"
    end
  end
end
