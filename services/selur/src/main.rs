// SPDX-License-Identifier: PMPL-1.0-or-later
//! Selur: Container image signing and verification service
//!
//! Integrates Cosign for cryptographic signing of container images.

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
use tracing::{error, info, warn};

// ============================================================================
// Types
// ============================================================================

#[derive(Clone)]
struct AppState {
    cosign_available: bool,
    key_dir: PathBuf,
}

#[derive(Debug, Serialize, Deserialize)]
struct SignRequest {
    image: String,
    #[serde(default)]
    key_path: Option<String>,
    #[serde(default)]
    annotations: Option<std::collections::HashMap<String, String>>,
}

#[derive(Debug, Serialize, Deserialize)]
struct SignResponse {
    image: String,
    signature_digest: String,
    public_key: String,
    signed_at: String,
    annotations: Option<std::collections::HashMap<String, String>>,
}

#[derive(Debug, Serialize, Deserialize)]
struct VerifyRequest {
    image: String,
    #[serde(default)]
    public_key_path: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
struct VerifyResponse {
    image: String,
    verified: bool,
    message: String,
    signatures: Vec<SignatureInfo>,
}

#[derive(Debug, Serialize, Deserialize)]
struct SignatureInfo {
    digest: String,
    signed_at: Option<String>,
    annotations: Option<std::collections::HashMap<String, String>>,
}

#[derive(Debug, Serialize, Deserialize)]
struct KeyGenRequest {
    #[serde(default)]
    key_name: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
struct KeyGenResponse {
    private_key_path: String,
    public_key_path: String,
    public_key: String,
}

#[derive(Debug, Serialize, Deserialize)]
struct HealthResponse {
    status: String,
    version: String,
    cosign_available: bool,
    cosign_version: Option<String>,
}

// ============================================================================
// Handlers
// ============================================================================

async fn health(State(state): State<AppState>) -> Json<HealthResponse> {
    let cosign_version = if state.cosign_available {
        get_cosign_version().await.ok()
    } else {
        None
    };

    Json(HealthResponse {
        status: "healthy".to_string(),
        version: env!("CARGO_PKG_VERSION").to_string(),
        cosign_available: state.cosign_available,
        cosign_version,
    })
}

async fn sign_image(
    State(state): State<AppState>,
    Json(request): Json<SignRequest>,
) -> Result<Json<SignResponse>, (StatusCode, String)> {
    if !state.cosign_available {
        return Err((
            StatusCode::SERVICE_UNAVAILABLE,
            "Cosign not available".to_string(),
        ));
    }

    info!("Signing image: {}", request.image);

    // Use provided key or default
    let key_path = match request.key_path {
        Some(path) => PathBuf::from(path),
        None => state.key_dir.join("cosign.key"),
    };

    if !key_path.exists() {
        return Err((
            StatusCode::BAD_REQUEST,
            format!("Key file not found: {}", key_path.display()),
        ));
    }

    // Build cosign command
    let mut cmd = Command::new("cosign");
    cmd.arg("sign")
        .arg("--key")
        .arg(&key_path)
        .arg("--yes") // Auto-confirm
        .arg(&request.image);

    // Add annotations if provided
    if let Some(annotations) = &request.annotations {
        for (key, value) in annotations {
            cmd.arg("-a").arg(format!("{}={}", key, value));
        }
    }

    let output = cmd
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to execute cosign: {}", e)))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        error!("Cosign sign failed: {}", stderr);
        return Err((
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Signing failed: {}", stderr),
        ));
    }

    // Read public key
    let pub_key_path = key_path.with_extension("pub");
    let public_key = fs::read_to_string(&pub_key_path)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to read public key: {}", e)))?;

    // Generate signature digest (simplified - in production would extract from cosign output)
    let signature_digest = format!("sha256:{}", hex::encode(&output.stdout[..32.min(output.stdout.len())]));

    let response = SignResponse {
        image: request.image,
        signature_digest,
        public_key: public_key.trim().to_string(),
        signed_at: Utc::now().to_rfc3339(),
        annotations: request.annotations,
    };

    info!("Image signed successfully");
    Ok(Json(response))
}

async fn verify_image(
    State(state): State<AppState>,
    Json(request): Json<VerifyRequest>,
) -> Result<Json<VerifyResponse>, (StatusCode, String)> {
    if !state.cosign_available {
        return Err((
            StatusCode::SERVICE_UNAVAILABLE,
            "Cosign not available".to_string(),
        ));
    }

    info!("Verifying image: {}", request.image);

    // Use provided public key or default
    let pub_key_path = match request.public_key_path {
        Some(path) => PathBuf::from(path),
        None => state.key_dir.join("cosign.pub"),
    };

    if !pub_key_path.exists() {
        return Err((
            StatusCode::BAD_REQUEST,
            format!("Public key file not found: {}", pub_key_path.display()),
        ));
    }

    let output = Command::new("cosign")
        .arg("verify")
        .arg("--key")
        .arg(&pub_key_path)
        .arg(&request.image)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to execute cosign: {}", e)))?;

    let verified = output.status.success();
    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);

