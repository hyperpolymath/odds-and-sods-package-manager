# SPDX-License-Identifier: MPL-2.0
defmodule Opsm.Security.SecurityTest do
  use ExUnit.Case, async: true

  alias Opsm.Security.Typosquat
  alias Opsm.Security.Scanner
  alias Opsm.Security.Osv

  # ---------------------------------------------------------------------------
  # Typosquat.edit_distance/2
  # ---------------------------------------------------------------------------

  describe "Typosquat.edit_distance/2" do
    test "identical strings have distance 0" do
      assert Typosquat.edit_distance("lodash", "lodash") == 0
    end

    test "single character substitution: distance 1" do
      assert Typosquat.edit_distance("lodash", "1odash") == 1
    end

    test "single character insertion: distance 1" do
      assert Typosquat.edit_distance("lodash", "lodassh") == 1
    end

    test "single character deletion: distance 1" do
      assert Typosquat.edit_distance("express", "expres") == 1
    end

    test "transposition counts as 2 edits (substitute+substitute)" do
      # 'od' -> 'do' requires 2 substitutions in standard Levenshtein
      assert Typosquat.edit_distance("lodash", "oldash") == 2
    end

    test "completely different short strings" do
      assert Typosquat.edit_distance("abc", "xyz") == 3
    end

    test "empty vs non-empty" do
      assert Typosquat.edit_distance("", "abc") == 3
      assert Typosquat.edit_distance("abc", "") == 3
    end

    test "length difference > 3 short-circuits to 99" do
      assert Typosquat.edit_distance("abc", "abcdefgh") == 99
    end

    test "two-character difference in medium names" do
      assert Typosquat.edit_distance("request", "reuqest") == 2
    end
  end

  # ---------------------------------------------------------------------------
  # Typosquat.check/2
  # ---------------------------------------------------------------------------

  describe "Typosquat.check/2" do
    test "exact match to known package is clean (not flagged)" do
      # The package IS lodash — not a typosquat of itself
      assert {:clean} = Typosquat.check("lodash", :npm)
    end

    test "clearly unrelated package name is clean" do
      assert {:clean} = Typosquat.check("completely-unrelated-xyzzyx", :npm)
    end

    test "1-character edit of popular npm package is suspicious" do
      # 'Iodash' (capital I → l homoglyph) or 'lodaash' (extra a)
      assert {:suspicious, matches} = Typosquat.check("lodaash", :npm)
      assert Enum.any?(matches, fn m -> m.package == "lodash" end)
    end

    test "homoglyph substitution is detected" do
      # l0dash (zero instead of 'o')
      assert {:suspicious, matches} = Typosquat.check("l0dash", :npm)
      assert Enum.any?(matches, fn m -> m.package == "lodash" and m.similarity == :homoglyph end)
    end

    test "dash-stripped homoglyph is detected" do
      # 'lo-dash' vs 'lodash' (dash stripped in normalisation)
      assert {:suspicious, matches} = Typosquat.check("lo-dash", :npm)
      assert Enum.any?(matches, fn m -> m.package == "lodash" end)
    end

    test "unknown ecosystem returns :clean (no known list)" do
      assert {:clean} = Typosquat.check("lodash", :betlang)
    end

    test "cargo ecosystem checks cargo packages" do
      assert {:suspicious, matches} = Typosquat.check("serd", :cargo)
      assert Enum.any?(matches, fn m -> m.package == "serde" end)
    end

    test "pypi ecosystem checks pypi packages" do
      assert {:suspicious, matches} = Typosquat.check("requets", :pypi)
      assert Enum.any?(matches, fn m -> m.package == "requests" end)
    end

    test "short names (<=3 chars) do not trigger edit_distance_1 checks" do
      # 'rx' is 1 edit from 'js' — should not trigger since name length <= 3
      # (but it IS in the list as 'rxjs' so won't match 'rx' anyway)
      assert {:clean} = Typosquat.check("rx", :npm)
    end

    test "Match struct contains similarity and package fields" do
      {:suspicious, [match | _]} = Typosquat.check("lodaash", :npm)
      assert is_binary(match.package)
      assert match.similarity in [:edit_distance_1, :edit_distance_2, :homoglyph]
    end
  end

  # ---------------------------------------------------------------------------
  # Osv.Vulnerability struct
  # ---------------------------------------------------------------------------

  describe "Osv.Vulnerability" do
    test "struct has expected fields" do
      v = %Osv.Vulnerability{
        id: "GHSA-abc-123",
        summary: "Test vuln",
        severity: :high,
        aliases: ["CVE-2024-0001"],
        fixed_in: "1.2.3",
        url: "https://osv.dev/vulnerability/GHSA-abc-123",
        published: "2024-01-01T00:00:00Z"
      }
      assert v.id == "GHSA-abc-123"
      assert v.severity == :high
      assert v.aliases == ["CVE-2024-0001"]
      assert v.fixed_in == "1.2.3"
    end
  end

  # ---------------------------------------------------------------------------
  # Scanner (offline — no network calls)
  # ---------------------------------------------------------------------------

  describe "Scanner.Report" do
    test "clean? returns true for empty vulns and clean typosquat" do
      report = %Scanner.Report{
        package: "lodash",
        version: "4.17.21",
        forth: :npm,
        vulnerabilities: [],
        typosquat: {:clean},
        scanned_at: DateTime.utc_now()
      }
      assert Scanner.Report.clean?(report)
    end

    test "clean? returns false when vulnerabilities present" do
      vuln = %Osv.Vulnerability{
        id: "GHSA-test",
        summary: "test",
        severity: :medium,
        aliases: [],
        fixed_in: nil,
        url: "https://osv.dev/vulnerability/GHSA-test",
        published: nil
      }
      report = %Scanner.Report{
        package: "test-pkg",
        version: "1.0.0",
        forth: :npm,
        vulnerabilities: [vuln],
        typosquat: {:clean},
        scanned_at: DateTime.utc_now()
      }
      refute Scanner.Report.clean?(report)
    end

    test "clean? returns false for suspicious typosquat" do
      report = %Scanner.Report{
        package: "lodaash",
        version: nil,
        forth: :npm,
        vulnerabilities: [],
        typosquat: {:suspicious, [%Typosquat.Match{package: "lodash", similarity: :edit_distance_1, flags: []}]},
        scanned_at: DateTime.utc_now()
      }
      refute Scanner.Report.clean?(report)
    end

    test "critical_count and high_count aggregate correctly" do
      vulns = [
        %Osv.Vulnerability{id: "A", summary: nil, severity: :critical, aliases: [], fixed_in: nil, url: "", published: nil},
        %Osv.Vulnerability{id: "B", summary: nil, severity: :high, aliases: [], fixed_in: nil, url: "", published: nil},
        %Osv.Vulnerability{id: "C", summary: nil, severity: :medium, aliases: [], fixed_in: nil, url: "", published: nil},
        %Osv.Vulnerability{id: "D", summary: nil, severity: :critical, aliases: [], fixed_in: nil, url: "", published: nil}
      ]
      report = %Scanner.Report{
        package: "pkg",
        version: "1.0.0",
        forth: :npm,
        vulnerabilities: vulns,
        typosquat: {:clean},
        scanned_at: DateTime.utc_now()
      }
      assert Scanner.Report.critical_count(report) == 2
      assert Scanner.Report.high_count(report) == 1
      assert Scanner.Report.has_critical_or_high?(report)
    end

    test "has_critical_or_high? is false for only medium/low vulns" do
      vulns = [
        %Osv.Vulnerability{id: "A", summary: nil, severity: :medium, aliases: [], fixed_in: nil, url: "", published: nil},
        %Osv.Vulnerability{id: "B", summary: nil, severity: :low, aliases: [], fixed_in: nil, url: "", published: nil}
      ]
      report = %Scanner.Report{
        package: "pkg",
        version: "1.0.0",
        forth: :npm,
        vulnerabilities: vulns,
        typosquat: {:clean},
        scanned_at: DateTime.utc_now()
      }
      refute Scanner.Report.has_critical_or_high?(report)
    end
  end

  describe "Scanner.scan/3 (offline — skips OSV network call gracefully)" do
    @tag :skip
    test "network unavailable produces empty vuln list and still runs typosquat" do
      # This test uses Bypass or a mock; skip in default run.
      # The rescue block in Scanner.scan/3 ensures OSV failure is non-fatal.
    end

    test "scan of suspicious name still detects typosquat without network" do
      # We patch the OSV call by relying on the fact that it will fail offline
      # and the scanner falls back gracefully. We only assert on typosquat.
      # Note: if network IS available, OSV may return real results; that's fine.
      {:ok, report} = Scanner.scan("lodaash", :npm)
      assert match?({:suspicious, _}, report.typosquat)
      assert is_list(report.vulnerabilities)
    end

    test "scan returns a Report struct with expected fields" do
      {:ok, report} = Scanner.scan("test-pkg-xyzzyx", :hex)
      assert %Scanner.Report{} = report
      assert report.package == "test-pkg-xyzzyx"
      assert report.forth == :hex
      assert is_list(report.vulnerabilities)
      assert match?({:clean}, report.typosquat) or match?({:suspicious, _}, report.typosquat)
      assert %DateTime{} = report.scanned_at
    end

    test "scan with version option is recorded in report" do
      {:ok, report} = Scanner.scan("some-pkg-xyzzyx", :cargo, version: "1.2.3")
      assert report.version == "1.2.3"
    end

    test "print_report/1 writes to stdout without crashing" do
      report = %Scanner.Report{
        package: "test-pkg",
        version: "1.0.0",
        forth: :npm,
        vulnerabilities: [],
        typosquat: {:clean},
        scanned_at: DateTime.utc_now()
      }
      assert :ok = Scanner.print_report(report)
    end
  end
end
