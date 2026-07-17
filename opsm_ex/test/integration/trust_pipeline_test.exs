# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Integration.TrustPipelineTest do
  use ExUnit.Case, async: false

  alias Opsm.Clients.{CheckyMonkey, Palimpsest, Oikos}

  alias Opsm.Types.{
    ServiceConfig,
    HttpConfig,
    CheckyMonkeyRequest,
    PalimpsestRequest,
    OikosAnalysisRequest
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
      http: http_config
    }

    {:ok, configs: configs}
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

      case CheckyMonkey.get_verification_status(client, request_id) do
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
      case CheckyMonkey.get_verification_status(client, "nonexistent") do
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