    let message = if verified {
        info!("Image verification successful");
        "Image signature verified successfully".to_string()
    } else {
        warn!("Image verification failed: {}", stderr);
        format!("Verification failed: {}", stderr)
    };

    // Parse signatures from output (simplified)
    let signatures = if verified {
        parse_verification_output(&stdout)
    } else {
        Vec::new()
    };

    let response = VerifyResponse {
        image: request.image,
        verified,
        message,
        signatures,
    };

    Ok(Json(response))
}

async fn generate_keypair(
    State(state): State<AppState>,
    Json(request): Json<KeyGenRequest>,
) -> Result<Json<KeyGenResponse>, (StatusCode, String)> {
    if !state.cosign_available {
        return Err((
            StatusCode::SERVICE_UNAVAILABLE,
            "Cosign not available".to_string(),
        ));
    }

    let key_name = request.key_name.unwrap_or_else(|| "cosign".to_string());
    let private_key_path = state.key_dir.join(&key_name).with_extension("key");
    let public_key_path = state.key_dir.join(&key_name).with_extension("pub");

    info!("Generating keypair: {}", key_name);

    // Ensure key directory exists
    fs::create_dir_all(&state.key_dir)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to create key directory: {}", e)))?;

    // Generate keypair with cosign
    let output = Command::new("cosign")
        .arg("generate-key-pair")
        .env("COSIGN_PASSWORD", "") // Empty password for automation
        .current_dir(&state.key_dir)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to execute cosign: {}", e)))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        error!("Keypair generation failed: {}", stderr);
        return Err((
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Keypair generation failed: {}", stderr),
        ));
    }

    // Rename generated keys if custom name provided
    if key_name != "cosign" {
        fs::rename(state.key_dir.join("cosign.key"), &private_key_path)
            .await
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to rename private key: {}", e)))?;
        fs::rename(state.key_dir.join("cosign.pub"), &public_key_path)
            .await
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to rename public key: {}", e)))?;
    }

    // Read public key
    let public_key = fs::read_to_string(&public_key_path)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Failed to read public key: {}", e)))?;

    let response = KeyGenResponse {
        private_key_path: private_key_path.display().to_string(),
        public_key_path: public_key_path.display().to_string(),
        public_key: public_key.trim().to_string(),
    };

    info!("Keypair generated successfully");
    Ok(Json(response))
}

// ============================================================================
// Helpers
// ============================================================================

async fn check_cosign_available() -> bool {
    Command::new("cosign")
        .arg("version")
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .await
        .map(|status| status.success())
        .unwrap_or(false)
}

async fn get_cosign_version() -> anyhow::Result<String> {
    let output = Command::new("cosign")
        .arg("version")
        .stdout(Stdio::piped())
        .output()
        .await?;

    let version = String::from_utf8(output.stdout)?;
    // Extract version from output (format varies)
    Ok(version
        .lines()
        .next()
        .unwrap_or("unknown")
        .trim()
        .to_string())
}

fn parse_verification_output(output: &str) -> Vec<SignatureInfo> {
    // Parse JSON output from cosign verify
    // This is simplified - real implementation would parse full JSON
    let mut signatures = Vec::new();

    if let Ok(json_arr) = serde_json::from_str::<Vec<serde_json::Value>>(output) {
        for item in json_arr {
            if let Some(optional) = item.get("optional") {
                let digest = item
                    .pointer("/critical/image/docker-manifest-digest")
                    .and_then(|v| v.as_str())
                    .unwrap_or("unknown")
                    .to_string();

                let annotations = if let Some(ann) = optional.as_object() {
                    Some(
                        ann.iter()
                            .map(|(k, v)| (k.clone(), v.as_str().unwrap_or("").to_string()))
                            .collect(),
                    )
                } else {
                    None
                };

                signatures.push(SignatureInfo {
                    digest,
                    signed_at: None,
                    annotations,
                });
            }
        }
    }

    signatures
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

    info!("Starting Selur v{}", env!("CARGO_PKG_VERSION"));

    // Check cosign availability
    let cosign_available = check_cosign_available().await;
    info!(
        "Cosign availability: {}",
        if cosign_available { "✓" } else { "✗" }
    );

    if !cosign_available {
        error!("Cosign not available!");
        error!("Please install Cosign: https://docs.sigstore.dev/cosign/installation/");
        anyhow::bail!("Cosign not available");
    }

    // Setup key directory
    let key_dir = std::env::var("SELUR_KEY_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("/keys"));

    info!("Key directory: {}", key_dir.display());

    let state = AppState {
        cosign_available,
        key_dir,
    };

    let app = Router::new()
        .route("/health", get(health))
        .route("/sign", post(sign_image))
        .route("/verify", post(verify_image))
        .route("/keygen", post(generate_keypair))
        .layer(TraceLayer::new_for_http())
        .with_state(state);

    let port = std::env::var("SELUR_PORT").unwrap_or_else(|_| "8086".to_string());
    let addr = format!("0.0.0.0:{}", port);

    info!("Listening on {}", addr);

    let listener = tokio::net::TcpListener::bind(&addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}
