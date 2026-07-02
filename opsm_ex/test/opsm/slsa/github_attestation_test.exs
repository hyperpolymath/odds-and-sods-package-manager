# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Slsa.GithubAttestationTest do
  use ExUnit.Case, async: true

  alias Opsm.Slsa.GithubAttestation
  alias Opsm.Slsa.Provenance
  alias Opsm.Types.GithubAttestationVerification

  @gh_builder "https://github.com/hyperpolymath/proven/.github/workflows/release.yml@refs/heads/main"

  defp statement(builder_id) do
    %{
      "_type" => "https://in-toto.io/Statement/v1",
      "predicateType" => "https://slsa.dev/provenance/v1",
      "subject" => [
        %{"name" => "proven", "digest" => %{"sha256" => String.duplicate("ab", 32)}}
      ],
      "predicate" => %{
        "buildDefinition" => %{
          "buildType" => "https://actions.github.io/buildtypes/workflow/v1",
          "externalParameters" => %{},
          "resolvedDependencies" => [
            %{
              "uri" => "git+https://github.com/hyperpolymath/proven@refs/heads/main",
              "digest" => %{"gitCommit" => String.duplicate("c", 40)}
            }
          ]
        },
        "runDetails" => %{"builder" => %{"id" => builder_id}, "metadata" => %{}}
      }
    }
  end

  defp bundle(statement) do
    %{
      "mediaType" => "application/vnd.dev.sigstore.bundle.v0.3+json",
      "verificationMaterial" => %{"certificate" => %{"rawBytes" => "..."}},
      "dsseEnvelope" => %{
        "payloadType" => "application/vnd.in-toto+json",
        "payload" => Base.encode64(Jason.encode!(statement))
      }
    }
  end

  describe "github_actions_builder?/1" do
    test "matches the GitHub Actions workflow builder identity" do
      assert GithubAttestation.github_actions_builder?(@gh_builder)

      assert GithubAttestation.github_actions_builder?(
               "https://github.com/o/r/.github/workflows/w.yml@refs/tags/v1.0.0"
             )
    end

    test "rejects non-builder identities" do
      refute GithubAttestation.github_actions_builder?("https://github.com/o/r")
      refute GithubAttestation.github_actions_builder?("https://evil.com/o/r/.github/workflows/w@x")
      refute GithubAttestation.github_actions_builder?("https://github.com/o/r/.github/workflows/w.yml")
      refute GithubAttestation.github_actions_builder?("https://opsm.dev/builders/elixir-mix")
      refute GithubAttestation.github_actions_builder?(nil)
      refute GithubAttestation.github_actions_builder?(42)
    end
  end

  describe "github_owner_repo/1" do
    test "extracts owner/repo from GitHub repository URLs" do
      for url <- [
            "https://github.com/hyperpolymath/proven",
            "https://github.com/hyperpolymath/proven.git",
            "https://github.com/hyperpolymath/proven/",
            "http://github.com/hyperpolymath/proven"
          ] do
        assert {:ok, "hyperpolymath/proven"} =
                 GithubAttestation.github_owner_repo(%{manifest: %{repository: url}})
      end
    end

    test "returns :none for non-GitHub or missing repositories" do
      assert {:none, _} =
               GithubAttestation.github_owner_repo(%{manifest: %{repository: "https://gitlab.com/a/b"}})

      assert {:none, _} =
               GithubAttestation.github_owner_repo(%{manifest: %{repository: nil}})

      assert {:none, _} = GithubAttestation.github_owner_repo(%{manifest: %{}})
    end
  end

  describe "artifact_digest/1" do
    test "normalizes a sha256 checksum" do
      hex = String.duplicate("AB", 32)

      assert {:ok, "sha256:" <> normalized} =
               GithubAttestation.artifact_digest(%{checksum: hex, checksum_algo: :sha256})

      assert normalized == String.downcase(hex)
    end

    test "returns :none for missing or non-sha256 checksums" do
      assert {:none, _} = GithubAttestation.artifact_digest(%{checksum: nil, checksum_algo: :sha256})
      assert {:none, _} = GithubAttestation.artifact_digest(%{checksum: "abc", checksum_algo: :sha512})
      assert {:none, _} = GithubAttestation.artifact_digest(%{checksum: "not-hex", checksum_algo: :sha256})
    end
  end

  describe "fetch_attestations/3 input validation" do
    test "rejects malformed owner/repo without touching the network" do
      assert {:error, _} = GithubAttestation.fetch_attestations("owner repo; rm", "sha256:" <> String.duplicate("a", 64))
      assert {:error, _} = GithubAttestation.fetch_attestations("noslash", "sha256:" <> String.duplicate("a", 64))
    end

    test "rejects malformed digests without touching the network" do
      assert {:error, _} = GithubAttestation.fetch_attestations("o/r", "sha256:short")
      assert {:error, _} = GithubAttestation.fetch_attestations("o/r", "md5:" <> String.duplicate("a", 64))
    end
  end

  describe "extract_statement/1" do
    test "decodes the in-toto statement from a DSSE envelope" do
      s = statement(@gh_builder)
      assert {:ok, decoded} = GithubAttestation.extract_statement(bundle(s))
      assert decoded == s
    end

    test "rejects wrong payload types, bad base64, and missing envelopes" do
      s = statement(@gh_builder)
      wrong_type = put_in(bundle(s), ["dsseEnvelope", "payloadType"], "application/json")
      assert {:error, _} = GithubAttestation.extract_statement(wrong_type)

      bad_b64 = put_in(bundle(s), ["dsseEnvelope", "payload"], "!!not-base64!!")
      assert {:error, _} = GithubAttestation.extract_statement(bad_b64)

      assert {:error, _} = GithubAttestation.extract_statement(%{"no" => "envelope"})
    end
  end

  describe "decode_gh_output/1" do
    test "extracts builder identity from gh verify JSON" do
      gh_output = [
        %{
          "verificationResult" => %{
            "statement" => statement(@gh_builder)
          }
        }
      ]

      assert %GithubAttestationVerification{
               verified: true,
               builder_id: @gh_builder,
               predicate_type: "https://slsa.dev/provenance/v1"
             } = GithubAttestation.decode_gh_output(gh_output)
    end

    test "empty output is not a verification" do
      assert %GithubAttestationVerification{verified: false} = GithubAttestation.decode_gh_output([])
      assert %GithubAttestationVerification{verified: false} = GithubAttestation.decode_gh_output(%{})
    end
  end

  describe "Provenance.verify_github_attestation/2 — verification-gated builder trust" do
    test "GitHub Actions builder is trusted when the bundle verified" do
      package = %{tarball_url: nil}

      assert {:ok, result} =
               Provenance.verify_github_attestation(statement(@gh_builder),
                 package: package,
                 bundle_verified: true
               )

      assert result.builder_trusted
      assert result.materials_match
      # Unsigned in-toto statement (signature lives in the Sigstore bundle,
      # already checked) → level 2 via trusted builder + materials.
      assert result.slsa_level == 2
      assert result.verified
    end

    test "the builder string alone confers no trust" do
      package = %{tarball_url: nil}

      assert {:ok, result} =
               Provenance.verify_github_attestation(statement(@gh_builder),
                 package: package,
                 bundle_verified: false
               )

      refute result.builder_trusted
      assert result.slsa_level == 1
      assert Enum.any?(result.warnings, &String.contains?(&1, "not in trusted list"))
    end

    test "a non-GitHub builder is not trusted even with a verified bundle" do
      package = %{tarball_url: nil}

      assert {:ok, result} =
               Provenance.verify_github_attestation(statement("https://evil.example/builder"),
                 package: package,
                 bundle_verified: true
               )

      refute result.builder_trusted
    end

    test "exact-match trusted builders keep working without the flag" do
      package = %{tarball_url: nil}

      assert {:ok, result} =
               Provenance.verify_github_attestation(
                 statement("https://github.com/slsa-framework/slsa-github-generator"),
                 package: package,
                 bundle_verified: false
               )

      assert result.builder_trusted
    end

    test "statement subject digest binds the artifact when it matches the package checksum" do
      # subject digest in statement/1 is "abab...": tarball_url would fail the
      # materials check, but the matching subject digest governs instead
      package = %{tarball_url: "https://example.com/not-in-materials.tgz", checksum: String.duplicate("ab", 32)}

      assert {:ok, result} =
               Provenance.verify_github_attestation(statement(@gh_builder),
                 package: package,
                 bundle_verified: true
               )

      assert result.materials_match
      assert result.slsa_level == 2
    end

    test "a mismatched subject digest fails the binding even with a verified bundle" do
      package = %{tarball_url: nil, checksum: String.duplicate("ff", 32)}

      assert {:ok, result} =
               Provenance.verify_github_attestation(statement(@gh_builder),
                 package: package,
                 bundle_verified: true
               )

      refute result.materials_match
      assert Enum.any?(result.warnings, &String.contains?(&1, "subject digest does not match"))
    end
  end

  describe "trust pipeline integration (no network)" do
    test "package without a GitHub repository skips the check" do
      package = %Opsm.Types.ResolvedPackage{
        package: "local-pkg",
        version: "1.0.0",
        forth: :elixir,
        registry_url: "https://example.invalid",
        tarball_url: nil,
        checksum: nil,
        manifest: %{repository: nil, license: "MIT", dependencies: %{}}
      }

      {:ok, results} =
        Opsm.Trust.Pipeline.verify(package,
          skip_checks: [:attestation, :license, :sustainability, :slsa]
        )

      assert {:skipped, _msg} = results.checks[:github_attestation]
    end

    test "package with GitHub repo but no sha256 checksum skips before any lookup" do
      package = %Opsm.Types.ResolvedPackage{
        package: "proven",
        version: "1.0.0",
        forth: :elixir,
        registry_url: "https://example.invalid",
        tarball_url: nil,
        checksum: nil,
        manifest: %{repository: "https://github.com/hyperpolymath/proven", license: "MPL-2.0", dependencies: %{}}
      }

      {:ok, results} =
        Opsm.Trust.Pipeline.verify(package,
          skip_checks: [:attestation, :license, :sustainability, :slsa]
        )

      assert {:skipped, msg} = results.checks[:github_attestation]
      assert msg =~ "sha256"
    end
  end
end
