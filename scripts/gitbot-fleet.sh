#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLEET_DIR="${GITBOT_FLEET_DIR:-$(cd "$REPO_ROOT/.." && pwd)/gitbot-fleet}"
FLEET_BIN="$FLEET_DIR/fleet-coordinator.sh"

if [[ ! -x "$FLEET_BIN" ]]; then
  echo "gitbot-fleet coordinator not found at: $FLEET_BIN" >&2
  echo "Set GITBOT_FLEET_DIR to your gitbot-fleet checkout." >&2
  exit 1
fi

cmd="${1:-run-scan}"

case "$cmd" in
  run-scan)
    "$FLEET_BIN" run-scan "$REPO_ROOT"
    ;;
  status|process-findings|deploy-bots)
    "$FLEET_BIN" "$cmd"
    ;;
  *)
    echo "Usage: $0 [run-scan|status|process-findings|deploy-bots]" >&2
    exit 2
    ;;
esac
