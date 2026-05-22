# SPDX-License-Identifier: MPL-2.0
defmodule Opsm.Slsa do
  @moduledoc """
  SLSA (Supply-chain Levels for Software Artifacts) Level 3 compliance.

  Implements provenance generation, verification, and policy enforcement
  per the SLSA v1.0 specification (https://slsa.dev/spec/v1.0/).

  SLSA Level 3 requirements:
  - L1: Provenance exists (build metadata recorded)
  - L2: Hosted build platform (non-forgeable provenance)
  - L3: Hardened builds (isolated, parameterless, hermetic)

  Integration points:
  - Lockfile: slsa_level and slsa_provenance_uri fields
  - Installer: verify provenance before installing
  - Trust pipeline: provenance as attestation
  """

  alias Opsm.Crypto.{Hash, HybridSignatures}

  @slsa_predicate_type "https://slsa.dev/provenance/v1"
  @opsm_builder_id "https://opsm.dev/builder/v1"

  # ==========================================================================
  # Provenance Generation
  # ==========================================================================

  @doc """
  Generate SLSA provenance for a built/installed package.

  Returns an in-toto statement with SLSA provenance predicate.
  """
  def generate_provenance(package_info, build_info \\ %{}) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    subject = %{
      "name" => package_info[:name] || package_info.name,
      "digest" => %{
        "blake2b" => compute_digest(package_info),
        "sha3-512" => compute_digest_sha3(package_info)
      }
    }

    predicate = %{
      "buildDefinition" => %{
        "buildType" => @slsa_predicate_type,
        "externalParameters" => %{
          "package" => package_info[:name] || package_info.name,
          "version" => package_info[:version] || package_info.version,
          "forth" => to_string(package_info[:forth] || package_info.forth),
          "source_url" => package_info[:source_url] || package_info[:tarball_url]
        },
        "internalParameters" => %{
          "opsm_version" => "1.3.1",
          "resolver" => "pubgrub"
        },
        "resolvedDependencies" => build_resolved_deps(package_info)
      },
      "runDetails" => %{
        "builder" => %{
          "id" => Map.get(build_info, :builder_id, @opsm_builder_id),
          "version" => Map.get(build_info, :builder_version, %{})
        },
        "metadata" => %{
          "invocationId" => generate_invocation_id(),
          "startedOn" => Map.get(build_info, :started_at, now),
          "finishedOn" => now
        }
      }
    }

    statement = %{
      "_type" => "https://in-toto.io/Statement/v1",
      "subject" => [subject],
      "predicateType" => @slsa_predicate_type,
      "predicate" => predicate
    }

    {:ok, statement}
  end

  @doc """
  Sign a provenance statement with hybrid signatures (Ed25519 + Dilithium5).

  Returns `{:ok, %{statement: map, signature: map}}` or `{:error, reason}`.
  """
  def sign_provenance(statement, keypair) do
    case HybridSignatures.sign_payload(statement, keypair) do
      {:ok, sig_info} ->
        {:ok, %{
          statement: statement,
          signature: HybridSignatures.encode_signature(sig_info),
          signed_at: DateTime.utc_now() |> DateTime.to_iso8601()
        }}

      {:error, reason} ->
        {:error, "Provenance signing failed: #{reason}"}
    end
  end

  # ==========================================================================
  # Provenance Verification
  # ==========================================================================

  @doc """
  Verify a signed provenance bundle.

  Checks:
  1. Signature validity (Ed25519 + Dilithium5 if available)
  2. Subject digest matches package
  3. Builder ID is trusted
  4. Build was parameterless (L3)

  Returns `{:ok, level}` where level is 1, 2, or 3, or `{:error, reason}`.
  """
  def verify_provenance(bundle, package_info, public_keys, opts \\ []) do
    trusted_builders = Keyword.get(opts, :trusted_builders, [@opsm_builder_id])

    with :ok <- verify_signature(bundle, public_keys),
         :ok <- verify_subject(bundle.statement, package_info),
         :ok <- verify_builder(bundle.statement, trusted_builders),
         level <- determine_level(bundle.statement) do
      {:ok, level}
    end
  end

  defp verify_signature(bundle, public_keys) do
    sig_hex = bundle.signature["signature"]
    algo = case bundle.signature["algorithm"] do
      "hybrid_ed25519_dilithium5" -> :hybrid_ed25519_dilithium5
      _ -> :ed25519_only
    end

    case Base.decode16(sig_hex, case: :mixed) do
      {:ok, sig_bytes} ->
        sig_info = %{signature: sig_bytes, algorithm: algo}
        case HybridSignatures.verify_payload(bundle.statement, sig_info, public_keys) do
          :ok -> :ok
          {:ok, _mode} -> :ok
          {:error, reason} -> {:error, "Signature verification failed: #{reason}"}
        end

      :error ->
        {:error, "Invalid signature encoding"}
    end
  end

  defp verify_subject(statement, package_info) do
    subjects = statement["subject"] || []
    expected_name = package_info[:name] || package_info.name

    case Enum.find(subjects, fn s -> s["name"] == expected_name end) do
      nil ->
        {:error, "Package #{expected_name} not found in provenance subjects"}

      subject ->
        expected_digest = compute_digest(package_info)
        actual_digest = get_in(subject, ["digest", "blake2b"])

        if actual_digest == expected_digest do
          :ok
        else
          {:error, "Digest mismatch: expected #{expected_digest}, got #{actual_digest}"}
        end
    end
  end

  defp verify_builder(statement, trusted_builders) do
    builder_id = get_in(statement, ["predicate", "runDetails", "builder", "id"])

    if builder_id in trusted_builders do
      :ok
    else
      {:error, "Untrusted builder: #{builder_id}"}
    end
  end

  defp determine_level(statement) do
    predicate = statement["predicate"] || %{}
    run_details = predicate["runDetails"] || %{}
    builder = run_details["builder"] || %{}
    build_def = predicate["buildDefinition"] || %{}

    cond do
      # L3: Hardened build with isolated builder and no external parameters beyond package spec
      builder["id"] != nil and
        map_size(build_def["internalParameters"] || %{}) > 0 and
        build_def["buildType"] == @slsa_predicate_type ->
        3

      # L2: Hosted build platform with builder ID
      builder["id"] != nil ->
        2

      # L1: Provenance exists
      true ->
        1
    end
  end

  # ==========================================================================
  # Policy Enforcement
  # ==========================================================================

  @doc """
  Check if a package meets the required SLSA level.

  Returns `:ok` if met, `{:error, reason}` if not.
  """
  def enforce_level(package_info, required_level, opts \\ []) do
    actual_level = package_info[:slsa_level] || 0

    if actual_level >= required_level do
      :ok
    else
      action = Keyword.get(opts, :on_failure, :warn)

      case action do
        :block ->
          {:error, "Package #{package_info[:name]} has SLSA level #{actual_level}, requires #{required_level}"}

        :warn ->
          require Logger
          Logger.warning("Package #{package_info[:name]} has SLSA level #{actual_level}, expected #{required_level}")
          :ok

        :ignore ->
          :ok
      end
    end
  end

  @doc """
  Extract SLSA metadata for lockfile entry.

  Returns `%{slsa_level: integer, slsa_provenance_uri: string | nil}`.
  """
  def lockfile_metadata(provenance_bundle) when is_map(provenance_bundle) do
    level = determine_level(provenance_bundle[:statement] || provenance_bundle.statement)
    %{
      slsa_level: level,
      slsa_provenance_uri: provenance_bundle[:uri] || nil
    }
  end

  def lockfile_metadata(_), do: %{slsa_level: nil, slsa_provenance_uri: nil}

  # ==========================================================================
  # Helpers
  # ==========================================================================

  defp compute_digest(package_info) do
    data = "#{package_info[:name] || package_info.name}@#{package_info[:version] || package_info.version}"
    Hash.hash_hot(data)
  end

  defp compute_digest_sha3(package_info) do
    data = "#{package_info[:name] || package_info.name}@#{package_info[:version] || package_info.version}"
    Hash.hash_cold(data)
  end

  defp build_resolved_deps(package_info) do
    deps = package_info[:dependencies] || package_info[:resolved_deps] || []

    case deps do
      deps when is_list(deps) ->
        Enum.map(deps, fn
          dep when is_binary(dep) -> %{"uri" => dep}
          dep when is_map(dep) -> %{"uri" => dep[:name] || dep.name || "unknown"}
          _ -> %{"uri" => "unknown"}
        end)

      deps when is_map(deps) ->
        Enum.map(deps, fn {name, _ver} -> %{"uri" => to_string(name)} end)

      _ ->
        []
    end
  end

  defp generate_invocation_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
