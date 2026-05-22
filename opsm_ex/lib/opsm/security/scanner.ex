# SPDX-License-Identifier: MPL-2.0
defmodule Opsm.Security.Scanner do
  @moduledoc """
  Unified security scanner: combines OSV advisory lookup with typosquat detection.

  Called explicitly via `opsm scan <package>` and passively (warn-only) during
  `opsm install`. Network failures from the OSV API are logged as warnings and
  never block installs.
  """

  alias Opsm.Security.Osv
  alias Opsm.Security.Typosquat

  defmodule Report do
    @moduledoc "Aggregated scan result for one package."
    defstruct [:package, :version, :forth, :vulnerabilities, :typosquat, :scanned_at]

    @type t :: %__MODULE__{
      package:         String.t(),
      version:         String.t() | nil,
      forth:           atom(),
      vulnerabilities: [Osv.Vulnerability.t()],
      typosquat:       {:clean} | {:suspicious, [Typosquat.Match.t()]},
      scanned_at:      DateTime.t()
    }

    def critical_count(%__MODULE__{vulnerabilities: vulns}),
      do: Enum.count(vulns, &(&1.severity == :critical))

    def high_count(%__MODULE__{vulnerabilities: vulns}),
      do: Enum.count(vulns, &(&1.severity == :high))

    def has_critical_or_high?(%__MODULE__{} = r),
      do: critical_count(r) > 0 or high_count(r) > 0

    def clean?(%__MODULE__{vulnerabilities: [], typosquat: {:clean}}), do: true
    def clean?(_), do: false
  end

  @doc """
  Scan a package by name + version + forth.

  When `version` is nil, queries OSV for all known advisories regardless of version.
  Always performs typosquat detection regardless of version.

  Returns `{:ok, Report.t()}`. OSV failures produce an empty vulnerability list
  (logged at warning level) so installs are never hard-blocked by API downtime.
  """
  @spec scan(String.t(), atom(), keyword()) :: {:ok, Report.t()}
  def scan(package, forth, opts \\ []) when is_binary(package) and is_atom(forth) do
    version = Keyword.get(opts, :version)

    vulns =
      case osv_query(package, version, forth) do
        {:ok, list}     -> list
        {:error, reason} ->
          require Logger
          Logger.warning("OSV lookup failed for #{package}: #{inspect(reason)}")
          []
      end

    typosquat = Typosquat.check(package, forth)

    report = %Report{
      package:         package,
      version:         version,
      forth:           forth,
      vulnerabilities: vulns,
      typosquat:       typosquat,
      scanned_at:      DateTime.utc_now()
    }

    {:ok, report}
  end

  @doc """
  Scan an already-resolved package (used during install).

  Returns `{:ok, Report.t()}`. Callers decide whether to block or warn based on
  the report's severity counts.
  """
  @spec scan_resolved(String.t(), String.t(), atom()) :: {:ok, Report.t()}
  def scan_resolved(package, version, forth)
      when is_binary(package) and is_binary(version) and is_atom(forth) do
    scan(package, forth, version: version)
  end

  @doc """
  Print a human-readable summary of a scan report to stdout.
  """
  @spec print_report(Report.t()) :: :ok
  def print_report(%Report{} = r) do
    IO.puts("")
    IO.puts("Security scan: #{r.package}#{if r.version, do: "@#{r.version}", else: ""} (@#{r.forth})")
    IO.puts(String.duplicate("─", 60))

    case r.typosquat do
      {:clean} ->
        IO.puts("  Typosquat:  clean")

      {:suspicious, matches} ->
        IO.puts("  Typosquat:  ⚠ SUSPICIOUS — name resembles known package(s):")
        for m <- matches do
          tag = case m.similarity do
            :edit_distance_1 -> "1 edit away from"
            :edit_distance_2 -> "2 edits away from"
            :homoglyph       -> "homoglyph of"
          end
          IO.puts("              #{tag} '#{m.package}'")
        end
    end

    if r.vulnerabilities == [] do
      IO.puts("  OSV vulns:  ✓ none found")
    else
      sev_order = [:critical, :high, :medium, :low, :none, :unknown]
      sorted = Enum.sort_by(r.vulnerabilities, &Enum.find_index(sev_order, fn s -> s == &1.severity end))

      IO.puts("  OSV vulns:  #{length(r.vulnerabilities)} advisory/ies")
      IO.puts("")

      for v <- sorted do
        sev_label = severity_label(v.severity)
        aliases = if v.aliases != [], do: " (#{Enum.join(v.aliases, ", ")})", else: ""
        IO.puts("  #{sev_label} #{v.id}#{aliases}")
        if v.summary, do: IO.puts("    #{v.summary}")
        if v.fixed_in, do: IO.puts("    Fix: upgrade to #{v.fixed_in}")
        IO.puts("    #{v.url}")
        IO.puts("")
      end
    end

    IO.puts("")
    :ok
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp osv_query(package, nil, forth),
    do: Osv.query_package(package, forth)

  defp osv_query(package, version, forth),
    do: Osv.query(package, version, forth)

  defp severity_label(:critical), do: "[CRIT]"
  defp severity_label(:high),     do: "[HIGH]"
  defp severity_label(:medium),   do: "[MED] "
  defp severity_label(:low),      do: "[LOW] "
  defp severity_label(:none),     do: "[NONE]"
  defp severity_label(_),         do: "[?]   "
end
