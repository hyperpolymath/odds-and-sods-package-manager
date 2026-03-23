#!/usr/bin/env bash
# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
#
# provision.sh — OPSM Runtime Provisioner
# ========================================
# Reads a Nickel runtime plugin definition and installs the specified
# version of the tool. Handles download, extraction, shim creation,
# and health check verification.
#
# Usage:
#   ./provision.sh <plugin.ncl> <version>
#   ./provision.sh --from-tool-versions <.tool-versions-path>
#
# This is the bridge between Nickel definitions and actual installation.
# Production OPSM will use the Elixir core + Zig shim; this script is
# the bootstrap provisioner for development and testing.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
INSTALL_BASE="${OPSM_RUNTIME_DIR:-$HOME/.opsm/runtimes}"
SHIM_DIR="${OPSM_SHIM_DIR:-$HOME/.opsm/shims}"

# --- Colours ---
if [[ -t 1 ]]; then
  BOLD='\033[1m' GREEN='\033[0;32m' BLUE='\033[0;34m'
  RED='\033[0;31m' YELLOW='\033[0;33m' NC='\033[0m'
else
  BOLD='' GREEN='' BLUE='' RED='' YELLOW='' NC=''
fi

info()  { echo -e "${BLUE}[opsm-provision]${NC} $*"; }
ok()    { echo -e "${GREEN}[opsm-provision]${NC} $*"; }
err()   { echo -e "${RED}[opsm-provision]${NC} $*" >&2; }
warn()  { echo -e "${YELLOW}[opsm-provision]${NC} $*"; }

# --- Detect platform ---
detect_platform() {
  local os arch
  case "$(uname -s)" in
    Linux*)  os="linux" ;;
    Darwin*) os="darwin" ;;
    MINGW*|MSYS*|CYGWIN*) os="windows" ;;
    FreeBSD*) os="freebsd" ;;
    *) err "Unsupported OS: $(uname -s)"; exit 1 ;;
  esac

  case "$(uname -m)" in
    x86_64|amd64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    i386|i686) arch="386" ;;
    *) err "Unsupported architecture: $(uname -m)"; exit 1 ;;
  esac

  echo "${os}-${arch}"
}

# --- Nickel field extraction (using nickel export or grep fallback) ---
ncl_field() {
  local file="$1" field="$2"
  if command -v nickel &>/dev/null; then
    nickel export "$file" 2>/dev/null | jq -r ".$field // empty" 2>/dev/null || true
  else
    # Fallback: grep-based extraction for simple string fields
    grep -oP "${field}\s*=\s*\"?\K[^\"]*" "$file" 2>/dev/null | head -1 || true
  fi
}

ncl_array() {
  local file="$1" field="$2"
  if command -v nickel &>/dev/null; then
    nickel export "$file" 2>/dev/null | jq -r ".$field[]? // empty" 2>/dev/null || true
  else
    grep -A5 "${field}\s*=" "$file" 2>/dev/null | grep -oP '"[^"]+"' | tr -d '"' || true
  fi
}

