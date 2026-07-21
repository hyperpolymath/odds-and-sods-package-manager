// SPDX-License-Identifier: MPL-2.0
// Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//! Svalinn: Container vulnerability scanning service
//!
//! Integrates Trivy and Grype for comprehensive vulnerability detection.

#![forbid(unsafe_code)]
use axum::{
    extract::{Json, State},
    http::StatusCode,
    routing::{get, post},
    Router,
};
use chrono::Utc;
use serde::{Deserialize, Serialize};
use std::process::Stdio;
use tokio::process::Command;
use tower_http::trace::TraceLayer;
use tracing::{error, info, warn};

// ============================================================================
// Types
// ============================================================================

#[derive(Clone)]
struct AppState {
    trivy_enabled: bool,
    grype_enabled: bool,
}

#[derive(Debug, Serialize, Deserialize)]
struct ScanRequest {
    image: String,
    #[serde(default)]
    scanners: Vec<Scanner>,
    #[serde(default)]
    severity_threshold: Option<Severity>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
enum Scanner {
    Trivy,
    Grype,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord)]
#[serde(rename_all = "UPPERCASE")]
enum Severity {
    Unknown,
    Low,
    Medium,
    High,
    Critical,
}

#[derive(Debug, Serialize, Deserialize)]
struct Vulnerability {
    id: String,
    package: String,
    version: String,
    severity: Severity,
    fixed_version: Option<String>,
    description: String,
    scanner: String,
}

#[derive(Debug, Serialize, Deserialize)]
struct ScanResponse {
    image: String,
    scan_time: String,
    scanners_used: Vec<String>,
    vulnerabilities: Vec<Vulnerability>,
    summary: VulnerabilitySummary,
}

#[derive(Debug, Serialize, Deserialize)]
struct VulnerabilitySummary {
    total: usize,
    critical: usize,
    high: usize,
    medium: usize,
    low: usize,
    unknown: usize,
}

#[derive(Debug, Serialize, Deserialize)]
struct HealthResponse {
    status: String,
    version: String,
    scanners: ScannerStatus,
}

#[derive(Debug, Serialize, Deserialize)]
struct ScannerStatus {
    trivy: bool,
    grype: bool,
}

// ============================================================================
// Handlers
// ============================================================================

async fn health(State(state): State<AppState>) -> Json<HealthResponse> {
    Json(HealthResponse {
        status: "healthy".to_string(),
        version: env!("CARGO_PKG_VERSION").to_string(),
        scanners: ScannerStatus {
            trivy: state.trivy_enabled,
            grype: state.grype_enabled,
        },
    })
}

async fn scan_image(
    State(state): State<AppState>,
    Json(request): Json<ScanRequest>,
) -> Result<Json<ScanResponse>, (StatusCode, String)> {
    info!("Scanning image: {}", request.image);

    let scanners = if request.scanners.is_empty() {
        // Default: use all available scanners
        let mut default_scanners = Vec::new();
        if state.trivy_enabled {
            default_scanners.push(Scanner::Trivy);
        }
        if state.grype_enabled {
            default_scanners.push(Scanner::Grype);
        }
        default_scanners
    } else {
        request.scanners.clone()
    };

    let mut all_vulnerabilities = Vec::new();
    let mut scanners_used = Vec::new();

    for scanner in scanners {
        match scanner {
            Scanner::Trivy if state.trivy_enabled => match scan_with_trivy(&request.image).await {
                Ok(vulns) => {
                    info!("Trivy found {} vulnerabilities", vulns.len());
                    all_vulnerabilities.extend(vulns);
                    scanners_used.push("trivy".to_string());
                }
                Err(e) => {
                    warn!("Trivy scan failed: {}", e);
                }
            },
            Scanner::Grype if state.grype_enabled => match scan_with_grype(&request.image).await {
                Ok(vulns) => {
                    info!("Grype found {} vulnerabilities", vulns.len());
                    all_vulnerabilities.extend(vulns);
                    scanners_used.push("grype".to_string());
                }
                Err(e) => {
                    warn!("Grype scan failed: {}", e);
                }
            },
            _ => {
                warn!("Scanner {:?} not available or not enabled", scanner);
            }
        }
    }

    // Filter by severity threshold if specified
    if let Some(threshold) = &request.severity_threshold {
        all_vulnerabilities.retain(|v| &v.severity >= threshold);
    }

    // Deduplicate vulnerabilities by ID
    all_vulnerabilities.sort_by(|a, b| a.id.cmp(&b.id));
    all_vulnerabilities.dedup_by(|a, b| a.id == b.id);

    let summary = calculate_summary(&all_vulnerabilities);

    let response = ScanResponse {
        image: request.image,
        scan_time: Utc::now().to_rfc3339(),
        scanners_used,
        vulnerabilities: all_vulnerabilities,
        summary,
    };

    info!(
        "Scan complete: {} total vulnerabilities ({} critical)",
        response.summary.total, response.summary.critical
    );

    Ok(Json(response))
}

// ============================================================================
// Scanner Implementations
// ============================================================================

async fn scan_with_trivy(image: &str) -> anyhow::Result<Vec<Vulnerability>> {
    info!("Running Trivy scan on {}", image);

    let output = Command::new("trivy")
        .args(&["image", "--format", "json", "--quiet", image])
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .await?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        anyhow::bail!("Trivy failed: {}", stderr);
    }

    let stdout = String::from_utf8(output.stdout)?;
    parse_trivy_output(&stdout)
}

async fn scan_with_grype(image: &str) -> anyhow::Result<Vec<Vulnerability>> {
    info!("Running Grype scan on {}", image);

    let output = Command::new("grype")
        .args(&[image, "-o", "json", "--quiet"])
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .await?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        anyhow::bail!("Grype failed: {}", stderr);
    }

    let stdout = String::from_utf8(output.stdout)?;
    parse_grype_output(&stdout)
}

