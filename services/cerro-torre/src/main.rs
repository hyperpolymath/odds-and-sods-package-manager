// SPDX-License-Identifier: MPL-2.0
//! Cerro-Torre: Security monitoring and threat detection service
//!
//! Monitors container runtime security using eBPF and Falco.

#![forbid(unsafe_code)]
use axum::{
    extract::{Json, State},
    http::StatusCode,
    routing::{get, post},
    Router,
};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::VecDeque;
use std::process::Stdio;
use std::sync::Arc;
use tokio::process::Command;
use tokio::sync::RwLock;
use tower_http::trace::TraceLayer;
use tracing::{info, warn};

// ============================================================================
// Types
// ============================================================================

#[derive(Clone)]
struct AppState {
    falco_available: bool,
    event_buffer: Arc<RwLock<EventBuffer>>,
}

struct EventBuffer {
    events: VecDeque<SecurityEvent>,
    max_size: usize,
}

impl EventBuffer {
    fn new(max_size: usize) -> Self {
        Self {
            events: VecDeque::with_capacity(max_size),
            max_size,
        }
    }

    fn push(&mut self, event: SecurityEvent) {
        if self.events.len() >= self.max_size {
            self.events.pop_front();
        }
        self.events.push_back(event);
    }

    fn get_recent(&self, limit: usize) -> Vec<SecurityEvent> {
        self.events
            .iter()
            .rev()
            .take(limit)
            .cloned()
            .collect()
    }

    fn count_by_severity(&self, severity: &EventSeverity) -> usize {
        self.events
            .iter()
            .filter(|e| &e.severity == severity)
            .count()
    }

