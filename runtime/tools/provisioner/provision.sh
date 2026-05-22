#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
#
# provision.sh — OPSM Runtime Provisioner
# ========================================
# Reads a Nickel runtime plugin definition and installs the specified
# version of the tool. Handles download, extraction, shim creation,
# and health check verification.
#
# Usage:
#   ./provision.sh <plugin.ncl> <version>          # single tool
#   ./provision.sh --from-opsm-toml [opsm.toml]    # from [runtime] section (preferred)
#   ./provision.sh --from-tool-versions [.tool-versions]  # legacy asdf format
#
# When `opsm` is in PATH, delegates to `opsm runtime install` (the Elixir/Zig
# native layer).  The bash download functions are a bootstrap fallback for
# environments where OPSM itself is not yet installed.
# Set OPSM_FORCE_BASH_PROVISIONER=1 to bypass delegation (for testing).

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
  local file="$1" field="$2" result=""
  # Try nickel export first, fall back to grep if it fails or returns empty
  if command -v nickel &>/dev/null; then
    result=$(nickel export "$file" 2>/dev/null | jq -r ".$field // empty" 2>/dev/null || true)
  fi
  if [[ -z "$result" ]]; then
    # Fallback: grep-based extraction for simple string fields
    result=$(grep -oP "${field}\s*=\s*\"?\K[^\",]*" "$file" 2>/dev/null | head -1 | sed 's/[[:space:]]*$//' || true)
  fi
  echo "$result"
}

ncl_array() {
  local file="$1" field="$2" result=""
  if command -v nickel &>/dev/null; then
    result=$(nickel export "$file" 2>/dev/null | jq -r ".$field[]? // empty" 2>/dev/null || true)
  fi
  if [[ -z "$result" ]]; then
    # Extract array values: find the field, grab quoted strings until closing bracket
    grep -A10 "^\s*${field}\s*=" "$file" 2>/dev/null | sed -n '/\[/,/\]/p' | grep -oP '"[^"]+"' | tr -d '"' || true
  else
    echo "$result"
  fi
}

# --- Delegate to opsm runtime install --from opsm.toml (preferred) ---
if [[ "${1:-}" == "--from-opsm-toml" ]]; then
  MANIFEST="${2:-opsm.toml}"
  if command -v opsm >/dev/null 2>&1; then
    info "Delegating to: opsm runtime install --from ${MANIFEST}"
    exec opsm runtime install --from "$MANIFEST"
  else
    err "opsm not found — cannot use --from-opsm-toml without OPSM installed"
    err "Bootstrap alternative: use --from-tool-versions with a .tool-versions file"
    exit 1
  fi
fi

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
STRIP_COMPONENTS=$(ncl_field "$PLUGIN_FILE" "strip_components" | grep -oP '^\d+' || echo "1")
STRIP_COMPONENTS="${STRIP_COMPONENTS:-1}"  # default to 1 if not specified

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

IFS='-' read -r PLAT_OS PLAT_ARCH <<< "$PLATFORM"

# --- Extract helper ---
extract_archive() {
  local file="$1" dest="$2" strip="${3:-$STRIP_COMPONENTS}"
  local fname
  fname=$(basename "$file")
  case "$fname" in
    *.tar.gz|*.tgz) tar xzf "$file" -C "$dest" --strip-components="$strip" ;;
    *.tar.xz)       tar xJf "$file" -C "$dest" --strip-components="$strip" ;;
    *.tar.bz2)      tar xjf "$file" -C "$dest" --strip-components="$strip" ;;
    *.zip)           unzip -qo "$file" -d "$dest" ;;
    *)
      # Raw binary — name it after the tool
      mv "$file" "${dest}/${TOOL_NAME}"
      chmod +x "${dest}/${TOOL_NAME}"
      ;;
  esac
}

# --- Download URL construction ---
# Check for a direct_url field in the plugin (custom download source)
DIRECT_URL=$(ncl_field "$PLUGIN_FILE" "direct_url")

# Read version_source to choose download strategy
VERSION_SOURCE=$(ncl_field "$PLUGIN_FILE" "version_source")

