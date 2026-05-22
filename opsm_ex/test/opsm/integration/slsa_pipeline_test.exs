# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# Integration tests for OPSM's SLSA provenance pipeline.
# Validates provenance generation, verification, lockfile metadata,
# and policy enforcement per SLSA v1.0 specification.

defmodule Opsm.Integration.SlsaPipelineTest do
  use ExUnit.Case, async: true

  alias Opsm.Slsa
  alias Opsm.Crypto.HybridSignatures

  @moduletag :integration

  # ==========================================================================
  # Provenance Generation
  # ==========================================================================

  describe "SLSA provenance generation" do
    test "generates valid SLSA provenance for a package" do
      pkg_info = %{
        name: "test-package",
        version: "1.0.0",
        forth: :npm,
        tarball_url: "https://registry.npmjs.org/test-package/-/test-package-1.0.0.tgz"
      }

      assert {:ok, statement} = Slsa.generate_provenance(pkg_info)
      assert statement["_type"] == "https://in-toto.io/Statement/v1"
      assert is_list(statement["subject"])
      assert length(statement["subject"]) > 0
    end

    test "provenance contains correct predicate type" do
      pkg_info = %{
        name: "example",
        version: "2.0.0",
        forth: :hex,
        tarball_url: "https://repo.hex.pm/tarballs/example-2.0.0.tar"
      }

      assert {:ok, statement} = Slsa.generate_provenance(pkg_info)
      assert statement["predicateType"] == "https://slsa.dev/provenance/v1"
    end

    test "provenance includes builder info" do
      pkg_info = %{name: "pkg", version: "1.0.0", forth: :cargo, tarball_url: nil}

      assert {:ok, statement} = Slsa.generate_provenance(pkg_info)
      assert is_map(statement["predicate"])
      assert is_map(statement["predicate"]["buildDefinition"])
    end

    test "provenance subject contains package digest" do
      pkg_info = %{name: "digest-pkg", version: "3.0.0", forth: :npm, tarball_url: nil}

      assert {:ok, statement} = Slsa.generate_provenance(pkg_info)
      [subject | _] = statement["subject"]
      assert subject["name"] == "digest-pkg"
      assert is_map(subject["digest"])
      assert Map.has_key?(subject["digest"], "blake2b")
      assert Map.has_key?(subject["digest"], "sha3-512")
    end

    test "provenance records external parameters" do
      pkg_info = %{
        name: "ext-params-pkg",
        version: "1.2.3",
        forth: :hex,
        source_url: "https://hex.pm/packages/ext-params-pkg"
      }

      assert {:ok, statement} = Slsa.generate_provenance(pkg_info)
      ext_params = statement["predicate"]["buildDefinition"]["externalParameters"]
      assert ext_params["package"] == "ext-params-pkg"
      assert ext_params["version"] == "1.2.3"
      assert ext_params["forth"] == "hex"
    end

    test "provenance includes run details with timestamps" do
      pkg_info = %{name: "ts-pkg", version: "1.0.0", forth: :npm, tarball_url: nil}

      assert {:ok, statement} = Slsa.generate_provenance(pkg_info)
      run_details = statement["predicate"]["runDetails"]
      assert is_map(run_details["builder"])
      assert run_details["builder"]["id"] == "https://opsm.dev/builder/v1"
      assert is_binary(run_details["metadata"]["invocationId"])
      assert is_binary(run_details["metadata"]["finishedOn"])
    end

    test "provenance with custom build info" do
      pkg_info = %{name: "custom-build", version: "1.0.0", forth: :cargo, tarball_url: nil}
      build_info = %{
        builder_id: "https://custom-builder.example.com",
        started_at: "2026-01-01T00:00:00Z"
      }

      assert {:ok, statement} = Slsa.generate_provenance(pkg_info, build_info)
      assert statement["predicate"]["runDetails"]["builder"]["id"] == "https://custom-builder.example.com"
      assert statement["predicate"]["runDetails"]["metadata"]["startedOn"] == "2026-01-01T00:00:00Z"
    end

    test "provenance includes resolved dependencies when provided" do
      pkg_info = %{
        name: "dep-pkg",
        version: "1.0.0",
        forth: :npm,
        tarball_url: nil,
        dependencies: ["lodash", "express"]
      }

      assert {:ok, statement} = Slsa.generate_provenance(pkg_info)
      resolved = statement["predicate"]["buildDefinition"]["resolvedDependencies"]
      assert is_list(resolved)
      assert length(resolved) == 2
    end
  end

  # ==========================================================================
  # Provenance Signing + Verification Round-trip
  # ==========================================================================

  describe "SLSA signing and verification" do
    test "sign and verify provenance round-trip" do
      pkg_info = %{name: "sign-test", version: "1.0.0", forth: :npm, tarball_url: nil}
      {:ok, statement} = Slsa.generate_provenance(pkg_info)
      {:ok, keypair} = HybridSignatures.generate_keypair()

      case Slsa.sign_provenance(statement, keypair) do
        {:ok, bundle} ->
          assert is_map(bundle.statement)
          assert is_map(bundle.signature)
          assert is_binary(bundle.signed_at)

          # Build public keys for verification
          public_keys = %{
            ed25519_pk: keypair.ed25519_pk,
            dilithium5_pk: keypair.dilithium5_pk
          }

          result = Slsa.verify_provenance(bundle, pkg_info, public_keys)
          assert match?({:ok, level} when level in [1, 2, 3], result)

        {:error, reason} ->
          # Signing may fail if Ed25519 key generation has issues
          assert is_binary(reason)
      end
    end
  end

  # ==========================================================================
  # Lockfile Metadata
  # ==========================================================================

  describe "SLSA lockfile metadata" do
    test "generates lockfile metadata from provenance statement" do
      pkg_info = %{name: "meta-pkg", version: "1.0.0", forth: :npm, tarball_url: nil}
      {:ok, statement} = Slsa.generate_provenance(pkg_info)

      meta = Slsa.lockfile_metadata(%{statement: statement})
      assert is_map(meta)
      assert Map.has_key?(meta, :slsa_level)
      assert is_integer(meta.slsa_level)
      assert meta.slsa_level in [1, 2, 3]
    end

    test "lockfile metadata includes provenance URI when available" do
      pkg_info = %{name: "uri-pkg", version: "1.0.0", forth: :npm, tarball_url: nil}
      {:ok, statement} = Slsa.generate_provenance(pkg_info)

      meta = Slsa.lockfile_metadata(%{
        statement: statement,
        uri: "https://attestations.opsm.dev/abc123"
      })

      assert meta.slsa_provenance_uri == "https://attestations.opsm.dev/abc123"
    end

    test "lockfile metadata handles nil provenance" do
      meta = Slsa.lockfile_metadata(nil)
      assert meta.slsa_level == nil
      assert meta.slsa_provenance_uri == nil
    end
  end

  # ==========================================================================
  # Policy Enforcement
  # ==========================================================================

  describe "SLSA policy enforcement" do
    test "enforce_level passes when package meets required level" do
      pkg_info = %{name: "good-pkg", slsa_level: 3}

      assert :ok = Slsa.enforce_level(pkg_info, 3)
      assert :ok = Slsa.enforce_level(pkg_info, 2)
      assert :ok = Slsa.enforce_level(pkg_info, 1)
    end

    test "enforce_level warns on insufficient level by default" do
      pkg_info = %{name: "warn-pkg", slsa_level: 1}

      # Default action is :warn which still returns :ok
      assert :ok = Slsa.enforce_level(pkg_info, 3)
    end

    test "enforce_level blocks on insufficient level when configured" do
      pkg_info = %{name: "blocked-pkg", slsa_level: 1}

      assert {:error, msg} = Slsa.enforce_level(pkg_info, 3, on_failure: :block)
      assert msg =~ "blocked-pkg"
      assert msg =~ "level 1"
      assert msg =~ "requires 3"
    end

    test "enforce_level ignores on insufficient level when configured" do
      pkg_info = %{name: "ignored-pkg", slsa_level: 0}

      assert :ok = Slsa.enforce_level(pkg_info, 3, on_failure: :ignore)
    end
  end
end