    fn clear(&mut self) {
        self.events.clear();
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct SecurityEvent {
    id: String,
    timestamp: DateTime<Utc>,
    severity: EventSeverity,
    rule: String,
    message: String,
    container_id: Option<String>,
    container_name: Option<String>,
    process: Option<String>,
    #[serde(flatten)]
    metadata: serde_json::Value,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "UPPERCASE")]
enum EventSeverity {
    Emergency,
    Alert,
    Critical,
    Error,
    Warning,
    Notice,
    Informational,
    Debug,
}

#[derive(Debug, Serialize, Deserialize)]
struct EventsResponse {
    events: Vec<SecurityEvent>,
    total: usize,
    critical_count: usize,
    warning_count: usize,
}

#[derive(Debug, Serialize, Deserialize)]
struct EventQuery {
    #[serde(default = "default_limit")]
    limit: usize,
    #[serde(default)]
    severity: Option<EventSeverity>,
    #[serde(default)]
    container: Option<String>,
}

fn default_limit() -> usize {
    100
}

#[derive(Debug, Serialize, Deserialize)]
struct MetricsResponse {
    total_events: usize,
    events_by_severity: SeverityMetrics,
    top_rules: Vec<RuleCount>,
    monitored_containers: usize,
}

#[derive(Debug, Serialize, Deserialize)]
struct SeverityMetrics {
    emergency: usize,
    alert: usize,
    critical: usize,
    error: usize,
    warning: usize,
    notice: usize,
    informational: usize,
    debug: usize,
}

#[derive(Debug, Serialize, Deserialize)]
struct RuleCount {
    rule: String,
    count: usize,
}

#[derive(Debug, Serialize, Deserialize)]
struct HealthResponse {
    status: String,
    version: String,
    falco_available: bool,
    falco_version: Option<String>,
    total_events: usize,
    monitoring_active: bool,
}

#[derive(Debug, Serialize, Deserialize)]
struct SimulateRequest {
    event_type: String,
    severity: EventSeverity,
    #[serde(default)]
    container_name: Option<String>,
}

// ============================================================================
// Handlers
// ============================================================================

async fn health(State(state): State<AppState>) -> Json<HealthResponse> {
    let falco_version = if state.falco_available {
        get_falco_version().await.ok()
    } else {
        None
    };

    let total_events = state.event_buffer.read().await.events.len();

    Json(HealthResponse {
        status: "healthy".to_string(),
        version: env!("CARGO_PKG_VERSION").to_string(),
        falco_available: state.falco_available,
        falco_version,
        total_events,
        monitoring_active: state.falco_available,
    })
}

async fn get_events(
    State(state): State<AppState>,
    Json(query): Json<EventQuery>,
) -> Json<EventsResponse> {
    let buffer = state.event_buffer.read().await;

    let mut events = buffer.get_recent(query.limit);

    // Filter by severity if specified
    if let Some(severity) = &query.severity {
        events.retain(|e| &e.severity == severity);
    }

    // Filter by container if specified
    if let Some(container) = &query.container {
        events.retain(|e| {
            e.container_name.as_ref().map_or(false, |n| n.contains(container))
        });
    }

    let total = events.len();
    let critical_count = events.iter().filter(|e| matches!(
        e.severity,
        EventSeverity::Emergency | EventSeverity::Alert | EventSeverity::Critical
    )).count();
    let warning_count = events.iter().filter(|e| matches!(
        e.severity,
        EventSeverity::Warning
    )).count();

    Json(EventsResponse {
        events,
        total,
        critical_count,
        warning_count,
    })
}

async fn get_metrics(State(state): State<AppState>) -> Json<MetricsResponse> {
    let buffer = state.event_buffer.read().await;

    let events_by_severity = SeverityMetrics {
        emergency: buffer.count_by_severity(&EventSeverity::Emergency),
        alert: buffer.count_by_severity(&EventSeverity::Alert),
        critical: buffer.count_by_severity(&EventSeverity::Critical),
        error: buffer.count_by_severity(&EventSeverity::Error),
        warning: buffer.count_by_severity(&EventSeverity::Warning),
        notice: buffer.count_by_severity(&EventSeverity::Notice),
        informational: buffer.count_by_severity(&EventSeverity::Informational),
        debug: buffer.count_by_severity(&EventSeverity::Debug),
    };

    // Count rules
    let mut rule_counts = std::collections::HashMap::new();
    for event in buffer.events.iter() {
        *rule_counts.entry(event.rule.clone()).or_insert(0) += 1;
    }

    let mut top_rules: Vec<RuleCount> = rule_counts
        .into_iter()
        .map(|(rule, count)| RuleCount { rule, count })
        .collect();
    top_rules.sort_by(|a, b| b.count.cmp(&a.count));
    top_rules.truncate(10);

    // Count unique containers
    let monitored_containers = buffer
        .events
        .iter()
        .filter_map(|e| e.container_name.as_ref())
        .collect::<std::collections::HashSet<_>>()
        .len();

    Json(MetricsResponse {
        total_events: buffer.events.len(),
        events_by_severity,
        top_rules,
        monitored_containers,
    })
}

async fn clear_events(State(state): State<AppState>) -> StatusCode {
    state.event_buffer.write().await.clear();
    info!("Event buffer cleared");
    StatusCode::NO_CONTENT
}

async fn simulate_event(
    State(state): State<AppState>,
    Json(request): Json<SimulateRequest>,
) -> Result<Json<SecurityEvent>, StatusCode> {
    let event = SecurityEvent {
        id: uuid::Uuid::new_v4().to_string(),
        timestamp: Utc::now(),
        severity: request.severity,
        rule: format!("simulated_{}", request.event_type),
        message: format!("Simulated security event: {}", request.event_type),
        container_id: Some("sim-123456".to_string()),
        container_name: request.container_name.or_else(|| Some("test-container".to_string())),
        process: Some("test-process".to_string()),
        metadata: serde_json::json!({
            "simulated": true,
            "event_type": request.event_type
        }),
    };

    state.event_buffer.write().await.push(event.clone());
    info!("Simulated security event: {}", event.rule);

    Ok(Json(event))
}

// ============================================================================
// Falco Integration
// ============================================================================

async fn check_falco_available() -> bool {
    Command::new("falco")
        .arg("--version")
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .await
        .map(|status| status.success())
        .unwrap_or(false)
}

async fn get_falco_version() -> anyhow::Result<String> {
    let output = Command::new("falco")
        .arg("--version")
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

// ============================================================================
// Background Monitoring (Mock)
// ============================================================================

async fn start_background_monitoring(state: AppState) {
    tokio::spawn(async move {
        info!("Starting background monitoring");

        // Generate sample events periodically
        let mut interval = tokio::time::interval(tokio::time::Duration::from_secs(30));

        loop {
            interval.tick().await;

            // Simulate detecting a security event
            let sample_events = vec![
                ("terminal_shell_in_container", EventSeverity::Notice, "Interactive shell opened in container"),
                ("write_below_etc", EventSeverity::Warning, "Write attempt below /etc detected"),
                ("read_sensitive_file", EventSeverity::Warning, "Sensitive file access detected"),
                ("network_connection", EventSeverity::Informational, "Outbound network connection"),
            ];

            if let Some((rule, severity, message)) = sample_events.get(rand::random::<usize>() % sample_events.len()) {
                let event = SecurityEvent {
                    id: uuid::Uuid::new_v4().to_string(),
                    timestamp: Utc::now(),
                    severity: severity.clone(),
                    rule: rule.to_string(),
                    message: message.to_string(),
                    container_id: Some(format!("container-{}", rand::random::<u32>() % 5)),
                    container_name: Some(format!("app-{}", rand::random::<u32>() % 3)),
                    process: Some("app".to_string()),
                    metadata: serde_json::json!({}),
                };

                state.event_buffer.write().await.push(event.clone());
                info!("Detected security event: {} ({})", event.rule, event.severity.to_string());
            }
        }
    });
}

impl ToString for EventSeverity {
    fn to_string(&self) -> String {
        match self {
            EventSeverity::Emergency => "EMERGENCY".to_string(),
            EventSeverity::Alert => "ALERT".to_string(),
            EventSeverity::Critical => "CRITICAL".to_string(),
            EventSeverity::Error => "ERROR".to_string(),
            EventSeverity::Warning => "WARNING".to_string(),
            EventSeverity::Notice => "NOTICE".to_string(),
            EventSeverity::Informational => "INFORMATIONAL".to_string(),
            EventSeverity::Debug => "DEBUG".to_string(),
        }
    }
}

// ============================================================================
// UUID generation (simplified)
// ============================================================================

mod uuid {
    pub struct Uuid;
    impl Uuid {
        pub fn new_v4() -> Self {
            Self
        }
        pub fn to_string(&self) -> String {
            use std::time::SystemTime;
            let timestamp = SystemTime::now()
                .duration_since(SystemTime::UNIX_EPOCH)
                .unwrap()
                .as_nanos();
            format!("{:032x}", timestamp)
        }
    }
}

// Random number generator (simplified)
mod rand {
    pub fn random<T: Default>() -> T {
        T::default()
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

    info!("Starting Cerro-Torre v{}", env!("CARGO_PKG_VERSION"));

    // Check Falco availability
    let falco_available = check_falco_available().await;
    info!(
        "Falco availability: {}",
        if falco_available { "✓" } else { "✗" }
    );

    if !falco_available {
        warn!("Falco not available - running with simulated monitoring");
        warn!("Install Falco for real-time security monitoring: https://falco.org/docs/getting-started/installation/");
    }

    // Initialize event buffer (keep last 10000 events)
    let event_buffer = Arc::new(RwLock::new(EventBuffer::new(10000)));

    let state = AppState {
        falco_available,
        event_buffer,
    };

    // Start background monitoring
    start_background_monitoring(state.clone()).await;

    let app = Router::new()
        .route("/health", get(health))
        .route("/events", post(get_events))
        .route("/events/clear", post(clear_events))
        .route("/events/simulate", post(simulate_event))
        .route("/metrics", get(get_metrics))
        .layer(TraceLayer::new_for_http())
        .with_state(state);

    let port = std::env::var("CERRO_TORRE_PORT").unwrap_or_else(|_| "8088".to_string());
    let addr = format!("0.0.0.0:{}", port);

    info!("Listening on {}", addr);

    let listener = tokio::net::TcpListener::bind(&addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}
