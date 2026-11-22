# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Property.TopoSortPropertyTest do
  @moduledoc """
  Properties of `Opsm.TopoSort.sort/1`, the installation order for resolved packages.

  Install order matters: a package installed before one of its dependencies can
  fail or run against the wrong version. These properties pin what the installer
  relies on, over generated dependency graphs rather than single examples.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Opsm.TopoSort

  @moduletag :property

  # A package as the resolver hands it over: `{version, resolved}` with the
  # dependency names under `manifest.dependencies`. `name` is carried along so a
  # sorted result can be mapped back to the package it came from.
  defp package(name, deps) do
    {"1.0.0", %{name: name, manifest: %{dependencies: Map.new(deps, &{&1, "^1.0"})}}}
  end

  defp names(sorted), do: Enum.map(sorted, fn {_version, pkg} -> pkg.name end)

  # An acyclic graph: node i may depend only on nodes with a smaller index.
  # Names are shuffled so that index order and alphabetical order differ, which
  # stops a sort that merely returns names alphabetically from passing.
  defp dag_gen do
    gen all(
          n <- integer(1..25),
          names <- uniq_list_of(string(:alphanumeric, min_length: 1, max_length: 8), length: n),
          picks <- list_of(list_of(integer(0..(n - 1)), max_length: 4), length: n)
        ) do
      indexed = Enum.with_index(names)

      Map.new(indexed, fn {name, i} ->
        deps =
          picks
          |> Enum.at(i)
          |> Enum.filter(&(&1 < i))
          |> Enum.uniq()
          |> Enum.map(&Enum.at(names, &1))

        {name, package(name, deps)}
      end)
    end
  end

  defp deps_of(packages, name) do
    {_version, pkg} = Map.fetch!(packages, name)
    Map.keys(pkg.manifest.dependencies)
  end

  property "every package is returned exactly once" do
    check all(packages <- dag_gen()) do
      result = names(TopoSort.sort(packages))
      assert Enum.sort(result) == Enum.sort(Map.keys(packages))
    end
  end

  property "on an acyclic graph, every dependency is installed before its dependant" do
    check all(packages <- dag_gen()) do
      position = names(TopoSort.sort(packages)) |> Enum.with_index() |> Map.new()

      for {name, _} <- packages, dep <- deps_of(packages, name) do
        assert position[dep] < position[name],
               "#{inspect(dep)} must precede #{inspect(name)}"
      end
    end
  end

  property "the order depends only on the graph" do
    check all(packages <- dag_gen()) do
      rebuilt = packages |> Enum.to_list() |> Enum.reverse() |> Map.new()
      assert TopoSort.sort(packages) == TopoSort.sort(rebuilt)
    end
  end

  property "a dependency outside the resolved set does not change the order" do
    check all(
            packages <- dag_gen(),
            external <- string(:alphanumeric, min_length: 9, max_length: 12)
          ) do
      # Names in dag_gen are at most 8 characters, so `external` is never resolved.
      with_external =
        Map.new(packages, fn {name, _} ->
          {name, package(name, [external | deps_of(packages, name)])}
        end)

      assert names(TopoSort.sort(with_external)) == names(TopoSort.sort(packages))
    end
  end

  test "an empty resolution sorts to an empty list" do
    assert TopoSort.sort(%{}) == []
  end

  test "a chain is installed leaves first" do
    packages = %{
      "app" => package("app", ["lib"]),
      "lib" => package("lib", ["base"]),
      "base" => package("base", [])
    }

    assert names(TopoSort.sort(packages)) == ["base", "lib", "app"]
  end

  test "a cycle still returns every package once, acyclic part first" do
    # a <-> b form a cycle; c has no dependencies and must still come first.
    packages = %{
      "a" => package("a", ["b"]),
      "b" => package("b", ["a"]),
      "c" => package("c", [])
    }

    assert names(TopoSort.sort(packages)) == ["c", "a", "b"]
  end

  test "a package without a manifest is treated as having no dependencies" do
    packages = %{"bare" => {"1.0.0", %{name: "bare"}}, "dep" => package("dep", ["bare"])}
    assert names(TopoSort.sort(packages)) == ["bare", "dep"]
  end

  test "atom dependency keys are matched by name" do
    packages = %{
      "app" => {"1.0.0", %{name: "app", manifest: %{dependencies: %{lib: "^1.0"}}}},
      "lib" => package("lib", [])
    }

    assert names(TopoSort.sort(packages)) == ["lib", "app"]
  end
end