download_from_direct_url() {
  # Plugin specifies an exact URL template with {{version}}, {{os}}, {{arch}} placeholders
  local url="$1"
  url="${url//\{\{version\}\}/$VERSION}"
  url="${url//\{\{os\}\}/$PLAT_OS}"
  url="${url//\{\{arch\}\}/$PLAT_ARCH}"
  # Also handle x86_64/aarch64 aliases
  if [[ "$PLAT_ARCH" == "amd64" ]]; then
    url="${url//\{\{arch64\}\}/x86_64}"
  elif [[ "$PLAT_ARCH" == "arm64" ]]; then
    url="${url//\{\{arch64\}\}/aarch64}"
  fi
  local fname
  fname=$(basename "$url")
  info "Downloading: ${fname}"
  curl -sSL -o "${DOWNLOAD_DIR}/${fname}" "$url" || { err "Download failed: $url"; exit 1; }
  extract_archive "${DOWNLOAD_DIR}/${fname}" "$INSTALL_DIR"
}

download_from_github_releases() {
  local owner_repo="$1"
  info "Fetching release info from GitHub..."
  local release_json=""
  for tag_prefix in "v" ""; do
    local url="https://api.github.com/repos/${owner_repo}/releases/tags/${tag_prefix}${VERSION}"
    release_json=$(curl -sSL "$url" 2>/dev/null || true)
    if [[ -n "$release_json" ]] && ! echo "$release_json" | jq -e '.message' &>/dev/null; then
      break
    fi
    release_json=""
  done

  if [[ -z "$release_json" ]]; then
    err "Could not fetch release: ${VERSION} from ${owner_repo}"
    exit 1
  fi

  local asset_url
  asset_url=$(echo "$release_json" | jq -r \
    --arg os "$PLAT_OS" --arg arch "$PLAT_ARCH" \
    '[.assets[].browser_download_url |
      select(test($os; "i")) |
      select(test($arch; "i") or test(
        if $arch == "amd64" then "x86_64|x64"
        elif $arch == "arm64" then "aarch64"
        else $arch end; "i"))] |
      map(select(test("sha256|SHA256|\\.sig|\\.asc|\\.md5|\\.sbom|CHANGELOG|\\.txt$|\\.h$|\\.hh$|-c-api"; "i") | not)) |
      first // empty' 2>/dev/null || true)

  if [[ -z "$asset_url" ]]; then
    err "No matching release asset found for ${PLATFORM}"
    err "Available assets:"
    echo "$release_json" | jq -r '.assets[].name' 2>/dev/null
    exit 1
  fi

  local fname
  fname=$(basename "$asset_url")
  info "Downloading: ${fname}"
  curl -sSL -o "${DOWNLOAD_DIR}/${fname}" "$asset_url"
  extract_archive "${DOWNLOAD_DIR}/${fname}" "$INSTALL_DIR"
}

# =================================================================
# Custom download handlers for tools with non-GitHub distributions
# =================================================================

download_zig() {
  # Zig distributes via ziglang.org with a JSON version index
  local arch_name
  case "$PLAT_ARCH" in
    amd64) arch_name="x86_64" ;;
    arm64) arch_name="aarch64" ;;
    *) arch_name="$PLAT_ARCH" ;;
  esac
  local url="https://ziglang.org/download/${VERSION}/zig-${arch_name}-${PLAT_OS}-${VERSION}.tar.xz"
  info "Downloading from ziglang.org..."
  local fname
  fname=$(basename "$url")
  curl -sSL -o "${DOWNLOAD_DIR}/${fname}" "$url" || { err "Download failed: $url"; exit 1; }
  extract_archive "${DOWNLOAD_DIR}/${fname}" "$INSTALL_DIR"
}

download_golang() {
  # Go distributes via go.dev/dl/
  local url="https://go.dev/dl/go${VERSION}.${PLAT_OS}-${PLAT_ARCH}.tar.gz"
  info "Downloading from go.dev..."
  local fname
  fname=$(basename "$url")
  curl -sSL -o "${DOWNLOAD_DIR}/${fname}" "$url" || { err "Download failed: $url"; exit 1; }
  extract_archive "${DOWNLOAD_DIR}/${fname}" "$INSTALL_DIR"
}

