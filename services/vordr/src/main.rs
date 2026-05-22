// SPDX-License-Identifier: MPL-2.0
//! Vordr: Runtime verification and OPA policy enforcement service
//!
//! Validates container configurations against security policies.

#![forbid(unsafe_code)]
use axum::{
    extract::{Json, State},
    http::StatusCode,
    routing::{get, post},
    Router,
};
use chrono::Utc;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::process::Stdio;
use tokio::fs;
use tokio::process::Command;
use tower_http::trace::TraceLayer;
use tracing::{info, warn};

// ============================================================================
// Types
// ============================================================================

#[derive(Clone)]
struct AppState {
    opa_available: bool,
    policy_dir: PathBuf,
}

#[derive(Debug, Serialize, Deserialize)]
struct VerifyRequest {
    #[serde(flatten)]
    input: ContainerInput,
    #[serde(default)]
    policy_path: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
struct ContainerInput {
    image: String,
    #[serde(default)]
    config: ContainerConfig,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
struct ContainerConfig {
    #[serde(default)]
    privileged: bool,
    #[serde(default)]
    user: Option<String>,
    #[serde(default)]
    capabilities: Vec<String>,
    #[serde(default)]
    read_only_root: bool,
    #[serde(default)]
    no_new_privileges: bool,
    #[serde(default)]
    resources: ResourceLimits,
    #[serde(default)]
    volumes: Vec<VolumeMount>,
    #[serde(default)]
    security_context: SecurityContext,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
struct ResourceLimits {
    #[serde(default)]
    memory_limit: Option<String>,
    #[serde(default)]
    cpu_limit: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct VolumeMount {
    source: String,
    destination: String,
    read_only: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
struct SecurityContext {
    #[serde(default)]
    run_as_non_root: bool,
    #[serde(default)]
    run_as_user: Option<u32>,
    #[serde(default)]
    seccomp_profile: Option<String>,
    #[serde(default)]
    apparmor_profile: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
struct VerifyResponse {
    allowed: bool,
    violations: Vec<PolicyViolation>,
    evaluation_time: String,
    policy_used: String,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
struct PolicyViolation {
    rule: String,
    severity: Severity,
    message: String,
    field: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "UPPERCASE")]
enum Severity {
    Critical,
    High,
    Medium,
    Low,
    Info,
}

#[derive(Debug, Serialize, Deserialize)]
struct PolicyListResponse {
    policies: Vec<PolicyInfo>,
}

#[derive(Debug, Serialize, Deserialize)]
struct PolicyInfo {
    name: String,
    path: String,
    description: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
struct HealthResponse {
    status: String,
    version: String,
    opa_available: bool,
    opa_version: Option<String>,
    policies_loaded: usize,
}

// ============================================================================
// Handlers
// ============================================================================

async fn health(State(state): State<AppState>) -> Json<HealthResponse> {
    let opa_version = if state.opa_available {
        get_opa_version().await.ok()
    } else {
        None
    };

    let policies_loaded = count_policies(&state.policy_dir).await.unwrap_or(0);

    Json(HealthResponse {
        status: "healthy".to_string(),
        version: env!("CARGO_PKG_VERSION").to_string(),
        opa_available: state.opa_available,
        opa_version,
        policies_loaded,
    })
}

async fn verify_container(
    State(state): State<AppState>,
    Json(request): Json<VerifyRequest>,
) -> Result<Json<VerifyResponse>, (StatusCode, String)> {
    info!("Verifying container: {}", request.input.image);

    // Use OPA if available, otherwise use built-in policy engine
    let (allowed, violations, policy_used) = if state.opa_available {
        verify_with_opa(&state, &request).await?
    } else {
        verify_builtin(&request)?
    };

    let response = VerifyResponse {
        allowed,
        violations,
        evaluation_time: Utc::now().to_rfc3339(),
        policy_used,
    };

    if response.allowed {
        info!("Container verification passed");
    } else {
        warn!(
            "Container verification failed with {} violations",
            response.violations.len()
        );
    }

    Ok(Json(response))
}

async fn list_policies(
    State(state): State<AppState>,
) -> Result<Json<PolicyListResponse>, (StatusCode, String)> {
    let policies = load_policy_list(&state.policy_dir)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    Ok(Json(PolicyListResponse { policies }))
}

// ============================================================================
// OPA Integration
// ============================================================================

async fn verify_with_opa(
    state: &AppState,
    request: &VerifyRequest,
) -> Result<(bool, Vec<PolicyViolation>, String), (StatusCode, String)> {
    let policy_path = match &request.policy_path {
        Some(path) => PathBuf::from(path),
        None => state.policy_dir.join("default.rego"),
    };

    if !policy_path.exists() {
        return Err((
            StatusCode::BAD_REQUEST,
            format!("Policy file not found: {}", policy_path.display()),
        ));
    }

    // Prepare input JSON
    let input_json = serde_json::json!({
        "input": {
            "image": request.input.image,
            "config": request.input.config,
        }
    });

    // Run OPA evaluation
    let mut child = Command::new("opa")
        .arg("eval")
        .arg("--data")
        .arg(&policy_path)
        .arg("--input")
        .arg("-")
        .arg("--format")
        .arg("json")
        .arg("data.container.deny")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to spawn OPA: {}", e)))?;

    // Write input to stdin
    if let Some(mut stdin) = child.stdin.take() {
        use tokio::io::AsyncWriteExt;
        stdin
            .write_all(input_json.to_string().as_bytes())
            .await
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to write input: {}", e)))?;
        drop(stdin); // Close stdin
    }

    let result = child
        .wait_with_output()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("OPA execution failed: {}", e)))?;

    if !result.status.success() {
        let stderr = String::from_utf8_lossy(&result.stderr);
        return Err((
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("OPA evaluation failed: {}", stderr),
        ));
    }

    // Parse OPA output
    let violations = parse_opa_output(&result.stdout)?;
    let allowed = violations.is_empty();

    Ok((allowed, violations, policy_path.display().to_string()))
}

fn parse_opa_output(output: &[u8]) -> Result<Vec<PolicyViolation>, (StatusCode, String)> {
    let json: serde_json::Value = serde_json::from_slice(output)
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to parse OPA output: {}", e)))?;

    let mut violations = Vec::new();

    if let Some(result_array) = json.get("result").and_then(|r| r.as_array()) {
        for result in result_array {
            if let Some(expressions) = result.get("expressions").and_then(|e| e.as_array()) {
                for expr in expressions {
                    if let Some(value) = expr.get("value").and_then(|v| v.as_array()) {
                        for violation_msg in value {
                            if let Some(msg) = violation_msg.as_str() {
                                violations.push(PolicyViolation {
                                    rule: "opa_policy".to_string(),
                                    severity: Severity::High,
                                    message: msg.to_string(),
                                    field: None,
                                });
                            }
                        }
                    }
                }
            }
        }
    }

    Ok(violations)
}

// ============================================================================
// Built-in Policy Engine
// ============================================================================

fn verify_builtin(
    request: &VerifyRequest,
) -> Result<(bool, Vec<PolicyViolation>, String), (StatusCode, String)> {
    let mut violations = Vec::new();

    // Rule 1: No privileged containers
    if request.input.config.privileged {
        violations.push(PolicyViolation {
            rule: "no_privileged".to_string(),
            severity: Severity::Critical,
            message: "Privileged containers are not allowed".to_string(),
            field: Some("privileged".to_string()),
        });
    }

    // Rule 2: Must run as non-root
    if request.input.config.user.as_deref() == Some("root") || request.input.config.user.is_none() {
        violations.push(PolicyViolation {
            rule: "non_root_user".to_string(),
            severity: Severity::High,
            message: "Container must run as non-root user".to_string(),
            field: Some("user".to_string()),
        });
    }

    // Rule 3: No dangerous capabilities
    let dangerous_caps = ["SYS_ADMIN", "NET_ADMIN", "SYS_MODULE", "CAP_SYS_ADMIN"];
    for cap in &request.input.config.capabilities {
        if dangerous_caps.iter().any(|d| cap.contains(d)) {
            violations.push(PolicyViolation {
                rule: "no_dangerous_caps".to_string(),
                severity: Severity::High,
                message: format!("Dangerous capability not allowed: {}", cap),
                field: Some("capabilities".to_string()),
            });
        }
    }

    // Rule 4: Read-only root filesystem recommended
    if !request.input.config.read_only_root {
        violations.push(PolicyViolation {
            rule: "read_only_root".to_string(),
            severity: Severity::Medium,
            message: "Read-only root filesystem is recommended".to_string(),
            field: Some("read_only_root".to_string()),
        });
    }

    // Rule 5: No new privileges
    if !request.input.config.no_new_privileges {
        violations.push(PolicyViolation {
            rule: "no_new_privileges".to_string(),
            severity: Severity::Medium,
            message: "Container should set no-new-privileges".to_string(),
            field: Some("no_new_privileges".to_string()),
        });
    }

    // Rule 6: Resource limits required
    if request.input.config.resources.memory_limit.is_none() {
        violations.push(PolicyViolation {
            rule: "memory_limit".to_string(),
            severity: Severity::Low,
            message: "Memory limit should be set".to_string(),
            field: Some("resources.memory_limit".to_string()),
        });
    }

    if request.input.config.resources.cpu_limit.is_none() {
        violations.push(PolicyViolation {
            rule: "cpu_limit".to_string(),
            severity: Severity::Low,
            message: "CPU limit should be set".to_string(),
            field: Some("resources.cpu_limit".to_string()),
        });
    }

    // Rule 7: No host path volumes with write access
    for volume in &request.input.config.volumes {
        if volume.source.starts_with('/') && !volume.read_only {
            violations.push(PolicyViolation {
                rule: "no_writable_host_paths".to_string(),
                severity: Severity::High,
                message: format!(
                    "Host path volume must be read-only: {}",
                    volume.source
                ),
                field: Some("volumes".to_string()),
            });
        }
    }

    // Only allow if no critical or high severity violations
    let allowed = !violations
        .iter()
        .any(|v| matches!(v.severity, Severity::Critical | Severity::High));

    Ok((allowed, violations, "builtin".to_string()))
}

// ============================================================================
// Helpers
// ============================================================================

async fn check_opa_available() -> bool {
    Command::new("opa")
        .arg("version")
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .await
        .map(|status| status.success())
        .unwrap_or(false)
}

async fn get_opa_version() -> anyhow::Result<String> {
    let output = Command::new("opa")
        .arg("version")
        .stdout(Stdio::piped())
        .output()
        .await?;

    let version = String::from_utf8(output.stdout)?;
    Ok(version
        .lines()
        .next()
        .unwrap_or("unknown")
        .trim()
        .to_string())
}

async fn count_policies(policy_dir: &PathBuf) -> anyhow::Result<usize> {
    if !policy_dir.exists() {
        return Ok(0);
    }

    let mut count = 0;
    let mut entries = fs::read_dir(policy_dir).await?;

    while let Some(entry) = entries.next_entry().await? {
        let path = entry.path();
        if path.extension().and_then(|s| s.to_str()) == Some("rego") {
            count += 1;
        }
    }

    Ok(count)
}

async fn load_policy_list(policy_dir: &PathBuf) -> anyhow::Result<Vec<PolicyInfo>> {
    let mut policies = Vec::new();

    if !policy_dir.exists() {
        return Ok(policies);
    }

    let mut entries = fs::read_dir(policy_dir).await?;

    while let Some(entry) = entries.next_entry().await? {
        let path = entry.path();
        if path.extension().and_then(|s| s.to_str()) == Some("rego") {
            let name = path
                .file_stem()
                .and_then(|s| s.to_str())
                .unwrap_or("unknown")
                .to_string();

            policies.push(PolicyInfo {
                name,
                path: path.display().to_string(),
                description: None,
            });
        }
    }

    Ok(policies)
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

    info!("Starting Vordr v{}", env!("CARGO_PKG_VERSION"));

    // Check OPA availability
    let opa_available = check_opa_available().await;
    info!(
        "OPA availability: {}",
        if opa_available { "✓" } else { "✗" }
    );

    if !opa_available {
        warn!("OPA not available - using built-in policy engine");
        warn!("Install OPA for custom policy support: https://www.openpolicyagent.org/docs/latest/#running-opa");
    }

    // Setup policy directory
    let policy_dir = std::env::var("VORDR_POLICY_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("/policies"));

    info!("Policy directory: {}", policy_dir.display());

    // Create policy directory if it doesn't exist
    if !policy_dir.exists() {
        fs::create_dir_all(&policy_dir).await?;
        info!("Created policy directory");
    }

    let state = AppState {
        opa_available,
        policy_dir,
    };

    let app = Router::new()
        .route("/health", get(health))
        .route("/verify", post(verify_container))
        .route("/policies", get(list_policies))
        .layer(TraceLayer::new_for_http())
        .with_state(state);

    let port = std::env::var("VORDR_PORT").unwrap_or_else(|_| "8087".to_string());
    let addr = format!("0.0.0.0:{}", port);

    info!("Listening on {}", addr);

    let listener = tokio::net::TcpListener::bind(&addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}
