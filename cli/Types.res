// SPDX-License-Identifier: PMPL-1.0
// Types.res - Core type definitions for OPM CLI

// =============================================================================
// Result type (compatible with proven)
// =============================================================================

type result<'a> = Ok('a) | Error(string)

// =============================================================================
// HTTP Configuration
// =============================================================================

type httpConfig = {
  timeoutMs: int,
  retries: int,
  backoffMs: int,
}

type httpOptions = {
  timeoutMs: int,
  retries: int,
  backoffMs: int,
}

// =============================================================================
// Service Configuration
// =============================================================================

type serviceConfig = {
  baseUrl: string,
  token: option<string>,
}

type opmConfig = {
  http: httpConfig,
  claimForge: serviceConfig,
  checkyMonkey: serviceConfig,
  palimpsestLicense: serviceConfig,
  cicdHyperA: serviceConfig,
  oikos: serviceConfig,
}

// =============================================================================
// CLI Request/Response Types
// =============================================================================

type publishRequest = {path: string}

type auditRequest = {package: string}

type statusResponse = {
  registryHub: string,
  federation: string,
}

// =============================================================================
// OIKOS - Ecosystem Sustainability Analysis
// =============================================================================

type oikosAnalysisRequest = {
  repositoryUrl: string,
  branch: option<string>,
  commitSha: option<string>,
}

type sustainabilityScores = {
  maintainability: int,
  documentation: int,
  testCoverage: int,
  communityHealth: int,
  securityPosture: int,
  dependencyHealth: int,
  releaseMaturity: int,
  codeQuality: int,
}

type riskSeverity = Low | Medium | High | Critical

type oikosRisk = {
  severity: riskSeverity,
  category: string,
  description: string,
  remediation: option<string>,
}

type oikosAnalysisResponse = {
  repositoryUrl: string,
  analyzedAt: string,
  overallScore: int,
  scores: sustainabilityScores,
  recommendations: array<string>,
  risks: array<oikosRisk>,
}

type oikosDiffRequest = {
  repositoryUrl: string,
  baseRef: string,
  headRef: string,
}

type oikosDiffResponse = {
  repositoryUrl: string,
  baseRef: string,
  headRef: string,
  analyzedAt: string,
  overallDelta: int,
  impactSummary: string,
}

type serviceStatus = Healthy | Degraded | Unhealthy

type oikosHealthResponse = {
  status: serviceStatus,
  version: string,
  uptime: int,
}

// =============================================================================
// CICD-HYPER-A - Registry and CI/CD Pipeline Hub
// =============================================================================

type packageMetadata = {
  name: string,
  version: string,
  description: option<string>,
  license: string,
  repository: option<string>,
  authors: array<string>,
  keywords: array<string>,
  dependencies: Dict.t<string>,
  devDependencies: option<Dict.t<string>>,
}

type attestationType = ClaimForge | Sigstore | InToto

type attestationRef = {
  attestationType: attestationType,
  uri: string,
  digest: string,
}

type cicdPublishRequest = {
  manifest: packageMetadata,
  tarballUrl: option<string>,
  attestations: array<attestationRef>,
}

type syncState = {
  synced: bool,
  lastSync: option<string>,
  error: option<string>,
}

type federationStatus = {
  github: syncState,
  gitlab: syncState,
  codeberg: syncState,
  radicle: syncState,
  ipfs: option<syncState>,
}

type cicdPublishResponse = {
  packageId: string,
  version: string,
  publishedAt: string,
  registryUrl: string,
  federationStatus: federationStatus,
}

type ruleSeverity = RuleError | RuleWarning | RuleInfo

type rule = {
  id: string,
  severity: ruleSeverity,
  message: string,
  check: string,
}

type ruleset = {
  id: string,
  name: string,
  version: string,
  rules: array<rule>,
  appliesTo: array<string>,
}

type packageQueryRequest = {
  name: string,
  version: option<string>,
  includeScores: option<bool>,
}

type packageQueryResponse = {
  package: packageMetadata,
  versions: array<string>,
  latestVersion: string,
  scores: option<sustainabilityScores>,
  dependents: int,
  downloads: int,
}

// =============================================================================
// CLAIM-FORGE - Attestation Generation
// =============================================================================

type claimType =
  | BuildProvenance
  | SourceAttestation
  | VulnerabilityScan
  | LicenseCompliance
  | CodeReview

type claimForgeRequest = {
  artifactPath: string,
  artifactDigest: string,
  claimType: claimType,
  metadata: option<Dict.t<JSON.t>>,
}

type claimForgeResponse = {
  attestationId: string,
  claimType: claimType,
  createdAt: string,
  expiresAt: option<string>,
  attestationUri: string,
  signature: string,
  publicKeyId: string,
}

type claimVerifyRequest = {
  attestationUri: string,
  artifactDigest: string,
}

type claimVerifyResponse = {
  valid: bool,
  claimType: claimType,
  issuer: string,
  issuedAt: string,
  errors: option<array<string>>,
}

// =============================================================================
// CHECKY-MONKEY - Code Verification
// =============================================================================

type verificationType =
  | PropertyTests
  | FuzzTesting
  | TypeChecking
  | FormalVerification
  | MutationTesting

type checkyMonkeyRequest = {
  repositoryUrl: string,
  commitSha: string,
  verificationTypes: array<verificationType>,
  timeout: option<int>,
}

type verificationStatus = Queued | Running | Completed | Failed

type codeLocation = {
  file: string,
  line: int,
  column: option<int>,
  endLine: option<int>,
  endColumn: option<int>,
}

type findingSeverity = FindingLow | FindingMedium | FindingHigh | FindingCritical

type finding = {
  severity: findingSeverity,
  category: string,
  location: option<codeLocation>,
  message: string,
  suggestion: option<string>,
}

type verificationResult = {
  verificationType: verificationType,
  passed: bool,
  coverage: option<float>,
  findings: array<finding>,
  duration: int,
}

type checkyMonkeyResponse = {
  requestId: string,
  status: verificationStatus,
  startedAt: option<string>,
  completedAt: option<string>,
  results: option<array<verificationResult>>,
}

// =============================================================================
// PALIMPSEST-LICENSE - License Analysis
// =============================================================================

type licenseSource = FileHeader | LicenseFile | Manifest | Inferred

type detectedLicense = {
  spdxId: string,
  confidence: float,
  locations: array<string>,
  source: licenseSource,
}

type conflictSeverity = ConflictWarning | ConflictError

type licenseConflict = {
  license1: string,
  license2: string,
  reason: string,
  severity: conflictSeverity,
}

type licenseCompatibility = {
  compatible: bool,
  targetLicense: option<string>,
  conflicts: array<licenseConflict>,
}

type obligationType = Notice | SourceDisclosure | SameLicense | PatentGrant

type licenseObligation = {
  license: string,
  obligation: string,
  obligationType: obligationType,
}

type licenseRiskSeverity = LicenseRiskLow | LicenseRiskMedium | LicenseRiskHigh

type licenseRisk = {
  severity: licenseRiskSeverity,
  license: string,
  risk: string,
  recommendation: string,
}

type palimpsestRequest = {
  artifactPath: string,
  includeTransitive: option<bool>,
  targetLicense: option<string>,
}

type palimpsestResponse = {
  analyzedAt: string,
  detectedLicenses: array<detectedLicense>,
  compatibility: licenseCompatibility,
  obligations: array<licenseObligation>,
  risks: array<licenseRisk>,
}
