# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Slsa.Provenance do
  @moduledoc """
  SLSA v1.0 provenance generation and verification.

  Implements the SLSA provenance predicate format:
  https://slsa.dev/provenance/v1

  SLSA Level Requirements:
  - Level 1: Documentation of build process
  - Level 2: Hosted build service, authenticated provenance
  - Level 3: Hardened build platform, non-falsifiable provenance
  - Level 4: Hermetic, reproducible builds (future)
  """

  alias Opsm.Types.{SlsaProvenance, BuildMaterial, SlsaVerificationResult}
  alias Opsm.Crypto.{Signatures, HybridSignatures}

  @slsa_predicate_type "https://slsa.dev/provenance/v1"
  @opsm_builder_id "https://opsm.dev/builders/elixir-mix"

  # Trusted builder IDs for SLSA Level 3
  @trusted_builders [
    "https://opsm.dev/builders/elixir-mix",
    "https://github.com/slsa-framework/slsa-github-generator",
    "https://cloudbuild.googleapis.com/GoogleHostedWorker",
    "https://tekton.dev/chains/v2"
  ]

  # ==========================================================================
  # Generation
  # ==========================================================================

  @doc """
  Generate a SLSA v1.0 provenance predicate for a package.

  ## Parameters
  - `package`: ResolvedPackage struct
  - `opts`: Options including:
    - `:source_uri` - Source repository URI
    - `:source_digest` - Source commit SHA
    - `:builder_id` - Builder identity (defaults to OPSM)
    - `:signing_key` - Ed25519 secret key for signing

  Returns {:ok, SlsaProvenance} or {:error, reason}.
  """
  def generate(package, opts \\ []) do
    source_uri = Keyword.get(opts, :source_uri, package.manifest.repository || "")
    source_digest = Keyword.get(opts, :source_digest, "")
    builder_id = Keyword.get(opts, :builder_id, @opsm_builder_id)
    signing_key = Keyword.get(opts, :signing_key)

    materials = build_materials(package, source_uri, source_digest)

    provenance = %SlsaProvenance{
      builder_id: builder_id,
      build_type: @slsa_predicate_type,
      invocation: %{
        "configSource" => %{
          "uri" => source_uri,
          "digest" => digest_map(source_digest),
          "entryPoint" => ""
        },
        "parameters" => %{
          "forth" => to_string(package.forth),
          "version" => package.version
        }
      },
      materials: materials,
      metadata: %{
        "buildInvocationId" => generate_invocation_id(),
        "buildStartedOn" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "completeness" => %{
          "parameters" => true,
          "environment" => false,
          "materials" => source_digest != ""
        },
        "reproducible" => false
      },
      slsa_level: calculate_level(builder_id, source_digest, materials)
    }

    # Sign if key provided (supports both classical and hybrid)
    hybrid_keypair = Keyword.get(opts, :hybrid_keypair)

    provenance = cond do
      hybrid_keypair ->
        # Hybrid Ed25519 + Dilithium5 signing
        case sign_provenance_hybrid(provenance, hybrid_keypair) do
          {:ok, sig, algo} ->
            %{provenance | signature: sig, signature_algo: algo}
          {:error, _} ->
            provenance
        end

      signing_key ->
        # Classical Ed25519 signing
        case sign_provenance(provenance, signing_key) do
          {:ok, sig} ->
            %{provenance | signature: sig, signature_algo: :ed25519}
          {:error, _} ->
            provenance
        end

      true ->
        provenance
    end

    {:ok, provenance}
  end

  # ==========================================================================
  # Verification
  # ==========================================================================

  @doc """
  Verify a SLSA provenance predicate.

  Checks:
  1. Builder identity is trusted
  2. Materials are consistent with package
  3. Signature is valid (if present)
  4. Calculates verified SLSA level

  Returns {:ok, SlsaVerificationResult}.
  """
  def verify(provenance, package, opts \\ []) do
    public_key = Keyword.get(opts, :public_key)

    result = %SlsaVerificationResult{}

    # Check builder trust
    {builder_trusted, result} = check_builder(provenance, result)

    # Check materials consistency
    {materials_match, result} = check_materials(provenance, package, result)

    # Check signature
    {sig_valid, result} = if provenance.signature && public_key do
      check_signature(provenance, public_key, result)
    else
      if provenance.signature do
        {false, add_warning(result, "Provenance is signed but no public key provided for verification")}
      else
        {:not_checked, add_warning(result, "Provenance is unsigned")}
      end
    end

    # Calculate verified level
    verified_level = verified_slsa_level(builder_trusted, materials_match, sig_valid)

    verified = verified_level >= 1 and result.errors == []

    {:ok, %{result |
      verified: verified,
      slsa_level: verified_level,
      builder_trusted: builder_trusted,
      materials_match: materials_match,
      signature_valid: sig_valid
    }}
  end

  @doc """
  Check if a provenance meets a minimum SLSA level.
  """
  def meets_level?(provenance_or_result, minimum_level)

  def meets_level?(%SlsaProvenance{slsa_level: level}, minimum), do: level >= minimum
  def meets_level?(%SlsaVerificationResult{slsa_level: level}, minimum), do: level >= minimum

  @doc """
  Serialize provenance to in-toto statement envelope format.
  """
  def to_envelope(provenance) do
    %{
      "_type" => "https://in-toto.io/Statement/v1",
      "predicateType" => @slsa_predicate_type,
      "predicate" => %{
        "buildDefinition" => %{
          "buildType" => provenance.build_type,
          "externalParameters" => provenance.invocation,
          "resolvedDependencies" => provenance.materials
        },
        "runDetails" => %{
          "builder" => %{"id" => provenance.builder_id},
          "metadata" => provenance.metadata
        }
      }
    }
  end

  @doc """
  Parse provenance from an in-toto statement envelope.
  """
  def from_envelope(envelope) when is_map(envelope) do
    predicate = envelope["predicate"] || %{}
    build_def = predicate["buildDefinition"] || %{}
    run_details = predicate["runDetails"] || %{}
    builder = run_details["builder"] || %{}
    metadata = run_details["metadata"] || %{}

    builder_id = builder["id"] || ""
    materials = build_def["resolvedDependencies"] || []

    provenance = %SlsaProvenance{
      builder_id: builder_id,
      build_type: build_def["buildType"] || @slsa_predicate_type,
      invocation: build_def["externalParameters"] || %{},
      materials: materials,
      metadata: metadata,
      slsa_level: calculate_level(builder_id, "", materials)
    }

    {:ok, provenance}
  end

  def from_envelope(_), do: {:error, "Invalid envelope format"}

  # ==========================================================================
  # Private
  # ==========================================================================

  defp build_materials(package, source_uri, source_digest) do
    materials = []

    # Source material
    materials = if source_uri != "" do
      [%BuildMaterial{
        uri: source_uri,
        digest: digest_map(source_digest)
      } | materials]
    else
      materials
    end

    # Package tarball material
    materials = if package.tarball_url do
      [%BuildMaterial{
        uri: package.tarball_url,
        digest: if(package.checksum,
          do: %{to_string(package.checksum_algo || "sha256") => package.checksum},
          else: %{})
      } | materials]
    else
      materials
    end

    # Dependency materials
    dep_materials = (package.manifest.dependencies || %{})
      |> Enum.map(fn {name, version} ->
        %BuildMaterial{uri: "pkg:#{package.forth}/#{name}@#{version}", digest: %{}}
      end)

    Enum.reverse(materials) ++ dep_materials
  end

  defp digest_map(""), do: %{}
  defp digest_map(nil), do: %{}
  defp digest_map(sha) when byte_size(sha) == 40, do: %{"sha1" => sha}
  defp digest_map(sha) when byte_size(sha) == 64, do: %{"sha256" => sha}
  defp digest_map(sha), do: %{"sha256" => sha}

  defp calculate_level(builder_id, source_digest, materials) do
    cond do
      # Level 3: Trusted builder + source tracking + materials
      builder_id in @trusted_builders and source_digest != "" and length(materials) > 0 ->
        3

      # Level 2: Authenticated provenance from hosted service
      builder_id in @trusted_builders and length(materials) > 0 ->
        2

      # Level 1: Provenance exists with materials
      length(materials) > 0 ->
        1

      # Level 0: No meaningful provenance
      true ->
        0
    end
  end

  defp verified_slsa_level(builder_trusted, materials_match, sig_valid) do
    cond do
      builder_trusted and materials_match and sig_valid == true -> 3
      builder_trusted and materials_match -> 2
      materials_match -> 1
      true -> 0
    end
  end

  defp check_builder(provenance, result) do
    if provenance.builder_id in @trusted_builders do
      {true, result}
    else
      {false, add_warning(result, "Builder '#{provenance.builder_id}' is not in trusted list")}
    end
  end

  defp check_materials(provenance, package, result) do
    # Check if package tarball appears in materials
    has_tarball = Enum.any?(provenance.materials, fn
      %BuildMaterial{uri: uri} -> uri == package.tarball_url
      %{uri: uri} -> uri == package.tarball_url
      %{"uri" => uri} -> uri == package.tarball_url
      _ -> false
    end)

    if has_tarball or is_nil(package.tarball_url) do
      {true, result}
    else
      {false, add_warning(result, "Package tarball not found in provenance materials")}
    end
  end

  defp check_signature(provenance, public_key, result) do
    algo = provenance.signature_algo || :ed25519
    envelope = to_envelope(provenance)

    case algo do
      :hybrid_ed25519_dilithium5 ->
        # Hybrid verification — public_key should be a map with :ed25519_pk and :dilithium5_pk
        sig_info = %{signature: provenance.signature, algorithm: algo}
        case HybridSignatures.verify_payload(envelope, sig_info, public_key) do
          :ok -> {true, result}
          {:ok, :classical_only} -> {true, add_warning(result, "Only classical Ed25519 verified (PQ NIF not loaded)")}
          {:ok, :pq_not_verified} -> {true, add_warning(result, "PQ signature not verified (NIF not loaded)")}
          {:error, reason} -> {false, add_error(result, "Hybrid signature invalid: #{reason}")}
        end

      :ed25519_only ->
        # Classical Ed25519 from hybrid keypair
        pk = if is_map(public_key) and Map.has_key?(public_key, :ed25519_pk),
          do: public_key.ed25519_pk,
          else: public_key
        case Signatures.verify_payload(envelope, provenance.signature, pk, :ed25519) do
          :ok -> {true, result}
          {:error, reason} -> {false, add_error(result, "Signature invalid: #{reason}")}
        end

      _ ->
        # Classical Ed25519
        case Signatures.verify_payload(envelope, provenance.signature, public_key, algo) do
          :ok -> {true, result}
          {:error, reason} -> {false, add_error(result, "Signature invalid: #{reason}")}
        end
    end
  end

  defp sign_provenance(provenance, secret_key) do
    envelope = to_envelope(provenance)
    Signatures.sign_payload(envelope, secret_key, :ed25519)
  end

  defp sign_provenance_hybrid(provenance, hybrid_keypair) do
    envelope = to_envelope(provenance)
    case HybridSignatures.sign_payload(envelope, hybrid_keypair) do
      {:ok, %{signature: sig, algorithm: algo}} -> {:ok, sig, algo}
      {:error, reason} -> {:error, reason}
    end
  end

  defp add_warning(result, msg), do: %{result | warnings: [msg | result.warnings]}
  defp add_error(result, msg), do: %{result | errors: [msg | result.errors]}

  defp generate_invocation_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
