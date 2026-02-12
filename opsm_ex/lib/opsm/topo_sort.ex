# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule Opsm.TopoSort do
  @moduledoc """
  Topological sort for dependency installation order.

  Uses Kahn's algorithm to produce a deterministic installation order
  where dependencies are installed before their dependants.
  Falls back to input order if cycles are detected (resolver should
  have already rejected circular dependencies).
  """

  @doc """
  Sort resolved packages in dependency order.

  Takes a map of `%{name => {version, ResolvedPackage}}` and returns
  a list of `{version, ResolvedPackage}` tuples in installation order
  (dependencies first).

  ## Examples

      iex> packages = %{
      ...>   "a" => {"1.0.0", %{manifest: %{dependencies: %{"b" => "^1.0"}}}},
      ...>   "b" => {"1.0.0", %{manifest: %{dependencies: %{}}}}
      ...> }
      iex> TopoSort.sort(packages)
      [{"1.0.0", %{...b...}}, {"1.0.0", %{...a...}}]
  """
  def sort(resolved_packages) when map_size(resolved_packages) == 0, do: []

  def sort(resolved_packages) do
    # Build adjacency list and in-degree map
    # Edge: dependency -> dependant (install dependency first)
    all_names = Map.keys(resolved_packages)

    # Initialize in-degree to 0 for all resolved packages
    in_degree = Map.new(all_names, fn name -> {name, 0} end)

    # Build edges: for each package, add edges from its dependencies to itself
    {edges, in_degree} =
      Enum.reduce(resolved_packages, {%{}, in_degree}, fn {name, {_ver, pkg}}, {edges_acc, deg_acc} ->
        dep_names = extract_dep_names(pkg)
        # Only count edges to packages that are in our resolved set
        resolved_deps = Enum.filter(dep_names, fn d -> Map.has_key?(resolved_packages, d) end)

        # Each resolved dep has an edge to this package
        new_edges = Enum.reduce(resolved_deps, edges_acc, fn dep, e_acc ->
          Map.update(e_acc, dep, [name], fn existing -> [name | existing] end)
        end)

        new_deg = Map.update!(deg_acc, name, fn d -> d + length(resolved_deps) end)

        {new_edges, new_deg}
      end)

    # Kahn's algorithm
    # Start with all nodes that have in-degree 0 (no dependencies in resolved set)
    queue =
      in_degree
      |> Enum.filter(fn {_name, deg} -> deg == 0 end)
      |> Enum.map(fn {name, _} -> name end)
      |> Enum.sort()  # Deterministic order for same-level packages

    kahn(queue, edges, in_degree, [], resolved_packages)
  end

  defp kahn([], _edges, in_degree, result_rev, resolved_packages) do
    # Check for remaining nodes (would indicate cycle)
    remaining = Enum.filter(in_degree, fn {_name, deg} -> deg > 0 end)

    result = :lists.reverse(result_rev)

    if remaining == [] do
      # Convert names back to {version, package} tuples
      Enum.map(result, fn name -> Map.fetch!(resolved_packages, name) end)
    else
      # Cycle detected — resolver should have caught this, but fall back gracefully
      # Add remaining in alphabetical order
      remaining_names = remaining |> Enum.map(fn {name, _} -> name end) |> Enum.sort()
      all_names = result ++ remaining_names
      Enum.map(all_names, fn name -> Map.fetch!(resolved_packages, name) end)
    end
  end

  defp kahn([current | rest], edges, in_degree, result_rev, resolved_packages) do
    # Process current node: reduce in-degree of all dependants
    dependants = Map.get(edges, current, [])

    {new_queue_additions, new_in_degree} =
      Enum.reduce(dependants, {[], in_degree}, fn dep, {q_acc, deg_acc} ->
        new_deg = Map.get(deg_acc, dep, 0) - 1
        updated_deg = Map.put(deg_acc, dep, new_deg)

        if new_deg == 0 do
          {[dep | q_acc], updated_deg}
        else
          {q_acc, updated_deg}
        end
      end)

    # Remove current from in-degree tracking
    new_in_degree = Map.delete(new_in_degree, current)

    # Use :queue or simple append for BFS queue; prepend to result (reversed at end)
    sorted_additions = Enum.sort(new_queue_additions)
    new_queue = rest ++ sorted_additions

    kahn(new_queue, edges, new_in_degree, [current | result_rev], resolved_packages)
  end

  defp extract_dep_names({_version, pkg}) do
    extract_dep_names(pkg)
  end

  defp extract_dep_names(%{manifest: %{dependencies: deps}}) when is_map(deps) do
    Map.keys(deps) |> Enum.map(&to_string/1)
  end

  defp extract_dep_names(_), do: []
end
