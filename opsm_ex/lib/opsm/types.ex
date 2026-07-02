# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Types do
  @moduledoc """
  Core type definitions for OPSM CLI.
  """

  # =============================================================================
  # HTTP Configuration
  # =============================================================================

  defmodule HttpConfig do
    @type t :: %__MODULE__{
            timeout_ms: pos_integer(),
            retries: non_neg_integer(),
            backoff_ms: pos_integer()
          }
    defstruct timeout_ms: 3000, retries: 2, backoff_ms: 200
  end

  # =============================================================================
  # Service Configuration
  # =============================================================================

  defmodule ServiceConfig do
    @type t :: %__MODULE__{
            base_url: String.t(),
            token: String.t() | nil
          }
    defstruct [:base_url, :token]
  end

  defmodule OpsmConfig do
    @type t :: %__MODULE__{
            http: HttpConfig.t(),
            checky_monkey: ServiceConfig.t(),
            palimpsest_license: ServiceConfig.t(),
            oikos: ServiceConfig.t()
          }
    defstruct [:http, :checky_monkey, :palimpsest_license, :oikos]
  end

  # =============================================================================
  # OIKOS - Ecosystem Sustainability Analysis
  # =============================================================================

  defmodule SustainabilityScores do
    @type t :: %__MODULE__{
            maintainability: integer(),
            documentation: integer(),
            test_coverage: integer(),
            community_health: integer(),
            security_posture: integer(),
            dependency_health: integer(),
            release_maturity: integer(),
            code_quality: integer()
          }
    defstruct maintainability: 0,
              documentation: 0,
              test_coverage: 0,
              community_health: 0,
              security_posture: 0,
              dependency_health: 0,
              release_maturity: 0,
              code_quality: 0
  end

  @type risk_severity :: :low | :medium | :high | :critical
  @type service_status :: :healthy | :degraded | :unhealthy

  defmodule OikosRisk do
    @type t :: %__MODULE__{
            severity: Opsm.Types.risk_severity(),
            category: String.t(),
            description: String.t(),
            remediation: String.t() | nil
          }
    defstruct [:severity, :category, :description, :remediation]
  end

  defmodule OikosAnalysisRequest do
    @type t :: %__MODULE__{
            repository_url: String.t(),
            branch: String.t() | nil,
            commit_sha: String.t() | nil
          }
    defstruct [:repository_url, :branch, :commit_sha]
  end

  defmodule OikosAnalysisResponse do
    @type t :: %__MODULE__{
            repository_url: String.t(),
            analyzed_at: String.t(),
            overall_score: integer(),
            scores: SustainabilityScores.t(),
            recommendations: [String.t()],
            risks: [OikosRisk.t()]
          }
    defstruct [:repository_url, :analyzed_at, :overall_score, :scores, recommendations: [], risks: []]
  end

  defmodule OikosHealthResponse do
    @type t :: %__MODULE__{
            status: Opsm.Types.service_status(),
            version: String.t(),
            uptime: integer()
          }
    defstruct [:status, :version, :uptime]
  end

  # =============================================================================
  # Attestation & Package Metadata
  # =============================================================================

  @type attestation_type :: :sigstore | :in_toto

  defmodule AttestationRef do
    @type t :: %__MODULE__{
            attestation_type: Opsm.Types.attestation_type(),
            uri: String.t(),
            digest: String.t()
          }
    defstruct [:attestation_type, :uri, :digest]
  end

  defmodule GithubAttestationVerification do
    @moduledoc """
    Result of verifying a GitHub native build-provenance attestation
    (a Sigstore bundle) — via checky-monkey or the local gh CLI.
    """
    @type t :: %__MODULE__{
            verified: boolean(),
            builder_id: String.t() | nil,
            predicate_type: String.t() | nil,
            message: String.t(),
            details: map() | nil
          }
    defstruct verified: false, builder_id: nil, predicate_type: nil, message: "", details: nil
  end

  defmodule PackageMetadata do
    @type t :: %__MODULE__{
            name: String.t(),
            version: String.t(),
            description: String.t() | nil,
            license: String.t(),
            repository: String.t() | nil,
            authors: [String.t()],
            keywords: [String.t()],
            dependencies: map(),
            dev_dependencies: map() | nil
          }
    defstruct [:name, :version, :description, :license, :repository,
               authors: [], keywords: [], dependencies: %{}, dev_dependencies: nil]
  end

  # =============================================================================
  # CHECKY-MONKEY - Code Verification
  # =============================================================================

  @type verification_type :: :property_tests | :fuzz_testing | :type_checking
                            | :formal_verification | :mutation_testing
  @type verification_status :: :queued | :running | :completed | :failed
  @type finding_severity :: :low | :medium | :high | :critical

  defmodule CodeLocation do
    @type t :: %__MODULE__{
            file: String.t(),
            line: integer(),
            column: integer() | nil,
            end_line: integer() | nil,
            end_column: integer() | nil
          }
    defstruct [:file, :line, :column, :end_line, :end_column]
  end

  defmodule Finding do
    @type t :: %__MODULE__{
            severity: Opsm.Types.finding_severity(),
            category: String.t(),
            location: CodeLocation.t() | nil,
            message: String.t(),
            suggestion: String.t() | nil
          }
    defstruct [:severity, :category, :location, :message, :suggestion]
  end

  defmodule VerificationResult do
    @type t :: %__MODULE__{
            verification_type: Opsm.Types.verification_type(),
            passed: boolean(),
            coverage: float() | nil,
            findings: [Finding.t()],
            duration: integer()
          }
    defstruct [:verification_type, :passed, :coverage, :duration, findings: []]
  end

  defmodule CheckyMonkeyRequest do
    @type t :: %__MODULE__{
            repository_url: String.t(),
            commit_sha: String.t(),
            verification_types: [Opsm.Types.verification_type()],
            timeout: integer() | nil
          }
    defstruct [:repository_url, :commit_sha, verification_types: [], timeout: nil]
  end

  defmodule CheckyMonkeyResponse do
    @type t :: %__MODULE__{
            request_id: String.t(),
            status: Opsm.Types.verification_status(),
            started_at: String.t() | nil,
            completed_at: String.t() | nil,
            results: [VerificationResult.t()] | nil
          }
    defstruct [:request_id, :status, :started_at, :completed_at, :results]
  end

  # =============================================================================
  # PALIMPSEST-LICENSE - License Analysis
  # =============================================================================

  @type license_source :: :file_header | :license_file | :manifest | :inferred
  @type conflict_severity :: :warning | :error
  @type obligation_type :: :notice | :source_disclosure | :same_license | :patent_grant
  @type license_risk_severity :: :low | :medium | :high

  defmodule DetectedLicense do
    @type t :: %__MODULE__{
            spdx_id: String.t(),
            confidence: float(),
            locations: [String.t()],
            source: Opsm.Types.license_source()
          }
    defstruct [:spdx_id, :confidence, :source, locations: []]
  end

  defmodule LicenseConflict do
    @type t :: %__MODULE__{
            license1: String.t(),
            license2: String.t(),
            reason: String.t(),
            severity: Opsm.Types.conflict_severity()
          }
    defstruct [:license1, :license2, :reason, :severity]
  end

  defmodule LicenseCompatibility do
    @type t :: %__MODULE__{
            compatible: boolean(),
            target_license: String.t() | nil,
            conflicts: [LicenseConflict.t()]
          }
    defstruct compatible: true, target_license: nil, conflicts: []
  end

  defmodule LicenseObligation do
    @type t :: %__MODULE__{
            license: String.t(),
            obligation: String.t(),
            obligation_type: Opsm.Types.obligation_type()
          }
    defstruct [:license, :obligation, :obligation_type]
  end

  defmodule LicenseRisk do
    @type t :: %__MODULE__{
            severity: Opsm.Types.license_risk_severity(),
            license: String.t(),
            risk: String.t(),
            recommendation: String.t()
          }
    defstruct [:severity, :license, :risk, :recommendation]
  end

  defmodule PalimpsestRequest do
    @type t :: %__MODULE__{
            artifact_path: String.t(),
            include_transitive: boolean() | nil,
            target_license: String.t() | nil
          }
    defstruct [:artifact_path, :include_transitive, :target_license]
  end

  defmodule PalimpsestResponse do
    @type t :: %__MODULE__{
            analyzed_at: String.t(),
            detected_licenses: [DetectedLicense.t()],
            compatibility: LicenseCompatibility.t(),
            obligations: [LicenseObligation.t()],
            risks: [LicenseRisk.t()]
          }
    defstruct [:analyzed_at, :compatibility,
               detected_licenses: [], obligations: [], risks: []]
  end

  # =============================================================================
  # FEDERATION - Multi-Source Package Resolution
  # =============================================================================

  @type federation_mode :: :manifest_convert | :agentic_fetch | :connection_port

  @type forth_type :: :npm | :cargo | :hex | :pypi | :gem | :nuget | :maven | :pub | :go
                     | :deb | :rpm | :winget | :choco | :scoop | :pacman | :homebrew
                     | :nix | :guix | :flatpak | :snap | :custom | :eclexia

  @type release_channel :: :snapshot | :alpha | :beta | :rc | :esr | :stable

  @type install_scope :: :systemwide | :user | :project

  defmodule ForthConfig do
    @moduledoc """
    Configuration for a federated package registry (forth).
    """
    @type t :: %__MODULE__{
            name: atom(),
            forth_type: Opsm.Types.forth_type(),
            base_url: String.t(),
            federation_mode: Opsm.Types.federation_mode(),
            manifest_converter: String.t() | nil,
            enabled: boolean()
          }
    defstruct [:name, :forth_type, :base_url, :federation_mode,
               :manifest_converter, enabled: true]
  end

  defmodule ManifestFormat do
    @moduledoc """
    Unified manifest format for cross-ecosystem conversion.
    Nickel/Idris2 manifests convert to this intermediate format.
    """
    @type t :: %__MODULE__{
            name: String.t(),
            version: String.t(),
            description: String.t() | nil,
            license: String.t() | nil,
            homepage: String.t() | nil,
            repository: String.t() | nil,
            authors: [String.t()],
            keywords: [String.t()],
            dependencies: map(),
            dev_dependencies: map(),
            optional_dependencies: map(),
            peer_dependencies: map(),
            bin: map(),
            scripts: map(),
            source_forth: Opsm.Types.forth_type() | nil,
            raw_manifest: map() | nil
          }
    defstruct [:name, :version, :description, :license, :homepage, :repository,
               :source_forth, :raw_manifest,
               authors: [], keywords: [], dependencies: %{}, dev_dependencies: %{},
               optional_dependencies: %{}, peer_dependencies: %{}, bin: %{}, scripts: %{}]
  end

  defmodule InstallRequest do
    @moduledoc """
    Unified install request across all forths.
    """
    @type t :: %__MODULE__{
            package: String.t(),
            version: String.t() | nil,
            forth: Opsm.Types.forth_type() | nil,
            channel: Opsm.Types.release_channel(),
            scope: Opsm.Types.install_scope(),
            dry_run: boolean(),
            force: boolean(),
            optional_deps: boolean(),
            dev_deps: boolean()
          }
    defstruct [:package, :version, :forth,
               channel: :stable, scope: :user, dry_run: false,
               force: false, optional_deps: false, dev_deps: false]
  end

  defmodule ResolvedPackage do
    @moduledoc """
    A package resolved from federation lookup.
    """
    @type t :: %__MODULE__{
            package: String.t(),
            version: String.t(),
            forth: Opsm.Types.forth_type(),
            registry_url: String.t(),
            tarball_url: String.t() | nil,
            checksum: String.t() | nil,
            checksum_algo: atom(),
            manifest: ManifestFormat.t(),
            attestations: [AttestationRef.t()],
            resolved_deps: [__MODULE__.t()]
          }
    defstruct [:package, :version, :forth, :registry_url, :tarball_url,
               :checksum, :manifest,
               checksum_algo: :sha256, attestations: [], resolved_deps: []]
  end

  defmodule PinSpec do
    @moduledoc """
    Version pin specification (like apt hold / dnf versionlock).
    """
    @type t :: %__MODULE__{
            package: String.t(),
            forth: Opsm.Types.forth_type() | nil,
            version: String.t() | nil,
            version_constraint: String.t() | nil,
            pinned_at: String.t(),
            reason: String.t() | nil
          }
    defstruct [:package, :forth, :version, :version_constraint, :pinned_at, :reason]
  end

  defmodule TransactionEntry do
    @moduledoc """
    History entry for package transactions (like dnf history).
    """
    @type action :: :install | :remove | :upgrade | :downgrade | :reinstall | :autoremove
    @type t :: %__MODULE__{
            id: integer(),
            action: action(),
            package: String.t(),
            version: String.t(),
            previous_version: String.t() | nil,
            forth: Opsm.Types.forth_type(),
            timestamp: String.t(),
            user: String.t() | nil,
            scope: Opsm.Types.install_scope()
          }
    defstruct [:id, :action, :package, :version, :previous_version,
               :forth, :timestamp, :user, :scope]
  end

  # =============================================================================
  # SLSA Provenance Types
  # =============================================================================

  @type slsa_level :: 0 | 1 | 2 | 3 | 4

  defmodule SlsaProvenance do
    @moduledoc "SLSA v1.0 provenance predicate."
    @type t :: %__MODULE__{
            builder_id: String.t(),
            build_type: String.t(),
            invocation: map(),
            materials: [map()],
            metadata: map(),
            slsa_level: Opsm.Types.slsa_level(),
            signature: String.t() | nil,
            signature_algo: atom() | nil
          }
    defstruct [
      :builder_id, :build_type, :invocation, :metadata,
      :signature, :signature_algo,
      materials: [], slsa_level: 0
    ]
  end

  defmodule BuildMaterial do
    @moduledoc "A single build input material (source, dependency, tool)."
    @type t :: %__MODULE__{
            uri: String.t(),
            digest: %{String.t() => String.t()}
          }
    defstruct [:uri, digest: %{}]
  end

  defmodule SlsaVerificationResult do
    @moduledoc "Result of SLSA provenance verification."
    @type t :: %__MODULE__{
            verified: boolean(),
            slsa_level: Opsm.Types.slsa_level(),
            builder_trusted: boolean(),
            materials_match: boolean(),
            signature_valid: boolean() | :not_checked,
            warnings: [String.t()],
            errors: [String.t()]
          }
    defstruct [
      verified: false, slsa_level: 0, builder_trusted: false,
      materials_match: false, signature_valid: :not_checked,
      warnings: [], errors: []
    ]
  end

  defmodule ConnectionPort do
    @moduledoc """
    Bridge configuration for system package managers.
    Allows OPSM to export packages to deb/rpm/winget/etc.
    """
    @type t :: %__MODULE__{
            target: Opsm.Types.forth_type(),
            command: String.t(),
            convert_script: String.t() | nil,
            post_install_hook: String.t() | nil,
            enabled: boolean()
          }
    defstruct [:target, :command, :convert_script, :post_install_hook, enabled: false]
  end
end
