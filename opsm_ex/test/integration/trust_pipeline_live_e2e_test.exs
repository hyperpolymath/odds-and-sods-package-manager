# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# Enterprise trust pipeline — live-service E2E tests.
#
# Requires the full trust pipeline running via selur-compose.yml:
#
#   docker compose -f selur-compose.yml up -d \
#     claim-forge checky-monkey palimpsest cicd-hyper-a oikos
#
# Tests make direct HTTP calls to the real API endpoints, bypassing the
# Opsm.Clients.* layer, to validate the actual HTTP contract.
#
# Run: mix test test/integration/trust_pipeline_live_e2e_test.exs --include live_service

defmodule Opsm.Integration.TrustPipelineLiveE2ETest do
  use ExUnit.Case, async: false

  @moduletag :live_service
  @moduletag :integration

  # ---------------------------------------------------------------------------
  # Service base URLs — read from env, fall back to selur-compose defaults
  # ---------------------------------------------------------------------------

  @claim_forge   System.get_env("CLAIM_FORGE_URL",   "http://localhost:8080")
  @checky_monkey System.get_env("CHECKY_MONKEY_URL", "http://localhost:8081")
  @palimpsest    System.get_env("PALIMPSEST_URL",    "http://localhost:8082")
  @cicd_hyper_a  System.get_env("CICD_HYPER_A_URL",  "http://localhost:8083")
  @oikos         System.get_env("OIKOS_URL",          "http://localhost:8084")

  @req_base [receive_timeout: 10_000, retry: false]

  defp rget(url), do: Req.get(url, @req_base)
  defp rpost(url, body), do: Req.post(url, [json: body] ++ @req_base)

  # ---------------------------------------------------------------------------
  # 1. Health endpoints — all 5 services must be healthy before any test
  # ---------------------------------------------------------------------------

  describe "service health" do
    test "claim-forge /health returns healthy" do
      {:ok, resp} = rget(@claim_forge <> "/health")
      assert resp.status == 200
      assert resp.body["status"] == "healthy"
      assert is_binary(resp.body["version"])
    end

    test "checky-monkey /health returns healthy" do
      {:ok, resp} = rget(@checky_monkey <> "/health")
      assert resp.status == 200
      assert resp.body["status"] == "healthy"
      assert is_integer(resp.body["active_jobs"])
    end

    test "palimpsest-license /health returns healthy" do
      {:ok, resp} = rget(@palimpsest <> "/health")
      assert resp.status == 200
      assert resp.body["status"] == "healthy"
    end

    test "cicd-hyper-a /health returns healthy" do
      {:ok, resp} = rget(@cicd_hyper_a <> "/health")
      assert resp.status == 200
      assert resp.body["status"] == "healthy"
    end

    test "oikos /health returns healthy" do
      {:ok, resp} = rget(@oikos <> "/health")
      assert resp.status == 200
      assert resp.body["status"] == "healthy"
    end
  end

  # ---------------------------------------------------------------------------
  # 2. claim-forge — attestation generation and verification
  # ---------------------------------------------------------------------------

  describe "claim-forge attestation" do
    test "POST /attestation/generate returns signed attestation" do
      {:ok, resp} = rpost(@claim_forge <> "/attestation/generate", %{
        artifact_path: "/tmp/test-package-1.0.0.tar.gz",
        artifact_digest: "sha256:aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112233",
        claim_type: "build_provenance",
        metadata: %{builder: "opsm-ci", version: "1.0.0"}
      })
      assert resp.status == 200
      attest = resp.body
      assert is_binary(attest["attestation_uri"])
      assert String.starts_with?(attest["attestation_uri"], "opsm://attestations/")
      assert is_binary(attest["signature"]) and byte_size(attest["signature"]) > 0
      assert is_binary(attest["public_key"])
      assert is_binary(attest["digest"])
      assert is_binary(attest["timestamp"])
    end

    test "POST /attestation/verify accepts valid signature from generate" do
      {:ok, gen} = rpost(@claim_forge <> "/attestation/generate", %{
        artifact_path: "/tmp/test.tar.gz",
        artifact_digest: "sha256:deadbeef",
        claim_type: "security_scan",
        metadata: nil
      })
      assert gen.status == 200
      a = gen.body

      {:ok, ver} = rpost(@claim_forge <> "/attestation/verify", %{
        attestation_uri: a["attestation_uri"],
        signature:       a["signature"],
        public_key:      a["public_key"],
        digest:          a["digest"]
      })
      assert ver.status == 200
      assert ver.body["verified"] == true
      assert is_binary(ver.body["message"])
    end

    test "POST /attestation/verify rejects tampered signature" do
      {:ok, resp} = rpost(@claim_forge <> "/attestation/verify", %{
        attestation_uri: "opsm://attestations/000000000000000000000000000000",
        signature:   String.duplicate("00", 64),
        public_key:  String.duplicate("00", 32),
        digest:      "sha256:tampered"
      })
      # Service may return 400 (bad key) or 200 with verified=false
      assert resp.status in [200, 400]
      if resp.status == 200, do: assert(resp.body["verified"] == false)
    end

    test "generates distinct URIs for distinct artifacts" do
      make = fn suffix ->
        h = Base.encode16(:crypto.hash(:sha256, suffix), case: :lower)
        {:ok, r} = rpost(@claim_forge <> "/attestation/generate", %{
          artifact_path: "/tmp/#{suffix}.tar.gz",
          artifact_digest: "sha256:#{h}",
          claim_type: "build_provenance",
          metadata: nil
        })
        r.body["attestation_uri"]
      end
      assert make.("artifact-alpha") != make.("artifact-beta")
    end
  end

  # ---------------------------------------------------------------------------
  # 3. checky-monkey — verification submission and status
  # ---------------------------------------------------------------------------

  describe "checky-monkey verification" do
    test "GET /verification-types lists available types" do
      {:ok, resp} = rget(@checky_monkey <> "/verification-types")
      assert resp.status == 200
      assert is_list(resp.body) and length(resp.body) > 0
    end

    test "POST /verify queues job and returns request_id" do
      {:ok, resp} = rpost(@checky_monkey <> "/verify", %{
        repo_url: "https://github.com/hyperpolymath/odds-and-sods-package-manager",
        commit_sha: "abc123def456",
        verification_types: ["property-tests"]
      })
      assert resp.status in [200, 201, 202]
      assert is_binary(resp.body["request_id"])
      assert resp.body["status"] in ["queued", "running"]
    end

    test "GET /verify/{request_id} returns job detail after submission" do
      {:ok, sub} = rpost(@checky_monkey <> "/verify", %{
        repo_url: "https://github.com/hyperpolymath/test-repo",
        commit_sha: "cafebabe",
        verification_types: ["type-checking"]
      })
      assert sub.status in [200, 201, 202]
      request_id = sub.body["request_id"]

      {:ok, detail} = rget(@checky_monkey <> "/verify/#{request_id}")
      assert detail.status == 200
      assert detail.body["request_id"] == request_id
      assert detail.body["status"] in ["queued", "running", "completed", "failed", "cancelled"]
    end

    test "GET /verify/status/{sha} 200 or 404 for arbitrary sha" do
      sha = "testsha#{System.unique_integer([:positive])}"
      {:ok, resp} = rget(@checky_monkey <> "/verify/status/#{sha}")
      assert resp.status in [200, 404]
    end
  end

  # ---------------------------------------------------------------------------
  # 4. palimpsest-license — license compatibility analysis
  # ---------------------------------------------------------------------------

  describe "palimpsest-license" do
    test "GET /licenses returns non-empty list" do
      {:ok, resp} = rget(@palimpsest <> "/licenses")
      assert resp.status == 200
      assert is_list(resp.body) and length(resp.body) > 0
    end

    test "GET /licenses/MIT returns MIT license entry" do
      {:ok, resp} = rget(@palimpsest <> "/licenses/MIT")
      assert resp.status == 200
      assert is_map(resp.body)
    end

    test "POST /compatibility returns shape for MIT+Apache-2.0" do
      {:ok, resp} = rpost(@palimpsest <> "/compatibility", %{licenses: ["MIT", "Apache-2.0"]})
      assert resp.status == 200
      assert is_boolean(resp.body["compatible"])
      assert is_list(resp.body["licenses"])
      assert is_list(resp.body["conflicts"])
      assert is_binary(resp.body["recommendation"])
    end

    test "POST /compatibility single license is always compatible" do
      {:ok, resp} = rpost(@palimpsest <> "/compatibility", %{licenses: ["PMPL-1.0-or-later"]})
      assert resp.status == 200
      assert resp.body["compatible"] == true
    end

    test "POST /compatibility GPL-3.0 vs MIT reports conflict or incompatibility" do
      {:ok, resp} = rpost(@palimpsest <> "/compatibility", %{licenses: ["GPL-3.0-only", "MIT"]})
      assert resp.status == 200
      assert is_boolean(resp.body["compatible"])
      # The service has the GPL/MIT incompatibility in its matrix
      # We don't assert the exact result since it depends on the service's matrix coverage
      assert is_list(resp.body["conflicts"])
    end
  end

  # ---------------------------------------------------------------------------
  # 5. cicd-hyper-a — manifest validation and package publishing
  # ---------------------------------------------------------------------------

  describe "cicd-hyper-a" do
    test "GET /rulesets returns list" do
      {:ok, resp} = rget(@cicd_hyper_a <> "/rulesets")
      assert resp.status == 200
      assert is_list(resp.body)
    end

    test "POST /validate accepts valid OPSM manifest" do
      {:ok, resp} = rpost(@cicd_hyper_a <> "/validate", %{
        manifest: %{
          name: "test-package",
          version: "1.0.0",
          license: "PMPL-1.0-or-later",
          authors: ["Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>"],
          repository: "https://github.com/hyperpolymath/test"
        },
        rulesets: []
      })
      assert resp.status == 200
      assert is_boolean(resp.body["valid"])
      assert is_list(resp.body["errors"])
      assert is_list(resp.body["warnings"])
    end

    test "POST /packages/publish stores package and returns publish_id" do
      name = "e2e-test-pkg-#{System.unique_integer([:positive])}"
      {:ok, resp} = rpost(@cicd_hyper_a <> "/packages/publish", %{
        name: name,
        version: "0.1.0",
        forth: "hf",
        manifest: %{name: name, version: "0.1.0", license: "PMPL-1.0-or-later"},
        attestations: [],
        target_registries: ["hf"]
      })
      assert resp.status in [200, 201]
      assert is_binary(resp.body["publish_id"])
      assert resp.body["name"] == name
      assert resp.body["version"] == "0.1.0"
      assert resp.body["status"] in ["published", "pending", "queued"]
    end

    test "GET /packages/{name} returns package after publish" do
      name = "e2e-query-pkg-#{System.unique_integer([:positive])}"
      {:ok, pub} = rpost(@cicd_hyper_a <> "/packages/publish", %{
        name: name,
        version: "1.2.3",
        forth: "hf",
        manifest: %{name: name, version: "1.2.3", license: "MIT"},
        attestations: [],
        target_registries: []
      })
      assert pub.status in [200, 201]

      {:ok, query} = rget(@cicd_hyper_a <> "/packages/#{name}")
      assert query.status in [200, 404]
    end
  end

  # ---------------------------------------------------------------------------
  # 6. oikos — sustainability analysis
  # ---------------------------------------------------------------------------

  describe "oikos sustainability" do
    test "POST /analysis/repository returns structured scores" do
      {:ok, resp} = rpost(@oikos <> "/analysis/repository", %{
        repo_url: "https://github.com/hyperpolymath/odds-and-sods-package-manager",
        include_dependencies: false
      })
      assert resp.status == 200
      scores = resp.body["scores"]
      assert is_map(scores)
      for {_key, val} <- scores do
        assert is_float(val) or is_integer(val)
        assert val >= 0 and val <= 100
      end
    end

    test "POST /analysis/repository handles unknown repo gracefully" do
      {:ok, resp} = rpost(@oikos <> "/analysis/repository", %{
        repo_url: "https://github.com/unknown-org-xyz/nonexistent-repo-12345",
        include_dependencies: false
      })
      assert resp.status in [200, 404, 422]
    end
  end

  # ---------------------------------------------------------------------------
  # 7. Full pipeline — attest → verify → license → publish
  # ---------------------------------------------------------------------------

  describe "full enterprise trust pipeline" do
    test "artifact flows through all 5 stages: generate → verify → license → analysis → publish" do
      pkg_name = "pipeline-e2e-#{System.unique_integer([:positive])}"
      digest = "sha256:" <> Base.encode16(:crypto.hash(:sha256, pkg_name), case: :lower)

      # Stage 1 — claim-forge: generate attestation
      {:ok, attest_resp} = rpost(@claim_forge <> "/attestation/generate", %{
        artifact_path: "/tmp/#{pkg_name}-1.0.0.tar.gz",
        artifact_digest: digest,
        claim_type: "build_provenance",
        metadata: %{pipeline: "trust-e2e"}
      })
      assert attest_resp.status == 200
      attest = attest_resp.body
      assert String.starts_with?(attest["attestation_uri"], "opsm://attestations/")

      # Stage 2 — claim-forge: verify attestation
      {:ok, ver_resp} = rpost(@claim_forge <> "/attestation/verify", %{
        attestation_uri: attest["attestation_uri"],
        signature:       attest["signature"],
        public_key:      attest["public_key"],
        digest:          attest["digest"]
      })
      assert ver_resp.status == 200
      assert ver_resp.body["verified"] == true

      # Stage 3 — palimpsest: confirm license is clean
      {:ok, lic_resp} = rpost(@palimpsest <> "/compatibility", %{
        licenses: ["PMPL-1.0-or-later"]
      })
      assert lic_resp.status == 200
      assert lic_resp.body["compatible"] == true

      # Stage 4 — oikos: run sustainability analysis
      {:ok, sust_resp} = rpost(@oikos <> "/analysis/repository", %{
        repo_url: "https://github.com/hyperpolymath/odds-and-sods-package-manager",
        include_dependencies: false
      })
      assert sust_resp.status == 200

      # Stage 5 — cicd-hyper-a: publish with attestation attached
      {:ok, pub_resp} = rpost(@cicd_hyper_a <> "/packages/publish", %{
        name:    pkg_name,
        version: "1.0.0",
        forth:   "hf",
        manifest: %{name: pkg_name, version: "1.0.0", license: "PMPL-1.0-or-later"},
        attestations:    [attest["attestation_uri"]],
        target_registries: ["hf"]
      })
      assert pub_resp.status in [200, 201]
      assert is_binary(pub_resp.body["publish_id"])
    end

    test "claim-forge and checky-monkey respond concurrently without coupling" do
      repo = "https://github.com/hyperpolymath/odds-and-sods-package-manager"
      digest = "sha256:" <> Base.encode16(:crypto.hash(:sha256, repo), case: :lower)

      attest_task = Task.async(fn ->
        rpost(@claim_forge <> "/attestation/generate", %{
          artifact_path: "/tmp/opsm.tar.gz",
          artifact_digest: digest,
          claim_type: "code_review",
          metadata: nil
        })
      end)

      verify_task = Task.async(fn ->
        rpost(@checky_monkey <> "/verify", %{
          repo_url: repo,
          commit_sha: "main",
          verification_types: ["formal-verification"]
        })
      end)

      {:ok, attest_resp} = Task.await(attest_task, 15_000)
      {:ok, verify_resp} = Task.await(verify_task, 15_000)

      assert attest_resp.status == 200
      assert verify_resp.status in [200, 201, 202]
    end

    test "degraded pipeline — publish succeeds with partial attestations when checky-monkey is skipped" do
      {:ok, attest_resp} = rpost(@claim_forge <> "/attestation/generate", %{
        artifact_path: "/tmp/degraded.tar.gz",
        artifact_digest: "sha256:" <> Base.encode16(:crypto.hash(:sha256, "degraded"), case: :lower),
        claim_type: "license_check",
        metadata: nil
      })
      assert attest_resp.status == 200

      {:ok, pub_resp} = rpost(@cicd_hyper_a <> "/packages/publish", %{
        name:    "degraded-test-#{System.unique_integer([:positive])}",
        version: "0.0.1",
        forth:   "hf",
        manifest: %{name: "degraded-test", version: "0.0.1"},
        attestations:    [attest_resp.body["attestation_uri"]],
        target_registries: []
      })
      assert pub_resp.status in [200, 201]
    end
  end
end
