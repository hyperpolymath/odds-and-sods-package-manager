#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
#
# configure.sh — OPSM Runtime Configurator
# ==========================================
# Manages OPSM runtime configuration: global/local tool versions,
# .tool-versions compatibility, and environment settings.
#
# Usage:
#   ./configure.sh set <tool> <version>           # Set version in current dir
#   ./configure.sh set --global <tool> <version>   # Set global version
#   ./configure.sh list                             # Show configured versions
#   ./configure.sh import <.tool-versions>          # Import from asdf format
#   ./configure.sh export                           # Export to .tool-versions
#   ./configure.sh env <tool>                       # Show env vars for tool
#   ./configure.sh which <command>                  # Show which version resolves

set -uo pipefail

OPSM_CONFIG_DIR="${OPSM_CONFIG_DIR:-$HOME/.opsm}"
OPSM_RUNTIME_DIR="${OPSM_RUNTIME_DIR:-$HOME/.opsm/runtimes}"
GLOBAL_VERSIONS="${OPSM_CONFIG_DIR}/tool-versions"
LOCAL_VERSIONS=".tool-versions"

# --- Colours ---
if [[ -t 1 ]]; then
  BOLD='\033[1m' GREEN='\033[0;32m' BLUE='\033[0;34m'
  RED='\033[0;31m' YELLOW='\033[0;33m' NC='\033[0m'
else
  BOLD='' GREEN='' BLUE='' RED='' YELLOW='' NC=''
fi

info()  { echo -e "${BLUE}[opsm-config]${NC} $*"; }
ok()    { echo -e "${GREEN}[opsm-config]${NC} $*"; }
err()   { echo -e "${RED}[opsm-config]${NC} $*" >&2; }

# --- Version resolution (same precedence as asdf) ---
# .tool-versions (local, walking up) > global config > legacy files
resolve_version() {
  local tool="$1"
  local dir="${2:-$(pwd)}"

  # Walk up directory tree for local .tool-versions
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/$LOCAL_VERSIONS" ]]; then
      local ver
      ver=$(grep -E "^${tool}\s+" "$dir/$LOCAL_VERSIONS" 2>/dev/null | awk '{print $2}' || true)
      if [[ -n "$ver" ]]; then
        echo "$ver|$dir/$LOCAL_VERSIONS"
        return 0
      fi
    fi
    dir=$(dirname "$dir")
  done

  # Check legacy files (.nvmrc, .ruby-version, .python-version, etc.)
  local legacy_file=""
  case "$tool" in
    nodejs|node) legacy_file=".nvmrc" ;;
    ruby)        legacy_file=".ruby-version" ;;
    python)      legacy_file=".python-version" ;;
    golang|go)   legacy_file=".go-version" ;;
    java)        legacy_file=".java-version" ;;
  esac
  if [[ -n "$legacy_file" && -f "$legacy_file" ]]; then
    local ver
    ver=$(cat "$legacy_file" | tr -d '[:space:]')
    if [[ -n "$ver" ]]; then
      echo "$ver|$legacy_file (legacy)"
      return 0
    fi
  fi

  # Global fallback
  if [[ -f "$GLOBAL_VERSIONS" ]]; then
    local ver
    ver=$(grep -E "^${tool}\s+" "$GLOBAL_VERSIONS" 2>/dev/null | awk '{print $2}' || true)
    if [[ -n "$ver" ]]; then
      echo "$ver|$GLOBAL_VERSIONS (global)"
      return 0
    fi
  fi

  echo "|not set"
  return 1
}

