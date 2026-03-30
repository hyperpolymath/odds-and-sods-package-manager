# SPDX-License-Identifier: PMPL-1.0
defmodule Opsm.Resolver do
  @moduledoc """
  Dependency resolution engine using a PubGrub-inspired algorithm.

  Resolves package dependencies across multiple registries, handling:
  - Version constraints (semver, Python, exact)
  - Transitive dependencies
  - Conflict detection
  - Cross-registry resolution

  Based on PubGrub algorithm (used by Cargo, pip, Poetry):
  https://github.com/dart-lang/pub/blob/master/doc/solver.md
  """

  alias Opsm.VersionConstraint
  alias Opsm.Registries.Registry
  alias Opsm.RegistryCache
  alias Opsm.Types.{ResolvedPackage, ManifestFormat}

  require Logger

  @type package_name :: String.t()
  @type version_string :: String.t()
  @type forth_type :: atom()

  @type dependency :: %{
          name: package_name(),
          constraint: String.t(),
          forth: forth_type() | nil
        }

  @type resolution :: %{
          package_name() => {version_string(), ResolvedPackage.t()}
        }

  @type conflict :: %{
          package: package_name(),
          version: version_string(),
          required_by: [package_name()],
          conflicting_constraints: [String.t()]
        }

  # =============================================================================
  # Public API
  # =============================================================================

  @doc """
  Resolve dependencies for a root package.

  Returns {:ok, resolution} with a map of package_name => {version, ResolvedPackage}
  or {:error, conflict} describing the first unresolvable conflict.

  ## Options

  - `:sustainability_preference` - Prefer packages with higher oikos scores (default: false)
  - `:max_depth` - Maximum dependency tree depth (default: 50)
  - `:include_dev` - Include dev dependencies (default: false)

  ## Examples

      iex> root_deps = [%{name: "express", constraint: "^4.0.0", forth: :npm}]
      iex> Resolver.resolve(root_deps, forth: :npm)
      {:ok, %{"express" => {"4.18.2", %ResolvedPackage{}}, ...}}
  """
  def resolve(root_dependencies, opts \\ []) do
    forth = Keyword.get(opts, :forth, :npm)
    max_packages = Keyword.get(opts, :max_packages, 1000)
    max_depth = Keyword.get(opts, :max_depth, 100)
    include_dev = Keyword.get(opts, :include_dev, false)
    sustainability = Keyword.get(opts, :sustainability_preference, false)

    state = %{
      # Resolved packages: package_name => {version, ResolvedPackage}
      resolved: %{},
      # Active constraints: package_name => [{constraint, required_by}]
      constraints: %{},
      # Unresolved package names (avoids recomputing from constraints - resolved diff)
      unresolved: MapSet.new(),
      # Visited nodes to prevent cycles
      visited: MapSet.new(),
      # Configuration
      forth: forth,
      max_packages: max_packages,
      max_depth: max_depth,
      include_dev: include_dev,
      sustainability: sustainability,
      # Current tree depth (reset per branch, for circular dep detection)
      depth: 0
    }

    # Convert root dependencies to constraints
    state =
      Enum.reduce(root_dependencies, state, fn dep, acc ->
        add_constraint(acc, dep.name, dep.constraint, dep.forth || forth, "root")
      end)

    # Start resolution
    case do_resolve(state) do
      {:ok, final_state} ->
        resolution = final_state.resolved

        # Persist resolution event to VeriSimDB
        root_name = case root_dependencies do
          [first | _] -> first.name
          _ -> "unknown"
        end
        root_constraint = case root_dependencies do
          [first | _] -> first.constraint
          _ -> "*"
        end
        Opsm.VeriSimDB.record_resolution(%{
          root_package: root_name,
          root_constraint: root_constraint,
          forth: forth,
          resolved: Map.keys(resolution),
          sustainability_preference: sustainability,
          backtrack_count: nil
        })

        {:ok, resolution}

      error ->
        error
    end
  end

  # =============================================================================
  # Resolution Algorithm
  # =============================================================================

  defp do_resolve(state) do
    # Find next unresolved package
    case next_unresolved(state) do
      nil ->
        # All packages resolved!
        {:ok, state}

      {package_name, constraints} ->
        # Fetch available versions
        forth = infer_forth(state, package_name)

        case fetch_available_versions(package_name, forth) do
          {:ok, versions} ->
            # Filter versions that satisfy all constraints
            valid_versions = filter_valid_versions(versions, constraints)

            # Sort by preference (newest first, or by sustainability)
            sorted_versions = sort_versions(valid_versions, state.sustainability)

            # Try each version until one succeeds
            try_versions(state, package_name, sorted_versions, forth, constraints)

          {:error, reason} ->
            {:error, format_fetch_error(package_name, forth, reason)}
        end
    end
  end

  defp try_versions(_state, package_name, [], _forth, constraints) do
    # No valid versions found
    {:error, format_no_valid_version(package_name, constraints)}
  end

  defp try_versions(state, package_name, [version | rest], forth, constraints) do
    # Check total packages limit (prevents runaway resolution)
    if map_size(state.resolved) >= state.max_packages do
      {:error,
       "Maximum package limit (#{state.max_packages}) exceeded while resolving #{package_name}. Resolution graph is too large."}
    else
      # Try to resolve with this version
      case resolve_with_version(state, package_name, version, forth) do
        {:ok, new_state} ->
          # Continue resolving remaining packages
          do_resolve(new_state)

        {:conflict, _reason} ->
          # Backtrack and try next version
          try_versions(state, package_name, rest, forth, constraints)

        {:error, reason} ->
          # Hard error, propagate up
          {:error, reason}
      end
    end
  end

  defp resolve_with_version(state, package_name, version, forth) do
    # Check for cycles using visited set
    key = "#{package_name}@#{version}"

    cond do
      MapSet.member?(state.visited, key) ->
        {:conflict, "Circular dependency detected: #{key}"}

      state.depth >= state.max_depth ->
        {:conflict, "Dependency tree depth (#{state.max_depth}) exceeded at #{package_name}. Possible circular dependency."}

      true ->
        # Fetch package metadata (cached)
        case RegistryCache.fetch_or_compute({:fetch, forth, package_name, version}, fn ->
          Registry.fetch(forth, package_name, version)
        end) do
          {:ok, resolved_pkg} ->
            # Add to resolved set, remove from unresolved, increment tree depth
            new_state = %{
              state
              | resolved: Map.put(state.resolved, package_name, {version, resolved_pkg}),
                unresolved: MapSet.delete(state.unresolved, package_name),
                visited: MapSet.put(state.visited, key),
                depth: state.depth + 1
            }

            # Add constraints from dependencies
            deps = extract_dependencies(resolved_pkg.manifest, state.include_dev)

            new_state_with_constraints =
              Enum.reduce(deps, new_state, fn dep, acc ->
                add_constraint(acc, dep.name, dep.constraint, dep.forth, package_name)
              end)

            # Check if new constraints conflict with existing resolutions
            case check_conflicts(new_state_with_constraints) do
              :ok ->
                {:ok, new_state_with_constraints}

              {:conflict, reason} ->
                {:conflict, reason}
            end

          {:error, :not_found} ->
            {:conflict, "Package #{package_name}@#{version} not found in #{forth} registry"}

          {:error, reason} ->
            {:error, "Failed to fetch #{package_name}@#{version}: #{reason}"}
        end
    end
  end

  # =============================================================================
  # Constraint Management
  # =============================================================================

  defp add_constraint(state, package_name, constraint_str, forth, required_by) do
    constraints = Map.get(state.constraints, package_name, [])
    new_entry = {constraint_str, required_by, forth}
    updated_constraints = [new_entry | constraints]

    # Track as unresolved if not already resolved
    unresolved =
      if Map.has_key?(state.resolved, package_name),
        do: state.unresolved,
        else: MapSet.put(state.unresolved, package_name)

    %{state |
      constraints: Map.put(state.constraints, package_name, updated_constraints),
      unresolved: unresolved
    }
  end

  defp check_conflicts(state) do
    # Check if any resolved package violates new constraints
    Enum.reduce_while(state.resolved, :ok, fn {pkg_name, {version, _resolved}}, _acc ->
      constraints = Map.get(state.constraints, pkg_name, [])

      # Parse version (lenient — handles Go v-prefix, Hackage 4-part, etc.)
      case parse_version_lenient(version) do
        {:ok, _parsed_version} ->
          # Check if version satisfies all constraints
          violating =
            Enum.reject(constraints, fn {constraint_str, _required_by, _forth} ->
              case VersionConstraint.parse(constraint_str, :semver) do
                {:ok, constraint} ->
                  VersionConstraint.satisfies?(version, constraint)

                {:error, _} ->
                  # Can't parse constraint, assume satisfied
                  true
              end
            end)

          if violating == [] do
            {:cont, :ok}
          else
            {:halt,
             {:conflict,
              format_constraint_violation(pkg_name, version, violating)}}
          end

        :error ->
          {:cont, :ok}
      end
    end)
  end

  # =============================================================================
  # Version Selection
  # =============================================================================

  defp next_unresolved(state) do
    # Pick from tracked unresolved set (O(1) membership check, no full scan)
    case MapSet.size(state.unresolved) do
      0 -> nil
      _ ->
        # Pick the package with the most constraints (most constrained first = fail fast)
        state.unresolved
        |> Enum.map(fn name -> {name, Map.get(state.constraints, name, [])} end)
        |> Enum.min_by(fn {_name, constraints} -> length(constraints) end, fn -> nil end)
    end
  end

  defp fetch_available_versions(package_name, forth) do
    # Use ETS cache to avoid repeated HTTP calls for the same package
    RegistryCache.fetch_or_compute({:versions, forth, package_name}, fn ->
      case Registry.versions(forth, package_name) do
        {:ok, versions} when is_list(versions) ->
          {:ok, versions}

        {:ok, _other} ->
          # Registry might return package metadata instead of version list
          # Try fetching "latest"
          case Registry.fetch(forth, package_name, "latest") do
            {:ok, pkg} -> {:ok, [pkg.version]}
            error -> error
          end

        error ->
          error
      end
    end)
  end

  defp filter_valid_versions(versions, constraints) do
    Enum.filter(versions, fn version ->
      Enum.all?(constraints, fn {constraint_str, _required_by, _forth} ->
        case VersionConstraint.parse(constraint_str, :semver) do
          {:ok, constraint} ->
            VersionConstraint.satisfies?(version, constraint)

          {:error, _} ->
            # Can't parse constraint, skip validation
            true
        end
      end)
    end)
  end

  defp sort_versions(versions, _sustainability_preference = false) do
    # Sort by semver (newest first), with lenient parsing for non-semver formats
    Enum.sort(versions, fn v1, v2 ->
      case {parse_version_lenient(v1), parse_version_lenient(v2)} do
        {{:ok, ver1}, {:ok, ver2}} ->
          Version.compare(ver1, ver2) == :gt

        _ ->
          v1 >= v2
      end
    end)
  end

  defp sort_versions(versions, _sustainability_preference = true) do
    # Fetch oikos sustainability scores for candidate versions.
    # Combines sustainability score (0-100) with version recency.
    # Falls back to version-only sorting if oikos is unavailable.
    config = try do
      Opsm.Config.load_config_or_example()
    rescue
      _ -> nil
    end

    oikos_scores = if config do
      try do
        client = Opsm.Clients.Oikos.new(config.oikos, config.http)
        case Opsm.Clients.Oikos.health(client) do
          {:ok, _} ->
            # Oikos is up — score each version via package-level analysis
            versions
            |> Enum.map(fn ver ->
              score = RegistryCache.fetch_or_compute({:oikos, ver}, fn ->
                case Opsm.Clients.Oikos.analyze_package(client, "pkg", ver) do
                  {:ok, s} when is_number(s) -> s
                  _ -> 50
                end
              end, 60_000)
              {ver, score}
            end)
            |> Map.new()

          {:error, _} ->
            nil
        end
      rescue
        _ -> nil
      end
    else
      nil
    end

    case oikos_scores do
      nil ->
        # Oikos unavailable — fall back to version sorting
        sort_versions(versions, false)

      scores ->
        # Sort by: sustainability score (desc), then version (desc)
        Enum.sort(versions, fn v1, v2 ->
          s1 = Map.get(scores, v1, 0)
          s2 = Map.get(scores, v2, 0)

          cond do
            s1 != s2 -> s1 > s2
            true ->
              case {parse_version_lenient(v1), parse_version_lenient(v2)} do
                {{:ok, ver1}, {:ok, ver2}} -> Version.compare(ver1, ver2) == :gt
                _ -> v1 >= v2
              end
          end
        end)
    end
  end

  # =============================================================================
  # Dependency Extraction
  # =============================================================================

  defp extract_dependencies(%ManifestFormat{} = manifest, include_dev) do
    runtime_deps =
      Enum.map(manifest.dependencies, fn {name, constraint} ->
        %{
          name: to_string(name),
          constraint: to_string(constraint),
          forth: manifest.source_forth
        }
      end)

    dev_deps =
      if include_dev and manifest.dev_dependencies do
        Enum.map(manifest.dev_dependencies, fn {name, constraint} ->
          %{
            name: to_string(name),
            constraint: to_string(constraint),
            forth: manifest.source_forth
          }
        end)
      else
        []
      end

    runtime_deps ++ dev_deps
  end

  defp extract_dependencies(_manifest, _include_dev) do
    # Handle cases where manifest is not in expected format
    []
  end

  # =============================================================================
  # Helpers
  # =============================================================================

  # Lenient version parsing for non-semver formats (Go v-prefix, Hackage 4-part)
  defp parse_version_lenient(version_string) do
    normalized = version_string
      |> String.trim_leading("v")
      |> String.trim_leading("V")

    case Version.parse(normalized) do
      {:ok, version} -> {:ok, version}
      :error ->
        parts = String.split(normalized, ".")
        if length(parts) > 3 do
          truncated = parts |> Enum.take(3) |> Enum.join(".")
          Version.parse(truncated)
        else
          :error
        end
    end
  end

  defp infer_forth(state, package_name) do
    # Try to infer forth from constraints
    constraints = Map.get(state.constraints, package_name, [])

    forth_from_constraints =
      Enum.find_value(constraints, fn {_constraint, _required_by, forth} ->
        forth
      end)

    forth_from_constraints || state.forth
  end

  # =============================================================================
  # Error Formatting
  # =============================================================================

  defp format_fetch_error(package_name, forth, reason) do
    "Failed to fetch versions for #{package_name} from @#{forth}: #{inspect(reason)}"
  end

  defp format_no_valid_version(package_name, constraints) do
    constraint_descriptions =
      Enum.map(constraints, fn {constraint_str, required_by, _forth} ->
        "  - #{constraint_str} (required by #{required_by})"
      end)
      |> Enum.join("\n")

    """
    Could not find a version of #{package_name} that satisfies all constraints:
    #{constraint_descriptions}
    """
  end

  defp format_constraint_violation(package_name, version, violating) do
    violations =
      Enum.map(violating, fn {constraint_str, required_by, _forth} ->
        "  - #{constraint_str} (required by #{required_by})"
      end)
      |> Enum.join("\n")

    """
    Version #{version} of #{package_name} violates constraints:
    #{violations}
    """
  end
end
