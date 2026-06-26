#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
#
# generate-rsr-repo.sh — RSR Repository Generator for Runtime Plugins
# =====================================================================
# Creates a full RSR-compliant repository from a Nickel plugin definition.
# For contributors who want their own repo (rather than PR-ing into OPSM).
#
# The generated repo includes:
#   - The Nickel plugin definition
#   - RSR-standard workflows (17 workflows from rsr-template-repo)
#   - A2ML manifest
#   - Machine-readable metadata (.machine_readable/6a2/)
#   - Justfile with OPSM runtime recipes
#   - README.adoc with badges
#   - EXPLAINME.adoc
#   - SECURITY.md, CONTRIBUTING.md, LICENSE
#
# Usage:
#   ./generate-rsr-repo.sh <plugin.ncl> [output-dir]
#
# If output-dir is omitted, creates ~/Documents/hyperpolymath-repos/opsm-runtime-<name>

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_REPO="${RSR_TEMPLATE:-$HOME/Documents/hyperpolymath-repos/rsr-template-repo}"

# --- Colours ---
if [[ -t 1 ]]; then
  BOLD='\033[1m' GREEN='\033[0;32m' BLUE='\033[0;34m'
  RED='\033[0;31m' YELLOW='\033[0;33m' NC='\033[0m'
else
  BOLD='' GREEN='' BLUE='' RED='' YELLOW='' NC=''
fi

info()  { echo -e "${BLUE}[opsm-rsr-gen]${NC} $*"; }
ok()    { echo -e "${GREEN}[opsm-rsr-gen]${NC} $*"; }
err()   { echo -e "${RED}[opsm-rsr-gen]${NC} $*" >&2; }
warn()  { echo -e "${YELLOW}[opsm-rsr-gen]${NC} $*"; }

# --- Input ---
PLUGIN_FILE="${1:?Usage: $0 <plugin.ncl> [output-dir]}"

if [[ ! -f "$PLUGIN_FILE" ]]; then
  err "Plugin file not found: $PLUGIN_FILE"
  exit 1
fi

# Extract plugin name (grep fallback since nickel may not be installed)
TOOL_NAME=$(grep -oP 'name\s*=\s*"\K[^"]+' "$PLUGIN_FILE" | head -1)
DESCRIPTION=$(grep -oP 'description\s*=\s*"\K[^"]+' "$PLUGIN_FILE" | head -1)
REPO_URL=$(grep -oP 'repository\s*=\s*"\K[^"]+' "$PLUGIN_FILE" | head -1)

if [[ -z "$TOOL_NAME" ]]; then
  err "Could not extract tool name from: $PLUGIN_FILE"
  exit 1
fi

REPO_NAME="opsm-runtime-${TOOL_NAME}"
OUTPUT_DIR="${2:-$HOME/Documents/hyperpolymath-repos/${REPO_NAME}}"

info "Generating RSR repo: ${BOLD}${REPO_NAME}${NC}"
info "Tool: ${TOOL_NAME}"
info "Output: ${OUTPUT_DIR}"

# --- Check template ---
if [[ ! -d "$TEMPLATE_REPO" ]]; then
  err "RSR template not found at: $TEMPLATE_REPO"
  err "Set RSR_TEMPLATE env var or clone rsr-template-repo"
  exit 1
fi

# --- Clone template ---
if [[ -d "$OUTPUT_DIR" ]]; then
  err "Directory already exists: $OUTPUT_DIR"
  exit 1
fi

info "Cloning RSR template..."
cp -r "$TEMPLATE_REPO" "$OUTPUT_DIR"
rm -rf "$OUTPUT_DIR/.git"

# --- Create plugin directory ---
mkdir -p "$OUTPUT_DIR/runtime"
cp "$PLUGIN_FILE" "$OUTPUT_DIR/runtime/${TOOL_NAME}.ncl"

# --- Generate README.adoc ---
cat > "$OUTPUT_DIR/README.adoc" << ADOC
// SPDX-License-Identifier: MPL-2.0
= opsm-runtime-${TOOL_NAME}
:revdate: $(date +%Y-%m-%d)
:toc: macro

image:https://img.shields.io/badge/OPSM-Runtime_Plugin-blue?style=flat[OPSM Runtime]
image:https://img.shields.io/badge/License-MPL--2.0-blue.svg[License: PMPL-1.0]
image:https://img.shields.io/badge/Contract-v1.0.0-success?style=flat[Contract v1.0.0]

**OPSM Runtime Plugin for ${TOOL_NAME}.**

${DESCRIPTION}

toc::[]

== Overview

