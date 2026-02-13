# SPDX-License-Identifier: PMPL-1.0
defmodule Opsm.Federation.DepMapperTest do
  use ExUnit.Case, async: true

  alias Opsm.Federation.DepMapper

  describe "find_equivalent/3" do
    test "maps numpy from pypi to deb" do
      assert {:ok, "python3-numpy"} = DepMapper.find_equivalent("numpy", :pypi, :deb)
    end

    test "maps numpy from pypi to rpm" do
      assert {:ok, "python3-numpy"} = DepMapper.find_equivalent("numpy", :pypi, :rpm)
    end

    test "maps express from npm to deb" do
      assert {:ok, "node-express"} = DepMapper.find_equivalent("express", :npm, :deb)
    end

    test "maps ripgrep from cargo to homebrew" do
      assert {:ok, "ripgrep"} = DepMapper.find_equivalent("ripgrep", :cargo, :homebrew)
    end

    test "maps rails from gem to deb" do
      assert {:ok, "ruby-rails"} = DepMapper.find_equivalent("rails", :gem, :deb)
    end

    test "maps rails from gem to rpm" do
      assert {:ok, "rubygem-rails"} = DepMapper.find_equivalent("rails", :gem, :rpm)
    end

    test "uses heuristic for unknown pypi package to deb" do
      assert {:ok, "python3-obscure-pkg"} = DepMapper.find_equivalent("obscure-pkg", :pypi, :deb)
    end

    test "uses heuristic for unknown npm package to deb" do
      assert {:ok, "node-my-tool"} = DepMapper.find_equivalent("my-tool", :npm, :deb)
    end

    test "uses heuristic for unknown gem to rpm" do
      assert {:ok, "rubygem-my-gem"} = DepMapper.find_equivalent("my-gem", :gem, :rpm)
    end

    test "returns error when no mapping exists" do
      assert {:error, :no_mapping} = DepMapper.find_equivalent("something", :cargo, :go)
    end
  end

  describe "list_mappings/2" do
    test "returns all mappings for numpy" do
      mappings = DepMapper.list_mappings("numpy", :pypi)
      assert Map.has_key?(mappings, :deb)
      assert Map.has_key?(mappings, :rpm)
    end

    test "returns empty map for unknown package" do
      assert %{} = DepMapper.list_mappings("totally-unknown-pkg-xyz", :npm)
    end
  end

  describe "suggest_candidates/3" do
    test "suggests multiple candidates for pypi to deb" do
      candidates = DepMapper.suggest_candidates("flask", :pypi, :deb)
      assert "python3-flask" in candidates
      assert "flask" in candidates
    end

    test "always includes original name as fallback" do
      candidates = DepMapper.suggest_candidates("unknown", :cargo, :deb)
      assert "unknown" in candidates
    end
  end
end
