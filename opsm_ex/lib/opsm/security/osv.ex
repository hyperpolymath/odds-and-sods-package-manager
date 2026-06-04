# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Security.Osv do
  @moduledoc """
  Client for the OSV (Open Source Vulnerabilities) API.

  Queries https://api.osv.dev/v1/query for known CVEs and security advisories
  affecting a given package version and ecosystem.

  OSV aggregates data from GitHub Security Advisories, PyPI Advisory DB,
  RustSec, npm audit, and many other vulnerability databases.
  """

  @osv_api "https://api.osv.dev/v1"
  @timeout_ms 10_000

  # Maps OPSM forth atoms to OSV ecosystem identifiers.
  @forth_to_ecosystem %{
    npm:     "npm",
    cargo:   "crates.io",
    hex:     "Hex",
    pypi:    "PyPI",
    gem:     "RubyGems",
    go:      "Go",
    pub:     "Pub",
    hackage: "Hackage",
    maven:   "Maven",
    nuget:   "NuGet",
    nimble:  "Nim"
  }

  defmodule Vulnerability do
    @moduledoc "A single OSV vulnerability record."
    defstruct [:id, :summary, :severity, :aliases, :fixed_in, :url, :published]

    @type severity :: :critical | :high | :medium | :low | :none | :unknown
    @type t :: %__MODULE__{
      id:        String.t(),
      summary:   String.t() | nil,
      severity:  severity(),
      aliases:   [String.t()],
      fixed_in:  String.t() | nil,
      url:       String.t(),
      published: String.t() | nil
    }
  end

  @doc """
  Query OSV for vulnerabilities affecting `package_name` at `version` in `forth`.

  Returns `{:ok, [Vulnerability.t()]}`. An empty list means no known advisories.
  Returns `{:error, reason}` on network failure (caller should treat as a warning,
  not a hard failure — the OSV API being down must not block installs).
  """
  @spec query(String.t(), String.t(), atom()) :: {:ok, [Vulnerability.t()]} | {:error, term()}
  def query(package_name, version, forth)
      when is_binary(package_name) and is_binary(version) and is_atom(forth) do
    body = %{
      "package" => %{
        "name"      => package_name,
        "ecosystem" => ecosystem_for(forth)
      },
      "version" => version
    }

    post_query(body)
  end

  @doc """
  Query OSV for all advisories for `package_name` in `forth`, regardless of version.

  Useful for the `opsm scan` command when no version is installed yet.
  """
  @spec query_package(String.t(), atom()) :: {:ok, [Vulnerability.t()]} | {:error, term()}
  def query_package(package_name, forth)
      when is_binary(package_name) and is_atom(forth) do
    body = %{
      "package" => %{
        "name"      => package_name,
        "ecosystem" => ecosystem_for(forth)
      }
    }

    post_query(body)
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp ecosystem_for(forth), do: Map.get(@forth_to_ecosystem, forth, to_string(forth))

  defp post_query(body) do
    case Req.post("#{@osv_api}/query",
           json: body,
           receive_timeout: @timeout_ms,
           retry: :transient,
           max_retries: 1
         ) do
      {:ok, %{status: 200, body: %{"vulns" => vulns}}} when is_list(vulns) ->
        {:ok, Enum.map(vulns, &decode_vuln/1)}

      {:ok, %{status: 200}} ->
        {:ok, []}

      {:ok, %{status: status}} ->
        {:error, "OSV API returned HTTP #{status}"}

      {:error, reason} ->
        {:error, "OSV API unavailable: #{inspect(reason)}"}
    end
  end

  defp decode_vuln(json) do
    %Vulnerability{
      id:        json["id"] || "unknown",
      summary:   json["summary"],
      severity:  extract_severity(json),
      aliases:   json["aliases"] || [],
      fixed_in:  extract_fixed_in(json),
      url:       "https://osv.dev/vulnerability/#{json["id"] || "unknown"}",
      published: json["published"]
    }
  end

  # OSV severity is provided in several possible locations. Try each in turn.
  defp extract_severity(%{"database_specific" => %{"severity" => s}}) when is_binary(s),
    do: label_to_severity(s)

  defp extract_severity(%{"severity" => [%{"type" => "CVSS_V3", "score" => s} | _]}),
    do: cvss_score_to_severity(s)

  defp extract_severity(%{"severity" => [%{"type" => "CVSS_V2", "score" => s} | _]}),
    do: cvss_score_to_severity(s)

  defp extract_severity(%{"affected" => [%{"ecosystem_specific" => %{"severity" => s}} | _]})
       when is_binary(s),
    do: label_to_severity(s)

  defp extract_severity(_), do: :unknown

  # CVSS v3 numeric base score interpretation.
  # The OSV API sometimes returns the numeric score directly in database_specific.
  defp cvss_score_to_severity(score) when is_float(score) do
    cond do
      score >= 9.0 -> :critical
      score >= 7.0 -> :high
      score >= 4.0 -> :medium
      score > 0.0  -> :low
      true         -> :none
    end
  end

  defp cvss_score_to_severity(score) when is_binary(score) do
    # CVSS vector strings don't embed the numeric score; fall back to unknown.
    # The numeric score lives in database_specific, which we handle first.
    cond do
      String.contains?(score, "CRITICAL") -> :critical
      String.contains?(score, "HIGH")     -> :high
      String.contains?(score, "MEDIUM")   -> :medium
      String.contains?(score, "LOW")      -> :low
      true                                -> :unknown
    end
  end

  defp cvss_score_to_severity(_), do: :unknown

  defp label_to_severity("CRITICAL"), do: :critical
  defp label_to_severity("HIGH"),     do: :high
  defp label_to_severity("MEDIUM"),   do: :medium
  defp label_to_severity("LOW"),      do: :low
  defp label_to_severity("NONE"),     do: :none
  defp label_to_severity(_),          do: :unknown

  # Extract the first "fixed" version from affected ranges.
  defp extract_fixed_in(%{"affected" => [%{"ranges" => ranges} | _]}) do
    ranges
    |> Enum.flat_map(fn r -> r["events"] || [] end)
    |> Enum.find_value(fn
      %{"fixed" => ver} -> ver
      _                 -> nil
    end)
  end

  defp extract_fixed_in(_), do: nil
end
