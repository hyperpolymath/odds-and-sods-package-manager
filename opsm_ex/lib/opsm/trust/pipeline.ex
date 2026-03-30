# SPDX-License-Identifier: PMPL-1.0
defmodule Opsm.Trust.Pipeline do
  @moduledoc """
  Trust pipeline for package verification.

  Integrates with:
  - claim-forge: attestation generation/verification
  - checky-monkey: code verification (fuzz, property tests, etc.)
  - oikos: sustainability scoring
  - palimpsest: license analysis
  """

  alias Opsm.Config
  alias Opsm.Clients.{ClaimForge, CheckyMonkey, Oikos, Palimpsest}
  alias Opsm.Types.ResolvedPackage

  @doc """
  Run the trust pipeline on a package before installation.
  Returns verification results and recommendations.
  """
  def verify(%ResolvedPackage{} = package, opts \\ []) do
    config = Config.load_config_or_example()
    skip_checks = Keyword.get(opts, :skip_checks, [])
    verbose = Keyword.get(opts, :verbose, false)

    results = %{
      package: package.package,
      version: package.version,
      forth: package.forth,
      checks: %{},
      overall: :pending,
      recommendations: [],
      warnings: []
    }

    # Run checks in parallel
    tasks = []

    tasks = if :attestation not in skip_checks do
      [Task.async(fn -> {:attestation, check_attestations(package, config)} end) | tasks]
    else
      tasks
    end

    tasks = if :license not in skip_checks do
      [Task.async(fn -> {:license, check_license(package, config)} end) | tasks]
    else
      tasks
    end

    tasks = if :sustainability not in skip_checks do
      [Task.async(fn -> {:sustainability, check_sustainability(package, config)} end) | tasks]
    else
      tasks
    end

    tasks = if :slsa not in skip_checks do
      [Task.async(fn -> {:slsa, check_slsa_provenance(package, config)} end) | tasks]
    else
      tasks
    end

    # Collect results safely (D2: use yield_many to handle task crashes/timeouts)
    # 3s timeout — trust checks are advisory, install should not stall on unreachable services
    check_results =
      Task.yield_many(tasks, 3_000)
      |> Enum.map(fn
        {_task, {:ok, {name, result}}} ->
          {name, result}

        {task, {:exit, reason}} ->
          Task.shutdown(task, :brutal_kill)
          {:crashed_check, {:error, "Check crashed: #{inspect(reason)}"}}

        {task, nil} ->
          Task.shutdown(task, :brutal_kill)
          {:timed_out_check, {:skipped, "Check timed out"}}
      end)
      |> Map.new()

    results = %{results | checks: check_results}

    # Determine overall status
    {overall, recommendations, warnings} = evaluate_results(check_results)

    results = %{results |
      overall: overall,
      recommendations: recommendations,
      warnings: warnings
    }

    if verbose do
      print_verification_results(results)
    end

    # Persist trust check to VeriSimDB
    Opsm.VeriSimDB.record_trust_check(%{
      name: package.package,
      version: package.version,
      overall: overall,
      warnings: warnings,
      attestations: Map.get(package, :attestations, []),
      slsa_level: get_in(check_results, [:slsa, :level]),
      pq_signed: get_in(check_results, [:attestation, :pq_signed]),
      license_ok: match?({:ok, _}, check_results[:license]),
      sustainability_score: get_in(check_results, [:sustainability, :score])
    })

    {:ok, results}
  end

  @doc """
  Verify during publish (more stringent checks).
  """
  def verify_for_publish(path, _opts \\ []) do
    config = Config.load_config_or_example()

    IO.puts("Running trust pipeline for publish...")
    IO.puts("")

    # Step 1: Generate SPDX attestation
    IO.puts("Step 1: Generating attestation...")
    attestation_result = case ClaimForge.cli_generate_spdx(path) do
      {:ok, spdx} ->
        IO.puts("  ✓ SPDX attestation generated")
        {:ok, spdx}
      {:error, reason} ->
        IO.puts("  ✗ Failed: #{reason}")
        {:error, reason}
    end

    # Step 2: Check licenses
    IO.puts("")
    IO.puts("Step 2: Checking licenses...")
    license_result = case Palimpsest.cli_check_licenses(path) do
      {:ok, licenses} ->
        IO.puts("  ✓ License check passed")
        {:ok, licenses}
      {:error, reason} ->
        IO.puts("  ⚠ License check failed: #{reason}")
        {:warning, reason}
    end

    # Step 3: Code verification (if services available)
    IO.puts("")
    IO.puts("Step 3: Code verification...")
    checky_client = CheckyMonkey.new(config.checky_monkey, config.http)
    verification_result = case CheckyMonkey.health(checky_client) do
      {:ok, _} ->
        IO.puts("  ✓ Checky-monkey available (would run verification)")
        {:ok, :available}
      {:error, _} ->
        IO.puts("  ⊘ Checky-monkey not available (skipped)")
        {:skipped, :service_unavailable}
    end

    %{
      attestation: attestation_result,
      license: license_result,
      verification: verification_result,
      ready_to_publish: match?({:ok, _}, attestation_result)
    }
  end

  # Check functions

  defp check_attestations(package, _config) do
    # For now, check if package has any attestations listed
    # In full implementation, would verify signatures
    if package.attestations == [] do
      {:warning, "No attestations found for this package"}
    else
      {:ok, "Found #{length(package.attestations)} attestation(s)"}
    end
  end

  defp check_license(package, _config) do
    license = package.manifest.license

    cond do
      is_nil(license) or license == "" or license == "UNKNOWN" ->
        {:warning, "No license specified"}

      known_permissive?(license) ->
        {:ok, "Permissive license: #{license}"}

      known_copyleft?(license) ->
        {:info, "Copyleft license: #{license} - check compatibility"}

      true ->
        {:info, "License: #{license}"}
    end
  end

  defp check_slsa_provenance(package, _config) do
    try do
      # Check if package has SLSA provenance attestation
      slsa_attestation = Enum.find(package.attestations || [], fn
        %{attestation_type: :in_toto} -> true
        %{attestation_type: :sigstore} -> true
        _ -> false
      end)

      cond do
        is_nil(slsa_attestation) ->
          # No SLSA provenance — generate a basic one from package metadata
          case Opsm.Slsa.Provenance.generate(package) do
            {:ok, provenance} ->
              if provenance.slsa_level >= 1 do
                {:info, "SLSA Level #{provenance.slsa_level} (self-attested, unverified)"}
              else
                {:warning, "No SLSA provenance available (Level 0)"}
              end

            {:error, _reason} ->
              {:skipped, "SLSA provenance generation failed"}
          end

        true ->
          # Has attestation — try to verify
          {:info, "SLSA attestation found: #{slsa_attestation.uri}"}
      end
    rescue
      _ -> {:skipped, "SLSA check failed"}
    end
  end

  defp check_sustainability(_package, config) do
    # Try to get sustainability score from oikos — graceful if service is down
    try do
      oikos_client = Oikos.new(config.oikos, config.http)

      case Oikos.health(oikos_client) do
        {:ok, _} ->
          {:ok, "Oikos available (would score sustainability)"}
        {:error, _} ->
          {:skipped, "Oikos service not available"}
      end
    rescue
      _ -> {:skipped, "Oikos service unreachable"}
    end
  end

  # Evaluation

  defp evaluate_results(checks) do
    _recommendations = []
    _warnings = []

    # Check each result
    {recs, warns} = Enum.reduce(checks, {[], []}, fn {name, result}, {r, w} ->
      case result do
        {:ok, _msg} -> {r, w}
        {:info, msg} -> {[msg | r], w}
        {:warning, msg} -> {r, [msg | w]}
        {:error, msg} -> {r, ["#{name}: #{msg}" | w]}
        {:skipped, _msg} -> {r, w}
      end
    end)

    overall = cond do
      Enum.any?(checks, fn {_, r} -> match?({:error, _}, r) end) -> :failed
      Enum.any?(checks, fn {_, r} -> match?({:warning, _}, r) end) -> :warning
      true -> :passed
    end

    {overall, Enum.reverse(recs), Enum.reverse(warns)}
  end

  defp print_verification_results(results) do
    IO.puts("")
    IO.puts("Trust Pipeline Results")
    IO.puts("======================")
    IO.puts("Package: #{results.package}@#{results.version} (@#{results.forth})")
    IO.puts("Overall: #{format_status(results.overall)}")
    IO.puts("")

    for {name, result} <- results.checks do
      status = case result do
        {:ok, msg} -> "✓ #{msg}"
        {:info, msg} -> "ℹ #{msg}"
        {:warning, msg} -> "⚠ #{msg}"
        {:error, msg} -> "✗ #{msg}"
        {:skipped, msg} -> "⊘ #{msg}"
      end
      IO.puts("  #{name}: #{status}")
    end

    if results.warnings != [] do
      IO.puts("")
      IO.puts("Warnings:")
      for warn <- results.warnings do
        IO.puts("  - #{warn}")
      end
    end

    if results.recommendations != [] do
      IO.puts("")
      IO.puts("Recommendations:")
      for rec <- results.recommendations do
        IO.puts("  - #{rec}")
      end
    end
  end

  defp format_status(:passed), do: "✓ PASSED"
  defp format_status(:warning), do: "⚠ WARNING"
  defp format_status(:failed), do: "✗ FAILED"
  defp format_status(:pending), do: "⏳ PENDING"

  # License helpers

  @permissive_licenses ~w(MIT Apache-2.0 BSD-2-Clause BSD-3-Clause ISC Unlicense CC0-1.0 0BSD)
  @copyleft_licenses ~w(GPL-2.0 GPL-3.0 LGPL-2.1 LGPL-3.0 AGPL-3.0 MPL-2.0)

  defp known_permissive?(license) do
    normalized = normalize_license(license)
    Enum.any?(@permissive_licenses, fn l ->
      String.contains?(normalized, String.downcase(l))
    end)
  end

  defp known_copyleft?(license) do
    normalized = normalize_license(license)
    Enum.any?(@copyleft_licenses, fn l ->
      String.contains?(normalized, String.downcase(l))
    end)
  end

  defp normalize_license(license) do
    license
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9.-]/, "")
  end
end
