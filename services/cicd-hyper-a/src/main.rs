// SPDX-License-Identifier: MPL-2.0
// Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//! CICD-Hyper-A: CI/CD pipeline and package publishing service
//!
//! Handles package publishing, manifest validation, federation sync
//! across registries, and ruleset enforcement.

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
    packages: Arc<RwLock<HashMap<String, Vec<PublishedPackage>>>>,
    rulesets: Arc<Vec<Ruleset>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct PublishedPackage {
    name: String,
    version: String,
    forth: String,
    manifest: serde_json::Value,
    attestations: Vec<String>,
    published_at: String,
    published_by: String,
    federation_status: FederationStatus,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct FederationStatus {
    synced_registries: Vec<String>,
    pending_registries: Vec<String>,
    failed_registries: Vec<FederationFailure>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct FederationFailure {
    registry: String,
    error: String,
    last_attempt: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct Ruleset {
    id: String,
    name: String,
    description: String,
    rules: Vec<Rule>,
    severity: RuleSeverity,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct Rule {
    id: String,
    check: String,
    message: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
enum RuleSeverity {
    Error,
    Warning,
    Info,
}

#[derive(Debug, Deserialize)]
struct PublishRequest {
    name: String,
    version: String,
    forth: String,
    manifest: serde_json::Value,
    #[serde(default)]
    attestations: Vec<String>,
    #[serde(default)]
    target_registries: Vec<String>,
}

#[derive(Debug, Serialize)]
struct PublishResponse {
    publish_id: String,
    name: String,
    version: String,
    status: String,
    federation_status: FederationStatus,
    published_at: String,
}

#[derive(Debug, Deserialize)]
struct ValidateRequest {
    manifest: serde_json::Value,
    #[serde(default)]
    rulesets: Vec<String>,
}

#[derive(Debug, Serialize)]
struct ValidateResponse {
    valid: bool,
    errors: Vec<ValidationIssue>,
    warnings: Vec<ValidationIssue>,
    rulesets_applied: Vec<String>,
}

#[derive(Debug, Serialize)]
struct ValidationIssue {
    rule_id: String,
    ruleset: String,
    message: String,
    field: Option<String>,
}

#[derive(Debug, Serialize)]
struct HealthResponse {
    status: String,
    version: String,
    packages_published: usize,
    rulesets_loaded: usize,
}

// ============================================================================
// Handlers
// ============================================================================

async fn health(State(state): State<AppState>) -> Json<HealthResponse> {
    let packages = state.packages.read().await;
    let total: usize = packages.values().map(|v| v.len()).sum();

    Json(HealthResponse {
        status: "healthy".to_string(),
        version: env!("CARGO_PKG_VERSION").to_string(),
        packages_published: total,
        rulesets_loaded: state.rulesets.len(),
    })
}

async fn publish_package(
    State(state): State<AppState>,
    Json(request): Json<PublishRequest>,
) -> Result<(StatusCode, Json<PublishResponse>), (StatusCode, String)> {
    info!("Publishing {}@{} to @{}", request.name, request.version, request.forth);

    let publish_id = Uuid::new_v4().to_string();
    let now = Utc::now().to_rfc3339();

    // Validate manifest before publishing
    let validation = validate_manifest(&request.manifest, &state.rulesets, &[]);
    if !validation.valid {
        return Err((
            StatusCode::BAD_REQUEST,
            format!(
                "Manifest validation failed: {}",
                validation
                    .errors
                    .iter()
                    .map(|e| e.message.as_str())
                    .collect::<Vec<_>>()
                    .join(", ")
            ),
        ));
    }

    let federation = FederationStatus {
        synced_registries: vec![request.forth.clone()],
        pending_registries: request.target_registries.clone(),
        failed_registries: vec![],
    };

    let pkg = PublishedPackage {
        name: request.name.clone(),
        version: request.version.clone(),
        forth: request.forth.clone(),
        manifest: request.manifest,
        attestations: request.attestations,
        published_at: now.clone(),
        published_by: "opsm-cli".to_string(),
        federation_status: federation.clone(),
    };

    let mut packages = state.packages.write().await;
    packages
        .entry(request.name.clone())
        .or_insert_with(Vec::new)
        .push(pkg);

    Ok((
        StatusCode::CREATED,
        Json(PublishResponse {
            publish_id,
            name: request.name,
            version: request.version,
            status: "published".to_string(),
            federation_status: federation,
            published_at: now,
        }),
    ))
}

async fn query_package_version(
    State(state): State<AppState>,
    Path((name, version)): Path<(String, String)>,
) -> Result<Json<PublishedPackage>, (StatusCode, String)> {
    let packages = state.packages.read().await;

    packages
        .get(&name)
        .and_then(|versions| versions.iter().find(|v| v.version == version))
        .cloned()
        .map(Json)
        .ok_or((
            StatusCode::NOT_FOUND,
            format!("Package {}@{} not found", name, version),
        ))
}

async fn query_package(
    State(state): State<AppState>,
    Path(name): Path<String>,
) -> Result<Json<Vec<PublishedPackage>>, (StatusCode, String)> {
    let packages = state.packages.read().await;

    packages
        .get(&name)
        .cloned()
        .map(Json)
        .ok_or((StatusCode::NOT_FOUND, format!("Package {} not found", name)))
}

async fn validate(
    State(state): State<AppState>,
    Json(request): Json<ValidateRequest>,
) -> Json<ValidateResponse> {
    info!("Validating manifest against {} rulesets", request.rulesets.len());
    let result = validate_manifest(&request.manifest, &state.rulesets, &request.rulesets);
    Json(result)
}

async fn list_rulesets(State(state): State<AppState>) -> Json<Vec<Ruleset>> {
    Json(state.rulesets.as_ref().clone())
}

async fn get_ruleset(
    State(state): State<AppState>,
    Path(ruleset_id): Path<String>,
) -> Result<Json<Ruleset>, (StatusCode, String)> {
    state
        .rulesets
        .iter()
        .find(|r| r.id == ruleset_id)
        .cloned()
        .map(Json)
        .ok_or((
            StatusCode::NOT_FOUND,
            format!("Ruleset {} not found", ruleset_id),
        ))
}

async fn federation_status(
    State(state): State<AppState>,
    Path((name, version)): Path<(String, String)>,
) -> Result<Json<FederationStatus>, (StatusCode, String)> {
    let packages = state.packages.read().await;

    packages
        .get(&name)
        .and_then(|versions| versions.iter().find(|v| v.version == version))
        .map(|pkg| Json(pkg.federation_status.clone()))
        .ok_or((
            StatusCode::NOT_FOUND,
            format!("Package {}@{} not found", name, version),
        ))
}

// ============================================================================
// Validation engine
// ============================================================================

fn validate_manifest(
    manifest: &serde_json::Value,
    all_rulesets: &[Ruleset],
    requested: &[String],
) -> ValidateResponse {
    let applicable: Vec<&Ruleset> = if requested.is_empty() {
        all_rulesets.iter().collect()
    } else {
        all_rulesets
            .iter()
            .filter(|r| requested.contains(&r.id))
            .collect()
    };

    let mut errors = Vec::new();
    let mut warnings = Vec::new();
    let rulesets_applied: Vec<String> = applicable.iter().map(|r| r.id.clone()).collect();

    for ruleset in &applicable {
        for rule in &ruleset.rules {
            let issue = check_rule(manifest, rule, &ruleset.id);
            if let Some(issue) = issue {
                match ruleset.severity {
                    RuleSeverity::Error => errors.push(issue),
                    RuleSeverity::Warning | RuleSeverity::Info => warnings.push(issue),
                }
            }
        }
    }

    ValidateResponse {
        valid: errors.is_empty(),
        errors,
        warnings,
        rulesets_applied,
    }
}

fn check_rule(
    manifest: &serde_json::Value,
    rule: &Rule,
    ruleset_id: &str,
) -> Option<ValidationIssue> {
    match rule.check.as_str() {
        "has_name" => {
            if manifest.get("name").and_then(|v| v.as_str()).is_none() {
                Some(ValidationIssue {
                    rule_id: rule.id.clone(),
                    ruleset: ruleset_id.to_string(),
                    message: rule.message.clone(),
                    field: Some("name".to_string()),
                })
            } else {
                None
            }
        }
        "has_version" => {
            if manifest.get("version").and_then(|v| v.as_str()).is_none() {
                Some(ValidationIssue {
                    rule_id: rule.id.clone(),
                    ruleset: ruleset_id.to_string(),
                    message: rule.message.clone(),
                    field: Some("version".to_string()),
                })
            } else {
                None
            }
        }
        "has_license" => {
            if manifest.get("license").and_then(|v| v.as_str()).is_none() {
                Some(ValidationIssue {
                    rule_id: rule.id.clone(),
                    ruleset: ruleset_id.to_string(),
                    message: rule.message.clone(),
                    field: Some("license".to_string()),
                })
            } else {
                None
            }
        }
        "has_description" => {
            if manifest
                .get("description")
                .and_then(|v| v.as_str())
                .is_none()
            {
                Some(ValidationIssue {
                    rule_id: rule.id.clone(),
                    ruleset: ruleset_id.to_string(),
                    message: rule.message.clone(),
                    field: Some("description".to_string()),
                })
            } else {
                None
            }
        }
        _ => None,
    }
}

// ============================================================================
// Default rulesets
// ============================================================================

fn build_default_rulesets() -> Vec<Ruleset> {
    vec![
        Ruleset {
            id: "opsm-required".to_string(),
            name: "OPSM Required Fields".to_string(),
            description: "Mandatory fields for OPSM package publishing".to_string(),
            rules: vec![
                Rule {
                    id: "R001".to_string(),
                    check: "has_name".to_string(),
                    message: "Package must have a name".to_string(),
                },
                Rule {
                    id: "R002".to_string(),
                    check: "has_version".to_string(),
                    message: "Package must have a version".to_string(),
                },
            ],
            severity: RuleSeverity::Error,
        },
        Ruleset {
            id: "opsm-recommended".to_string(),
            name: "OPSM Recommended Fields".to_string(),
            description: "Recommended metadata for better discoverability".to_string(),
            rules: vec![
                Rule {
                    id: "W001".to_string(),
                    check: "has_license".to_string(),
                    message: "Package should specify a license".to_string(),
                },
                Rule {
                    id: "W002".to_string(),
                    check: "has_description".to_string(),
                    message: "Package should have a description".to_string(),
                },
            ],
            severity: RuleSeverity::Warning,
        },
    ]
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

    info!("Starting CICD-Hyper-A v{}", env!("CARGO_PKG_VERSION"));

    let state = AppState {
        packages: Arc::new(RwLock::new(HashMap::new())),
        rulesets: Arc::new(build_default_rulesets()),
    };

    info!("{} rulesets loaded", state.rulesets.len());

    let app = Router::new()
        .route("/health", get(health))
        .route("/packages/publish", post(publish_package))
        .route("/packages/{name}/{version}", get(query_package_version))
        .route("/packages/{name}", get(query_package))
        .route(
            "/packages/{name}/{version}/federation",
            get(federation_status),
        )
        .route("/validate", post(validate))
        .route("/rulesets", get(list_rulesets))
        .route("/rulesets/{ruleset_id}", get(get_ruleset))
        .layer(TraceLayer::new_for_http())
        .with_state(state);

    let port = std::env::var("CICD_HYPER_A_PORT").unwrap_or_else(|_| "8084".to_string());
    let addr = format!("0.0.0.0:{}", port);

    info!("Listening on {}", addr);

    let listener = tokio::net::TcpListener::bind(&addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}
