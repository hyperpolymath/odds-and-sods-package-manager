# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule Opsm.VersionConstraintTest do
  use ExUnit.Case, async: true
  alias Opsm.VersionConstraint

  describe "parse/2 - semver" do
    test "parses exact version" do
      assert {:ok, constraint} = VersionConstraint.parse("1.2.3", :semver)
      assert constraint.constraint_type == :semver
      assert {:exact, _} = constraint.ast
    end

    test "parses wildcard *" do
      assert {:ok, constraint} = VersionConstraint.parse("*", :semver)
      assert constraint.ast == {:any}
    end

    test "parses caret range" do
      assert {:ok, constraint} = VersionConstraint.parse("^1.2.3", :semver)
      assert {:caret, _} = constraint.ast
    end

    test "parses tilde range" do
      assert {:ok, constraint} = VersionConstraint.parse("~1.2.3", :semver)
      assert {:tilde, _} = constraint.ast
    end

    test "parses comparison operators" do
      assert {:ok, _} = VersionConstraint.parse(">=1.0.0", :semver)
      assert {:ok, _} = VersionConstraint.parse(">1.0.0", :semver)
      assert {:ok, _} = VersionConstraint.parse("<=2.0.0", :semver)
      assert {:ok, _} = VersionConstraint.parse("<2.0.0", :semver)
    end

    test "parses wildcard versions" do
      assert {:ok, constraint} = VersionConstraint.parse("1.x", :semver)
      assert {:wildcard, 1, :any} = constraint.ast

      assert {:ok, constraint} = VersionConstraint.parse("1.2.x", :semver)
      assert {:wildcard, 1, 2} = constraint.ast
    end
  end

  describe "parse/2 - python" do
    test "parses compatible release" do
      assert {:ok, constraint} = VersionConstraint.parse("~=1.4.2", :python)
      assert {:tilde, _} = constraint.ast
    end

    test "parses comma-separated constraints" do
      assert {:ok, constraint} = VersionConstraint.parse(">=1.0,<2.0", :python)
      assert {:and, _} = constraint.ast
    end

    test "parses exact with ==" do
      assert {:ok, constraint} = VersionConstraint.parse("==1.2.3", :python)
      assert {:exact, _} = constraint.ast
    end
  end

  describe "satisfies?/2" do
    test "exact version matches" do
      {:ok, constraint} = VersionConstraint.parse("1.2.3", :semver)
      assert VersionConstraint.satisfies?("1.2.3", constraint)
      refute VersionConstraint.satisfies?("1.2.4", constraint)
    end

    test "wildcard * matches everything" do
      {:ok, constraint} = VersionConstraint.parse("*", :semver)
      assert VersionConstraint.satisfies?("1.2.3", constraint)
      assert VersionConstraint.satisfies?("99.99.99", constraint)
    end

    test "caret range ^1.2.3" do
      {:ok, constraint} = VersionConstraint.parse("^1.2.3", :semver)
      assert VersionConstraint.satisfies?("1.2.3", constraint)
      assert VersionConstraint.satisfies?("1.2.5", constraint)
      assert VersionConstraint.satisfies?("1.9.0", constraint)
      refute VersionConstraint.satisfies?("2.0.0", constraint)
      refute VersionConstraint.satisfies?("1.2.2", constraint)
    end

    test "caret range ^0.2.3 (minor-level changes)" do
      {:ok, constraint} = VersionConstraint.parse("^0.2.3", :semver)
      assert VersionConstraint.satisfies?("0.2.3", constraint)
      assert VersionConstraint.satisfies?("0.2.5", constraint)
      refute VersionConstraint.satisfies?("0.3.0", constraint)
      refute VersionConstraint.satisfies?("1.0.0", constraint)
    end

    test "tilde range ~1.2.3" do
      {:ok, constraint} = VersionConstraint.parse("~1.2.3", :semver)
      assert VersionConstraint.satisfies?("1.2.3", constraint)
      assert VersionConstraint.satisfies?("1.2.9", constraint)
      refute VersionConstraint.satisfies?("1.3.0", constraint)
      refute VersionConstraint.satisfies?("2.0.0", constraint)
    end

    test ">=1.0.0" do
      {:ok, constraint} = VersionConstraint.parse(">=1.0.0", :semver)
      assert VersionConstraint.satisfies?("1.0.0", constraint)
      assert VersionConstraint.satisfies?("1.0.1", constraint)
      assert VersionConstraint.satisfies?("2.0.0", constraint)
      refute VersionConstraint.satisfies?("0.9.9", constraint)
    end

    test "<2.0.0" do
      {:ok, constraint} = VersionConstraint.parse("<2.0.0", :semver)
      assert VersionConstraint.satisfies?("1.9.9", constraint)
      assert VersionConstraint.satisfies?("0.0.1", constraint)
      refute VersionConstraint.satisfies?("2.0.0", constraint)
      refute VersionConstraint.satisfies?("3.0.0", constraint)
    end

    test "wildcard 1.x" do
      {:ok, constraint} = VersionConstraint.parse("1.x", :semver)
      assert VersionConstraint.satisfies?("1.0.0", constraint)
      assert VersionConstraint.satisfies?("1.9.9", constraint)
      refute VersionConstraint.satisfies?("2.0.0", constraint)
      refute VersionConstraint.satisfies?("0.9.9", constraint)
    end

    test "wildcard 1.2.x" do
      {:ok, constraint} = VersionConstraint.parse("1.2.x", :semver)
      assert VersionConstraint.satisfies?("1.2.0", constraint)
      assert VersionConstraint.satisfies?("1.2.9", constraint)
      refute VersionConstraint.satisfies?("1.3.0", constraint)
      refute VersionConstraint.satisfies?("2.2.0", constraint)
    end

    test "Python AND constraint >=1.0,<2.0" do
      {:ok, constraint} = VersionConstraint.parse(">=1.0,<2.0", :python)
      assert VersionConstraint.satisfies?("1.0.0", constraint)
      assert VersionConstraint.satisfies?("1.5.0", constraint)
      refute VersionConstraint.satisfies?("0.9.9", constraint)
      refute VersionConstraint.satisfies?("2.0.0", constraint)
    end
  end
end
