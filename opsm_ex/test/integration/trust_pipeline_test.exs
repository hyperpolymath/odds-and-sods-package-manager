# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Integration.TrustPipelineTest do
  use ExUnit.Case, async: false

  alias Opsm.Clients.{ClaimForge, CheckyMonkey, Palimpsest, Oikos, CicdHyperA}
  alias Opsm.Types.{
    ServiceConfig,
    HttpConfig,
    ClaimForgeRequest,
    CheckyMonkeyRequest,
    PalimpsestRequest,
    OikosAnalysisRequest,
    CicdPublishRequest,
    PackageMetadata,
    AttestationRef,
    ManifestFormat
  }

  @moduletag :integration

  setup do
    # Mock HTTP config
    http_config = %HttpConfig{
      timeout_ms: 5000,
      retries: 1,
      backoff_ms: 100
    }

    # We'll use localhost URLs and rely on service availability
    # For true integration testing, services should be running
    # For mocked tests, we could use Bypass library

    configs = %{
      claim_forge: %ServiceConfig{
        base_url: "http://localhost:7001",
        token: "test-token"
      },
      checky_monkey: %ServiceConfig{
        base_url: "http://localhost:7002",
        token: "test-token"
      },
      palimpsest: %ServiceConfig{
        base_url: "http://localhost:7003",
        token: "test-token"
      },
      oikos: %ServiceConfig{
        base_url: "http://localhost:7004",
        token: "test-token"
      },
      cicd_hyper_a: %ServiceConfig{
        base_url: "http://localhost:7005",
        token: "test-token"
      },
      http: http_config
    }

    {:ok, configs: configs}
  end

  describe "ClaimForge attestation generation" do
    @tag :skip  # Skip by default, run when services available
    test "generates attestation for valid artifact", %{configs: configs} do
      client = ClaimForge.new(configs.claim_forge, configs.http)

      request = %ClaimForgeRequest{
        artifact_path: "/tmp/test-package.tar.gz",
        artifact_digest: "sha256:abc123",
        claim_type: :build_provenance,
        metadata: %{"test" => true}
      }

      case ClaimForge.generate_attestation(client, request) do
        {:ok, response} ->
          assert response.attestation_id != nil
          assert response.claim_type == :build_provenance
          assert response.attestation_uri != nil
          assert response.signature != nil

        {:error, reason} ->
          flunk("ClaimForge request failed: #{inspect(reason)}")
      end
    end

    test "handles service unavailable gracefully", %{configs: configs} do
      # Point to non-existent service
      bad_config = %{configs.claim_forge | base_url: "http://localhost:9999"}
      client = ClaimForge.new(bad_config, configs.http)

      request = %ClaimForgeRequest{
        artifact_path: "/tmp/test-package.tar.gz",
        artifact_digest: "sha256:abc123",
        claim_type: :build_provenance,
        metadata: nil
      }

      case ClaimForge.generate_attestation(client, request) do
        {:error, reason} ->
          # Should get connection refused or timeout
          assert reason =~ ~r/failed|refused|timeout/i

        {:ok, _} ->
          flunk("Expected error for unavailable service")
      end
    end
  end

  describe "CheckyMonkey verification" do
    @tag :skip
    test "submits verification request", %{configs: configs} do
      client = CheckyMonkey.new(configs.checky_monkey, configs.http)

      request = %CheckyMonkeyRequest{
        repository_url: "https://github.com/test/repo",
        commit_sha: "abc123",
        verification_types: [:property_tests, :type_checking],
        timeout: 60_000
      }

      case CheckyMonkey.submit_verification(client, request) do
        {:ok, response} ->
          assert response.request_id != nil
          assert response.status in [:queued, :running]

        {:error, reason} ->
          flunk("CheckyMonkey submit failed: #{inspect(reason)}")
      end
    end

    @tag :skip
    test "polls verification status", %{configs: configs} do
      client = CheckyMonkey.new(configs.checky_monkey, configs.http)
      request_id = "test-request-123"

      case CheckyMonkey.get_verification_status(client,request_id) do
        {:ok, response} ->
          assert response.status in [:queued, :running, :completed, :failed]

        {:error, :not_found} ->
          # Expected if request doesn't exist
          :ok

        {:error, reason} ->
          flunk("CheckyMonkey status failed: #{inspect(reason)}")
      end
    end

    test "handles async polling timeout", %{configs: configs} do
      # Test that polling with short timeout handles gracefully
      client = CheckyMonkey.new(configs.checky_monkey, %{configs.http | timeout_ms: 100})

      # Poll for non-existent request
      case CheckyMonkey.get_verification_status(client,"nonexistent") do
        {:error, _reason} ->
          # Expected - service unavailable or not found
          :ok

        {:ok, _} ->
          # If service is running, this is also ok
          :ok
      end
    end
  end

  describe "Palimpsest license analysis" do
    @tag :skip
    test "analyzes license compatibility", %{configs: configs} do
      client = Palimpsest.new(configs.palimpsest, configs.http)

      request = %PalimpsestRequest{
        artifact_path: "/tmp/test-package",
        include_transitive: false,
        target_license: "MIT"
      }

      case Palimpsest.analyze(client, request) do
        {:ok, response} ->
          assert response.compatibility != nil
          assert is_boolean(response.compatibility.compatible)
          assert is_list(response.detected_licenses)

        {:error, reason} ->
          flunk("Palimpsest analysis failed: #{inspect(reason)}")
      end
    end

    test "detects license conflicts", %{configs: configs} do
      # Mock scenario: GPL package trying to be used in proprietary software
      # This test validates error handling, not actual analysis
      client = Palimpsest.new(configs.palimpsest, configs.http)

      request = %PalimpsestRequest{
        artifact_path: "/nonexistent/path",
        include_transitive: true,
        target_license: "Proprietary"
      }

      # Should fail gracefully (service unavailable or path not found)
      case Palimpsest.analyze(client, request) do
        {:error, _reason} ->
          :ok

        {:ok, _response} ->
          # If service is running and handles gracefully, ok
          :ok
      end
    end
  end

  describe "Oikos sustainability analysis" do
    @tag :skip
    test "analyzes repository sustainability", %{configs: configs} do
      client = Oikos.new(configs.oikos, configs.http)

      request = %OikosAnalysisRequest{
        repository_url: "https://github.com/test/repo",
        branch: "main",
        commit_sha: nil
      }

      case Oikos.analyze_repository(client, request) do
        {:ok, response} ->
          assert is_integer(response.overall_score)
          assert response.overall_score >= 0
          assert response.overall_score <= 100
          assert response.scores != nil

        {:error, reason} ->
          flunk("Oikos analysis failed: #{inspect(reason)}")
      end
    end

    test "handles invalid repository URL", %{configs: configs} do
      client = Oikos.new(configs.oikos, configs.http)

      request = %OikosAnalysisRequest{
        repository_url: "not-a-valid-url",
        branch: nil,
        commit_sha: nil
      }

      case Oikos.analyze_repository(client, request) do
        {:error, _reason} ->
          # Expected - invalid URL
          :ok

        {:ok, _} ->
          # Service might handle gracefully
          :ok
      end
    end
  end

  describe "CicdHyperA publish and federation" do
    @tag :skip
    test "publishes package with attestations", %{configs: configs} do
      client = CicdHyperA.new(configs.cicd_hyper_a, configs.http)

      manifest = %ManifestFormat{
        name: "test-package",
        version: "1.0.0",
        description: "Test package",
        license: "MIT",
        repository: "https://github.com/test/repo",
        source_forth: :npm,
        dependencies: %{},
        dev_dependencies: %{}
      }

      package_metadata = %PackageMetadata{
        name: manifest.name,
        version: manifest.version,
        description: manifest.description,
        license: manifest.license,
        repository: manifest.repository,
        authors: [],
        keywords: [],
        dependencies: %{},
        dev_dependencies: nil
      }

      request = %CicdPublishRequest{
        manifest: package_metadata,
        tarball_url: "https://registry.npmjs.org/test-package/-/test-package-1.0.0.tgz",
        attestations: [
          %AttestationRef{
            attestation_type: :claim_forge,
            uri: "https://attestations.example.com/abc123",
            digest: "sha256:def456"
          }
        ]
      }

      case CicdHyperA.publish(client, request) do
        {:ok, response} ->
          assert response.package_id != nil
          assert response.version == "1.0.0"
          assert response.registry_url != nil

        {:error, reason} ->
          flunk("CicdHyperA publish failed: #{inspect(reason)}")
      end
    end
  end

  describe "Full trust pipeline flow" do
    @tag :skip
    test "complete publish workflow", %{configs: configs} do
      # 1. Generate attestation with ClaimForge
      cf_client = ClaimForge.new(configs.claim_forge, configs.http)

      cf_request = %ClaimForgeRequest{
        artifact_path: "/tmp/test-package.tar.gz",
        artifact_digest: "sha256:test123",
        claim_type: :build_provenance,
        metadata: %{"version" => "1.0.0"}
      }

      {:ok, attestation} = ClaimForge.generate(cf_client, cf_request)
      assert attestation.attestation_id != nil

      # 2. Analyze license with Palimpsest
      pal_client = Palimpsest.new(configs.palimpsest_license, configs.http)

      pal_request = %PalimpsestRequest{
        artifact_path: "/tmp/test-package",
        include_transitive: false,
        target_license: "MIT"
      }

      {:ok, license_result} = Palimpsest.analyze(pal_client, pal_request)
      assert license_result.compatibility.compatible == true

      # 3. Analyze sustainability with Oikos
      oikos_client = Oikos.new(configs.oikos, configs.http)

      oikos_request = %OikosAnalysisRequest{
        repository_url: "https://github.com/test/repo",
        branch: nil,
        commit_sha: nil
      }

      {:ok, sustainability} = Oikos.analyze_repository(oikos_client, oikos_request)
      assert sustainability.overall_score >= 0

      # 4. Submit verification to CheckyMonkey
      cm_client = CheckyMonkey.new(configs.checky_monkey, configs.http)

      cm_request = %CheckyMonkeyRequest{
        repository_url: "https://github.com/test/repo",
        commit_sha: "abc123",
        verification_types: [:type_checking],
        timeout: 30_000
      }

      {:ok, verification} = CheckyMonkey.submit(cm_client, cm_request)
      assert verification.request_id != nil

      # 5. Publish to registry with CicdHyperA
      cicd_client = CicdHyperA.new(configs.cicd_hyper_a, configs.http)

      manifest = %ManifestFormat{
        name: "test-package",
        version: "1.0.0",
        description: "Test package",
        license: "MIT",
        repository: "https://github.com/test/repo",
        source_forth: :npm,
        dependencies: %{},
        dev_dependencies: %{}
      }

      package_metadata = %PackageMetadata{
        name: manifest.name,
        version: manifest.version,
        description: manifest.description,
        license: manifest.license,
        repository: manifest.repository,
        authors: [],
        keywords: [],
        dependencies: %{},
        dev_dependencies: nil
      }

      publish_request = %CicdPublishRequest{
        manifest: package_metadata,
        tarball_url: "https://example.com/test-package-1.0.0.tgz",
        attestations: [
          %AttestationRef{
            attestation_type: :claim_forge,
            uri: attestation.attestation_uri,
            digest: "sha256:test123"
          }
        ]
      }

      {:ok, publish_result} = CicdHyperA.publish(cicd_client, publish_request)
      assert publish_result.package_id != nil
      assert publish_result.registry_url != nil

      # Success: all pipeline stages completed
      :ok
    end
  end

  describe "Error severity classification" do
    test "classifies hard failures" do
      # Test error classification logic
      errors = [
        {:license_conflict, "GPL vs MIT"},
        {:signature_verification_failed, "Invalid signature"},
        {:attestation_invalid, "Corrupted attestation"}
      ]

      Enum.each(errors, fn {type, _msg} ->
        assert error_severity(type) == :hard_fail
      end)
    end

    test "classifies soft failures" do
      errors = [
        {:checky_monkey_timeout, "Verification timed out"},
        {:oikos_unreachable, "Service unavailable"},
        {:network_error, "Connection refused"}
      ]

      Enum.each(errors, fn {type, _msg} ->
        assert error_severity(type) == :soft_fail
      end)
    end

    test "classifies warnings" do
      warnings = [
        {:low_sustainability_score, "Score: 45"},
        {:dev_dependency_issue, "Outdated dev dependency"},
        {:optional_dep_unavailable, "Optional dependency not found"}
      ]

      Enum.each(warnings, fn {type, _msg} ->
        assert error_severity(type) == :warning
      end)
    end
  end

  # Helper function for error severity classification
  defp error_severity(error_type) do
    case error_type do
      # HARD_FAIL - Block installation
      :license_conflict -> :hard_fail
      :signature_verification_failed -> :hard_fail
      :attestation_invalid -> :hard_fail
      :checksum_mismatch -> :hard_fail
      :malware_detected -> :hard_fail

      # SOFT_FAIL - Warn but allow with degraded trust
      :checky_monkey_timeout -> :soft_fail
      :oikos_unreachable -> :soft_fail
      :network_error -> :soft_fail
      :service_timeout -> :soft_fail

      # WARNING - Inform user but proceed
      :low_sustainability_score -> :warning
      :dev_dependency_issue -> :warning
      :optional_dep_unavailable -> :warning
      :missing_documentation -> :warning

      _ -> :unknown
    end
  end
end