download_nodejs() {
  # Node.js distributes via nodejs.org
  local arch_name
  case "$PLAT_ARCH" in
    amd64) arch_name="x64" ;;
    arm64) arch_name="arm64" ;;
    *) arch_name="$PLAT_ARCH" ;;
  esac
  local url="https://nodejs.org/dist/v${VERSION}/node-v${VERSION}-${PLAT_OS}-${arch_name}.tar.xz"
  info "Downloading from nodejs.org..."
  local fname
  fname=$(basename "$url")
  curl -sSL -o "${DOWNLOAD_DIR}/${fname}" "$url" || { err "Download failed: $url"; exit 1; }
  extract_archive "${DOWNLOAD_DIR}/${fname}" "$INSTALL_DIR"
}

download_julia() {
  # Julia distributes via julialang-s3.julialang.org
  local arch_name
  case "$PLAT_ARCH" in
    amd64) arch_name="x86_64" ;;
    arm64) arch_name="aarch64" ;;
    *) arch_name="$PLAT_ARCH" ;;
  esac
  # Julia version format: major.minor.patch -> major.minor for URL path
  local major_minor
  major_minor=$(echo "$VERSION" | grep -oP '^\d+\.\d+')
  local url="https://julialang-s3.julialang.org/bin/${PLAT_OS}/x64/${major_minor}/julia-${VERSION}-${PLAT_OS}-${arch_name}.tar.gz"
  info "Downloading from julialang.org..."
  local fname
  fname=$(basename "$url")
  curl -sSL -o "${DOWNLOAD_DIR}/${fname}" "$url" || { err "Download failed: $url"; exit 1; }
  extract_archive "${DOWNLOAD_DIR}/${fname}" "$INSTALL_DIR"
}

download_dart() {
  # Dart distributes via storage.googleapis.com
  local arch_name
  case "$PLAT_ARCH" in
    amd64) arch_name="x64" ;;
    arm64) arch_name="arm64" ;;
    *) arch_name="$PLAT_ARCH" ;;
  esac
  local url="https://storage.googleapis.com/dart-archive/channels/stable/release/${VERSION}/sdk/dartsdk-${PLAT_OS}-${arch_name}-release.zip"
  info "Downloading from storage.googleapis.com..."
  local fname
  fname=$(basename "$url")
  curl -sSL -o "${DOWNLOAD_DIR}/${fname}" "$url" || { err "Download failed: $url"; exit 1; }
  extract_archive "${DOWNLOAD_DIR}/${fname}" "$INSTALL_DIR"
}

download_kubectl() {
  # kubectl distributes via dl.k8s.io
  local url="https://dl.k8s.io/release/v${VERSION}/bin/${PLAT_OS}/${PLAT_ARCH}/kubectl"
  info "Downloading from dl.k8s.io..."
  curl -sSL -o "${DOWNLOAD_DIR}/kubectl" "$url" || { err "Download failed: $url"; exit 1; }
  mv "${DOWNLOAD_DIR}/kubectl" "${INSTALL_DIR}/kubectl"
  chmod +x "${INSTALL_DIR}/kubectl"
}

download_nim() {
  # Nim distributes via nim-lang.org
  local arch_name
  case "$PLAT_ARCH" in
    amd64) arch_name="x64" ;;
    arm64) arch_name="arm64" ;;
    *) arch_name="$PLAT_ARCH" ;;
  esac
  local url="https://nim-lang.org/download/nim-${VERSION}-linux_${arch_name}.tar.xz"
  info "Downloading from nim-lang.org..."
  local fname
  fname=$(basename "$url")
  curl -sSL -o "${DOWNLOAD_DIR}/${fname}" "$url" || { err "Download failed: $url"; exit 1; }
  extract_archive "${DOWNLOAD_DIR}/${fname}" "$INSTALL_DIR"
}

download_cue() {
  # CUE distributes via GitHub but needs specific asset name filtering
  local arch_name
  case "$PLAT_ARCH" in
    amd64) arch_name="amd64" ;;
    arm64) arch_name="arm64" ;;
    *) arch_name="$PLAT_ARCH" ;;
  esac
  local url="https://github.com/cue-lang/cue/releases/download/v${VERSION}/cue_v${VERSION}_${PLAT_OS}_${arch_name}.tar.gz"
  info "Downloading CUE from GitHub..."
  local fname
  fname=$(basename "$url")
  curl -sSL -o "${DOWNLOAD_DIR}/${fname}" "$url" || { err "Download failed: $url"; exit 1; }
  extract_archive "${DOWNLOAD_DIR}/${fname}" "$INSTALL_DIR"
}

