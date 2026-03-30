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
// CLI-backed command handler (Gossamer IPC + Tauri fallback)
// ============================================================================

/// Response from CLI invocation — used by both Gossamer panel and Tauri commands
#[derive(Debug, Serialize, Deserialize)]
pub struct CliResponse {
    pub success: bool,
    pub output: String,
    pub exit_code: i32,
    pub parsed: Option<serde_json::Value>,
}

/// Find the opsm CLI binary — checks PATH, then well-known locations
fn find_opsm_binary() -> Result<String, String> {
    // Check PATH first
    if let Ok(output) = std::process::Command::new("which").arg("opsm").output() {
        if output.status.success() {
            let path = String::from_utf8_lossy(&output.stdout).trim().to_string();
            if !path.is_empty() {
                return Ok(path);
            }
        }
    }

    // Well-known locations
    let candidates = [
        dirs::home_dir().map(|h| h.join(".local/bin/opsm")),
        Some(std::path::PathBuf::from("/usr/local/bin/opsm")),
    ];

    for candidate in candidates.iter().flatten() {
        if candidate.exists() {
            return Ok(candidate.to_string_lossy().to_string());
        }
    }

    Err("opsm binary not found — install with: mix escript.build && ln -s $(pwd)/opsm ~/.local/bin/opsm".to_string())
}

/// Execute an opsm CLI command and return structured output.
///
/// This is the core handler that backs both the Gossamer panel IPC
/// (`window.__gossamer_invoke('opsm_runtime', ...)`) and the Tauri
/// command fallback when the HTTP API is unavailable.
fn run_opsm_cli(args: &[&str]) -> Result<CliResponse, String> {
    let binary = find_opsm_binary()?;

    let output = std::process::Command::new(&binary)
        .args(args)
        .env("NO_COLOR", "1") // Strip ANSI for JSON-friendly output
        .output()
        .map_err(|e| format!("Failed to execute opsm: {}", e))?;

    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();
    let exit_code = output.status.code().unwrap_or(-1);

    // Try to parse stdout as JSON for structured responses
    let parsed = serde_json::from_str::<serde_json::Value>(&stdout).ok();

    let combined_output = if stderr.is_empty() {
        stdout.clone()
    } else {
        format!("{}\n{}", stdout, stderr)
    };

    Ok(CliResponse {
        success: exit_code == 0,
        output: combined_output,
        exit_code,
        parsed,
    })
}

/// Gossamer panel IPC handler — receives commands from panel.html via
/// `window.__gossamer_invoke('opsm_runtime', { cmd, tool, version })`.
///
/// Supported commands: list, install, set, doctor, search, remove, check, info
#[tauri::command]
async fn opsm_runtime(cmd: String, tool: Option<String>, version: Option<String>) -> Result<CliResponse, String> {
    let args: Vec<&str> = match cmd.as_str() {
        "list" => vec!["list", "--installed", "--json"],

        "install" => {
            let t = tool.as_deref().ok_or("install requires a tool name")?;
            match version.as_deref() {
                Some(v) => vec!["install", t, "--version", v],
                None => vec!["install", t],
            }
        }

        "remove" | "uninstall" => {
            let t = tool.as_deref().ok_or("remove requires a package name")?;
            vec!["remove", t]
        }

        "set" => {
            // Switch active version of a runtime tool
            let t = tool.as_deref().ok_or("set requires a tool name")?;
            let v = version.as_deref().ok_or("set requires a version")?;
            vec!["pin", t, v]
        }

        "doctor" => vec!["check", "--json"],

        "search" => {
            let q = tool.as_deref().ok_or("search requires a query")?;
            vec!["search", q, "--json"]
        }

        "info" => {
            let t = tool.as_deref().ok_or("info requires a package name")?;
            vec!["info", t, "--json"]
        }

        "history" => vec!["history", "list", "--json"],

        other => return Err(format!("Unknown opsm_runtime command: {}", other)),
    };

    // Leak is safe here — args vec is short-lived and only used in run_opsm_cli
    // We need owned strings for the version/tool args
    let owned_args: Vec<String> = args.iter().map(|s| s.to_string()).collect();
    let ref_args: Vec<&str> = owned_args.iter().map(|s| s.as_str()).collect();

    run_opsm_cli(&ref_args)
}

/// CLI-backed install — fallback when HTTP API is unavailable
#[tauri::command]
async fn install_package_cli(name: String, registry: Option<String>, version: Option<String>) -> Result<CliResponse, String> {
    let mut args = vec!["install".to_string()];
    if let Some(reg) = registry {
        args.push(format!("@{}", reg));
    }
    args.push(name);
    if let Some(v) = version {
        args.push("--version".to_string());
        args.push(v);
    }
    let ref_args: Vec<&str> = args.iter().map(|s| s.as_str()).collect();
    run_opsm_cli(&ref_args)
}

/// CLI-backed remove — fallback when HTTP API is unavailable
#[tauri::command]
async fn remove_package_cli(name: String) -> Result<CliResponse, String> {
    run_opsm_cli(&["remove", &name])
}

/// CLI-backed search — fallback when HTTP API is unavailable
#[tauri::command]
async fn search_packages_cli(query: String) -> Result<CliResponse, String> {
    run_opsm_cli(&["search", &query, "--json"])
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
            // HTTP API-backed commands (when backend is running)
            search_packages,
            get_package_info,
            install_package,
            list_installed_packages,
            audit_lockfile,
            health_check,
            // CLI-backed commands (always available)
            opsm_runtime,
            install_package_cli,
            remove_package_cli,
            search_packages_cli,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
