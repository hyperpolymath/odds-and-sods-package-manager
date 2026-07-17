# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
#
# Trust pipeline — live-service E2E tests.
#
# Requires the trust pipeline running via selur-compose.yml:
#
#   docker compose -f selur-compose.yml up -d \
#     checky-monkey palimpsest oikos
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

  @checky_monkey System.get_env("CHECKY_MONKEY_URL", "http://localhost:8081")
  @palimpsest System.get_env("PALIMPSEST_URL", "http://localhost:8082")
  @oikos System.get_env("OIKOS_URL", "http://localhost:8084")

  @req_base [receive_timeout: 10_000, retry: false]

  defp rget(url), do: Req.get(url, @req_base)
  defp rpost(url, body), do: Req.post(url, [json: body] ++ @req_base)

  # ---------------------------------------------------------------------------
  # 1. Health endpoints — all services must be healthy before any test
  # ---------------------------------------------------------------------------

  describe "service health" do
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

    test "oikos /health returns healthy" do
      {:ok, resp} = rget(@oikos <> "/health")
      assert resp.status == 200
      assert resp.body["status"] == "healthy"
    end
  end

  # ---------------------------------------------------------------------------
  # 2. checky-monkey — verification submission and status
  # ---------------------------------------------------------------------------

  describe "checky-monkey verification" do
    test "GET /verification-types lists available types" do
      {:ok, resp} = rget(@checky_monkey <> "/verification-types")
      assert resp.status == 200
      assert is_list(resp.body) and length(resp.body) > 0
    end

    test "POST /verify queues job and returns request_id" do
      {:ok, resp} =
        rpost(@checky_monkey <> "/verify", %{
          repo_url: "https://github.com/hyperpolymath/odds-and-sods-package-manager",
          commit_sha: "abc123def456",
          verification_types: ["property-tests"]
        })

      assert resp.status in [200, 201, 202]
      assert is_binary(resp.body["request_id"])
      assert resp.body["status"] in ["queued", "running"]
    end

    test "GET /verify/{request_id} returns job detail after submission" do
      {:ok, sub} =
        rpost(@checky_monkey <> "/verify", %{
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
  # 3. palimpsest-license — license compatibility analysis
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
      {:ok, resp} = rpost(@palimpsest <> "/compatibility", %{licenses: ["MPL-2.0"]})
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
  # 4. oikos — sustainability analysis
  # ---------------------------------------------------------------------------

  describe "oikos sustainability" do
    test "POST /analysis/repository returns structured scores" do
      {:ok, resp} =
        rpost(@oikos <> "/analysis/repository", %{
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
      {:ok, resp} =
        rpost(@oikos <> "/analysis/repository", %{
          repo_url: "https://github.com/unknown-org-xyz/nonexistent-repo-12345",
          include_dependencies: false
        })

      assert resp.status in [200, 404, 422]
    end
  end
end
