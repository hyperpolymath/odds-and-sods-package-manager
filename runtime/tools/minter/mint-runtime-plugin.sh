#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
#
# mint-runtime-plugin.sh — OPSM Runtime Plugin Minter
# ====================================================
# Interactive tool for creating new OPSM runtime plugin definitions.
# Generates a valid Nickel file satisfying the runtime-plugin contract.
#
# Usage:
#   ./mint-runtime-plugin.sh                    # Interactive mode
#   ./mint-runtime-plugin.sh --quick <name> <repo> <binary>  # Quick mode
#
# Output goes to runtime/community/ by default (runtime/core/ for --core).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# --- Colours ---
if [[ -t 1 ]]; then
  BOLD='\033[1m'
  GREEN='\033[0;32m'
  BLUE='\033[0;34m'
  YELLOW='\033[0;33m'
  NC='\033[0m'
else
  BOLD='' GREEN='' BLUE='' YELLOW='' NC=''
fi

info()  { echo -e "${BLUE}[opsm-minter]${NC} $*"; }
ok()    { echo -e "${GREEN}[opsm-minter]${NC} $*"; }
warn()  { echo -e "${YELLOW}[opsm-minter]${NC} $*"; }

# --- Quick mode ---
if [[ "${1:-}" == "--quick" ]]; then
  NAME="${2:?Quick mode: --quick <name> <github-owner/repo> <binary>}"
  REPO="${3:?Quick mode: --quick <name> <github-owner/repo> <binary>}"
  BINARY="${4:?Quick mode: --quick <name> <github-owner/repo> <binary>}"
  OUTPUT_DIR="${RUNTIME_DIR}/community"
  TIER="'Community"
  DESCRIPTION="${NAME} — managed by OPSM runtime"
  CONTRIBUTOR_NAME=""
  CONTRIBUTOR_EMAIL=""
  ECOSYSTEM="system"
  FUNCTIONS="'CLI"
  USAGE="'Oneshot"
  HEALTH_CHECK="${BINARY} --version"
  VERSION_SOURCE="'GitHubReleases"
  ARCHIVE_FORMAT="'TarGz"
else
  # --- Interactive mode ---
  echo -e "${BOLD}OPSM Runtime Plugin Minter${NC}"
  echo "Creates a new Nickel runtime plugin definition."
  echo

  read -rp "Tool name (as users type it, e.g. 'age'): " NAME
  read -rp "GitHub repository (owner/repo, e.g. 'FiloSottile/age'): " REPO
  read -rp "Binary name (e.g. 'age'): " BINARY
  read -rp "Description [${NAME} — managed by OPSM runtime]: " DESCRIPTION
  DESCRIPTION="${DESCRIPTION:-${NAME} — managed by OPSM runtime}"

  read -rp "Health check command [${BINARY} --version]: " HEALTH_CHECK
  HEALTH_CHECK="${HEALTH_CHECK:-${BINARY} --version}"

  echo
  echo "Version source:"
  echo "  1) GitHub Releases (most common)"
  echo "  2) GitHub Tags"
  echo "  3) GitLab Releases"
  echo "  4) JSON Index (e.g. ziglang.org/download/index.json)"
  echo "  5) Custom API"
  read -rp "Choose [1]: " VS_CHOICE
  case "${VS_CHOICE:-1}" in
    1) VERSION_SOURCE="'GitHubReleases" ;;
    2) VERSION_SOURCE="'GitHubTags" ;;
    3) VERSION_SOURCE="'GitLabReleases" ;;
    4) VERSION_SOURCE="'JsonIndex" ;;
    5) VERSION_SOURCE="'CustomApi" ;;
    *) VERSION_SOURCE="'GitHubReleases" ;;
  esac

  echo
  echo "Archive format:"
  echo "  1) .tar.gz  2) .tar.xz  3) .zip  4) Raw binary"
  read -rp "Choose [1]: " AF_CHOICE
  case "${AF_CHOICE:-1}" in
    1) ARCHIVE_FORMAT="'TarGz" ;;
    2) ARCHIVE_FORMAT="'TarXz" ;;
    3) ARCHIVE_FORMAT="'Zip" ;;
    4) ARCHIVE_FORMAT="'RawBinary" ;;
    *) ARCHIVE_FORMAT="'TarGz" ;;
  esac

  echo
  echo "Tool function (comma-separated):"
  echo "  Runtime, Compiler, Linter, Formatter, BuildTool, PackageManager,"
  echo "  Database, Security, Server, CLI, Editor, ContainerTool"
  read -rp "Choose [CLI]: " FUNC_INPUT
  FUNC_INPUT="${FUNC_INPUT:-CLI}"
  # Convert to Nickel enum format
  FUNCTIONS=$(echo "$FUNC_INPUT" | tr ',' '\n' | sed "s/^[[:space:]]*//;s/[[:space:]]*$//" | sed "s/^/'/" | paste -sd', ')

  read -rp "Ecosystem (e.g. 'beam', 'rust', 'javascript', 'system') [system]: " ECOSYSTEM
  ECOSYSTEM="${ECOSYSTEM:-system}"

  echo
  echo "Usage mode:"
  echo "  1) Oneshot (CLI tool)  2) Interactive (REPL)  3) Daemon (server)  4) Batch (compiler)"
  read -rp "Choose [1]: " USAGE_CHOICE
  case "${USAGE_CHOICE:-1}" in
    1) USAGE="'Oneshot" ;;
    2) USAGE="'Interactive" ;;
    3) USAGE="'Daemon" ;;
    4) USAGE="'Batch" ;;
    *) USAGE="'Oneshot" ;;
  esac

  echo
  echo "Tier:"
  echo "  1) Core (hyperpolymath maintained)"
  echo "  2) Community (contributed via PR)"
  echo "  3) Experimental (auto-converted/unverified)"
  read -rp "Choose [2]: " TIER_CHOICE
  case "${TIER_CHOICE:-2}" in
    1) TIER="'Core"; OUTPUT_DIR="${RUNTIME_DIR}/core" ;;
    2) TIER="'Community"; OUTPUT_DIR="${RUNTIME_DIR}/community" ;;
    3) TIER="'Experimental"; OUTPUT_DIR="${RUNTIME_DIR}/community" ;;
    *) TIER="'Community"; OUTPUT_DIR="${RUNTIME_DIR}/community" ;;
  esac

  echo
  read -rp "Your name (for contributor attribution, optional): " CONTRIBUTOR_NAME
  read -rp "Your email (optional): " CONTRIBUTOR_EMAIL
