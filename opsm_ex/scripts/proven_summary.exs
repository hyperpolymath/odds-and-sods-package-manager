# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# Render the Proven-Tests report as Markdown for $GITHUB_STEP_SUMMARY.
#
#   mix run --no-start scripts/proven_summary.exs
#
# Reads  test/proven_manifest.toml  (what each test *claims*)
#        proven-report.json         (what actually ran and passed)
# Writes proven-summary.md
#
# The distinction is the whole framework: a cell is COVERED only when a module
# declared at those coordinates ran at least one test and none failed. A cell
# with a declaration but no execution is "declared, unexercised" — the number
# that a declaration-only census would have reported as covered.

defmodule ProvenSummary do
  @manifest "test/proven_manifest.toml"
  @report "proven-report.json"
  @out "proven-summary.md"

  def main do
    manifest = entries()
    report = report()

    # module -> %{passed:, failed:, skipped:, total:}
    ran = Map.get(report, "modules", %{})

    rows = Enum.map(manifest, &row(&1, ran))
    covered = Enum.filter(rows, & &1.covered)
    cells = MapSet.new(covered, &{&1.category, &1.aspect})

    md = [
      "## Proven-Tests report\n",
      "Framework: `hyperpolymath/proven-tests-and-benches` — provenance is a claim about evidence, not a label.\n",
      table(rows, cells),
      tiers(rows),
      coverage(rows, cells),
      honesty(rows)
    ]

    File.write!(@out, Enum.join(md, "\n") <> "\n")
    IO.puts("proven-summary: wrote #{@out} (#{length(rows)} modules, #{MapSet.size(cells)}/238 cells)")
  end

  # --- inputs ---------------------------------------------------------------

  defp entries do
    case Toml.decode(File.read!(@manifest)) do
      {:ok, %{"test" => list}} -> list
      other -> raise "cannot read #{@manifest}: #{inspect(other)}"
    end
  end

  defp report do
    case File.read(@report) do
      {:ok, text} ->
        case Jason.decode(text) do
          {:ok, map} -> map
          _ -> %{}
        end

      {:error, _} ->
        # Fail closed when the reporter was supposed to run. Silence here is how
        # a formatter that crashed at start-up went unnoticed: the summary said
        # "not found", printed a lattice of zeroes, and exited 0 — which reads
        # exactly like a suite with nothing worth reporting.
        if System.get_env("OPSM_PROVEN_REPORT") == "1" do
          IO.puts(:stderr, """
          proven-summary: #{@report} is missing but OPSM_PROVEN_REPORT=1.

          The reporter is an ExUnit formatter (test/support/proven_reporter.ex).
          If it did not run, the lattice below is not evidence of anything.
          Check that ExUnit.start/1 registers it through :formatters — ExUnit
          has no :event_managers option, and an unknown key is ignored silently.
          """)

          System.halt(1)
        else
          IO.puts(:stderr, "proven-summary: #{@report} not found; run with OPSM_PROVEN_REPORT=1")
          %{}
        end
    end
  end

  # --- rows -----------------------------------------------------------------

  defp row(entry, ran) do
    counts = Map.get(ran, entry["module"], %{"passed" => 0, "failed" => 0, "skipped" => 0})

    %{
      module: entry["module"],
      category: entry["category"],
      aspect: entry["aspect"],
      tier: entry["tier"],
      passed: counts["passed"] || 0,
      failed: counts["failed"] || 0,
      skipped: counts["skipped"] || 0,
      covered: (counts["passed"] || 0) > 0 and (counts["failed"] || 0) == 0
    }
  end

  # --- rendering ------------------------------------------------------------

  defp table(rows, _cells) do
    header = """
    | Category | Aspect | Modules | Passed | Failed | Skipped | Covered |
    |---|---|---|---|---|---|---|
    """

    body =
      rows
      |> Enum.group_by(&{&1.category, &1.aspect})
      |> Enum.sort()
      |> Enum.map(fn {{category, aspect}, group} ->
        sum = fn key -> Enum.reduce(group, 0, &(&1[key] + &2)) end

        "| #{category} | #{aspect} | #{length(group)} | #{sum.(:passed)} | " <>
          "#{sum.(:failed)} | #{sum.(:skipped)} | #{if Enum.any?(group, & &1.covered), do: "yes", else: "—"} |"
      end)
      |> Enum.join("\n")

    header <> body <> "\n"
  end

  defp tiers(rows) do
    counts = Enum.frequencies_by(rows, & &1.tier)

    "### Provenance\n\n" <>
      Enum.map_join(["actually_proven", "provisionally_proven", "unproven"], "\n", fn tier ->
        total = Map.get(counts, tier, 0)
        executed = Enum.count(rows, &(&1.tier == tier and &1.passed > 0))
        "- `#{tier}`: #{total} module(s), #{executed} with tests that ran and passed"
      end) <> "\n"
  end

  defp coverage(rows, cells) do
    declared = rows |> Enum.map(&{&1.category, &1.aspect}) |> MapSet.new() |> MapSet.size()
    lattice = 17 * 14

    "### Lattice coverage\n\n" <>
      "- cells covered by executed, passing tests: **#{MapSet.size(cells)} / #{lattice}**\n" <>
      "- cells declared but not exercised in this run: **#{declared - MapSet.size(cells)}**\n" <>
      "- unclaimed cells: **#{lattice - declared}**\n"
  end

  defp honesty(rows) do
    skipped = Enum.reduce(rows, 0, &(&1.skipped + &2))
    failed = Enum.reduce(rows, 0, &(&1.failed + &2))
    unexercised = Enum.count(rows, &(&1.passed == 0))

    "### Honesty\n\n" <>
      "- #{skipped} test(s) skipped at source (`:skip`), #{failed} failed\n" <>
      "- #{unexercised} declared module(s) contributed no passing test to this run\n" <>
      "- a cell is credited only from a test that ran and passed — never from a declaration\n"
  end
end

ProvenSummary.main()