# --- Parse .tool-versions ---
if [[ "${1:-}" == "--from-tool-versions" ]]; then
  TV_FILE="${2:-.tool-versions}"
  if [[ ! -f "$TV_FILE" ]]; then
    err "File not found: $TV_FILE"
    exit 1
  fi

  info "Provisioning from: $TV_FILE"
  while IFS=' ' read -r tool version rest; do
    [[ "$tool" =~ ^#.*$ ]] && continue
    [[ -z "$tool" ]] && continue

    # Find matching .ncl file
    ncl_file=""
    for dir in "$RUNTIME_DIR/core" "$RUNTIME_DIR/community"; do
      if [[ -f "$dir/${tool}.ncl" ]]; then
        ncl_file="$dir/${tool}.ncl"
        break
      fi
    done

    if [[ -z "$ncl_file" ]]; then
      warn "No OPSM plugin for: $tool (skipping)"
      continue
    fi

    info "Installing $tool $version..."
    "$0" "$ncl_file" "$version"
  done < "$TV_FILE"
  exit 0
fi

# --- Single plugin mode ---
PLUGIN_FILE="${1:?Usage: $0 <plugin.ncl> <version>}"
VERSION="${2:?Usage: $0 <plugin.ncl> <version>}"

if [[ ! -f "$PLUGIN_FILE" ]]; then
  err "Plugin file not found: $PLUGIN_FILE"
  exit 1
fi

# --- Extract plugin data ---
TOOL_NAME=$(ncl_field "$PLUGIN_FILE" "name")
REPO_URL=$(ncl_field "$PLUGIN_FILE" "repository")
HEALTH_CMD=$(ncl_field "$PLUGIN_FILE" "health_check")

if [[ -z "$TOOL_NAME" ]]; then
  err "Could not extract tool name from: $PLUGIN_FILE"
  exit 1
fi

PLATFORM=$(detect_platform)
INSTALL_DIR="${INSTALL_BASE}/${TOOL_NAME}/${VERSION}"

info "${BOLD}Installing ${TOOL_NAME} ${VERSION}${NC} (${PLATFORM})"

# --- Check if already installed ---
if [[ -d "$INSTALL_DIR" ]]; then
  warn "${TOOL_NAME} ${VERSION} already installed at ${INSTALL_DIR}"
  read -rp "Reinstall? [y/N]: " REINSTALL
  [[ "$REINSTALL" != [yY] ]] && exit 0
  rm -rf "$INSTALL_DIR"
fi

# --- Download ---
mkdir -p "$INSTALL_DIR"
DOWNLOAD_DIR=$(mktemp -d)
trap 'rm -rf "$DOWNLOAD_DIR"' EXIT

# Construct download URL from GitHub releases (most common case)
# In production, the Elixir core handles this with full platform mapping
OWNER_REPO=$(echo "$REPO_URL" | sed 's|https://github.com/||;s|\.git$||')

if [[ -n "$OWNER_REPO" && "$OWNER_REPO" != "$REPO_URL" ]]; then
  # Try GitHub releases API
  info "Fetching release info from GitHub..."
  RELEASE_URL="https://api.github.com/repos/${OWNER_REPO}/releases/tags/v${VERSION}"
  RELEASE_JSON=$(curl -sSL "$RELEASE_URL" 2>/dev/null || true)

  if [[ -z "$RELEASE_JSON" ]] || echo "$RELEASE_JSON" | jq -e '.message' &>/dev/null; then
    # Try without v prefix
    RELEASE_URL="https://api.github.com/repos/${OWNER_REPO}/releases/tags/${VERSION}"
    RELEASE_JSON=$(curl -sSL "$RELEASE_URL" 2>/dev/null || true)
  fi

  if [[ -n "$RELEASE_JSON" ]] && ! echo "$RELEASE_JSON" | jq -e '.message' &>/dev/null; then
    # Find matching asset for our platform
    IFS='-' read -r os arch <<< "$PLATFORM"
    ASSET_URL=$(echo "$RELEASE_JSON" | jq -r \
      --arg os "$os" --arg arch "$arch" \
      '[.assets[].browser_download_url |
        select(test($os; "i")) |
        select(test($arch; "i") or test(
          if $arch == "amd64" then "x86_64|x64"
          elif $arch == "arm64" then "aarch64"
          else $arch end; "i"))] |
        map(select(test("sha256|\.sig|\.asc|\.md5|\.sbom"; "i") | not)) |
        first // empty' 2>/dev/null || true)

    if [[ -n "$ASSET_URL" ]]; then
      FILENAME=$(basename "$ASSET_URL")
      info "Downloading: ${FILENAME}"
      curl -sSL -o "${DOWNLOAD_DIR}/${FILENAME}" "$ASSET_URL"

      # Extract based on file type
      case "$FILENAME" in
        *.tar.gz|*.tgz)
          tar xzf "${DOWNLOAD_DIR}/${FILENAME}" -C "$INSTALL_DIR" --strip-components=1 2>/dev/null \
            || tar xzf "${DOWNLOAD_DIR}/${FILENAME}" -C "$INSTALL_DIR"
          ;;
        *.tar.xz)
          tar xJf "${DOWNLOAD_DIR}/${FILENAME}" -C "$INSTALL_DIR" --strip-components=1 2>/dev/null \
            || tar xJf "${DOWNLOAD_DIR}/${FILENAME}" -C "$INSTALL_DIR"
          ;;
        *.zip)
          unzip -q "${DOWNLOAD_DIR}/${FILENAME}" -d "$INSTALL_DIR"
          ;;
        *)
          # Raw binary
          mv "${DOWNLOAD_DIR}/${FILENAME}" "${INSTALL_DIR}/${TOOL_NAME}"
          chmod +x "${INSTALL_DIR}/${TOOL_NAME}"
          ;;
      esac
    else
      err "No matching release asset found for ${PLATFORM}"
      err "Available assets:"
      echo "$RELEASE_JSON" | jq -r '.assets[].name' 2>/dev/null
      exit 1
    fi
  else
    err "Could not fetch release: ${VERSION} from ${OWNER_REPO}"
    exit 1
  fi
