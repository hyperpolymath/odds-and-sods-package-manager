# Cerro-Torre - Security Monitoring Service

**Cerro-Torre** is OPSM's runtime security monitoring and threat detection service, providing real-time visibility into container behavior using eBPF and Falco.

## Features

- **Falco Integration**: Runtime security monitoring with Falco rules
- **Event Collection**: Captures security-relevant events from containers
- **Severity Classification**: EMERGENCY to DEBUG severity levels
- **Real-time Metrics**: Container monitoring statistics
- **Event Simulation**: Test alerting and workflows
- **REST API**: Query events, metrics, and trigger simulations

## Quick Start

### Running Locally

```bash
# Without Falco (simulated monitoring)
cargo run --release

# With Falco (real monitoring)
# Install Falco first, then:
cargo run --release
```

### Running in Container

```bash
# Build
podman build -t cerro-torre:latest -f Containerfile .

# Run with privileged access (required for eBPF)
podman run --privileged -p 8088:8088 cerro-torre:latest
```

## API Reference

### Health Check

```bash
GET /health
```

**Response:**
```json
{
  "status": "healthy",
  "version": "1.0.0",
  "falco_available": false,
  "falco_version": null,
  "total_events": 42,
  "monitoring_active": false
}
```

### Get Security Events

```bash
POST /events
Content-Type: application/json

{
  "limit": 100,
  "severity": "CRITICAL",
  "container": "app-prod"
}
```

**Query Parameters:**
- `limit` (optional): Max events to return (default: 100)
- `severity` (optional): Filter by severity level
- `container` (optional): Filter by container name (partial match)

**Response:**
```json
{
  "events": [
    {
      "id": "evt-123456",
      "timestamp": "2026-02-05T07:15:00Z",
      "severity": "CRITICAL",
      "rule": "privilege_escalation_detected",
      "message": "Process attempted privilege escalation",
      "container_id": "container-abc123",
      "container_name": "app-prod",
      "process": "su",
      "metadata": {}
    }
  ],
  "total": 1,
  "critical_count": 1,
  "warning_count": 0
}
```

### Get Metrics

```bash
GET /metrics
```

**Response:**
```json
{
  "total_events": 156,
  "events_by_severity": {
    "emergency": 0,
    "alert": 2,
    "critical": 5,
    "error": 12,
    "warning": 45,
    "notice": 67,
    "informational": 23,
    "debug": 2
  },
  "top_rules": [
    {
      "rule": "terminal_shell_in_container",
      "count": 45
    },
    {
      "rule": "write_below_etc",
      "count": 23
    }
  ],
  "monitored_containers": 8
}
```

### Simulate Security Event

```bash
POST /events/simulate
Content-Type: application/json

{
  "event_type": "privilege_escalation",
  "severity": "CRITICAL",
  "container_name": "test-container"
}
```

**Response:**
```json
{
  "id": "evt-sim-789",
  "timestamp": "2026-02-05T07:16:00Z",
  "severity": "CRITICAL",
  "rule": "simulated_privilege_escalation",
  "message": "Simulated security event: privilege_escalation",
  "container_id": "sim-123456",
  "container_name": "test-container",
  "process": "test-process"
}
```

### Clear Events

```bash
POST /events/clear
```

**Response:** `204 No Content`

## Event Severity Levels

| Level | Description | Action Required |
|-------|-------------|-----------------|
| **EMERGENCY** | System unusable | Immediate response |
| **ALERT** | Action required immediately | Alert on-call team |
| **CRITICAL** | Critical security violation | Investigate urgently |
| **ERROR** | Error condition | Review and remediate |
| **WARNING** | Warning condition | Monitor closely |
| **NOTICE** | Normal but significant | Log for audit |
| **INFORMATIONAL** | Informational message | Log only |
| **DEBUG** | Debug-level message | Development only |

## Common Security Rules

When Falco is active, Cerro-Torre monitors these security events:

| Rule | Severity | Description |
|------|----------|-------------|
| **privilege_escalation** | CRITICAL | Process gained elevated privileges |
| **write_below_etc** | WARNING | Write to /etc directory |
| **read_sensitive_file** | WARNING | Access to sensitive files (/etc/shadow, SSH keys) |
| **terminal_shell_in_container** | NOTICE | Interactive shell opened |
| **network_connection** | INFORMATIONAL | Outbound network connection |
| **file_opened_for_writing** | DEBUG | File write operation |