fn parse_trivy_output(json: &str) -> anyhow::Result<Vec<Vulnerability>> {
    let data: serde_json::Value = serde_json::from_str(json)?;
    let mut vulnerabilities = Vec::new();

    if let Some(results) = data.get("Results").and_then(|r| r.as_array()) {
        for result in results {
            if let Some(vulns) = result.get("Vulnerabilities").and_then(|v| v.as_array()) {
                for vuln in vulns {
                    let id = vuln
                        .get("VulnerabilityID")
                        .and_then(|v| v.as_str())
                        .unwrap_or("UNKNOWN")
                        .to_string();

                    let package = vuln
                        .get("PkgName")
                        .and_then(|v| v.as_str())
                        .unwrap_or("unknown")
                        .to_string();

                    let version = vuln
                        .get("InstalledVersion")
                        .and_then(|v| v.as_str())
                        .unwrap_or("unknown")
                        .to_string();

                    let severity_str = vuln
                        .get("Severity")
                        .and_then(|v| v.as_str())
                        .unwrap_or("UNKNOWN");

                    let severity = parse_severity(severity_str);

                    let fixed_version = vuln
                        .get("FixedVersion")
                        .and_then(|v| v.as_str())
                        .map(|s| s.to_string());

                    let description = vuln
                        .get("Title")
                        .or_else(|| vuln.get("Description"))
                        .and_then(|v| v.as_str())
                        .unwrap_or("")
                        .to_string();

                    vulnerabilities.push(Vulnerability {
                        id,
                        package,
                        version,
                        severity,
                        fixed_version,
                        description,
                        scanner: "trivy".to_string(),
                    });
                }
            }
        }
    }

    Ok(vulnerabilities)
}

fn parse_grype_output(json: &str) -> anyhow::Result<Vec<Vulnerability>> {
    let data: serde_json::Value = serde_json::from_str(json)?;
    let mut vulnerabilities = Vec::new();

    if let Some(matches) = data.get("matches").and_then(|m| m.as_array()) {
        for vuln_match in matches {
            let vuln_data = vuln_match.get("vulnerability");
            let artifact = vuln_match.get("artifact");

            if let (Some(vuln), Some(art)) = (vuln_data, artifact) {
                let id = vuln
                    .get("id")
                    .and_then(|v| v.as_str())
                    .unwrap_or("UNKNOWN")
                    .to_string();

                let package = art
                    .get("name")
                    .and_then(|v| v.as_str())
                    .unwrap_or("unknown")
                    .to_string();

                let version = art
                    .get("version")
                    .and_then(|v| v.as_str())
                    .unwrap_or("unknown")
                    .to_string();

                let severity_str = vuln
                    .get("severity")
                    .and_then(|v| v.as_str())
                    .unwrap_or("Unknown");

                let severity = parse_severity(severity_str);

                let fixed_version = vuln
                    .get("fix")
                    .and_then(|f| f.get("versions"))
                    .and_then(|v| v.as_array())
                    .and_then(|arr| arr.first())
                    .and_then(|v| v.as_str())
                    .map(|s| s.to_string());

                let description = vuln
                    .get("description")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_string();

                vulnerabilities.push(Vulnerability {
                    id,
                    package,
                    version,
                    severity,
                    fixed_version,
                    description,
                    scanner: "grype".to_string(),
                });
            }
        }
    }

    Ok(vulnerabilities)
}

fn parse_severity(s: &str) -> Severity {
    match s.to_uppercase().as_str() {
        "CRITICAL" => Severity::Critical,
        "HIGH" => Severity::High,
        "MEDIUM" => Severity::Medium,
        "LOW" => Severity::Low,
        _ => Severity::Unknown,
    }
}

fn calculate_summary(vulnerabilities: &[Vulnerability]) -> VulnerabilitySummary {
    let mut summary = VulnerabilitySummary {
        total: vulnerabilities.len(),
        critical: 0,
        high: 0,
        medium: 0,
        low: 0,
        unknown: 0,
    };

    for vuln in vulnerabilities {
        match vuln.severity {
            Severity::Critical => summary.critical += 1,
            Severity::High => summary.high += 1,
            Severity::Medium => summary.medium += 1,
            Severity::Low => summary.low += 1,
            Severity::Unknown => summary.unknown += 1,
        }
    }

    summary
}

// ============================================================================
// Scanner Detection
// ============================================================================

async fn check_scanner_available(command: &str) -> bool {
    Command::new(command)
        .arg("--version")
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .await
        .map(|status| status.success())
        .unwrap_or(false)
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

    info!("Starting Svalinn v{}", env!("CARGO_PKG_VERSION"));

    // Check scanner availability
    let trivy_enabled = check_scanner_available("trivy").await;
    let grype_enabled = check_scanner_available("grype").await;

    info!("Scanner availability:");
    info!("  Trivy: {}", if trivy_enabled { "✓" } else { "✗" });
    info!("  Grype: {}", if grype_enabled { "✓" } else { "✗" });

    if !trivy_enabled && !grype_enabled {
        error!("No vulnerability scanners available!");
        error!("Please install Trivy and/or Grype");
        anyhow::bail!("No scanners available");
    }

    let state = AppState {
        trivy_enabled,
        grype_enabled,
    };

    let app = Router::new()
        .route("/health", get(health))
        .route("/scan", post(scan_image))
        .layer(TraceLayer::new_for_http())
        .with_state(state);

    let port = std::env::var("SVALINN_PORT").unwrap_or_else(|_| "8085".to_string());
    let addr = format!("0.0.0.0:{}", port);

    info!("Listening on {}", addr);

    let listener = tokio::net::TcpListener::bind(&addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}
