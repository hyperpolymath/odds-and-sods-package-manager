# SPDX-License-Identifier: PMPL-1.0
defmodule Opsm.VersionConstraint do
  @moduledoc """
  Parse and evaluate version constraints across different ecosystems.

  Supports:
  - Semver (npm, Hex, Cargo): ^1.0.0, ~1.2, >=2.0.0, 1.x, *
  - Python (PyPI): >=1.0,<2.0, ~=1.4.2
  - Exact versions: 1.2.3

  Based on industry standards:
  - npm: https://docs.npmjs.com/cli/v6/using-npm/semver
  - Cargo: https://doc.rust-lang.org/cargo/reference/specifying-dependencies.html
  - PEP 440: https://peps.python.org/pep-0440/
  """

  @type constraint_type :: :semver | :python | :exact

  @type constraint_ast ::
          {:any}
          | {:exact, Version.t()}
          | {:gte, Version.t()}
          | {:gt, Version.t()}
          | {:lte, Version.t()}
          | {:lt, Version.t()}
          | {:caret, Version.t()}
          | {:tilde, Version.t()}
          | {:wildcard, integer(), integer() | :any}
          | {:and, [constraint_ast()]}
          | {:or, [constraint_ast()]}

  @type t :: %__MODULE__{
          constraint_type: constraint_type(),
          ast: constraint_ast(),
          original: String.t()
        }

  defstruct [:constraint_type, :ast, :original]

  # =============================================================================
  # Public API
  # =============================================================================

  @doc """
  Parse a version constraint string.

  ## Examples

      iex> VersionConstraint.parse("^1.0.0", :semver)
      {:ok, %VersionConstraint{constraint_type: :semver, ast: {:caret, ...}}}

      iex> VersionConstraint.parse(">=1.0,<2.0", :python)
      {:ok, %VersionConstraint{constraint_type: :python, ast: {:and, ...}}}
  """
  def parse(constraint_string, constraint_type \\ :semver)

  def parse("*", _type) do
    {:ok,
     %__MODULE__{
       constraint_type: :semver,
       ast: {:any},
       original: "*"
     }}
  end

  def parse(constraint_string, constraint_type) when is_binary(constraint_string) do
    constraint_string = String.trim(constraint_string)

    case constraint_type do
      :semver -> parse_semver(constraint_string)
      :python -> parse_python(constraint_string)
      :exact -> parse_exact(constraint_string)
      _ -> {:error, "Unknown constraint type: #{constraint_type}"}
    end
  end

  @doc """
  Check if a version satisfies a constraint.

  ## Examples

      iex> {:ok, constraint} = VersionConstraint.parse("^1.0.0", :semver)
      iex> VersionConstraint.satisfies?("1.2.3", constraint)
      true

      iex> VersionConstraint.satisfies?("2.0.0", constraint)
      false
  """
  def satisfies?(version_string, %__MODULE__{} = constraint) when is_binary(version_string) do
    case Version.parse(version_string) do
      {:ok, version} -> evaluate_constraint(version, constraint.ast)
      :error -> false
    end
  end

  # =============================================================================
  # Semver Parsing
  # =============================================================================

  defp parse_semver(str) do
    cond do
      # Wildcard: * (any version)
      str == "*" ->
        {:ok, %__MODULE__{constraint_type: :semver, ast: {:any}, original: str}}

      # Caret range: ^1.2.3
      String.starts_with?(str, "^") ->
        version_str = String.trim_leading(str, "^") |> normalize_version()

        case Version.parse(version_str) do
          {:ok, version} ->
            {:ok,
             %__MODULE__{
               constraint_type: :semver,
               ast: {:caret, version},
               original: str
             }}

          :error ->
            {:error, "Invalid version in caret constraint: #{version_str}"}
        end

      # Tilde range: ~1.2.3
      String.starts_with?(str, "~") ->
        version_str = String.trim_leading(str, "~") |> normalize_version()

        case Version.parse(version_str) do
          {:ok, version} ->
            {:ok,
             %__MODULE__{
               constraint_type: :semver,
               ast: {:tilde, version},
               original: str
             }}

          :error ->
            {:error, "Invalid version in tilde constraint: #{version_str}"}
        end

      # Comparison operators: >=1.0.0, >1.0.0, <=2.0.0, <2.0.0
      String.starts_with?(str, ">=") ->
        parse_comparison(:gte, String.trim_leading(str, ">="), str)

      String.starts_with?(str, ">") ->
        parse_comparison(:gt, String.trim_leading(str, ">"), str)

      String.starts_with?(str, "<=") ->
        parse_comparison(:lte, String.trim_leading(str, "<="), str)

      String.starts_with?(str, "<") ->
        parse_comparison(:lt, String.trim_leading(str, "<"), str)

      # Wildcard with partial versions: 1.x, 1.2.x
      String.contains?(str, "x") or String.contains?(str, "X") or String.contains?(str, "*") ->
        parse_wildcard(str)

      # Exact version: 1.2.3
      true ->
        case Version.parse(str) do
          {:ok, version} ->
            {:ok,
             %__MODULE__{
               constraint_type: :semver,
               ast: {:exact, version},
               original: str
             }}

          :error ->
            {:error, "Invalid version: #{str}"}
        end
    end
  end

  defp parse_comparison(op, version_str, original) do
    normalized = normalize_version(String.trim(version_str))

    case Version.parse(normalized) do
      {:ok, version} ->
        {:ok,
         %__MODULE__{
           constraint_type: :semver,
           ast: {op, version},
           original: original
         }}

      :error ->
        {:error, "Invalid version in comparison: #{version_str}"}
    end
  end

  # Normalize version to x.y.z format (Elixir Version module requirement)
  # Python allows "1.0", we need "1.0.0"
  defp normalize_version(version_str) do
    parts = String.split(version_str, ".")

    case length(parts) do
      1 -> "#{version_str}.0.0"
      2 -> "#{version_str}.0"
      _ -> version_str
    end
  end

  defp parse_wildcard(str) do
    parts =
      String.split(str, ".")
      |> Enum.with_index()
      |> Enum.find(fn {part, _idx} -> part in ["x", "X", "*"] end)

    case parts do
      {_, idx} ->
        # Parse up to the wildcard position
        version_parts =
          String.split(str, ".")
          |> Enum.take(idx)
          |> Enum.map(fn
            "x" -> 0
            "X" -> 0
            "*" -> 0
            part -> String.to_integer(part)
          end)

        major = Enum.at(version_parts, 0, 0)
        # idx 1 means wildcard at position 1 (minor), so minor is :any
        # idx 2 means wildcard at position 2 (patch), so minor comes from version_parts[1]
        minor =
          case idx do
            1 -> :any
            2 -> Enum.at(version_parts, 1, 0)
            _ -> :any
          end

        {:ok,
         %__MODULE__{
           constraint_type: :semver,
           ast: {:wildcard, major, minor},
           original: str
         }}

      nil ->
        {:error, "Invalid wildcard constraint: #{str}"}
    end
  end

  # =============================================================================
  # Python PEP 440 Parsing
  # =============================================================================

  defp parse_python(str) do
    # Python constraints can be comma-separated: ">=1.0,<2.0"
    if String.contains?(str, ",") do
      parts = String.split(str, ",") |> Enum.map(&String.trim/1)

      case parse_python_parts(parts) do
        {:ok, asts} ->
          {:ok,
           %__MODULE__{
             constraint_type: :python,
             ast: {:and, asts},
             original: str
           }}

        error ->
          error
      end
    else
      parse_python_single(str)
    end
  end

  defp parse_python_parts(parts) do
    results =
      Enum.map(parts, fn part ->
        case parse_python_single(part) do
          {:ok, constraint} -> {:ok, constraint.ast}
          error -> error
        end
      end)

    if Enum.all?(results, fn r -> match?({:ok, _}, r) end) do
      {:ok, Enum.map(results, fn {:ok, ast} -> ast end)}
    else
      error = Enum.find(results, fn r -> match?({:error, _}, r) end)
      error
    end
  end

  defp parse_python_single(str) do
    cond do
      # Compatible release: ~=1.4.2
      String.starts_with?(str, "~=") ->
        version_str = String.trim_leading(str, "~=")
        normalized = normalize_version(version_str)

        case Version.parse(normalized) do
          {:ok, version} ->
            {:ok,
             %__MODULE__{
               constraint_type: :python,
               ast: {:tilde, version},
               original: str
             }}

          :error ->
            {:error, "Invalid version in compatible release: #{version_str}"}
        end

      # Comparison operators
      String.starts_with?(str, ">=") ->
        parse_comparison(:gte, String.trim_leading(str, ">="), str)

      String.starts_with?(str, ">") ->
        parse_comparison(:gt, String.trim_leading(str, ">"), str)

      String.starts_with?(str, "<=") ->
        parse_comparison(:lte, String.trim_leading(str, "<="), str)

      String.starts_with?(str, "<") ->
        parse_comparison(:lt, String.trim_leading(str, "<"), str)

      String.starts_with?(str, "==") ->
        version_str = String.trim_leading(str, "==")
        normalized = normalize_version(version_str)

        case Version.parse(normalized) do
          {:ok, version} ->
            {:ok,
             %__MODULE__{
               constraint_type: :python,
               ast: {:exact, version},
               original: str
             }}

          :error ->
            {:error, "Invalid version in exact constraint: #{version_str}"}
        end

      # Exact version
      true ->
        normalized = normalize_version(str)

        case Version.parse(normalized) do
          {:ok, version} ->
            {:ok,
             %__MODULE__{
               constraint_type: :python,
               ast: {:exact, version},
               original: str
             }}

          :error ->
            {:error, "Invalid version: #{str}"}
        end
    end
  end

  # =============================================================================
  # Exact Version Parsing
  # =============================================================================

  defp parse_exact(str) do
    case Version.parse(str) do
      {:ok, version} ->
        {:ok, %__MODULE__{constraint_type: :exact, ast: {:exact, version}, original: str}}

      :error ->
        {:error, "Invalid version: #{str}"}
    end
  end

  # =============================================================================
  # Constraint Evaluation
  # =============================================================================

  defp evaluate_constraint(_version, {:any}), do: true

  defp evaluate_constraint(version, {:exact, target}) do
    Version.compare(version, target) == :eq
  end

  defp evaluate_constraint(version, {:gte, target}) do
    Version.compare(version, target) in [:eq, :gt]
  end

  defp evaluate_constraint(version, {:gt, target}) do
    Version.compare(version, target) == :gt
  end

  defp evaluate_constraint(version, {:lte, target}) do
    Version.compare(version, target) in [:eq, :lt]
  end

  defp evaluate_constraint(version, {:lt, target}) do
    Version.compare(version, target) == :lt
  end

  # Caret range: ^1.2.3
  # Allows changes that don't modify the left-most non-zero digit
  # ^1.2.3 := >=1.2.3 <2.0.0
  # ^0.2.3 := >=0.2.3 <0.3.0
  # ^0.0.3 := >=0.0.3 <0.0.4
  defp evaluate_constraint(version, {:caret, target}) do
    cond do
      target.major > 0 ->
        # Allow minor and patch changes
        version.major == target.major and
          Version.compare(version, target) in [:eq, :gt] and
          version.major < target.major + 1

      target.minor > 0 ->
        # Allow patch changes only
        version.major == target.major and
          version.minor == target.minor and
          Version.compare(version, target) in [:eq, :gt] and
          version.minor < target.minor + 1

      true ->
        # Exact match for 0.0.x
        version.major == target.major and
          version.minor == target.minor and
          version.patch == target.patch
    end
  end

  # Tilde range: ~1.2.3
  # Allows patch-level changes
  # ~1.2.3 := >=1.2.3 <1.3.0
  # ~1.2 := >=1.2.0 <1.3.0
  defp evaluate_constraint(version, {:tilde, target}) do
    version.major == target.major and
      version.minor == target.minor and
      Version.compare(version, target) in [:eq, :gt]
  end

  # Wildcard: 1.x, 1.2.x
  # 1.x := >=1.0.0 <2.0.0
  # 1.2.x := >=1.2.0 <1.3.0
  defp evaluate_constraint(version, {:wildcard, major, :any}) do
    version.major == major
  end

  defp evaluate_constraint(version, {:wildcard, major, minor}) do
    version.major == major and version.minor == minor
  end

  # AND: all constraints must be satisfied
  defp evaluate_constraint(version, {:and, constraints}) do
    Enum.all?(constraints, fn constraint ->
      evaluate_constraint(version, constraint)
    end)
  end

  # OR: at least one constraint must be satisfied
  defp evaluate_constraint(version, {:or, constraints}) do
    Enum.any?(constraints, fn constraint ->
      evaluate_constraint(version, constraint)
    end)
  end

  # =============================================================================
  # Helpers
  # =============================================================================

  @doc """
  Get a human-readable description of the constraint.
  """
  def describe(%__MODULE__{original: original}) do
    original
  end
end
