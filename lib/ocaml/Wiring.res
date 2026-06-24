// SPDX-License-Identifier: MPL-2.0
@@warning("-44-45")
open Types

// =============================================================================
// Publish Pipeline
// =============================================================================

let runPublish = async (config: opsmConfig, path: string): result<unit> => {
  let httpOpts: httpOptions = {
    timeoutMs: config.http.timeoutMs,
    retries: config.http.retries,
    backoffMs: config.http.backoffMs,
  }

  Console.log(`Publishing package from: ${path}`)

  // Step 1: Generate attestation via claim-forge
  Console.log("  → Generating attestation via claim-forge...")
  let claimForgeClient = ClaimForge.make(
    config.claimForge.baseUrl,
    config.claimForge.token,
    httpOpts,
  )

  let attestResult = await claimForgeClient->ClaimForge.attest({
    artifactPath: path,
    artifactDigest: "sha256:placeholder",
    claimType: BuildProvenance,
    metadata: None,
  })

  switch attestResult {
  | Error(e) => Console.log(`  ✗ Attestation failed: ${e}`)
  | Ok(_) => Console.log("  ✓ Attestation generated")
  }

  // Step 2: Verify with checky-monkey
  Console.log("  → Running verification via checky-monkey...")
  let checkyClient = CheckyMonkey.make(
    config.checkyMonkey.baseUrl,
    config.checkyMonkey.token,
    httpOpts,
  )

  let verifyResult = await checkyClient->CheckyMonkey.submitVerification({
    repositoryUrl: path,
    commitSha: "HEAD",
    verificationTypes: [PropertyTests, TypeChecking],
    timeout: Some(300),
  })

  switch verifyResult {
  | Error(e) => Console.log(`  ✗ Verification failed: ${e}`)
  | Ok(resp) => Console.log(`  ✓ Verification submitted: ${resp.requestId}`)
  }

  // Step 3: Check license compliance
  Console.log("  → Checking license compliance via palimpsest-license...")
  let palimpsestClient = Palimpsest.make(
    config.palimpsestLicense.baseUrl,
    config.palimpsestLicense.token,
    httpOpts,
  )

  let licenseResult = await palimpsestClient->Palimpsest.analyze({
    artifactPath: path,
    includeTransitive: Some(true),
    targetLicense: Some("PMPL-1.0"),
  })

  switch licenseResult {
  | Error(e) => Console.log(`  ✗ License check failed: ${e}`)
  | Ok(resp) =>
    if resp.compatibility.compatible {
      Console.log("  ✓ License compatible")
    } else {
      Console.log("  ✗ License conflicts detected")
    }
  }

  // Step 4: Publish to registry
  Console.log("  → Publishing to registry via cicd-hyper-a...")
  let cicdClient = CicdHyperA.make(config.cicdHyperA.baseUrl, config.cicdHyperA.token, httpOpts)

  let publishResult = await cicdClient->CicdHyperA.publish({
    manifest: {
      name: path,
      version: "0.1.0",
      description: None,
      license: "PMPL-1.0",
      repository: None,
      authors: [],
      keywords: [],
      dependencies: Dict.make(),
      devDependencies: None,
    },
    tarballUrl: None,
    attestations: [],
  })

  switch publishResult {
  | Error(e) => {
      Console.log(`  ✗ Publish failed: ${e}`)
      Error(e)
    }
  | Ok(resp) => {
      Console.log(`  ✓ Published: ${resp.packageId}`)
      Ok()
    }
  }
}

// =============================================================================
// Audit Pipeline
// =============================================================================

let runAudit = async (config: opsmConfig, packageName: string): result<unit> => {
  let httpOpts: httpOptions = {
    timeoutMs: config.http.timeoutMs,
    retries: config.http.retries,
    backoffMs: config.http.backoffMs,
  }

  Console.log(`Auditing package: ${packageName}`)

  // Step 1: Get sustainability scores from oikos
  Console.log("  → Getting sustainability scores from oikos...")
  let oikosClient = Oikos.make(config.oikos.baseUrl, config.oikos.token, httpOpts)

  let analysisResult = await oikosClient->Oikos.analyzeRepository({
    repositoryUrl: packageName,
    branch: None,
    commitSha: None,
  })

  switch analysisResult {
  | Error(e) => Console.log(`  ✗ Analysis failed: ${e}`)
  | Ok(resp) => {
      Console.log(`  ✓ Overall score: ${resp.overallScore->Int.toString}/100`)
      Console.log(`    - Maintainability: ${resp.scores.maintainability->Int.toString}`)
      Console.log(`    - Documentation: ${resp.scores.documentation->Int.toString}`)
      Console.log(`    - Test Coverage: ${resp.scores.testCoverage->Int.toString}`)
      Console.log(`    - Security: ${resp.scores.securityPosture->Int.toString}`)
    }
  }

  // Step 2: Check licenses
  Console.log("  → Checking licenses via palimpsest-license...")
  let palimpsestClient = Palimpsest.make(
    config.palimpsestLicense.baseUrl,
    config.palimpsestLicense.token,
    httpOpts,
  )

  let licenseResult = await palimpsestClient->Palimpsest.analyze({
    artifactPath: packageName,
    includeTransitive: Some(true),
    targetLicense: None,
  })

  switch licenseResult {
  | Error(e) => Console.log(`  ✗ License analysis failed: ${e}`)
  | Ok(resp) => {
      let count = resp.detectedLicenses->Array.length
      Console.log(`  ✓ Found ${count->Int.toString} licenses`)
    }
  }

  Ok()
}

// =============================================================================
// Status Check
// =============================================================================

let runStatus = async (config: opsmConfig): result<unit> => {
  let httpOpts: httpOptions = {
    timeoutMs: config.http.timeoutMs,
    retries: config.http.retries,
    backoffMs: config.http.backoffMs,
  }

  Console.log("OPSM Service Status")
  Console.log("==================")

  // Check oikos
  let oikosClient = Oikos.make(config.oikos.baseUrl, config.oikos.token, httpOpts)
  let oikosHealth = await oikosClient->Oikos.health
  switch oikosHealth {
  | Ok(h) =>
    let status = switch h.status {
    | Healthy => "✓ healthy"
    | Degraded => "⚠ degraded"
    | Unhealthy => "✗ unhealthy"
    }
    Console.log(`oikos: ${status} (${h.version})`)
  | Error(_) => Console.log("oikos: ✗ unreachable")
  }

  // Check checky-monkey
  let checkyClient = CheckyMonkey.make(
    config.checkyMonkey.baseUrl,
    config.checkyMonkey.token,
    httpOpts,
  )
  let checkyHealth = await checkyClient->CheckyMonkey.health
  switch checkyHealth {
  | Ok(h) =>
    let status = switch h.status {
    | Healthy => "✓ healthy"
    | Degraded => "⚠ degraded"
    | Unhealthy => "✗ unhealthy"
    }
    Console.log(`checky-monkey: ${status} (${h.version})`)
  | Error(_) => Console.log("checky-monkey: ✗ unreachable")
  }

  // Show config info
  Console.log("")
  Console.log("Configuration")
  Console.log("-------------")
  Console.log(`claim-forge: ${config.claimForge.baseUrl}`)
  Console.log(`checky-monkey: ${config.checkyMonkey.baseUrl}`)
  Console.log(`palimpsest-license: ${config.palimpsestLicense.baseUrl}`)
  Console.log(`cicd-hyper-a: ${config.cicdHyperA.baseUrl}`)
  Console.log(`oikos: ${config.oikos.baseUrl}`)

  Ok()
}
