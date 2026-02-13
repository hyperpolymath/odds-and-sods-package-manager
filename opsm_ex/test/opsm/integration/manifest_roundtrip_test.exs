# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk>
#
# Integration tests for OPSM's manifest conversion pipeline.
# Validates round-trip conversion of various manifest formats
# (mix.exs, package.json, Cargo.toml) through the Federation layer.

defmodule Opsm.Integration.ManifestRoundtripTest do
  use ExUnit.Case, async: true

  alias Opsm.Federation

  @moduletag :integration

  # ==========================================================================
  # mix.exs Manifest Conversion
  # ==========================================================================

  describe "manifest conversion: mix.exs" do
    test "convert_manifest handles mix.exs" do
      tmp = Path.join(System.tmp_dir!(), "test_mix_#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp)
      mix_path = Path.join(tmp, "mix.exs")

      File.write!(mix_path, """
      defmodule TestApp.MixProject do
        use Mix.Project

        def project do
          [
            app: :test_app,
            version: "1.2.3",
            elixir: "~> 1.14",
            deps: deps()
          ]
        end

        defp deps do
          [
            {:jason, "~> 1.4"},
            {:req, "~> 0.5"}
          ]
        end
      end
      """)

      result = Federation.convert_manifest(mix_path)
      assert {:ok, manifest} = result
      assert manifest.name == "test_app"
      assert manifest.version == "1.2.3"
      assert manifest.source_forth == :hex
      assert is_map(manifest.dependencies)
      assert manifest.dependencies["jason"] == "~> 1.4"
      assert manifest.dependencies["req"] == "~> 0.5"

      # Cleanup
      File.rm_rf!(tmp)
    end
  end

  # ==========================================================================
  # package.json Manifest Conversion
  # ==========================================================================

  describe "manifest conversion: package.json" do
    test "convert_manifest handles package.json" do
      tmp = Path.join(System.tmp_dir!(), "test_npm_#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp)
      pkg_path = Path.join(tmp, "package.json")

      File.write!(pkg_path, Jason.encode!(%{
        "name" => "test-pkg",
        "version" => "2.0.0",
        "description" => "A test package",
        "license" => "MIT",
        "dependencies" => %{"lodash" => "^4.17.0"}
      }))

      result = Federation.convert_manifest(pkg_path)
      assert {:ok, manifest} = result
      assert manifest.name == "test-pkg"
      assert manifest.version == "2.0.0"
      assert manifest.description == "A test package"
      assert manifest.license == "MIT"
      assert manifest.source_forth == :npm
      assert manifest.dependencies["lodash"] == "^4.17.0"

      File.rm_rf!(tmp)
    end

    test "convert_manifest handles package.json with devDependencies" do
      tmp = Path.join(System.tmp_dir!(), "test_npm_dev_#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp)
      pkg_path = Path.join(tmp, "package.json")

      File.write!(pkg_path, Jason.encode!(%{
        "name" => "dev-dep-pkg",
        "version" => "1.0.0",
        "dependencies" => %{"express" => "^4.18.0"},
        "devDependencies" => %{"jest" => "^29.0.0"}
      }))

      result = Federation.convert_manifest(pkg_path)
      assert {:ok, manifest} = result
      assert manifest.dependencies["express"] == "^4.18.0"
      assert manifest.dev_dependencies["jest"] == "^29.0.0"

      File.rm_rf!(tmp)
    end

    test "convert_manifest handles package.json with repository object" do
      tmp = Path.join(System.tmp_dir!(), "test_npm_repo_#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp)
      pkg_path = Path.join(tmp, "package.json")

      File.write!(pkg_path, Jason.encode!(%{
        "name" => "repo-pkg",
        "version" => "1.0.0",
        "repository" => %{
          "type" => "git",
          "url" => "https://github.com/example/repo-pkg.git"
        }
      }))

      result = Federation.convert_manifest(pkg_path)
      assert {:ok, manifest} = result
      assert manifest.repository == "https://github.com/example/repo-pkg.git"

      File.rm_rf!(tmp)
    end
  end

  # ==========================================================================
  # Unknown Format
  # ==========================================================================

  describe "manifest conversion: unknown format" do
    test "convert_manifest rejects unknown file formats" do
      tmp = Path.join(System.tmp_dir!(), "test_unknown_#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp)
      unknown_path = Path.join(tmp, "unknown.xyz")
      File.write!(unknown_path, "some content")

      result = Federation.convert_manifest(unknown_path)
      assert {:error, msg} = result
      assert msg =~ "Unknown manifest format"

      File.rm_rf!(tmp)
    end
  end

  # ==========================================================================
  # Forth Configuration
  # ==========================================================================

  describe "forth configuration" do
    test "list_forths returns all configured forths" do
      forths = Federation.list_forths()
      assert is_list(forths)
      assert length(forths) > 0

      names = Enum.map(forths, & &1.name)
      assert :npm in names
      assert :cargo in names
      assert :hex in names
    end

    test "get_forth retrieves forth by name" do
      npm = Federation.get_forth(:npm)
      assert npm != nil
      assert npm.name == :npm
      assert npm.base_url == "https://registry.npmjs.org"
    end

    test "enabled_forths excludes disabled forths" do
      enabled = Federation.enabled_forths()
      disabled_names = [:deb, :rpm, :winget, :choco, :scoop, :pacman, :homebrew, :nix, :guix]

      enabled_names = Enum.map(enabled, & &1.name)
      Enum.each(disabled_names, fn name ->
        refute name in enabled_names, "#{name} should be disabled but was in enabled list"
      end)
    end
  end

  # ==========================================================================
  # Toolchain Detection
  # ==========================================================================

  describe "toolchain detection" do
    test "check_toolchain returns result for known forths" do
      result = Federation.check_toolchain(:hex)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "check_toolchain returns no_toolchain_required for unknown forths" do
      result = Federation.check_toolchain(:unknown_forth)
      assert {:ok, :no_toolchain_required} = result
    end

    test "toolchain_status returns map of all toolchain statuses" do
      status = Federation.toolchain_status()
      assert is_map(status)
      assert Map.has_key?(status, :npm)
      assert Map.has_key?(status, :cargo)
      assert Map.has_key?(status, :hex)
    end
  end
end
