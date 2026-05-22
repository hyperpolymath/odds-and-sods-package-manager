#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
#
# convert-asdf-plugins.sh
# =======================
# Converts asdf plugin directories to OPSM Nickel runtime definitions.
# Reads lib/utils.bash from each plugin, extracts structured data,
# and emits a .ncl file satisfying the runtime-plugin contract.
#
# Usage:
#   ./convert-asdf-plugins.sh <plugins-dir> <output-dir> [--tier core|community]
#
# The factual data (repo URL, binary name, archive format) is not
# copyrightable. We extract facts, not code. Each output file credits
# the original asdf plugin for attribution.

set -uo pipefail

PLUGINS_DIR="${1:?Usage: $0 <plugins-dir> <output-dir> [--tier core|community]}"
OUTPUT_DIR="${2:?Usage: $0 <plugins-dir> <output-dir> [--tier core|community]}"
TIER="${3:---tier core}"
TIER="${TIER#--tier }"
TIER="${TIER:-core}"

# Capitalise tier for Nickel enum
case "$TIER" in
  core) NICKEL_TIER="'Core" ;;
  community) NICKEL_TIER="'Community" ;;
  experimental) NICKEL_TIER="'Experimental" ;;
  upstream) NICKEL_TIER="'Upstream" ;;
  *) NICKEL_TIER="'Core" ;;
esac

mkdir -p "$OUTPUT_DIR"

converted=0
skipped=0
errors=0

# --- Helper: detect archive format from download logic ---
detect_archive_format() {
  local utils="$1"
  if grep -q '\.tar\.gz\|\.tgz' "$utils" 2>/dev/null; then
    echo "'TarGz"
  elif grep -q '\.tar\.xz' "$utils" 2>/dev/null; then
    echo "'TarXz"
  elif grep -q '\.zip' "$utils" 2>/dev/null; then
    echo "'Zip"
  elif grep -q '\.tar\.bz2' "$utils" 2>/dev/null; then
    echo "'TarBz2"
  else
    echo "'TarGz"
  fi
}

# --- Helper: detect executables from bin/list-bin-paths or TOOL_CMD ---
detect_executables() {
  local plugin_dir="$1"
  local cmd="$2"

  # Check for list-bin-paths which may list additional binaries
  if [ -f "$plugin_dir/bin/list-bin-paths" ]; then
    # Try to extract paths, fall back to cmd
    echo "\"$cmd\""
  else
    echo "\"$cmd\""
  fi
}

# --- Helper: detect version source ---
detect_version_source() {
  local utils="$1"
  local list_all="$2"

  if grep -q 'api\.github\.com/repos.*releases\|releases/download' "$utils" 2>/dev/null; then
    echo "'GitHubReleases"
  elif grep -q 'git ls-remote.*tags' "$list_all" 2>/dev/null; then
    echo "'GitHubTags"
  elif grep -q 'index\.json\|versions\.json' "$utils" 2>/dev/null; then
    echo "'JsonIndex"
  elif grep -q 'gitlab' "$utils" 2>/dev/null; then
    echo "'GitLabReleases"
  else
    echo "'GitHubReleases"
  fi
}

# --- Helper: detect usage mode ---
detect_usage() {
  local cmd="$1"
  local utils="$2"

  # Daemons/servers
  if grep -qiE 'server|daemon|service|start.*stop' "$utils" 2>/dev/null; then
    echo "'Daemon"
  # Interactive REPLs
  elif grep -qiE 'repl|shell|console|iex|irb|ghci|erl$' <<< "$cmd" 2>/dev/null; then
    echo "'Interactive"
  else
    echo "'Oneshot"
  fi
}

# --- Helper: detect function ---
detect_function() {
  local name="$1"
  local utils="$2"

  local functions=""

  # Language runtimes/compilers
  case "$name" in
    *erlang*|*elixir*|*gleam*|*python*|*ruby*|*nodejs*|*deno*|*perl*|*racket*|*julia*|*clojure*|*crystal*|*dart*|*nim*|*haskell*|*ocaml*|*scala*|*rust*|*golang*|*zig*|*lean*|*idris2*|*zig*|*dmd*)
      functions="'Compiler, 'Runtime" ;;
    *cosign*|*age*|*cfssl*|*trivy*|*grype*|*syft*)
      functions="'Security" ;;
    *arangodb*|*cassandra*|*couchdb*|*mariadb*|*redis*|*postgres*|*mongo*)
      functions="'Database, 'Server" ;;
    *kubectl*|*helm*|*k9s*|*kind*|*minikube*|*podman*|*apko*)
      functions="'ContainerTool" ;;
    *just*|*make*|*cmake*|*meson*|*ninja*|*gradle*)
      functions="'BuildTool" ;;
    *)
      functions="'CLI" ;;
  esac

  echo "$functions"
}

# --- Helper: detect ecosystem ---
detect_ecosystem() {
  local name="$1"

  case "$name" in
    *erlang*|*elixir*|*gleam*|*rebar*)
      echo "\"beam\"" ;;
    *nodejs*|*deno*|*bun*)
      echo "\"javascript\"" ;;
    *rust*|*cargo*)
      echo "\"rust\"" ;;
    *golang*|*go-*)
      echo "\"go\"" ;;
    *python*|*pip*)
      echo "\"python\"" ;;
    *ruby*)
      echo "\"ruby\"" ;;
    *haskell*|*ghc*|*cabal*|*stack*)
      echo "\"haskell\"" ;;
    *ocaml*|*opam*)
      echo "\"ocaml\"" ;;
    *zig*)
      echo "\"zig\"" ;;
    *java*|*kotlin*|*scala*|*gradle*|*maven*)
      echo "\"jvm\"" ;;
    *)
      echo "\"system\"" ;;
  esac
}