# --- Commands ---
case "${1:-help}" in
  set)
    shift
    SCOPE="local"
    if [[ "${1:-}" == "--global" ]] || [[ "${1:-}" == "-g" ]]; then
      SCOPE="global"
      shift
    fi

    TOOL="${1:?Usage: configure.sh set [--global] <tool> <version>}"
    VERSION="${2:?Usage: configure.sh set [--global] <tool> <version>}"

    if [[ "$SCOPE" == "global" ]]; then
      TARGET="$GLOBAL_VERSIONS"
      mkdir -p "$(dirname "$TARGET")"
    else
      TARGET="$LOCAL_VERSIONS"
    fi

    # Update or add the version line
    if [[ -f "$TARGET" ]] && grep -qE "^${TOOL}\s+" "$TARGET" 2>/dev/null; then
      sed -i "s|^${TOOL}\s.*|${TOOL} ${VERSION}|" "$TARGET"
    else
      echo "${TOOL} ${VERSION}" >> "$TARGET"
    fi

    ok "Set ${TOOL} ${VERSION} (${SCOPE}: ${TARGET})"
    ;;

  list)
    echo -e "${BOLD}OPSM Runtime Versions${NC}"
    echo

    # Collect all known tools from installed runtimes
    if [[ -d "$OPSM_RUNTIME_DIR" ]]; then
      for tool_dir in "$OPSM_RUNTIME_DIR"/*/; do
        [[ -d "$tool_dir" ]] || continue
        tool=$(basename "$tool_dir")
        resolved=$(resolve_version "$tool" 2>/dev/null || true)
        IFS='|' read -r ver source <<< "$resolved"

        # List installed versions
        installed=$(ls "$tool_dir" 2>/dev/null | tr '\n' ', ' | sed 's/,$//')

        if [[ -n "$ver" ]]; then
          echo -e "  ${GREEN}${tool}${NC}  ${BOLD}${ver}${NC}  (from: ${source})"
          echo -e "    installed: ${installed:-none}"
        else
          echo -e "  ${YELLOW}${tool}${NC}  not set"
          echo -e "    installed: ${installed:-none}"
        fi
      done
    else
      info "No runtimes installed yet."
      info "Install with: opsm runtime install <tool> <version>"
    fi

    # Also show .tool-versions if present
    if [[ -f "$LOCAL_VERSIONS" ]]; then
      echo
      echo -e "${BOLD}Local .tool-versions:${NC}"
      while IFS=' ' read -r tool ver rest; do
        [[ "$tool" =~ ^#.*$ || -z "$tool" ]] && continue
        # Check if installed
        if [[ -d "${OPSM_RUNTIME_DIR}/${tool}/${ver}" ]]; then
          echo -e "  ${GREEN}${tool}${NC} ${ver} ✓"
        else
          echo -e "  ${YELLOW}${tool}${NC} ${ver} (not installed)"
        fi
      done < "$LOCAL_VERSIONS"
    fi
    ;;

  import)
    SOURCE="${2:-.tool-versions}"
    if [[ ! -f "$SOURCE" ]]; then
      err "File not found: $SOURCE"
      exit 1
    fi

    info "Importing from: $SOURCE"
    count=0
    while IFS=' ' read -r tool ver rest; do
      [[ "$tool" =~ ^#.*$ || -z "$tool" ]] && continue
      # Normalise tool names (asdf uses 'nodejs', we accept both)
      ok "  ${tool} → ${ver}"
      count=$((count + 1))
    done < "$SOURCE"

    ok "Imported ${count} tool versions"
    info "Run 'opsm runtime provision --from-tool-versions ${SOURCE}' to install"
    ;;

  export)
    TARGET="${2:-.tool-versions}"
    if [[ -d "$OPSM_RUNTIME_DIR" ]]; then
      > "$TARGET"
      for tool_dir in "$OPSM_RUNTIME_DIR"/*/; do
        [[ -d "$tool_dir" ]] || continue
        tool=$(basename "$tool_dir")
        resolved=$(resolve_version "$tool" 2>/dev/null || true)
        IFS='|' read -r ver source <<< "$resolved"
        [[ -n "$ver" ]] && echo "${tool} ${ver}" >> "$TARGET"
      done
      ok "Exported to: $TARGET"
    else
      err "No runtimes configured"
      exit 1
    fi
    ;;

  which)
    COMMAND="${2:?Usage: configure.sh which <command>}"
    SHIM_DIR="${OPSM_SHIM_DIR:-$HOME/.opsm/shims}"
    if [[ -f "${SHIM_DIR}/${COMMAND}" ]]; then
      # Read the shim to find the real binary
      REAL=$(grep '^exec ' "${SHIM_DIR}/${COMMAND}" 2>/dev/null | sed 's/exec "//;s/" .*//')
      echo "$REAL"
    else
      err "No OPSM shim for: ${COMMAND}"
      exit 1
    fi
    ;;

  env)
    TOOL="${2:?Usage: configure.sh env <tool>}"
    resolved=$(resolve_version "$TOOL" 2>/dev/null || true)
    IFS='|' read -r ver source <<< "$resolved"

    if [[ -n "$ver" ]]; then
      INSTALL_DIR="${OPSM_RUNTIME_DIR}/${TOOL}/${ver}"
      echo "OPSM_TOOL_NAME=${TOOL}"
      echo "OPSM_TOOL_VERSION=${ver}"
      echo "OPSM_TOOL_DIR=${INSTALL_DIR}"
      echo "PATH=${INSTALL_DIR}/bin:${INSTALL_DIR}:\${PATH}"
    else
      err "${TOOL} version not set"
      exit 1
    fi
    ;;

  help|--help|-h)
    echo "OPSM Runtime Configurator"
    echo
    echo "Usage:"
    echo "  configure.sh set [--global] <tool> <version>"
    echo "  configure.sh list"
    echo "  configure.sh import [.tool-versions]"
    echo "  configure.sh export [output-file]"
    echo "  configure.sh which <command>"
    echo "  configure.sh env <tool>"
    ;;

  *)
    err "Unknown command: $1"
    exit 1
    ;;
esac