download_wasmtime() {
  # Wasmtime — need the CLI, not the C API
  local arch_name
  case "$PLAT_ARCH" in
    amd64) arch_name="x86_64" ;;
    arm64) arch_name="aarch64" ;;
    *) arch_name="$PLAT_ARCH" ;;
  esac
  local url="https://github.com/bytecodealliance/wasmtime/releases/download/v${VERSION}/wasmtime-v${VERSION}-${arch_name}-${PLAT_OS}.tar.xz"
  info "Downloading Wasmtime CLI..."
  local fname
  fname=$(basename "$url")
  curl -sSL -o "${DOWNLOAD_DIR}/${fname}" "$url" || { err "Download failed: $url"; exit 1; }
  extract_archive "${DOWNLOAD_DIR}/${fname}" "$INSTALL_DIR"
}

# =================================================================
# Dispatch: OPSM-native first, bash bootstrap fallback
# =================================================================
#
# When `opsm` is in PATH, delegate to `opsm runtime install` — this
# uses Runtime.Manager + UrlHandler + SourceBuilder (the Elixir core).
# The bash download functions below are a bootstrap-only fallback for
# environments where OPSM itself is not yet installed.

if command -v opsm >/dev/null 2>&1 && [[ "${OPSM_FORCE_BASH_PROVISIONER:-}" != "1" ]]; then
  info "Delegating to OPSM native runtime: opsm runtime install ${TOOL_NAME}@${VERSION}"
  opsm runtime install "${TOOL_NAME}@${VERSION}"
  OPSM_EXIT=$?
  if [[ $OPSM_EXIT -ne 0 ]]; then
    warn "opsm runtime install exited $OPSM_EXIT — falling back to bash provisioner"
  else
    # OPSM handled install + shims; skip the bash shim block below
    OPSM_SKIP_BASH_SHIMS=1
    ok "Installed via OPSM native runtime"
    exit 0
  fi
fi

# Bootstrap fallback — used when OPSM binary is not yet available,
# or when OPSM_FORCE_BASH_PROVISIONER=1 is set for testing.
info "Using bash bootstrap provisioner for: ${TOOL_NAME} ${VERSION}"

case "$TOOL_NAME" in
  zig)       download_zig ;;
  golang)    download_golang ;;
  nodejs)    download_nodejs ;;
  julia)     download_julia ;;
  dart)      download_dart ;;
  kubectl)   download_kubectl ;;
  nim)       download_nim ;;
  cue)       download_cue ;;
  wasmtime)  download_wasmtime ;;
  *)
    # Default: try GitHub Releases
    OWNER_REPO=$(echo "$REPO_URL" | sed 's|https://github.com/||;s|\.git$||')
    if [[ -n "$OWNER_REPO" && "$OWNER_REPO" != "$REPO_URL" ]]; then
      download_from_github_releases "$OWNER_REPO"
    elif [[ -n "$DIRECT_URL" ]]; then
      download_from_direct_url "$DIRECT_URL"
    else
      err "No download handler for: $TOOL_NAME (repo: $REPO_URL)"
      err "Add a custom handler in provisioner or set direct_url in the plugin"
      err "Or install OPSM and let it handle this automatically."
      exit 1
    fi
    ;;
esac

# --- Create shims ---
# Extract executables list (needed for health check even if we skip shim creation)
EXECUTABLES=$(ncl_array "$PLUGIN_FILE" "executables")

# Skip bash shim creation if OPSM_SKIP_BASH_SHIMS is set
# (opsm-runtime uses the Zig dispatcher instead)
if [[ -n "${OPSM_SKIP_BASH_SHIMS:-}" ]]; then
  ok "Skipping bash shims (Zig dispatcher in use)"
else
mkdir -p "$SHIM_DIR"

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
fi  # end OPSM_SKIP_BASH_SHIMS check

# --- Health check ---
if [[ -n "$HEALTH_CMD" ]]; then
  info "Running health check: ${HEALTH_CMD}"
  # Add install dir to PATH for the check
  FIRST_EXE=$(echo "${EXECUTABLES:-$TOOL_NAME}" | head -1)
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