# --- Main loop ---
for plugin_dir in "$PLUGINS_DIR"/asdf-*/; do
  [ -d "$plugin_dir" ] || continue

  plugin_name=$(basename "$plugin_dir")
  utils="$plugin_dir/lib/utils.bash"
  list_all="$plugin_dir/bin/list-all"

  # Skip non-plugins (no bin/ directory)
  if [ ! -d "$plugin_dir/bin" ]; then
    skipped=$((skipped + 1))
    continue
  fi

  # Skip if no utils.bash (unusual structure)
  if [ ! -f "$utils" ]; then
    echo "SKIP (no utils.bash): $plugin_name" >&2
    skipped=$((skipped + 1))
    continue
  fi

  # Extract data (|| true prevents pipefail exit on no-match)
  gh_repo=$(grep -oP '(?:GH_REPO|REPO|GITHUB_REPO)[= ]*"?\K[^"]+' "$utils" 2>/dev/null | head -1 || true)
  tool_name=$(grep -oP 'TOOL_NAME[= ]*"?\K[^"]+' "$utils" 2>/dev/null | head -1 || true)
  tool_cmd=$(grep -oP 'TOOL_CMD[= ]*"?\K[^"]+' "$utils" 2>/dev/null | head -1 || true)

  # Fallback: derive tool name from plugin directory name
  if [ -z "$tool_name" ]; then
    tool_name=$(echo "$plugin_name" | sed 's/^asdf-//;s/-plugin$//')
  fi
  if [ -z "$tool_cmd" ]; then
    tool_cmd="$tool_name"
  fi

  # Build repository URL
  if [ -n "$gh_repo" ]; then
    repo_url="https://github.com/$gh_repo"
  else
    repo_url=""
  fi

  # Detect characteristics
  archive_format=$(detect_archive_format "$utils")
  version_source=$(detect_version_source "$utils" "$list_all")
  usage_mode=$(detect_usage "$tool_cmd" "$utils")
  tool_functions=$(detect_function "$plugin_name" "$utils")
  ecosystem=$(detect_ecosystem "$plugin_name")

  # Clean name for output file
  clean_name=$(echo "$tool_name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
  output_file="$OUTPUT_DIR/${clean_name}.ncl"

  # Generate Nickel definition
  cat > "$output_file" << NICKEL
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
#
# OPSM Runtime Plugin: ${tool_name}
# Auto-converted from asdf plugin: ${plugin_name}
# Original asdf plugin maintained by hyperpolymath (MIT)
#
# This definition expresses factual data (repository URL, binary name,
# archive format) in OPSM's Nickel contract format. The asdf plugin
# ecosystem's pioneering work is gratefully acknowledged.

let { RuntimePlugin, .. } = import "../contract/runtime-plugin.ncl" in

{
  name = "${tool_name}",
  description = "${tool_name} — managed by OPSM runtime",
  repository = "${repo_url}",

  version_source = ${version_source},
NICKEL

  # Add version_pattern if we can detect tag prefix
  tag_prefix=$(grep -oP 'TAG_PREFIX[= ]*"?\K[^"]+' "$utils" 2>/dev/null | head -1 || true)
  if [ -n "$tag_prefix" ]; then
    echo "  version_pattern = \"${tag_prefix}(.+)\"," >> "$output_file"
  fi

  cat >> "$output_file" << NICKEL

  install = {
    strategy = 'PrebuiltBinary,
    platforms = [
      {
        platform = 'LinuxAmd64,
        archive_name_template = "${tool_name}-{{version}}-linux-amd64.{{ext}}",
        archive_format = ${archive_format},
      },
      {
        platform = 'LinuxArm64,
        archive_name_template = "${tool_name}-{{version}}-linux-arm64.{{ext}}",
        archive_format = ${archive_format},
      },
      {
        platform = 'DarwinAmd64,
        archive_name_template = "${tool_name}-{{version}}-darwin-amd64.{{ext}}",
        archive_format = ${archive_format},
      },
      {
        platform = 'DarwinArm64,
        archive_name_template = "${tool_name}-{{version}}-darwin-arm64.{{ext}}",
        archive_format = ${archive_format},
      },
    ],
    strip_components = 1,
  },

  executables = ["${tool_cmd}"],
  health_check = "${tool_cmd} --version",

  facets = {
    function = [${tool_functions}],
    ecosystem = [${ecosystem}],
    usage = [${usage_mode}],
    tier = ${NICKEL_TIER},
  },

  asdf_origin = "https://github.com/hyperpolymath/asdf-tool-plugins/tree/main/${plugin_name}",
  schema_version = "1.0.0",
} | RuntimePlugin
NICKEL

  converted=$((converted + 1))
done

echo "=== Conversion Summary ==="
echo "Converted: $converted"
echo "Skipped:   $skipped"
echo "Errors:    $errors"
echo "Output:    $OUTPUT_DIR/"
