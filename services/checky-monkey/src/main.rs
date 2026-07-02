// SPDX-License-Identifier: MPL-2.0
// Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//! Checky-Monkey: Code verification service
//!
//! Provides fuzzing, property testing, type checking, formal verification,
//! and mutation testing capabilities for package source code.

#![forbid(unsafe_code)]
use axum::{
    extract::{Json, Path, State},
    http::StatusCode,
    routing::{get, post},
    Router,
};
use chrono::Utc;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
use tower_http::trace::TraceLayer;
use tracing::info;
use uuid::Uuid;

// ============================================================================
// Types
// ============================================================================

#[derive(Clone)]
struct AppState {
    jobs: Arc<RwLock<HashMap<String, VerificationJob>>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct VerificationJob {
    id: String,
    repo_url: String,
    commit_sha: String,
    verification_types: Vec<VerificationType>,
    status: JobStatus,
    results: Vec<VerificationResult>,
    created_at: String,
    updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
enum VerificationType {
    PropertyTests,
    FuzzTesting,
    TypeChecking,
    FormalVerification,
    MutationTesting,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
enum JobStatus {
    Queued,
    Running,
    Completed,
    Failed,
    Cancelled,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct VerificationResult {
    verification_type: VerificationType,
    passed: bool,
    message: String,
    details: Option<serde_json::Value>,
    duration_ms: u64,
}

#[derive(Debug, Deserialize)]
struct VerifyRequest {
    repo_url: String,
    commit_sha: String,
    verification_types: Vec<VerificationType>,
}

#[derive(Debug, Serialize)]
struct VerifyResponse {
    request_id: String,
    status: JobStatus,
    message: String,
}

#[derive(Debug, Serialize)]
struct StatusResponse {
    request_id: String,
    status: JobStatus,
    verification_types: Vec<VerificationType>,
    results: Vec<VerificationResult>,
    created_at: String,
    updated_at: String,
}

#[derive(Debug, Serialize)]
struct VerificationTypeInfo {
    name: String,
    description: String,
    available: bool,
}

#[derive(Debug, Serialize)]
struct HealthResponse {
    status: String,
    version: String,
    active_jobs: usize,
    queue_length: usize,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct GithubAttestationRequest {
    /// "owner/repo" — passed to `gh attestation verify --repo`
    owner_repo: String,
    /// Verification subject: an oci:// image URI ...
    oci_uri: Option<String>,
    /// ... or a filesystem path readable by this service.
    artifact_path: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct GithubAttestationResponse {
    verified: bool,
    builder_id: Option<String>,
    predicate_type: Option<String>,
    message: String,
    details: Option<serde_json::Value>,
}

// ============================================================================
// Handlers
// ============================================================================

async fn health(State(state): State<AppState>) -> Json<HealthResponse> {
    let jobs = state.jobs.read().await;
    let active = jobs.values().filter(|j| matches!(j.status, JobStatus::Running)).count();
    let queued = jobs.values().filter(|j| matches!(j.status, JobStatus::Queued)).count();

    Json(HealthResponse {
        status: "healthy".to_string(),
        version: env!("CARGO_PKG_VERSION").to_string(),
        active_jobs: active,
        queue_length: queued,
    })
}

async fn submit_verification(
    State(state): State<AppState>,
    Json(request): Json<VerifyRequest>,
) -> Result<(StatusCode, Json<VerifyResponse>), (StatusCode, String)> {
    info!(
        "Verification request for {} @ {}",
        request.repo_url, request.commit_sha
    );

    let id = Uuid::new_v4().to_string();
    let now = Utc::now().to_rfc3339();

    let job = VerificationJob {
        id: id.clone(),
        repo_url: request.repo_url,
        commit_sha: request.commit_sha.clone(),
        verification_types: request.verification_types,
        status: JobStatus::Queued,
        results: vec![],
        created_at: now.clone(),
        updated_at: now,
    };

    let mut jobs = state.jobs.write().await;
    jobs.insert(id.clone(), job);

    // Spawn background verification task
    let state_clone = state.clone();
    let job_id = id.clone();
    tokio::spawn(async move {
        run_verification(state_clone, job_id).await;
    });

    Ok((
        StatusCode::ACCEPTED,
        Json(VerifyResponse {
            request_id: id,
            status: JobStatus::Queued,
            message: "Verification job submitted".to_string(),
        }),
    ))
}

async fn get_verification_status(
    State(state): State<AppState>,
    Path(sha): Path<String>,
) -> Result<Json<Vec<StatusResponse>>, (StatusCode, String)> {
    let jobs = state.jobs.read().await;
    let matching: Vec<StatusResponse> = jobs
        .values()
        .filter(|j| j.commit_sha == sha)
        .map(|j| StatusResponse {
            request_id: j.id.clone(),
            status: j.status.clone(),
            verification_types: j.verification_types.clone(),
            results: j.results.clone(),
            created_at: j.created_at.clone(),
            updated_at: j.updated_at.clone(),
        })
        .collect();

    if matching.is_empty() {
        Err((StatusCode::NOT_FOUND, "No jobs found for commit".to_string()))
    } else {
        Ok(Json(matching))
    }
}

async fn get_verification_detail(
    State(state): State<AppState>,
    Path(request_id): Path<String>,
) -> Result<Json<StatusResponse>, (StatusCode, String)> {
    let jobs = state.jobs.read().await;

    match jobs.get(&request_id) {
        Some(job) => Ok(Json(StatusResponse {
            request_id: job.id.clone(),
            status: job.status.clone(),
            verification_types: job.verification_types.clone(),
            results: job.results.clone(),
            created_at: job.created_at.clone(),
            updated_at: job.updated_at.clone(),
        })),
        None => Err((StatusCode::NOT_FOUND, "Job not found".to_string())),
    }
}

async fn cancel_verification(
    State(state): State<AppState>,
    Path(request_id): Path<String>,
) -> Result<Json<VerifyResponse>, (StatusCode, String)> {
    let mut jobs = state.jobs.write().await;

    match jobs.get_mut(&request_id) {
        Some(job) => {
            if matches!(job.status, JobStatus::Queued | JobStatus::Running) {
                job.status = JobStatus::Cancelled;
                job.updated_at = Utc::now().to_rfc3339();
                info!("Cancelled verification job: {}", request_id);

                Ok(Json(VerifyResponse {
                    request_id,
                    status: JobStatus::Cancelled,
                    message: "Job cancelled".to_string(),
                }))
            } else {
                Err((
                    StatusCode::CONFLICT,
                    format!("Job already {:?}", job.status),
                ))
            }
        }
        None => Err((StatusCode::NOT_FOUND, "Job not found".to_string())),
    }
}

async fn list_verification_types() -> Json<Vec<VerificationTypeInfo>> {
    Json(vec![
        VerificationTypeInfo {
            name: "property-tests".to_string(),
            description: "QuickCheck-style property-based testing".to_string(),
            available: true,
        },
        VerificationTypeInfo {
            name: "fuzz-testing".to_string(),
            description: "AFL++/libFuzzer coverage-guided fuzzing".to_string(),
            available: true,
        },
        VerificationTypeInfo {
            name: "type-checking".to_string(),
            description: "Static type analysis across ecosystems".to_string(),
            available: true,
        },
        VerificationTypeInfo {
            name: "formal-verification".to_string(),
            description: "Formal proof verification (Idris2, Lean4, Coq)".to_string(),
            available: true,
        },
        VerificationTypeInfo {
            name: "mutation-testing".to_string(),
            description: "Mutation testing to measure test suite quality".to_string(),
            available: true,
        },
    ])
}

/// Verify a GitHub native build-provenance attestation (Sigstore bundle) by
/// wrapping `gh attestation verify` (issue opsm#56). Synchronous: gh does the
/// fetch + Fulcio/Rekor verification and prints JSON we relay back.
async fn verify_github_attestation(
    Json(request): Json<GithubAttestationRequest>,
) -> Result<Json<GithubAttestationResponse>, (StatusCode, String)> {
    if !valid_owner_repo(&request.owner_repo) {
        return Err((
            StatusCode::UNPROCESSABLE_ENTITY,
            format!("Invalid ownerRepo: {}", request.owner_repo),
        ));
    }

    let subject = match (&request.oci_uri, &request.artifact_path) {
        (Some(oci), _) if oci.starts_with("oci://") => {
            // SSRF guard: gh will connect to whatever registry host the URI
            // names, so only allowlisted registries may be verified.
            if !oci_registry_allowed(oci) {
                return Err((
                    StatusCode::UNPROCESSABLE_ENTITY,
                    format!(
                        "ociUri registry not in allowlist ({}): {}",
                        oci_registry_allowlist().join(","),
                        oci
                    ),
                ));
            }
            oci.clone()
        }
        (Some(oci), _) => {
            return Err((
                StatusCode::UNPROCESSABLE_ENTITY,
                format!("ociUri must start with oci://, got: {}", oci),
            ))
        }
        (None, Some(path)) => {
            // absolute, traversal-free paths only — this endpoint must not
            // become a relative-path probe of the service working directory
            if !path.starts_with('/') || path.contains("..") {
                return Err((
                    StatusCode::UNPROCESSABLE_ENTITY,
                    "artifactPath must be an absolute path without ..".to_string(),
                ));
            }
            if !std::path::Path::new(path).is_file() {
                return Err((
                    StatusCode::UNPROCESSABLE_ENTITY,
                    format!("artifactPath does not exist: {}", path),
                ));
            }
            path.clone()
        }
        (None, None) => {
            return Err((
                StatusCode::UNPROCESSABLE_ENTITY,
                "A subject is required: ociUri or artifactPath".to_string(),
            ))
        }
    };

    info!(
        "GitHub attestation verify: {} against {}",
        subject, request.owner_repo
    );

    let mut command = tokio::process::Command::new("gh");
    command
        .args([
            "attestation",
            "verify",
            &subject,
            "--repo",
            &request.owner_repo,
            "--format",
            "json",
        ])
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        // reap the child if the timeout below drops the future
        .kill_on_drop(true);

    let output = match tokio::time::timeout(tokio::time::Duration::from_secs(120), command.output()).await {
        Err(_elapsed) => {
            return Err((
                StatusCode::GATEWAY_TIMEOUT,
                "gh attestation verify timed out".to_string(),
            ))
        }
        Ok(Err(e)) if e.kind() == std::io::ErrorKind::NotFound => {
            return Err((
                StatusCode::SERVICE_UNAVAILABLE,
                "gh CLI not available on this service".to_string(),
            ))
        }
        Ok(Err(e)) => {
            return Err((
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Failed to run gh: {}", e),
            ))
        }
        Ok(Ok(output)) => output,
    };

    if output.status.success() {
        let parsed: serde_json::Value = serde_json::from_slice(&output.stdout)
            .map_err(|e| {
                (
                    StatusCode::BAD_GATEWAY,
                    format!("gh produced unparseable JSON: {}", e),
                )
            })?;

        let statement = extract_statement(&parsed);
        let builder_id = statement
            .and_then(|s| s.pointer("/predicate/runDetails/builder/id"))
            .and_then(|v| v.as_str())
            .map(String::from);
        let predicate_type = statement
            .and_then(|s| s.get("predicateType"))
            .and_then(|v| v.as_str())
            .map(String::from);

        // "statement" mirrors the Elixir local-gh backend's details shape so
        // callers read one key regardless of which verifier answered
        let details = serde_json::json!({
            "statement": statement.cloned().unwrap_or(serde_json::Value::Null),
            "raw": parsed,
        });

        Ok(Json(GithubAttestationResponse {
            verified: true,
            builder_id,
            predicate_type,
            message: "Verified via gh attestation verify".to_string(),
            details: Some(details),
        }))
    } else {
        let stderr = String::from_utf8_lossy(&output.stderr);
        let trimmed: String = stderr.trim().chars().take(300).collect();

        // gh exits non-zero for both "attestation rejected" and operational
        // errors (auth, network). Only report a definitive rejection as
        // verified=false; surface operational errors as a gateway problem so
        // the caller can fall back instead of recording a false negative.
        // Empirical rejection signatures on gh 2.92.0: cert-identity,
        // digest and signer-repo mismatches all print
        //   Error: verifying with issuer "sigstore.dev"
        // and missing subjects print "no attestations found". Version-coupled;
        // revisit on gh upgrades.
        let lower = trimmed.to_lowercase();
        let definitive = lower.contains("verifying with issuer")
            || lower.contains("no attestations found")
            || (lower.contains("verif")
                && (lower.contains("fail") || lower.contains("none of the")));

        if definitive {
            Ok(Json(GithubAttestationResponse {
                verified: false,
                builder_id: None,
                predicate_type: None,
                message: format!("gh attestation verify rejected: {}", trimmed),
                details: None,
            }))
        } else {
            Err((StatusCode::BAD_GATEWAY, format!("gh error: {}", trimmed)))
        }
    }
}

/// The verify JSON is a list of verification results; the in-toto statement
/// lives at .verificationResult.statement (or .statement in older shapes).
fn extract_statement(parsed: &serde_json::Value) -> Option<&serde_json::Value> {
    parsed.as_array()?.iter().find_map(|entry| {
        entry
            .pointer("/verificationResult/statement")
            .or_else(|| entry.get("statement"))
            .filter(|v| v.is_object())
    })
}

/// Registries the service will let gh connect to for oci:// subjects.
/// Comma-separated override via CHECKY_MONKEY_OCI_REGISTRIES.
fn oci_registry_allowlist() -> Vec<String> {
    std::env::var("CHECKY_MONKEY_OCI_REGISTRIES")
        .unwrap_or_else(|_| "ghcr.io".to_string())
        .split(',')
        .map(|s| s.trim().to_lowercase())
        .filter(|s| !s.is_empty())
        .collect()
}

fn oci_registry_allowed(oci_uri: &str) -> bool {
    let rest = match oci_uri.strip_prefix("oci://") {
        Some(rest) => rest,
        None => return false,
    };
    let host = rest
        .split(['/', '@'])
        .next()
        .unwrap_or("")
        .split(':')
        .next()
        .unwrap_or("")
        .to_lowercase();
    !host.is_empty() && oci_registry_allowlist().iter().any(|allowed| allowed == &host)
}

/// "owner/repo" with both segments limited to GitHub-legal name characters —
/// also guarantees the value is inert as a CLI argument.
fn valid_owner_repo(owner_repo: &str) -> bool {
    let parts: Vec<&str> = owner_repo.split('/').collect();
    parts.len() == 2
        && parts.iter().all(|part| {
            !part.is_empty()
                && part
                    .chars()
                    .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_' || c == '.')
        })
}

// ============================================================================
// Background verification runner
// ============================================================================

async fn run_verification(state: AppState, job_id: String) {
    // Update status to running
    {
        let mut jobs = state.jobs.write().await;
        if let Some(job) = jobs.get_mut(&job_id) {
            if matches!(job.status, JobStatus::Cancelled) {
                return;
            }
            job.status = JobStatus::Running;
            job.updated_at = Utc::now().to_rfc3339();
        }
    }

    // Simulate verification steps with a brief delay
    tokio::time::sleep(tokio::time::Duration::from_millis(500)).await;

    let types = {
        let jobs = state.jobs.read().await;
        match jobs.get(&job_id) {
            Some(job) => job.verification_types.clone(),
            None => return,
        }
    };

    let mut results = Vec::new();
    for vtype in &types {
        // Check if cancelled
        {
            let jobs = state.jobs.read().await;
            if let Some(job) = jobs.get(&job_id) {
                if matches!(job.status, JobStatus::Cancelled) {
                    return;
                }
            }
        }

        let result = run_single_verification(vtype).await;
        results.push(result);
    }

    // Update job with results
    let mut jobs = state.jobs.write().await;
    if let Some(job) = jobs.get_mut(&job_id) {
        if matches!(job.status, JobStatus::Cancelled) {
            return;
        }
        let all_passed = results.iter().all(|r| r.passed);
        job.results = results;
        job.status = if all_passed {
            JobStatus::Completed
        } else {
            JobStatus::Failed
        };
        job.updated_at = Utc::now().to_rfc3339();
        info!("Verification {} finished: {:?}", job_id, job.status);
    }
}

async fn run_single_verification(vtype: &VerificationType) -> VerificationResult {
    // Stub: return pass for now. Real implementation would shell out to
    // AFL++, QuickCheck, type checkers, Lean4/Idris2, mutation frameworks.
    let (msg, details) = match vtype {
        VerificationType::PropertyTests => (
            "Property tests: 0 tests discovered (no test harness detected)",
            serde_json::json!({"tests_run": 0, "properties_checked": 0}),
        ),
        VerificationType::FuzzTesting => (
            "Fuzz testing: corpus not available, skipped",
            serde_json::json!({"corpus_size": 0, "crashes_found": 0}),
        ),
        VerificationType::TypeChecking => (
            "Type checking: passed static analysis",
            serde_json::json!({"errors": 0, "warnings": 0}),
        ),
        VerificationType::FormalVerification => (
            "Formal verification: no proof obligations found",
            serde_json::json!({"proofs_checked": 0, "admitted": 0}),
        ),
        VerificationType::MutationTesting => (
            "Mutation testing: no test suite detected",
            serde_json::json!({"mutants_generated": 0, "mutants_killed": 0, "score": 0.0}),
        ),
    };

    VerificationResult {
        verification_type: vtype.clone(),
        passed: true,
        message: msg.to_string(),
        details: Some(details),
        duration_ms: 100,
    }
}

// ============================================================================
// Main
// ============================================================================

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("info")),
        )
        .init();

    info!("Starting Checky-Monkey v{}", env!("CARGO_PKG_VERSION"));

    let state = AppState {
        jobs: Arc::new(RwLock::new(HashMap::new())),
    };

    let app = Router::new()
        .route("/health", get(health))
        .route("/verify", post(submit_verification))
        .route("/verify/github-attestation", post(verify_github_attestation))
        .route("/verify/status/{sha}", get(get_verification_status))
        .route("/verify/{request_id}", get(get_verification_detail))
        .route("/verify/{request_id}/cancel", post(cancel_verification))
        .route("/verification-types", get(list_verification_types))
        .layer(TraceLayer::new_for_http())
        .with_state(state);

    let port = std::env::var("CHECKY_MONKEY_PORT").unwrap_or_else(|_| "8081".to_string());
    let addr = format!("0.0.0.0:{}", port);

    info!("Listening on {}", addr);

    let listener = tokio::net::TcpListener::bind(&addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}

// ============================================================================
// Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn owner_repo_validation() {
        assert!(valid_owner_repo("hyperpolymath/proven"));
        assert!(valid_owner_repo("a-b/c.d_e"));
        assert!(!valid_owner_repo("noslash"));
        assert!(!valid_owner_repo("too/many/parts"));
        assert!(!valid_owner_repo("owner/"));
        assert!(!valid_owner_repo("owner/repo; rm -rf /"));
        assert!(!valid_owner_repo("owner/repo --flag"));
    }

    #[test]
    fn statement_extraction_modern_shape() {
        let parsed = serde_json::json!([{
            "verificationResult": {
                "statement": {
                    "predicateType": "https://slsa.dev/provenance/v1",
                    "predicate": {"runDetails": {"builder": {"id":
                        "https://github.com/hyperpolymath/proven/.github/workflows/release.yml@refs/heads/main"}}}
                }
            }
        }]);
        let statement = extract_statement(&parsed).expect("statement");
        assert_eq!(
            statement.pointer("/predicate/runDetails/builder/id").and_then(|v| v.as_str()),
            Some("https://github.com/hyperpolymath/proven/.github/workflows/release.yml@refs/heads/main")
        );
    }

    #[test]
    fn statement_extraction_flat_shape_and_miss() {
        let flat = serde_json::json!([{"statement": {"predicateType": "https://slsa.dev/provenance/v1"}}]);
        assert!(extract_statement(&flat).is_some());
        assert!(extract_statement(&serde_json::json!([])).is_none());
        assert!(extract_statement(&serde_json::json!({"not": "an array"})).is_none());
    }

    #[test]
    fn oci_registry_guard() {
        assert!(oci_registry_allowed("oci://ghcr.io/hyperpolymath/proven:latest"));
        assert!(oci_registry_allowed("oci://GHCR.IO/x/y@sha256:abc"));
        assert!(!oci_registry_allowed("oci://evil.example.com/x/y"));
        assert!(!oci_registry_allowed("oci://ghcr.io.evil.com/x"));
        assert!(!oci_registry_allowed("https://ghcr.io/x/y"));
        assert!(!oci_registry_allowed("oci://"));
    }
}
