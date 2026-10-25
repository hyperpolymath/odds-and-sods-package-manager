# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# Validate test/proven_manifest.toml against the suite as it exists on disk.
#
#   mix run --no-start scripts/validate_proven.exs
#
# Fails (exit 1) when:
#   * a test module on disk has no manifest entry  — an undeclared test;
#   * a manifest entry names a module that no longer exists — a stale claim;
#   * a category, aspect or provenance tier is not in the framework's enums;
#   * a test claims `actually_proven` without a `proof` citation — the whole
#     point of the tier is that the claim carries its evidence;
#   * `[taxonomy]` cardinalities disagree with the enumerations below.
#
# The enumerations are copied from ProvenTests.Types in
# hyperpolymath/proven-tests-and-benches (17 categories, 14 aspects). They are
# duplicated here deliberately and pinned by the check in `taxonomy/0`: a
# silent upstream addition (Category 18) must break this build, not slip
# through as an unknown name that everyone ignores.

defmodule ValidateProven do
  @manifest "test/proven_manifest.toml"

  @categories ~w(
    UnitTest PointToPoint EndToEnd BuildTest ExecutionRuntime ReflexiveTest
    LifecycleTest SmokeTest PropertyBasedTest MutationTest FuzzTest
    ContractInvariantTest RegressionTest ChaosResilienceTest CompatibilityTest
    ProofRegressionTest TypeSafeTest
  )

  @aspects ~w(
    Dependability Security Usability Interoperability Safety Performance
    Functionality Versability Accessibility Maintainability Privacy
    Observability Reproducibility Portability
  )

  @tiers ~w(actually_proven provisionally_proven unproven)

  @doc """
  Validate `test/proven_manifest.toml` against test modules in the current
  working directory without running the tests.

  Check declarations against modules found in `test/**/*_test.exs`, taxonomy
  values and cardinalities, proof citations, duplicate declarations and file
  existence. Print module and tier counts and return `:ok` on success.

  Halt the VM with status 1 if the manifest is unreadable, invalid TOML, lacks
  a test-entry list or fails validation. File read errors while scanning test
  sources or rereading the taxonomy propagate as `File.Error`.
  """
  def main do
    manifest = manifest_entries()
    on_disk = test_modules()

    declared = Map.new(manifest, fn entry -> {entry["module"], entry} end)

    problems =
      missing_entries(on_disk, declared) ++
        stale_entries(manifest, on_disk) ++
        taxonomy_problems(manifest) ++
        shape_problems(manifest)

    IO.puts(
      "proven: #{map_size(declared)} modules declared, #{length(on_disk)} test modules on disk"
    )

    case problems do
      [] ->
        IO.puts("proven: manifest valid ✅")
        report_tiers(manifest)

      _ ->
        Enum.each(problems, fn p -> IO.puts(:stderr, "  ✗ " <> p) end)

        IO.puts(:stderr, """

        provenance is a claim about evidence. Fix the manifest, not this script:
          * a new test        -> add a [[test]] entry with its category, aspect and tier
          * a deleted test    -> remove its entry
          * actually_proven   -> cite the proof (`proof = "..."`)
        """)

        System.halt(1)
    end
  end

  # --- inputs ---------------------------------------------------------------

  defp manifest_entries do
    case File.read(@manifest) do
      {:ok, text} ->
        case Toml.decode(text) do
          {:ok, %{"test" => entries}} when is_list(entries) ->
            entries

          {:ok, _other} ->
            IO.puts(:stderr, "proven: #{@manifest} has no [[test]] entries")
            System.halt(1)

          {:error, err} ->
            IO.puts(:stderr, "proven: #{@manifest} is not valid TOML: #{inspect(err)}")
            System.halt(1)
        end

      {:error, reason} ->
        IO.puts(:stderr, "proven: cannot read #{@manifest}: #{inspect(reason)}")
        System.halt(1)
    end
  end

  # Only modules whose name ends in `Test` count. Test files legitimately
  # define helper modules too, and those are not test cases.
  defp test_modules do
    "test/**/*_test.exs"
    |> Path.wildcard()
    |> Enum.flat_map(fn path ->
      source = File.read!(path)

      ~r/^defmodule\s+([A-Za-z0-9_.]+Test)\s+do/m
      |> Regex.scan(source, capture: :all_but_first)
      |> List.flatten()
      |> Enum.map(fn module -> %{module: module, file: path} end)
    end)
    |> Enum.sort_by(& &1.module)
  end

  defp taxonomy do
    case Toml.decode(File.read!(@manifest)) do
      {:ok, %{"taxonomy" => t}} -> t
      _ -> %{}
    end
  end

  # --- checks ---------------------------------------------------------------

  defp missing_entries(on_disk, declared) do
    on_disk
    |> Enum.reject(fn %{module: m} -> Map.has_key?(declared, m) end)
    |> Enum.map(fn %{module: m, file: f} -> "#{f}: #{m} has no [[test]] entry" end)
  end

  defp stale_entries(manifest, on_disk) do
    present = MapSet.new(on_disk, & &1.module)

    manifest
    |> Enum.map(& &1["module"])
    |> Enum.reject(&MapSet.member?(present, &1))
    |> Enum.map(&"manifest declares #{&1}, which no *_test.exs defines")
  end

  defp taxonomy_problems(manifest) do
    cardinality =
      case taxonomy() do
        %{"categories" => c, "aspects" => a}
        when is_integer(c) and is_integer(a) ->
          if c != length(@categories) or a != length(@aspects) do
            [
              "taxonomy says #{c} categories x #{a} aspects, this validator pins " <>
                "#{length(@categories)} x #{length(@aspects)} — re-read ProvenTests.Types"
            ]
          else
            []
          end

        _ ->
          ["[taxonomy] must declare integer `categories` and `aspects`"]
      end

    per_entry =
      Enum.flat_map(manifest, fn e ->
        name = e["module"] || "<unnamed>"

        []
        |> check_enum(name, "category", e["category"], @categories)
        |> check_enum(name, "aspect", e["aspect"], @aspects)
        |> check_enum(name, "tier", e["tier"], @tiers)
        |> check_proof(name, e)
      end)

    cardinality ++ per_entry
  end

  defp check_enum(problems, name, field, value, allowed) do
    cond do
      is_nil(value) -> problems ++ ["#{name}: missing `#{field}`"]
      value in allowed -> problems
      true -> problems ++ ["#{name}: #{field} #{inspect(value)} is not in #{inspect(allowed)}"]
    end
  end

  defp check_proof(problems, name, entry) do
    if entry["tier"] == "actually_proven" and
         not (is_binary(entry["proof"]) and String.trim(entry["proof"]) != "") do
      problems ++
        ["#{name}: tier actually_proven requires a `proof` citation — demote it instead"]
    else
      problems
    end
  end

  defp shape_problems(manifest) do
    duplicates =
      manifest
      |> Enum.map(& &1["module"])
      |> Enum.frequencies()
      |> Enum.filter(fn {_m, n} -> n > 1 end)
      |> Enum.map(fn {m, n} -> "#{m} is declared #{n} times" end)

    missing_file =
      manifest
      |> Enum.reject(fn e -> is_binary(e["file"]) and File.exists?(e["file"]) end)
      |> Enum.map(fn e -> "#{e["module"]}: file #{inspect(e["file"])} does not exist" end)

    duplicates ++ missing_file
  end

  defp report_tiers(manifest) do
    counts = Enum.frequencies_by(manifest, & &1["tier"])

    Enum.each(@tiers, fn tier ->
      IO.puts("  #{String.pad_trailing(tier, 20)} #{Map.get(counts, tier, 0)}")
    end)
  end
end

ValidateProven.main()
