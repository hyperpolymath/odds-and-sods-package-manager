// SPDX-License-Identifier: PMPL-1.0-or-later

#![forbid(unsafe_code)]
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::LazyLock;
use std::time::Duration;

// Phoenix API base URL (configurable via OPSM_API_URL env var)
static API_BASE: LazyLock<String> = LazyLock::new(|| {
    std::env::var("OPSM_API_URL").unwrap_or_else(|_| "http://localhost:4051/api".to_string())
});

const REQUEST_TIMEOUT: Duration = Duration::from_secs(30);
const CONNECT_TIMEOUT: Duration = Duration::from_secs(10);

fn http_client() -> reqwest::Client {
    reqwest::Client::builder()
        .timeout(REQUEST_TIMEOUT)
        .connect_timeout(CONNECT_TIMEOUT)
        .build()
        .expect("failed to build HTTP client")
}

// ============================================================================
// Data Structures
// ============================================================================

#[derive(Debug, Serialize, Deserialize)]
pub struct Package {
    pub name: String,
    pub version: String,
    pub registry: Option<String>,
    pub description: Option<String>,
    pub dependencies: Option<HashMap<String, String>>,
    pub metadata: Option<serde_json::Value>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SearchResult {
    pub packages: Vec<Package>,
    pub total: usize,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct InstallRequest {
    pub name: String,
    pub version: String,
    pub registry: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct InstallResponse {
    pub success: bool,
    pub message: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct AuditRequest {
    pub lockfile_content: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct AuditResponse {
    pub issues: Vec<serde_json::Value>,
    pub sustainability_score: Option<f64>,
    pub security_score: Option<f64>,
}

// ============================================================================
// Tauri Commands
// ============================================================================

/// Search for packages across registries
#[tauri::command]
async fn search_packages(query: String, registry: Option<String>) -> Result<SearchResult, String> {
    let client = http_client();
    let mut url = format!("{}/packages/search?q={}", *API_BASE, urlencoding::encode(&query));

    if let Some(reg) = registry {
        url.push_str(&format!("&registry={}", urlencoding::encode(&reg)));
    }

    let response = client
        .get(&url)
        .send()
        .await
        .map_err(|e| format!("HTTP request failed: {}", e))?;

    if !response.status().is_success() {
        return Err(format!("API error: {}", response.status()));
    }

    response
        .json::<SearchResult>()
        .await
        .map_err(|e| format!("Failed to parse response: {}", e))
}

/// Get detailed information about a specific package
#[tauri::command]
async fn get_package_info(
    name: String,
    version: String,
    registry: Option<String>,
) -> Result<Package, String> {
    let client = http_client();
    let mut url = format!(
        "{}/packages/{}/{}",
        *API_BASE,
        urlencoding::encode(&name),
        urlencoding::encode(&version)
    );

    if let Some(reg) = registry {
        url.push_str(&format!("?registry={}", urlencoding::encode(&reg)));
    }

    let response = client
        .get(&url)
        .send()
        .await
        .map_err(|e| format!("HTTP request failed: {}", e))?;

    if !response.status().is_success() {
        return Err(format!("API error: {}", response.status()));
    }

    response
        .json::<Package>()
        .await
        .map_err(|e| format!("Failed to parse response: {}", e))
}

/// Install a package
#[tauri::command]
async fn install_package(
    name: String,
    version: String,
    registry: String,
) -> Result<InstallResponse, String> {
    let client = http_client();
    let url = format!("{}/packages/install", *API_BASE);

    let request_body = InstallRequest {
        name,
        version,
        registry,
    };

    let response = client
        .post(&url)
        .json(&request_body)
        .send()
        .await
        .map_err(|e| format!("HTTP request failed: {}", e))?;

    if !response.status().is_success() {
        return Err(format!("API error: {}", response.status()));
    }

    response
        .json::<InstallResponse>()
        .await
        .map_err(|e| format!("Failed to parse response: {}", e))
}

/// List all installed packages
#[tauri::command]
async fn list_installed_packages() -> Result<Vec<Package>, String> {
    let client = http_client();
    let url = format!("{}/packages/installed", *API_BASE);

    let response = client
        .get(&url)
        .send()
        .await
        .map_err(|e| format!("HTTP request failed: {}", e))?;

    if !response.status().is_success() {
        return Err(format!("API error: {}", response.status()));
    }

    response
        .json::<Vec<Package>>()
        .await
        .map_err(|e| format!("Failed to parse response: {}", e))
}

/// Audit a lockfile for security and sustainability issues
#[tauri::command]
async fn audit_lockfile(lockfile_path: String) -> Result<AuditResponse, String> {
    // Read lockfile content
    let lockfile_content = std::fs::read_to_string(&lockfile_path)
        .map_err(|e| format!("Failed to read lockfile: {}", e))?;

    let client = http_client();
    let url = format!("{}/lockfile/audit", *API_BASE);

    let request_body = AuditRequest { lockfile_content };

    let response = client
        .post(&url)
        .json(&request_body)
        .send()
        .await
        .map_err(|e| format!("HTTP request failed: {}", e))?;

    if !response.status().is_success() {
        return Err(format!("API error: {}", response.status()));
    }

    response
        .json::<AuditResponse>()
        .await
        .map_err(|e| format!("Failed to parse response: {}", e))
}

/// Health check for the API backend
#[tauri::command]
async fn health_check() -> Result<serde_json::Value, String> {
    let client = http_client();
    let url = format!("{}/health", *API_BASE);

    let response = client
        .get(&url)
        .send()
        .await
        .map_err(|e| format!("HTTP request failed: {}", e))?;

    if !response.status().is_success() {
        return Err(format!("API error: {}", response.status()));
    }

    response
        .json::<serde_json::Value>()
        .await
        .map_err(|e| format!("Failed to parse response: {}", e))
}

// ============================================================================
// Tauri Application Entry Point
// ============================================================================

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .setup(|app| {
            if cfg!(debug_assertions) {
                app.handle().plugin(
                    tauri_plugin_log::Builder::default()
                        .level(log::LevelFilter::Info)
                        .build(),
                )?;
            }
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            search_packages,
            get_package_info,
            install_package,
            list_installed_packages,
            audit_lockfile,
            health_check,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