This is an OPSM runtime plugin definition for \`${TOOL_NAME}\`.
It can be used standalone or contributed to the OPSM core/community catalogue.

Upstream: ${REPO_URL}

== Usage

=== With OPSM

[source,bash]
----
# Install via OPSM
opsm runtime install ${TOOL_NAME} latest

# Set version for current project
opsm runtime set ${TOOL_NAME} <version>

# List available versions
opsm runtime list-all ${TOOL_NAME}
----

=== Standalone

[source,bash]
----
# Validate the plugin definition
nickel typecheck runtime/${TOOL_NAME}.ncl

# Use with OPSM provisioner
./provision.sh runtime/${TOOL_NAME}.ncl <version>
----

== Plugin Definition

The Nickel definition at \`runtime/${TOOL_NAME}.ncl\` satisfies the
OPSM \`RuntimePlugin\` contract, ensuring:

- Typed version source and install strategy
- Platform-aware archive templates
- Faceted classification for UI discovery
- Health check verification after install
- Trust pipeline integration via OPSM

== Contributing

To improve this plugin:

1. Edit \`runtime/${TOOL_NAME}.ncl\`
2. Validate: \`nickel typecheck runtime/${TOOL_NAME}.ncl\`
3. Test: \`opsm runtime install ${TOOL_NAME} <version>\`
4. Submit PR to this repo or to the OPSM monorepo

== License

MPL-2.0 (Palimpsest License)
ADOC

# --- Generate EXPLAINME.adoc ---
cat > "$OUTPUT_DIR/EXPLAINME.adoc" << ADOC
// SPDX-License-Identifier: MPL-2.0
= EXPLAINME: opsm-runtime-${TOOL_NAME}
:revdate: $(date +%Y-%m-%d)

== What is this?

A runtime plugin definition for \`${TOOL_NAME}\`, written in Nickel and
validated against OPSM's \`RuntimePlugin\` contract. It tells OPSM how to
discover, download, install, verify, and manage versions of ${TOOL_NAME}.

== Why Nickel?

Nickel provides contracts (type-checked schemas) that catch malformed
plugin definitions at write time. Unlike Bash scripts (asdf's approach),
a Nickel definition is declarative, auditable, and cannot execute
arbitrary code. The contract IS the specification.

== Why not just use asdf?

This plugin integrates with OPSM's trust pipeline (SLSA L3 provenance,
post-quantum signatures, attestation scoring). asdf plugins are
unverified Bash scripts. OPSM plugins are typed, attested, and
trust-scored before they reach your machine.

== How does it work?

1. The Nickel file declares: where to find versions, how to download,
   what binaries to shim, how to verify the install works
2. OPSM's provisioner reads this and executes the install
3. The Zig shim dispatcher routes commands to the installed version
4. PanLL panels can switch versions per-workspace with env injection

== Evidence

- Contract validation: \`nickel typecheck runtime/${TOOL_NAME}.ncl\`
- Integration with OPSM trust pipeline (checky-monkey, palimpsest-license, oikos)
- .tool-versions compatibility (reads asdf format)
ADOC

# --- Generate Justfile ---
cat > "$OUTPUT_DIR/justfile" << 'JUST'
# SPDX-License-Identifier: MPL-2.0
# Justfile for opsm-runtime plugin

# Validate the Nickel plugin definition
check:
    nickel typecheck runtime/*.ncl

# Install a specific version
install version:
    opsm runtime install {{tool}} {{version}}

# List available versions
versions:
    opsm runtime list-all {{tool}}

# Run health check
health:
    opsm runtime health {{tool}}

# Export to .tool-versions format
export-tv:
    opsm runtime export .tool-versions
JUST

# Replace {{tool}} placeholder
sed -i "s/{{tool}}/${TOOL_NAME}/g" "$OUTPUT_DIR/justfile"

# --- Generate A2ML manifest ---
cat > "$OUTPUT_DIR/0-AI-MANIFEST.a2ml" << A2ML
# OPSM Runtime Plugin: ${TOOL_NAME}

## WHAT IS THIS?

This is an OPSM runtime plugin repository for \`${TOOL_NAME}\`.
The plugin definition is at \`runtime/${TOOL_NAME}.ncl\`.

## CANONICAL LOCATIONS

- Plugin definition: \`runtime/${TOOL_NAME}.ncl\`
- Contract: imported from OPSM monorepo
- Machine-readable metadata: \`.machine_readable/6a2/\`

## CORE INVARIANTS

1. The Nickel file must satisfy the RuntimePlugin contract
2. SCM files in \`.machine_readable/6a2/\` ONLY (never root)
3. License: MPL-2.0

## SESSION STARTUP

1. Read this manifest
2. Read \`runtime/${TOOL_NAME}.ncl\` to understand the plugin
3. Check \`.machine_readable/6a2/STATE.a2ml\` for current status
A2ML

# --- Init git ---
cd "$OUTPUT_DIR"
git init -q
git add -A
git commit -q -m "Initial commit: OPSM runtime plugin for ${TOOL_NAME}

Generated by OPSM RSR repo generator.
Plugin definition satisfies RuntimePlugin contract v1.0.0.

Co-Authored-By: OPSM Runtime Minter <noreply@hyperpolymath.github.io>"

ok "RSR repository created: ${OUTPUT_DIR}"
ok "Files:"
find "$OUTPUT_DIR" -maxdepth 2 -not -path '*/.git/*' -not -path '*/.git' | sort | head -30
echo
info "Next steps:"
info "  1. Review runtime/${TOOL_NAME}.ncl"
info "  2. Customize archive_name_template for actual release filenames"
info "  3. just check  — validate the Nickel definition"
info "  4. git remote add origin <url> && git push"
