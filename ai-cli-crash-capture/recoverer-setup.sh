#!/usr/bin/env bash
# SPDX-License-Identifier: PMPL-1.0-or-later
set -euo pipefail

# Resolve the directory containing this script so we can find the
# companion files shipped alongside it.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Install paths
BIN_DIR="${HOME}/.local/bin"
BASHRC_D="${HOME}/.bashrc.d"
SYSTEMD_USER_DIR="${HOME}/.config/systemd/user"
LOG_DIR="${HOME}/Documents/terminal-logs"
CRASH_DIR="${HOME}/Documents/crash-captures"

mkdir -p "${BIN_DIR}" "${BASHRC_D}" "${SYSTEMD_USER_DIR}" "${LOG_DIR}" "${CRASH_DIR}"

install -m 0755 "${SCRIPT_DIR}/bash/terminal-recoverer"  "${BIN_DIR}/terminal-recoverer"
install -m 0644 "${SCRIPT_DIR}/bash/recoverer.sh"        "${BASHRC_D}/recoverer.sh"
install -m 0644 "${SCRIPT_DIR}/systemd/terminal-recoverer.service"          "${SYSTEMD_USER_DIR}/terminal-recoverer.service"
install -m 0644 "${SCRIPT_DIR}/systemd/terminal-recoverer-coredump.service" "${SYSTEMD_USER_DIR}/terminal-recoverer-coredump.service"
install -m 0644 "${SCRIPT_DIR}/bash/terminal-recoverer-HOWTO.txt"           "${HOME}/terminal-recoverer-HOWTO.txt"

echo "Installed:"
echo "- ${BIN_DIR}/terminal-recoverer"
echo "- ${BASHRC_D}/recoverer.sh"
echo "- ${SYSTEMD_USER_DIR}/terminal-recoverer.service"
echo "- ${SYSTEMD_USER_DIR}/terminal-recoverer-coredump.service"
echo "- ${HOME}/terminal-recoverer-HOWTO.txt"
