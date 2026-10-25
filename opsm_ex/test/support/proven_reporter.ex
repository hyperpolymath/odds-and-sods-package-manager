# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# Proven-Tests reporter — an ExUnit event manager.
#
# The framework (hyperpolymath/proven-tests-and-benches) makes one demand of a
# harness above all others: coverage must be *derived from tests that actually
# ran and passed*, never from a declaration. A manifest can claim a cell is
# covered; only this file can show that something ran in it.
#
# So this reporter records, per test module, how many tests passed, failed,
# were skipped or were excluded, and writes that to `proven-report.json`.
# scripts/proven_summary.exs joins it to test/proven_manifest.toml; a cell in
# the 17x14 lattice counts as covered only when `passed > 0 and failed == 0`
# for a module declared at those coordinates.
#
# Enabled by CI only (`OPSM_PROVEN_REPORT=1`), so a developer's `mix test` is
# unchanged and no file is written outside CI.
defmodule Opsm.ProvenReporter do
  @moduledoc false
  use GenServer

  @report "proven-report.json"

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  # ExUnit does NOT call start_link/1 on a formatter. It calls
  # `GenServer.start_link(formatter, opts)` — the low-level starter — which goes
  # straight to `init(opts)` with `opts` being the formatter's options (`[]`
  # here). The first version of this file matched `init(:ok)` only, so every
  # formatter start raised FunctionClauseError, `DynamicSupervisor` dropped the
  # child (restart: :temporary), and ExUnit carried on without a word. The
  # report was never written and nothing failed.
  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def handle_cast({:test_finished, %ExUnit.Test{module: module, state: state, time: time}}, acc) do
    base = %{passed: 0, failed: 0, skipped: 0, total: 0, time_us: 0}
    entry = Map.get(acc, module, base)

    # `{:excluded, _}` means the test never ran (tag-filtered); it is not a
    # test that "did not pass", so it must not enter the denominator either.
    case state do
      nil ->
        {:noreply, Map.put(acc, module, bump(entry, :passed, time))}

      {:skipped, _} ->
        {:noreply, Map.put(acc, module, bump(entry, :skipped, time))}

      {:excluded, _} ->
        {:noreply, acc}

      _other ->
        {:noreply, Map.put(acc, module, bump(entry, :failed, time))}
    end
  end

  # ExUnit casts `{:suite_finished, times_us}`. The first version of this file
  # matched a three-element tuple instead — the shape ExUnit used many releases
  # ago — so this clause never fired, no report was written, and
  # `proven_summary.exs` reported "proven-report.json not found" while the rest
  # of the pipeline looked fine. A reporter that silently reports nothing is
  # worse than no reporter: keep both shapes, and fail loudly if neither fits.
  def handle_cast({:suite_finished, _times_us}, acc), do: finish(acc)
  def handle_cast({:suite_finished, _run_us, _load_us}, acc), do: finish(acc)

  def handle_cast(_event, acc), do: {:noreply, acc}

  defp finish(acc) do
    write_report(acc)
    {:noreply, acc}
  end

  defp bump(entry, key, time) do
    entry
    |> Map.update!(key, &(&1 + 1))
    |> Map.update!(:total, &(&1 + 1))
    |> Map.update!(:time_us, &(&1 + (time || 0)))
  end

  defp write_report(acc) do
    modules =
      acc
      |> Enum.map(fn {module, counts} -> {short_name(module), counts} end)
      |> Enum.sort_by(fn {name, _} -> name end)
      |> Map.new()

    totals =
      Enum.reduce(acc, %{passed: 0, failed: 0, skipped: 0, total: 0, time_us: 0}, fn {_m, c}, t ->
        Map.merge(t, c, fn _k, a, b -> a + b end)
      end)

    payload = %{schema: "opsm.proven-report/1", modules: modules, totals: totals}

    case Jason.encode(payload, pretty: true) do
      {:ok, json} ->
        File.write!(@report, json <> "\n")

        IO.puts(
          "proven-reporter: wrote #{@report} (#{map_size(modules)} modules, #{totals.total} tests)"
        )

      {:error, reason} ->
        # Loud, and with a non-zero exit at the end of the run: a report that
        # could not be written must not be indistinguishable from a clean suite.
        IO.puts(:stderr, "proven-reporter: error: could not encode report: #{inspect(reason)}")
    end
  end

  defp short_name(module) do
    module |> Atom.to_string() |> String.replace_prefix("Elixir.", "")
  end
end
