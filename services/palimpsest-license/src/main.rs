// SPDX-License-Identifier: PMPL-1.0-or-later
//! Palimpsest: License analysis and compatibility service
//!
//! Analyzes artifacts for license declarations, checks compatibility
//! between licenses, and provides SPDX license metadata.

use axum::{
    extract::{Json, Path, State},
    http::StatusCode,
    routing::{get, post},
    Router,
};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tower_http::trace::TraceLayer;
use tracing::info;

// ============================================================================
// Types
// ============================================================================

#[derive(Clone)]
struct AppState {
    licenses: Arc<HashMap<String, LicenseInfo>>,
    compatibility_matrix: Arc<CompatibilityMatrix>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct LicenseInfo {
    spdx_id: String,
    name: String,
    osi_approved: bool,
    fsf_libre: bool,
    copyleft: CopyleftType,
    permissions: Vec<String>,
    conditions: Vec<String>,
    limitations: Vec<String>,
    url: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
enum CopyleftType {
    None,
    Weak,
    Strong,
    Network,
}

#[derive(Debug, Clone)]
struct CompatibilityMatrix {
    rules: Vec<CompatibilityRule>,
}

#[derive(Debug, Clone)]
struct CompatibilityRule {
    from: String,
    to: String,
    compatible: bool,
    note: String,
}

#[derive(Debug, Deserialize)]
struct AnalyzeRequest {
    artifact_path: String,
    #[serde(default)]
    #[allow(dead_code)]
    deep_scan: bool,
}

#[derive(Debug, Serialize)]
struct AnalyzeResponse {
    artifact_path: String,
    detected_licenses: Vec<DetectedLicense>,
    overall_spdx: Option<String>,
    confidence: f64,
    warnings: Vec<String>,
}

#[derive(Debug, Serialize)]
struct DetectedLicense {
    spdx_id: String,
    file_path: String,
    confidence: f64,
    method: String,
}

#[derive(Debug, Deserialize)]
struct CompatibilityRequest {
    licenses: Vec<String>,
}

#[derive(Debug, Serialize)]
struct CompatibilityResponse {
    compatible: bool,
    licenses: Vec<String>,
    conflicts: Vec<CompatibilityConflict>,
    combined_spdx: Option<String>,
    recommendation: String,
}

#[derive(Debug, Serialize)]
struct CompatibilityConflict {
    license_a: String,
    license_b: String,
    reason: String,
}

#[derive(Debug, Serialize)]
struct HealthResponse {
    status: String,
    version: String,
    licenses_indexed: usize,
}

// ============================================================================
// Handlers
// ============================================================================

async fn health(State(state): State<AppState>) -> Json<HealthResponse> {
    Json(HealthResponse {
        status: "healthy".to_string(),
        version: env!("CARGO_PKG_VERSION").to_string(),
        licenses_indexed: state.licenses.len(),
    })
}

async fn analyze_artifact(
    State(_state): State<AppState>,
    Json(request): Json<AnalyzeRequest>,
) -> Json<AnalyzeResponse> {
    info!("Analyzing licenses for: {}", request.artifact_path);

    // Stub: would use license detection heuristics (header scanning, LICENSE file parsing)
    Json(AnalyzeResponse {
        artifact_path: request.artifact_path,
        detected_licenses: vec![],
        overall_spdx: None,
        confidence: 0.0,
        warnings: vec!["License detection not yet implemented — stub service".to_string()],
    })
}

async fn get_analysis(
    Path(encoded_path): Path<String>,
) -> Result<Json<AnalyzeResponse>, (StatusCode, String)> {
    let path = urlencoding::decode(&encoded_path)
        .map_err(|_| (StatusCode::BAD_REQUEST, "Invalid path encoding".to_string()))?;

    Ok(Json(AnalyzeResponse {
        artifact_path: path.to_string(),
        detected_licenses: vec![],
        overall_spdx: None,
        confidence: 0.0,
        warnings: vec!["Cached analysis not available".to_string()],
    }))
}

async fn check_compatibility(
    State(state): State<AppState>,
    Json(request): Json<CompatibilityRequest>,
) -> Json<CompatibilityResponse> {
    info!("Checking compatibility for: {:?}", request.licenses);

    let mut conflicts = Vec::new();

    // Check each pair of licenses against compatibility matrix
    for (i, l1) in request.licenses.iter().enumerate() {
        for l2 in request.licenses.iter().skip(i + 1) {
            if let Some(conflict) = check_pair(&state.compatibility_matrix, l1, l2) {
                conflicts.push(conflict);
            }
        }
    }

    let compatible = conflicts.is_empty();

    let combined = if compatible && !request.licenses.is_empty() {
        Some(request.licenses.join(" AND "))
    } else {
        None
    };

    let recommendation = if compatible {
        "All licenses are compatible".to_string()
    } else {
        format!(
            "Found {} compatibility conflict(s) — review before combining",
            conflicts.len()
        )
    };

    Json(CompatibilityResponse {
        compatible,
        licenses: request.licenses,
        conflicts,
        combined_spdx: combined,
        recommendation,
    })
}

async fn get_compatibility_pair(
    State(state): State<AppState>,
    Path((l1, l2)): Path<(String, String)>,
) -> Json<CompatibilityResponse> {
    let licenses = vec![l1.clone(), l2.clone()];
    let conflict = check_pair(&state.compatibility_matrix, &l1, &l2);

    Json(CompatibilityResponse {
        compatible: conflict.is_none(),
        licenses,
        conflicts: conflict.into_iter().collect(),
        combined_spdx: None,
        recommendation: String::new(),
    })
}

async fn get_license(
    State(state): State<AppState>,
    Path(spdx_id): Path<String>,
) -> Result<Json<LicenseInfo>, (StatusCode, String)> {
    let upper = spdx_id.to_uppercase();
    state
        .licenses
        .get(&upper)
        .cloned()
        .map(Json)
        .ok_or((StatusCode::NOT_FOUND, format!("License {} not found", spdx_id)))
}

async fn list_licenses(State(state): State<AppState>) -> Json<Vec<LicenseInfo>> {
    let mut licenses: Vec<LicenseInfo> = state.licenses.values().cloned().collect();
    licenses.sort_by(|a, b| a.spdx_id.cmp(&b.spdx_id));
    Json(licenses)
}

// ============================================================================
// Compatibility engine
// ============================================================================

fn check_pair(matrix: &CompatibilityMatrix, l1: &str, l2: &str) -> Option<CompatibilityConflict> {
    let l1_upper = l1.to_uppercase();
    let l2_upper = l2.to_uppercase();

    for rule in &matrix.rules {
        let matches = (rule.from.to_uppercase() == l1_upper && rule.to.to_uppercase() == l2_upper)
            || (rule.from.to_uppercase() == l2_upper && rule.to.to_uppercase() == l1_upper);

        if matches && !rule.compatible {
            return Some(CompatibilityConflict {
                license_a: l1.to_string(),
                license_b: l2.to_string(),
                reason: rule.note.clone(),
            });
        }
    }
    None
}

// ============================================================================
// License database (built-in core set)
// ============================================================================

fn build_license_db() -> HashMap<String, LicenseInfo> {
    let mut db = HashMap::new();

    let entries = vec![
        ("MIT", "MIT License", true, true, CopyleftType::None),
        ("Apache-2.0", "Apache License 2.0", true, true, CopyleftType::None),
        ("BSD-2-Clause", "BSD 2-Clause", true, true, CopyleftType::None),
        ("BSD-3-Clause", "BSD 3-Clause", true, true, CopyleftType::None),
        ("ISC", "ISC License", true, true, CopyleftType::None),
        ("MPL-2.0", "Mozilla Public License 2.0", true, true, CopyleftType::Weak),
        ("LGPL-2.1-only", "GNU LGPL v2.1", true, true, CopyleftType::Weak),
        ("LGPL-3.0-only", "GNU LGPL v3.0", true, true, CopyleftType::Weak),
        ("GPL-2.0-only", "GNU GPL v2.0", true, true, CopyleftType::Strong),
        ("GPL-3.0-only", "GNU GPL v3.0", true, true, CopyleftType::Strong),
        ("AGPL-3.0-only", "GNU AGPL v3.0", true, true, CopyleftType::Network),
        ("Unlicense", "The Unlicense", true, true, CopyleftType::None),
        ("0BSD", "Zero-Clause BSD", true, true, CopyleftType::None),
        ("CC0-1.0", "CC0 1.0 Universal", false, false, CopyleftType::None),
        ("PMPL-1.0-or-later", "Palimpsest License", false, false, CopyleftType::Weak),
    ];

    for (spdx, name, osi, fsf, copyleft) in entries {
        db.insert(
            spdx.to_uppercase(),
            LicenseInfo {
                spdx_id: spdx.to_string(),
                name: name.to_string(),
                osi_approved: osi,
                fsf_libre: fsf,
                copyleft,
                permissions: vec![],
                conditions: vec![],
                limitations: vec![],
                url: format!("https://spdx.org/licenses/{}.html", spdx),
            },
        );
    }

    db
}

fn build_compatibility_matrix() -> CompatibilityMatrix {
    CompatibilityMatrix {
        rules: vec![
            CompatibilityRule {
                from: "GPL-3.0-only".into(),
                to: "Apache-2.0".into(),
                compatible: true,
                note: "Apache-2.0 is compatible with GPL-3.0".into(),
            },
            CompatibilityRule {
                from: "GPL-2.0-only".into(),
                to: "Apache-2.0".into(),
                compatible: false,
                note: "Apache-2.0 patent clause conflicts with GPL-2.0".into(),
            },
            CompatibilityRule {
                from: "GPL-3.0-only".into(),
                to: "MPL-2.0".into(),
                compatible: true,
                note: "MPL-2.0 allows relicensing under GPL-3.0".into(),
            },
            CompatibilityRule {
                from: "AGPL-3.0-only".into(),
                to: "GPL-3.0-only".into(),
                compatible: false,
                note: "AGPL network clause not present in GPL-3.0".into(),
            },
        ],
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

    info!(
        "Starting Palimpsest License v{}",
        env!("CARGO_PKG_VERSION")
    );

    let state = AppState {
        licenses: Arc::new(build_license_db()),
        compatibility_matrix: Arc::new(build_compatibility_matrix()),
    };

    info!("{} licenses indexed", state.licenses.len());

    let app = Router::new()
        .route("/health", get(health))
        .route("/analyze", post(analyze_artifact))
        .route("/analyze/{path}", get(get_analysis))
        .route("/compatibility", post(check_compatibility))
        .route("/compatibility/{l1}/{l2}", get(get_compatibility_pair))
        .route("/licenses/{spdx_id}", get(get_license))
        .route("/licenses", get(list_licenses))
        .layer(TraceLayer::new_for_http())
        .with_state(state);

    let port =
        std::env::var("PALIMPSEST_LICENSE_PORT").unwrap_or_else(|_| "8082".to_string());
    let addr = format!("0.0.0.0:{}", port);

    info!("Listening on {}", addr);

    let listener = tokio::net::TcpListener::bind(&addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}