else
  err "Non-GitHub repositories not yet supported in bootstrap provisioner"
  err "Repository: $REPO_URL"
  exit 1
fi

# --- Create shims ---
mkdir -p "$SHIM_DIR"
EXECUTABLES=$(ncl_array "$PLUGIN_FILE" "executables")

for exe in $EXECUTABLES; do
  # Find the actual binary (might be in bin/ subdirectory)
  REAL_BIN=$(find "$INSTALL_DIR" -name "$exe" -type f -executable 2>/dev/null | head -1)
  if [[ -z "$REAL_BIN" ]]; then
    REAL_BIN=$(find "$INSTALL_DIR" -name "$exe" -type f 2>/dev/null | head -1)
    [[ -n "$REAL_BIN" ]] && chmod +x "$REAL_BIN"
  fi

  if [[ -n "$REAL_BIN" ]]; then
    # Create shim script (bootstrap version — production uses Zig dispatcher)
    cat > "${SHIM_DIR}/${exe}" << SHIM
#!/usr/bin/env bash
# OPSM runtime shim for: ${exe} (${TOOL_NAME} ${VERSION})
# This is a bootstrap shim. Production OPSM uses a Zig dispatcher.
exec "${REAL_BIN}" "\$@"
SHIM
    chmod +x "${SHIM_DIR}/${exe}"
    ok "Shim created: ${SHIM_DIR}/${exe}"
  else
    warn "Binary not found: ${exe} (searched ${INSTALL_DIR})"
  fi
done

# --- Health check ---
if [[ -n "$HEALTH_CMD" ]]; then
  info "Running health check: ${HEALTH_CMD}"
  # Add install dir to PATH for the check
  FIRST_EXE=$(echo "$EXECUTABLES" | head -1)
  BIN_DIR=$(dirname "$(find "$INSTALL_DIR" -name "$FIRST_EXE" -type f 2>/dev/null | head -1)" 2>/dev/null || echo "$INSTALL_DIR")

  if PATH="${BIN_DIR}:${PATH}" eval "$HEALTH_CMD" &>/dev/null; then
    ok "Health check passed"
  else
    warn "Health check failed (tool may still work)"
  fi
fi

ok "${BOLD}${TOOL_NAME} ${VERSION}${NC} installed to: ${INSTALL_DIR}"
info "Shims at: ${SHIM_DIR}/"
info "Add to PATH: export PATH=\"${SHIM_DIR}:\$PATH\""
