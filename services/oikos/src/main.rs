// SPDX-License-Identifier: PMPL-1.0-or-later
//! Oikos: Repository sustainability and health analysis service
//!
//! Analyzes repositories for maintainability, documentation quality,
//! test coverage, community health, security posture, dependency health,
//! release maturity, and code quality.

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

// ============================================================================
// Types
// ============================================================================

#[derive(Clone)]
struct AppState {
    analyses: Arc<RwLock<HashMap<String, AnalysisResult>>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct SustainabilityScores {
    maintainability: f64,
    documentation: f64,
    test_coverage: f64,
    community_health: f64,
    security_posture: f64,
    dependency_health: f64,
    release_maturity: f64,
    code_quality: f64,
}

impl SustainabilityScores {
    fn overall(&self) -> f64 {
        (self.maintainability
            + self.documentation
            + self.test_coverage
            + self.community_health
            + self.security_posture
            + self.dependency_health
            + self.release_maturity
            + self.code_quality)
            / 8.0
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct AnalysisResult {
    repo_url: String,
    scores: SustainabilityScores,
    overall_score: f64,
    grade: String,
    findings: Vec<Finding>,
    recommendations: Vec<String>,
    analyzed_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct Finding {
    category: String,
    severity: FindingSeverity,
    message: String,
    file_path: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
enum FindingSeverity {
    Info,
    Warning,
    Critical,
}

#[derive(Debug, Deserialize)]
struct RepoAnalysisRequest {
    repo_url: String,
    #[serde(default)]
    #[allow(dead_code)]
    include_dependencies: bool,
}

#[derive(Debug, Deserialize)]
struct DiffAnalysisRequest {
    repo_url: String,
    base_ref: String,
    head_ref: String,
}

#[derive(Debug, Serialize)]
struct DiffAnalysisResponse {
    repo_url: String,
    base_ref: String,
    head_ref: String,
    score_delta: SustainabilityScores,
    overall_delta: f64,
    improved: Vec<String>,
    degraded: Vec<String>,
    analyzed_at: String,
}

#[derive(Debug, Serialize)]
struct HealthResponse {
    status: String,
    version: String,
    analyses_cached: usize,
}

// ============================================================================
// Handlers
// ============================================================================

async fn health(State(state): State<AppState>) -> Json<HealthResponse> {
    let analyses = state.analyses.read().await;
    Json(HealthResponse {
        status: "healthy".to_string(),
        version: env!("CARGO_PKG_VERSION").to_string(),
        analyses_cached: analyses.len(),
    })
}

async fn analyze_repository(
    State(state): State<AppState>,
    Json(request): Json<RepoAnalysisRequest>,
) -> Json<AnalysisResult> {
    info!("Analyzing repository: {}", request.repo_url);

    // Stub analysis — real implementation would clone the repo and run checks
    let scores = SustainabilityScores {
        maintainability: 0.0,
        documentation: 0.0,
        test_coverage: 0.0,
        community_health: 0.0,
        security_posture: 0.0,
        dependency_health: 0.0,
        release_maturity: 0.0,
        code_quality: 0.0,
    };

    let overall = scores.overall();
    let grade = score_to_grade(overall);

    let result = AnalysisResult {
        repo_url: request.repo_url.clone(),
        scores,
        overall_score: overall,
        grade,
        findings: vec![Finding {
            category: "meta".to_string(),
            severity: FindingSeverity::Info,
            message: "Repository analysis is in stub mode — metrics not yet computed"
                .to_string(),
            file_path: None,
        }],
        recommendations: vec![
            "Add a SECURITY.md file".to_string(),
            "Set up CI/CD pipeline".to_string(),
            "Add CONTRIBUTING.md guidelines".to_string(),
        ],
        analyzed_at: Utc::now().to_rfc3339(),
    };

    // Cache result
    let key = urlencoding::encode(&request.repo_url).to_string();
    let mut analyses = state.analyses.write().await;
    analyses.insert(key, result.clone());

    Json(result)
}

async fn get_repository_analysis(
    State(state): State<AppState>,
    Path(encoded_url): Path<String>,
) -> Result<Json<AnalysisResult>, (StatusCode, String)> {
    let analyses = state.analyses.read().await;

    analyses
        .get(&encoded_url)
        .cloned()
        .map(Json)
        .ok_or((StatusCode::NOT_FOUND, "No cached analysis found".to_string()))
}

async fn analyze_diff(
    Json(request): Json<DiffAnalysisRequest>,
) -> Json<DiffAnalysisResponse> {
    info!(
        "Analyzing diff for {} ({}..{})",
        request.repo_url, request.base_ref, request.head_ref
    );

    // Stub: real implementation would diff analysis between two refs
    Json(DiffAnalysisResponse {
        repo_url: request.repo_url,
        base_ref: request.base_ref,
        head_ref: request.head_ref,
        score_delta: SustainabilityScores {
            maintainability: 0.0,
            documentation: 0.0,
            test_coverage: 0.0,
            community_health: 0.0,
            security_posture: 0.0,
            dependency_health: 0.0,
            release_maturity: 0.0,
            code_quality: 0.0,
        },
        overall_delta: 0.0,
        improved: vec![],
        degraded: vec![],
        analyzed_at: Utc::now().to_rfc3339(),
    })
}

async fn get_diff_analysis(
    Path(encoded_url): Path<String>,
) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    Err((
        StatusCode::NOT_FOUND,
        format!("No cached diff analysis for {}", encoded_url),
    ))
}

// ============================================================================
// Helpers
// ============================================================================

fn score_to_grade(score: f64) -> String {
    match score {
        s if s >= 90.0 => "A+",
        s if s >= 80.0 => "A",
        s if s >= 70.0 => "B",
        s if s >= 60.0 => "C",
        s if s >= 50.0 => "D",
        _ => "F",
    }
    .to_string()
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

    info!("Starting Oikos v{}", env!("CARGO_PKG_VERSION"));

    let state = AppState {
        analyses: Arc::new(RwLock::new(HashMap::new())),
    };

    let app = Router::new()
        .route("/health", get(health))
        .route("/analysis/repository", post(analyze_repository))
        .route(
            "/analysis/repository/{encoded_url}",
            get(get_repository_analysis),
        )
        .route("/analysis/diff", post(analyze_diff))
        .route("/analysis/diff/{encoded_url}", get(get_diff_analysis))
        .layer(TraceLayer::new_for_http())
        .with_state(state);

    let port = std::env::var("OIKOS_PORT").unwrap_or_else(|_| "8083".to_string());
    let addr = format!("0.0.0.0:{}", port);

    info!("Listening on {}", addr);

    let listener = tokio::net::TcpListener::bind(&addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}
