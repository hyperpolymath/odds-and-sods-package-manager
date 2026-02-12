#!/usr/bin/env bash
# SPDX-License-Identifier: PMPL-1.0
# Install HAR agent systemd services

set -euo pipefail

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $*"
}

error() {
    echo -e "${RED}[$(date +'%H:%M:%S')] ERROR:${NC} $*" >&2
}

warn() {
    echo -e "${YELLOW}[$(date +'%H:%M:%S')] WARN:${NC} $*"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
        exit 1
    fi
}

check_dependencies() {
    log "Checking dependencies..."

    local missing=()

    command -v curl >/dev/null 2>&1 || missing+=("curl")
    command -v jq >/dev/null 2>&1 || missing+=("jq")
    command -v julia >/dev/null 2>&1 || missing+=("julia")

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing dependencies: ${missing[*]}"
        echo "Install with: sudo dnf install ${missing[*]}"
        exit 1
    fi

    log "All dependencies present"
}

create_user() {
    if id "opsm" &>/dev/null; then
        log "User 'opsm' already exists"
    else
        log "Creating user 'opsm'..."
        useradd --system --no-create-home --shell /bin/false opsm
    fi
}

create_queue_dir() {
    local queue_dir="${OPSM_HAR_QUEUE_DIR:-/tmp/opsm-har-ingest}"
    log "Creating HAR queue directory at $queue_dir..."
    mkdir -p "${queue_dir}"/{results,processed}
    chown -R opsm:opsm "${queue_dir}"
    chmod 755 "${queue_dir}"
}

install_services() {
    log "Installing systemd service files..."

    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local services=(
        "har-github-search.service"
        "har-web-scraper.service"
        "har-mirror-finder.service"
    )

    for service in "${services[@]}"; do
        if [[ ! -f "$script_dir/$service" ]]; then
            error "Service file not found: $service"
            exit 1
        fi

        log "Installing $service..."
        cp "$script_dir/$service" /etc/systemd/system/
        chmod 644 "/etc/systemd/system/$service"
    done

    log "Reloading systemd daemon..."
    systemctl daemon-reload
}

enable_services() {
    log "Enabling services..."

    local services=(
        "har-github-search"
        "har-web-scraper"
        "har-mirror-finder"
    )

    for service in "${services[@]}"; do
        log "Enabling $service..."
        systemctl enable "$service"
    done
}

start_services() {
    log "Starting services..."

    local services=(
        "har-github-search"
        "har-web-scraper"
        "har-mirror-finder"
    )

    for service in "${services[@]}"; do
        log "Starting $service..."
        systemctl start "$service"

        # Wait a bit and check status
        sleep 2
        if systemctl is-active --quiet "$service"; then
            log "✓ $service is running"
        else
            warn "✗ $service failed to start - check logs with: journalctl -u $service"
        fi
    done
}

show_status() {
    log ""
    log "Service Status:"
    log "==============="
    systemctl status har-github-search --no-pager -l || true
    echo ""
    systemctl status har-web-scraper --no-pager -l || true
    echo ""
    systemctl status har-mirror-finder --no-pager -l || true
}

main() {
    log "HAR Agent Service Installation"
    log "=============================="

    check_root
    check_dependencies
    create_user
    create_queue_dir
    install_services
    enable_services
    start_services
    show_status

    log ""
    log "Installation complete!"
    log ""
    log "Useful commands:"
    log "  - View logs: journalctl -u har-github-search -f"
    log "  - Stop all: systemctl stop har-*"
    log "  - Start all: systemctl start har-*"
    log "  - Restart all: systemctl restart har-*"
    log "  - Check status: systemctl status har-*"
}

main "$@"