## Examples

### Monitor for Critical Events

```bash
# Start monitoring
curl -X POST http://localhost:8088/events \
  -H "Content-Type: application/json" \
  -d '{"severity": "CRITICAL", "limit": 50}'

# Check metrics
curl http://localhost:8088/metrics | jq '.events_by_severity.critical'
```

### Test Alert Pipeline

```bash
# Simulate critical event
curl -X POST http://localhost:8088/events/simulate \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "ransomware_detected",
    "severity": "EMERGENCY",
    "container_name": "production-app"
  }'

# Verify event was captured
curl -X POST http://localhost:8088/events \
  -H "Content-Type: application/json" \
  -d '{"severity": "EMERGENCY", "limit": 1}' | jq .
```

### Container-Specific Monitoring

```bash
# Get all events from specific container
curl -X POST http://localhost:8088/events \
  -H "Content-Type: application/json" \
  -d '{"container": "production", "limit": 100}' \
  | jq '.events[] | {timestamp, severity, rule, message}'
```

## Configuration

Environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `CERRO_TORRE_PORT` | `8088` | HTTP server port |
| `RUST_LOG` | `info` | Log level |

## Integration with OPSM

Cerro-Torre completes the OPSM security pipeline:

```bash
# Full container security workflow
opsm container pipeline ./Containerfile \
  --scan         # Svalinn: vulnerability scanning
  --sign         # Selur: image signing
  --verify       # Vordr: policy verification
  --monitor      # Cerro-Torre: runtime monitoring

# Query runtime security events
opsm container monitor --critical --container myapp
```

## Architecture

```
┌─────────────────┐
│   REST API      │
│   (Axum)        │
└────────┬────────┘
         │
    ┌────▼────┐
    │ Falco   │
    │ (eBPF)  │
    └────┬────┘
         │
    ┌────▼────────┐
    │   Kernel    │
    │   Events    │
    └─────────────┘
```

## Falco Integration

When Falco is installed, Cerro-Torre:
1. Monitors kernel syscalls via eBPF
2. Applies Falco security rules
3. Captures security-relevant events
4. Classifies by severity
5. Exposes via REST API

## Monitoring Flow

1. **Event Detection**: Falco detects suspicious behavior
2. **Classification**: Event severity determined by rule
3. **Storage**: Event added to in-memory buffer (10,000 events)
4. **API Exposure**: Available via /events endpoint
5. **Metrics**: Aggregated statistics via /metrics

## Alert Integration

### Webhook Example

```bash
# Monitor for critical events and POST to webhook
while true; do
  curl -s -X POST http://localhost:8088/events \
    -H "Content-Type: application/json" \
    -d '{"severity": "CRITICAL", "limit": 1}' \
  | jq -r '.events[] | @json' \
  | while read event; do
    curl -X POST https://alerts.example.com/webhook \
      -H "Content-Type: application/json" \
      -d "$event"
  done
  sleep 5
done
```

### Prometheus Metrics

```bash
# Export metrics to Prometheus format
curl http://localhost:8088/metrics | jq -r '
  .events_by_severity | to_entries[] |
  "cerro_torre_events_total{severity=\"\(.key)\"} \(.value)"
'
```

## Troubleshooting

**"Falco not available - running with simulated monitoring"**
- This is informational - simulated mode works for testing
- Install Falco for production: `https://falco.org/docs/getting-started/installation/`

**"monitoring_active: false"**
- Falco is not installed or not running
- Check: `falco --version`

**Events buffer full**
- Increase buffer size in code (default: 10,000 events)
- Clear old events: `POST /events/clear`

**No events captured**
- Verify Falco is running with proper permissions
- Check Falco rules are loaded
- Ensure containers are generating activity

## Performance

- **Memory**: ~10MB + (events × 1KB average)
- **CPU**: Minimal (<1% idle, <5% under load)
- **Latency**: <10ms API response time
- **Throughput**: 1000+ events/second

## License

MPL-2.0

## Author

Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