fi

# --- Generate ---
mkdir -p "$OUTPUT_DIR"
CLEAN_NAME=$(echo "$NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
OUTPUT_FILE="${OUTPUT_DIR}/${CLEAN_NAME}.ncl"

# Build contributor block
CONTRIBUTOR_BLOCK=""
if [ -n "$CONTRIBUTOR_NAME" ]; then
  CONTRIBUTOR_BLOCK="
  contributor = {
    name = \"${CONTRIBUTOR_NAME}\","
  if [ -n "$CONTRIBUTOR_EMAIL" ]; then
    CONTRIBUTOR_BLOCK="${CONTRIBUTOR_BLOCK}
    email = \"${CONTRIBUTOR_EMAIL}\","
  fi
  CONTRIBUTOR_BLOCK="${CONTRIBUTOR_BLOCK}
  },"
fi

cat > "$OUTPUT_FILE" << NICKEL
# SPDX-License-Identifier: MPL-2.0
#
# OPSM Runtime Plugin: ${NAME}
# Created with OPSM Runtime Plugin Minter

let { RuntimePlugin, .. } = import "../contract/runtime-plugin.ncl" in

{
  name = "${NAME}",
  description = "${DESCRIPTION}",
  repository = "https://github.com/${REPO}",

  version_source = ${VERSION_SOURCE},

  install = {
    strategy = 'PrebuiltBinary,
    platforms = [
      {
        platform = 'LinuxAmd64,
        archive_name_template = "${NAME}-{{version}}-linux-amd64.{{ext}}",
        archive_format = ${ARCHIVE_FORMAT},
      },
      {
        platform = 'LinuxArm64,
        archive_name_template = "${NAME}-{{version}}-linux-arm64.{{ext}}",
        archive_format = ${ARCHIVE_FORMAT},
      },
      {
        platform = 'DarwinAmd64,
        archive_name_template = "${NAME}-{{version}}-darwin-amd64.{{ext}}",
        archive_format = ${ARCHIVE_FORMAT},
      },
      {
        platform = 'DarwinArm64,
        archive_name_template = "${NAME}-{{version}}-darwin-arm64.{{ext}}",
        archive_format = ${ARCHIVE_FORMAT},
      },
    ],
    strip_components = 1,
  },

  executables = ["${BINARY}"],
  health_check = "${HEALTH_CHECK}",

  facets = {
    function = [${FUNCTIONS}],
    ecosystem = ["${ECOSYSTEM}"],
    usage = [${USAGE}],
    tier = ${TIER},
  },
${CONTRIBUTOR_BLOCK}
  schema_version = "1.0.0",
} | RuntimePlugin
NICKEL

ok "Created: ${OUTPUT_FILE}"
ok "Validate with: nickel typecheck ${OUTPUT_FILE}"
echo
info "Next steps:"
info "  1. Edit the archive_name_template to match actual release filenames"
info "  2. Run: nickel typecheck ${OUTPUT_FILE}"
info "  3. Test: opsm runtime install ${NAME} latest"
info "  4. If contributing: git add ${OUTPUT_FILE} && git commit"
