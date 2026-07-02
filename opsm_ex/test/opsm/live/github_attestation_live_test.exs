# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Live.GithubAttestationLiveTest do
  @moduledoc """
  Live contract tests for GitHub native build-provenance attestations
  (issue #56). Excluded from the default run.

  The stable subject is a released GitHub CLI artifact: release assets are
  immutable, so its digest and attestation are permanent fixtures. Estate
  artifacts (e.g. ghcr.io/hyperpolymath/*) should replace it once any
  estate image/binary is rebuilt after the 2026-06-25 producer rollout —
  as of 2026-07-01 none of the published :latest artifacts carry bundles.

  Override the subject via OPSM_ATTESTED_REPO / OPSM_ATTESTED_DIGEST.
  """
  use ExUnit.Case, async: false

  alias Opsm.Slsa.GithubAttestation

  @moduletag :external_api

  # gh v2.92.0 linux amd64 tarball — released artifact, digest is permanent
  @default_repo "cli/cli"
  @default_digest "b57848131bdf0c229cd35e1f2a51aa718199858b2e728410b37e89a428943ec4"

  defp attested_repo, do: System.get_env("OPSM_ATTESTED_REPO", @default_repo)
  defp attested_digest, do: System.get_env("OPSM_ATTESTED_DIGEST", @default_digest)

  test "attestations API returns records for an attested artifact digest" do
    assert {:ok, records} = GithubAttestation.fetch_attestations(attested_repo(), attested_digest())
    assert records != [], "expected at least one attestation record"
    assert Enum.all?(records, &is_map/1)
  end

  test "unknown digests yield an empty record list, not an error" do
    absent = String.duplicate("0", 63) <> "1"
    assert {:ok, []} = GithubAttestation.fetch_attestations(attested_repo(), absent)
  end

  @tag :live_download
  test "full chain: fetch, verify via gh, gate builder trust on verification" do
    # ~12MB download; needs `gh` on PATH with auth. Mirrors the manual
    # acceptance run for issue #56.
    tmp = Path.join(System.tmp_dir!(), "opsm-attest-live-#{System.unique_integer([:positive])}.tar.gz")

    try do
      url = "https://github.com/cli/cli/releases/download/v2.92.0/gh_2.92.0_linux_amd64.tar.gz"
      {:ok, %{status: 200, body: body}} = Opsm.Verified.Http.get(url, timeout: 120_000)
      File.write!(tmp, body)

      config = Opsm.Config.load_config_or_example()

      assert {:ok, verification} =
               GithubAttestation.verify_subject({:artifact, tmp}, attested_repo(), config,
                 bundle_count: 1
               )

      assert verification.verified
      assert GithubAttestation.github_actions_builder?(verification.builder_id)

      statement = verification.details["statement"]
      assert is_map(statement)

      {:ok, slsa} =
        Opsm.Slsa.Provenance.verify_github_attestation(statement,
          package: %{tarball_url: nil},
          bundle_verified: verification.verified
        )

      assert slsa.builder_trusted
      assert slsa.slsa_level >= 2
      assert slsa.verified
    after
      File.rm(tmp)
    end
  end
end
