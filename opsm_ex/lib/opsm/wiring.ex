# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule Opsm.Wiring do
  @moduledoc """
  Command orchestration - wires together service clients for publish, audit, status flows.
  """

  require Logger

  alias Opsm.Clients.{CicdHyperA, CheckyMonkey, ClaimForge, Oikos, Palimpsest}
  alias Opsm.{Errors, ManifestIngestion}
  alias Opsm.Types.{
    OpsmConfig,
    ClaimForgeRequest,
    CheckyMonkeyRequest,
    CicdPublishRequest,
    PackageMetadata,
    AttestationRef,
    PalimpsestRequest,
    OikosAnalysisRequest
  }

  # =============================================================================
  # Status
  # =============================================================================

  def run_status(%OpsmConfig{} = config) do
    clients = [
      {"oikos", Oikos.new(config.oikos, config.http), &Oikos.health/1},
      {"checky-monkey", CheckyMonkey.new(config.checky_monkey, config.http), &CheckyMonkey.health/1},
      {"claim-forge", ClaimForge.new(config.claim_forge, config.http), &ClaimForge.health/1},
      {"palimpsest-license", Palimpsest.new(config.palimpsest_license, config.http), &Palimpsest.health/1},
      {"cicd-hyper-a", CicdHyperA.new(config.cicd_hyper_a, config.http), &CicdHyperA.health/1}
    ]

    IO.puts("OPSM Service Status")
    IO.puts("==================")

    Enum.each(clients, fn {name, client, health_fn} ->
      print_status(name, check_health(client, health_fn))
    end)

    IO.puts("")
    IO.puts("Configuration")
    IO.puts("-------------")
    IO.puts("claim-forge: #{config.claim_forge.base_url}")
    IO.puts("checky-monkey: #{config.checky_monkey.base_url}")
    IO.puts("palimpsest-license: #{config.palimpsest_license.base_url}")
    IO.puts("cicd-hyper-a: #{config.cicd_hyper_a.base_url}")
    IO.puts("oikos: #{config.oikos.base_url}")

    :ok
  end

  # =============================================================================
  # Publish
  # =============================================================================

  def run_publish(%OpsmConfig{} = config, path) do
    IO.puts("Publishing package from: #{path}")
    IO.puts("")

    with {:ok, ingestion} <- ManifestIngestion.ingest(path),
         {:ok, claim_response} <- generate_attestation(config, ingestion.manifest_path, ingestion.digest),
         {:ok, _license_result} <- run_license_check(config, ingestion.manifest_path, ingestion.manifest),
         :ok <- run_sustainability_check(config, ingestion.manifest),
         :ok <- validate_publish_metadata(ingestion.manifest),
         {:ok, publish_response} <-
           publish_manifest(config, ingestion.manifest, ingestion.tarball_url, ingestion.digest, claim_response) do
      maybe_run_checky(config, ingestion.manifest_path)
      IO.puts("")
      print_publish_summary(ingestion.manifest, publish_response)
      {:ok, publish_response}
    else
      {:error, reason} ->
        IO.puts("  ✗ Publish pipeline failed: #{reason}")
        {:error, reason}
    end
  end

  # =============================================================================
  # Audit
  # =============================================================================

  def run_audit(%OpsmConfig{} = config, package) do
    IO.puts("Auditing package: #{package}")
    IO.puts("")

    oikos_client = Oikos.new(config.oikos, config.http)
    analysis_request = %OikosAnalysisRequest{repository_url: package, branch: nil, commit_sha: nil}

    case Oikos.analyze_repository(oikos_client, analysis_request) do
      {:ok, resp} ->
        IO.puts("Sustainability Analysis (oikos)")
        IO.puts("--------------------------------")
        print_oikos_summary(resp)
      {:error, reason} ->
        IO.puts("Sustainability Analysis (oikos)")
        IO.puts("--------------------------------")
        IO.puts("  ⚠ Failed to analyze #{package}: #{reason}")
    end

    IO.puts("")
    IO.puts("License Analysis (palimpsest)")
    IO.puts("-----------------------------")

    artifact_path = if File.exists?(package), do: package, else: File.cwd!()
    palimpsest_client = Palimpsest.new(config.palimpsest_license, config.http)
    request = %PalimpsestRequest{artifact_path: artifact_path, include_transitive: true, target_license: nil}

    case Palimpsest.analyze(palimpsest_client, request) do
      {:ok, resp} ->
        IO.puts("  ✓ Detected #{length(resp.detected_licenses || [])} licenses")
        compat = resp.compatibility
        status = if compat.compatible, do: "compatible", else: "conflicts"
        IO.puts("  ✓ Compatibility: #{status}")
        if not compat.compatible do
          for conflict <- compat.conflicts || [] do
            IO.puts("    - #{conflict.license1} vs #{conflict.license2}: #{conflict.reason}")
          end
        end
      {:error, reason} ->
        IO.puts("  ⚠ License service unavailable: #{reason}")
    end

    {:ok, "Audit completed"}
  end

  # =============================================================================
  # Helpers
  # =============================================================================

  defp generate_attestation(config, manifest_path, digest) do
    client = ClaimForge.new(config.claim_forge, config.http)

    request = %ClaimForgeRequest{
      artifact_path: manifest_path,
      artifact_digest: digest,
      claim_type: :build_provenance,
      metadata: %{"source" => "opsm", "artifact" => Path.basename(manifest_path)}
    }

    ClaimForge.generate_attestation(client, request)
  end

  defp run_license_check(config, manifest_path, manifest) do
    client = Palimpsest.new(config.palimpsest_license, config.http)
    artifact_dir = Path.dirname(manifest_path)

    request = %PalimpsestRequest{
      artifact_path: artifact_dir,
      include_transitive: true,
      target_license: manifest.license
    }

    case Palimpsest.analyze(client, request) do
      {:ok, resp} ->
        compat = resp.compatibility

        if compat.compatible do
          IO.puts("  ✓ License compatibility: #{manifest.license || "unspecified"}")
          {:ok, resp}
        else
          conflict_list =
            compat.conflicts
            |> Enum.map(fn conflict -> "#{conflict.license1} vs #{conflict.license2}" end)
            |> Enum.join(", ")

          error_type = {:license_conflict, conflict_list}
          severity = Errors.classify_severity(error_type)

          IO.puts("  ✗ #{Errors.severity_description(severity)}")
          IO.puts("    License conflicts detected: #{conflict_list}")

          # License conflicts are HARD_FAIL - block publication
          {:error, "License conflicts detected: #{conflict_list}"}
        end

      {:error, reason} ->
        # Service unavailable is SOFT_FAIL - allow with warning
        severity = Errors.classify_severity({:network_error, reason})
        IO.puts("  ⚠ #{Errors.severity_description(severity)}")
        IO.puts("    License analysis unavailable: #{reason}")
        {:ok, :skipped}
    end
  end

  # Run oikos sustainability analysis during publish.
  # This is advisory — a low score warns but does not block publication.
  # A missing oikos service is a soft-fail (the publish continues).
  defp run_sustainability_check(config, manifest) do
    oikos_client = Oikos.new(config.oikos, config.http)
    repo_url = manifest.repository

    case Oikos.analyze_package(oikos_client, manifest.name, manifest.version,
           repository_url: repo_url,
           forth: :unknown
         ) do
      {:ok, score} when is_integer(score) and score >= 40 ->
        IO.puts("  ✓ Sustainability score: #{score}/100")
        :ok

      {:ok, score} when is_integer(score) ->
        IO.puts("  ⚠ Low sustainability score: #{score}/100 — consider improving before publish")
        :ok

      {:error, reason} ->
        severity = Errors.classify_severity({:network_error, reason})
        IO.puts("  ⚠ #{Errors.severity_description(severity)}")
        IO.puts("    Sustainability analysis unavailable: #{inspect(reason)}")
        :ok
    end
  end

  # Validate that the manifest has required fields before attempting to publish.
  # Catches common issues like missing name, missing version, or placeholder values.
  defp validate_publish_metadata(manifest) do
    errors = []

    errors =
      if is_nil(manifest.name) or manifest.name == "",
        do: ["Package name is required" | errors],
        else: errors

    errors =
      if is_nil(manifest.version) or manifest.version == "" or manifest.version == "0.0.0",
        do: ["Package version is required (found: #{inspect(manifest.version)})" | errors],
        else: errors

    case errors do
      [] -> :ok
      _ ->
        combined = Enum.join(errors, "; ")
        {:error, "Publish metadata validation failed: #{combined}"}
    end
  end

  defp publish_manifest(config, manifest, tarball_url, digest, claim_response) do
    client = CicdHyperA.new(config.cicd_hyper_a, config.http)

    request = %CicdPublishRequest{
      manifest: package_metadata_from_manifest(manifest),
      tarball_url: tarball_url,
      attestations: [
        %AttestationRef{
          attestation_type: :claim_forge,
          uri: claim_response.attestation_uri,
          digest: digest
        }
      ]
    }

    CicdHyperA.publish(client, request)
  end

  defp package_metadata_from_manifest(manifest) do
    %PackageMetadata{
      name: manifest.name,
      version: manifest.version || "0.0.0",
      description: manifest.description,
      license: manifest.license || "UNKNOWN",
      repository: manifest.repository,
      authors: manifest.authors || [],
      keywords: manifest.keywords || [],
      dependencies: manifest.dependencies || %{},
      dev_dependencies: manifest.dev_dependencies || %{}
    }
  end

  defp maybe_run_checky(config, manifest_path) do
    dir = project_directory(manifest_path)

    case git_metadata(dir) do
      {:ok, %{repo_url: repo_url, commit_sha: commit_sha}} ->
        client = CheckyMonkey.new(config.checky_monkey, config.http)

        request = %CheckyMonkeyRequest{
          repository_url: repo_url,
          commit_sha: commit_sha,
          verification_types: [:property_tests, :type_checking],
          timeout: 600
        }

        case CheckyMonkey.submit_verification(client, request) do
          {:ok, resp} ->
            IO.puts("  ✓ Checky-monkey request queued: #{resp.request_id}")
            wait_for_verification(config, client, resp.request_id, timeout: 60_000)

          {:error, reason} ->
            IO.puts("  ⚠ Checky-monkey submission failed: #{reason}")
            {:error, reason}
        end

      {:error, reason} ->
        IO.puts("  ⚠ Checky-monkey skipped: #{reason}")
        {:ok, :skipped}
    end
  end

  defp wait_for_verification(_config, client, request_id, opts) do
    timeout = Keyword.get(opts, :timeout, 60_000)
    poll_interval = 5_000
    max_attempts = div(timeout, poll_interval)

    IO.puts("  ⏳ Polling checky-monkey for results (timeout: #{timeout}ms)...")

    do_poll_verification(client, request_id, max_attempts, poll_interval)
  end

  defp do_poll_verification(_client, _request_id, 0, _interval) do
    IO.puts("  ⚠ Checky-monkey verification timed out")
    {:error, :timeout}
  end

  defp do_poll_verification(client, request_id, attempts_left, interval) do
    case CheckyMonkey.get_verification_status(client, request_id) do
      {:ok, %{status: :completed, results: results}} ->
        IO.puts("  ✓ Checky-monkey verification completed")
        print_verification_results(results)
        {:ok, results}

      {:ok, %{status: :failed} = response} ->
        error = Map.get(response, :error, "Verification failed")
        IO.puts("  ✗ Checky-monkey verification failed: #{error}")
        {:error, error}

      {:ok, %{status: status}} when status in [:queued, :running] ->
        Process.sleep(interval)
        do_poll_verification(client, request_id, attempts_left - 1, interval)

      {:error, :not_found} ->
        IO.puts("  ⚠ Checky-monkey request not found: #{request_id}")
        {:error, :not_found}

      {:error, reason} ->
        IO.puts("  ⚠ Checky-monkey polling failed: #{reason}")
        {:error, reason}
    end
  end

  defp print_verification_results(results) when is_map(results) do
    IO.puts("  Verification results:")

    if results[:property_tests] do
      IO.puts("    property tests: #{results.property_tests.status}")
      if results.property_tests.tests_passed do
        IO.puts("      passed: #{results.property_tests.tests_passed}")
      end
    end

    if results[:type_checking] do
      IO.puts("    type checking: #{results.type_checking.status}")
      if results.type_checking.errors do
        IO.puts("      errors: #{length(results.type_checking.errors)}")
      end
    end
  end

  defp print_verification_results(_results), do: :ok

  defp git_metadata(dir) do
    case Opsm.SafeExec.cmd("git", ["-C", dir, "rev-parse", "HEAD"], stderr_to_stdout: true) do
      {commit, 0} ->
        case Opsm.SafeExec.cmd("git", ["-C", dir, "remote", "get-url", "origin"], stderr_to_stdout: true) do
          {url, 0} ->
            {:ok, %{repo_url: String.trim(url), commit_sha: String.trim(commit)}}

          {error, _} ->
            {:error, "git remote error: #{String.trim(error)}"}
        end

      {error, _} ->
        {:error, "git rev-parse failed: #{String.trim(error)}"}
    end
  rescue
    e in ErlangError ->
      {:error, "git unavailable: #{Exception.message(e)}"}
  end

  defp project_directory(path) do
    expanded = Path.expand(path)
    if File.dir?(expanded), do: expanded, else: Path.dirname(expanded)
  end

  defp print_publish_summary(manifest, publish_response) do
    IO.puts("Publish summary")
    IO.puts("---------------")
    IO.puts("  package: #{manifest.name}@#{manifest.version}")
    IO.puts("  registryUrl: #{publish_response.registry_url}")
    IO.puts("  publishedAt: #{publish_response.published_at}")

    if publish_response.federation_status do
      IO.puts("  federation:")

      Enum.each(
        [
          {"github", publish_response.federation_status.github},
          {"gitlab", publish_response.federation_status.gitlab},
          {"codeberg", publish_response.federation_status.codeberg},
          {"radicle", publish_response.federation_status.radicle},
          {"ipfs", publish_response.federation_status.ipfs}
        ],
        fn
          {_name, nil} ->
            :ok

          {name, state} ->
            status = if state.synced, do: "synced", else: "pending"
            info = if state.error, do: " (#{state.error})", else: ""
            IO.puts("    #{name}: #{status}#{info}")
        end
      )
    end
  end

  defp print_oikos_summary(resp) do
    IO.puts("  overall score: #{resp.overall_score}/100")
    IO.puts("  scores:")
    IO.puts("    maintainability: #{resp.scores.maintainability}")
    IO.puts("    documentation: #{resp.scores.documentation}")
    IO.puts("    testCoverage: #{resp.scores.test_coverage}")
    IO.puts("    communityHealth: #{resp.scores.community_health}")
    IO.puts("    securityPosture: #{resp.scores.security_posture}")
    IO.puts("    dependencyHealth: #{resp.scores.dependency_health}")
    IO.puts("    releaseMaturity: #{resp.scores.release_maturity}")
    IO.puts("    codeQuality: #{resp.scores.code_quality}")

    for risk <- resp.risks || [] do
      IO.puts("  risk: #{risk.category} (#{risk.severity}) - #{risk.description}")
    end
  end

  defp check_health(client, health_fn) do
    case health_fn.(client) do
      {:ok, response} -> {:ok, response.status}
      {:error, reason} -> {:error, reason}
    end
  end

  defp print_status(name, {:ok, status}) do
    symbol = if status == :healthy, do: "✓", else: "⚠"
    IO.puts("#{name}: #{symbol} #{status}")
  end

  defp print_status(name, {:error, _}) do
    IO.puts("#{name}: ✗ unreachable")
  end
end
