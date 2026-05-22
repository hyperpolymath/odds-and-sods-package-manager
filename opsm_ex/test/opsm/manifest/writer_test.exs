# SPDX-License-Identifier: MPL-2.0
defmodule Opsm.Manifest.WriterTest do
  use ExUnit.Case, async: true

  alias Opsm.Manifest.Writer
  alias Opsm.Types.ManifestFormat

  @sample_manifest %ManifestFormat{
    name: "my-tool",
    version: "1.2.3",
    description: "A useful tool",
    license: "MPL-2.0",
    homepage: "https://example.com",
    repository: "https://github.com/hyperpolymath/my-tool",
    authors: ["Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>"],
    keywords: ["tool", "utility"],
    dependencies: %{"req" => "0.5.0", "jason" => "1.4.0"},
    dev_dependencies: %{"stream_data" => "0.6.0"},
    source_forth: :hex
  }

  describe "to_package_json/1" do
    test "generates valid JSON" do
      result = Writer.to_package_json(@sample_manifest)
      assert {:ok, parsed} = Jason.decode(result)
      assert parsed["name"] == "my-tool"
      assert parsed["version"] == "1.2.3"
      assert parsed["description"] == "A useful tool"
      assert parsed["license"] == "MPL-2.0"
      assert is_map(parsed["dependencies"])
      assert is_map(parsed["devDependencies"])
    end

    test "includes author" do
      result = Writer.to_package_json(@sample_manifest)
      {:ok, parsed} = Jason.decode(result)
      assert parsed["author"] =~ "Jonathan"
    end

    test "adds ^ prefix to dependency versions" do
      result = Writer.to_package_json(@sample_manifest)
      {:ok, parsed} = Jason.decode(result)
      assert parsed["dependencies"]["req"] =~ "^"
    end
  end

  describe "to_cargo_toml/1" do
    test "generates valid TOML structure" do
      result = Writer.to_cargo_toml(@sample_manifest)
      assert result =~ "[package]"
      assert result =~ ~s(name = "my-tool")
      assert result =~ ~s(version = "1.2.3")
      assert result =~ ~s(edition = "2021")
      assert result =~ "[dependencies]"
    end

    test "includes authors and keywords" do
      result = Writer.to_cargo_toml(@sample_manifest)
      assert result =~ "authors"
      assert result =~ "keywords"
    end
  end

  describe "to_mix_exs/1" do
    test "generates valid Elixir module" do
      result = Writer.to_mix_exs(@sample_manifest)
      assert result =~ "defmodule MyTool.MixProject"
      assert result =~ "use Mix.Project"
      assert result =~ ~s(app: :my_tool)
      assert result =~ ~s(version: "1.2.3")
    end

    test "includes SPDX header" do
      result = Writer.to_mix_exs(@sample_manifest)
      assert result =~ "SPDX-License-Identifier"
    end
  end

  describe "to_pyproject_toml/1" do
    test "generates valid pyproject structure" do
      result = Writer.to_pyproject_toml(@sample_manifest)
      assert result =~ "[build-system]"
      assert result =~ "[project]"
      assert result =~ ~s(name = "my-tool")
      assert result =~ ~s(version = "1.2.3")
    end

    test "includes dependencies" do
      result = Writer.to_pyproject_toml(@sample_manifest)
      assert result =~ "dependencies"
    end
  end

  describe "to_pubspec_yaml/1" do
    test "generates valid pubspec structure" do
      result = Writer.to_pubspec_yaml(@sample_manifest)
      assert result =~ "name: my-tool"
      assert result =~ "version: 1.2.3"
      assert result =~ "environment:"
      assert result =~ "sdk:"
    end
  end

  describe "to_go_mod/1" do
    test "generates valid go.mod" do
      result = Writer.to_go_mod(@sample_manifest)
      assert result =~ "module github.com/hyperpolymath/my-tool"
      assert result =~ "go 1.21"
    end

    test "includes require block when deps exist" do
      result = Writer.to_go_mod(@sample_manifest)
      assert result =~ "require ("
    end
  end

  describe "to_opsm_toml/1" do
    test "generates valid opsm.toml" do
      result = Writer.to_opsm_toml(@sample_manifest)
      assert result =~ "[package]"
      assert result =~ ~s(name = "my-tool")
      assert result =~ ~s(version = "1.2.3")
      assert result =~ ~s(license = "MPL-2.0")
      assert result =~ "[dependencies]"
    end

    test "includes source_forth" do
      result = Writer.to_opsm_toml(@sample_manifest)
      assert result =~ ~s(source_forth = "hex")
    end
  end

  describe "convert/2" do
    test "supports all documented targets" do
      targets = [:package_json, :cargo_toml, :mix_exs, :pyproject_toml, :pubspec_yaml, :go_mod, :opsm_toml]

      for target <- targets do
        assert {:ok, result} = Writer.convert(@sample_manifest, target)
        assert is_binary(result)
        assert byte_size(result) > 0
      end
    end

    test "returns error for unknown target" do
      assert {:error, _} = Writer.convert(@sample_manifest, :unknown_format)
    end
  end
end
