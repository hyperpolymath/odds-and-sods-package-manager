// SPDX-License-Identifier: PMPL-1.0-or-later
//! Claim-Forge: Cryptographic attestation generation service
//!
//! Generates SLSA provenance attestations and signs artifacts with Ed25519.

use axum::{
    extract::{Json, State},
    http::StatusCode,
    routing::{get, post},
    Router,
};
use chrono::Utc;
use ed25519_dalek::{Signature, Signer, SigningKey, VerifyingKey};
use rand::rngs::OsRng;
use serde::{Deserialize, Serialize};
use sha3::{Digest, Sha3_512};
use std::sync::Arc;
use tower_http::trace::TraceLayer;
use tracing::{info, warn};

// ============================================================================
// Types
// ============================================================================

#[derive(Clone)]
struct AppState {
    signing_key: Arc<SigningKey>,
    verifying_key: Arc<VerifyingKey>,
}

#[derive(Debug, Serialize, Deserialize)]
struct AttestationRequest {
    artifact_path: String,
    artifact_digest: String,
    claim_type: ClaimType,
    metadata: Option<serde_json::Value>,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
enum ClaimType {
    BuildProvenance,
    CodeReview,
    SecurityScan,
    LicenseCheck,
}

#[derive(Debug, Serialize, Deserialize)]
struct AttestationResponse {
    attestation_uri: String,
    signature: String,
    public_key: String,
    digest: String,
    timestamp: String,
}

#[derive(Debug, Serialize, Deserialize)]
struct VerifyRequest {
    attestation_uri: String,
    signature: String,
    public_key: String,
    digest: String,
}

#[derive(Debug, Serialize, Deserialize)]
struct VerifyResponse {
    verified: bool,
    message: String,
}

#[derive(Debug, Serialize, Deserialize)]
struct HealthResponse {
    status: String,
    version: String,
    uptime: u64,
}

// ============================================================================
// Handlers
// ============================================================================

async fn health() -> Json<HealthResponse> {
    Json(HealthResponse {
        status: "healthy".to_string(),
        version: env!("CARGO_PKG_VERSION").to_string(),
        uptime: 0,
    })
}

async fn generate_attestation(
    State(state): State<AppState>,
    Json(request): Json<AttestationRequest>,
) -> Result<Json<AttestationResponse>, (StatusCode, String)> {
    info!(
        "Generating attestation for: {} (type: {:?})",
        request.artifact_path, request.claim_type
    );

    let attestation = create_attestation(&request);
    let signature = sign_attestation(&state.signing_key, &attestation);
    let attestation_uri = format!("opsm://attestations/{}", hex::encode(&attestation[..16]));

    let response = AttestationResponse {
        attestation_uri,
        signature: hex::encode(signature.to_bytes()),
        public_key: hex::encode(state.verifying_key.to_bytes()),
        digest: request.artifact_digest.clone(),
        timestamp: Utc::now().to_rfc3339(),
    };

    info!("Attestation generated successfully");
    Ok(Json(response))
}

async fn verify_attestation(
    State(state): State<AppState>,
    Json(request): Json<VerifyRequest>,
) -> Result<Json<VerifyResponse>, (StatusCode, String)> {
    info!("Verifying attestation: {}", request.attestation_uri);

    let signature_bytes = hex::decode(&request.signature)
        .map_err(|e| (StatusCode::BAD_REQUEST, format!("Invalid signature hex: {}", e)))?;

    let signature = Signature::from_bytes(
        &signature_bytes
            .try_into()
            .map_err(|_| (StatusCode::BAD_REQUEST, "Invalid signature length".to_string()))?,
    );

    let pubkey_bytes = hex::decode(&request.public_key)
        .map_err(|e| (StatusCode::BAD_REQUEST, format!("Invalid public key hex: {}", e)))?;

    let verifying_key = VerifyingKey::from_bytes(
        &pubkey_bytes
            .try_into()
            .map_err(|_| (StatusCode::BAD_REQUEST, "Invalid public key length".to_string()))?,
    )
    .map_err(|e| (StatusCode::BAD_REQUEST, format!("Invalid public key: {}", e)))?;

    let message = request.digest.as_bytes();
    let verified = verifying_key.verify_strict(message, &signature).is_ok();

    let response = VerifyResponse {
        verified,
        message: if verified {
            "Attestation signature verified successfully".to_string()
        } else {
            "Attestation signature verification failed".to_string()
        },
    };

    if verified {
        info!("Attestation verified successfully");
    } else {
        warn!("Attestation verification failed");
    }

    Ok(Json(response))
}

// ============================================================================
// Helpers
// ============================================================================

fn create_attestation(request: &AttestationRequest) -> Vec<u8> {
    let provenance = serde_json::json!({
        "artifact": request.artifact_path,
        "digest": request.artifact_digest,
        "claim_type": format!("{:?}", request.claim_type),
        "metadata": request.metadata,
        "timestamp": Utc::now().to_rfc3339(),
        "issuer": "claim-forge/1.0.0",
    });

    provenance.to_string().into_bytes()
}

fn sign_attestation(signing_key: &SigningKey, attestation: &[u8]) -> Signature {
    let mut hasher = Sha3_512::new();
    hasher.update(attestation);
    let hash = hasher.finalize();
    signing_key.sign(&hash)
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

    info!("Starting Claim-Forge v{}", env!("CARGO_PKG_VERSION"));

    let mut csprng = OsRng;
    let signing_key = SigningKey::generate(&mut csprng);
    let verifying_key = signing_key.verifying_key();

    info!("Public key: {}", hex::encode(verifying_key.to_bytes()));

    let state = AppState {
        signing_key: Arc::new(signing_key),
        verifying_key: Arc::new(verifying_key),
    };

    let app = Router::new()
        .route("/health", get(health))
        .route("/attestation/generate", post(generate_attestation))
        .route("/attestation/verify", post(verify_attestation))
        .layer(TraceLayer::new_for_http())
        .with_state(state);

    let port = std::env::var("CLAIM_FORGE_PORT").unwrap_or_else(|_| "8080".to_string());
    let addr = format!("0.0.0.0:{}", port);

    info!("Listening on {}", addr);

    let listener = tokio::net::TcpListener::bind(&addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}
