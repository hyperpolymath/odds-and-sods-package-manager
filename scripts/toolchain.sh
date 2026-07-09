#!/bin/sh
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
#
# toolchain.sh — derive .tool-versions from the canonical [runtime] block in
# opsm.toml, and verify that no downstream copy has drifted.
#
#   scripts/toolchain.sh sync    regenerate .tool-versions from opsm.toml
#   scripts/toolchain.sh check   exit 1 if .tool-versions or .gitlab-ci.yml
#                                image pins disagree with opsm.toml [runtime]
#
# opsm.toml [runtime] is the single source of truth (see docs/TOOLCHAIN.adoc).
# Tools excluded from the generated .tool-versions:
#   idris2 — no asdf plugin exists; provisioned via pack/Chez (docs/TOOLCHAIN.adoc)
#   rust   — managed via asdf global to avoid conflicting with cargo-audit and
#            other cargo subcommands; CI pins it to the same canonical version

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
MANIFEST="$ROOT/opsm.toml"
TOOL_VERSIONS="$ROOT/.tool-versions"
GITLAB_CI="$ROOT/.gitlab-ci.yml"
SKIP_TOOLS="idris2 rust"

usage() {
    echo "usage: $0 {sync|check}" >&2
    exit 2
}

[ $# -eq 1 ] || usage

# Emit "tool version" pairs from the [runtime] section, in file order.
runtime_pins() {
    awk -F'=' '
        /^\[runtime\]/ { insec = 1; next }
        /^\[/          { insec = 0 }
        insec && $0 !~ /^[[:space:]]*#/ && NF >= 2 {
            key = $1; val = $2
            gsub(/[[:space:]]/, "", key)
            sub(/#.*/, "", val)
            gsub(/[[:space:]"]/, "", val)
            if (key != "" && val != "") print key, val
        }
    ' "$MANIFEST"
}

pin_version() {
    runtime_pins | awk -v t="$1" '$1 == t { print $2 }'
}

skipped() {
    for s in $SKIP_TOOLS; do
        [ "$1" = "$s" ] && return 0
    done
    return 1
}

generate() {
    idris2_v=$(pin_version idris2)
    rust_v=$(pin_version rust)
    cat <<EOF
# SPDX-License-Identifier: MPL-2.0
# GENERATED FILE — do not edit by hand.
# Source of truth: opsm.toml [runtime]. Regenerate with: just toolchain-sync
# Drift is CI-gated by: just toolchain-check
#
# Plugin sources: erlang/elixir via the standard asdf plugins;
# zig, deno, nickel via https://github.com/hyperpolymath/asdf-tool-plugins
#
# Canonical pins deliberately NOT listed here (see docs/TOOLCHAIN.adoc):
#   idris2 $idris2_v — no asdf plugin; provision via pack + Chez Scheme + GMP
#   rust $rust_v — asdf-global-managed to avoid cargo-audit conflicts; CI pins it
EOF
    runtime_pins | while read -r tool version; do
        skipped "$tool" || echo "$tool $version"
    done
}

check_gitlab_image() {
    image="$1" expected="$2"
    if grep -qE "image:[[:space:]]*${image}:latest" "$GITLAB_CI"; then
        echo "DRIFT: $GITLAB_CI uses ${image}:latest — pin it to ${image}:${expected}" >&2
        return 1
    fi
    if grep -qE "image:[[:space:]]*${image}:" "$GITLAB_CI" &&
        ! grep -qE "image:[[:space:]]*${image}:${expected}" "$GITLAB_CI"; then
        echo "DRIFT: $GITLAB_CI pins ${image} to something other than ${expected} (opsm.toml [runtime])" >&2
        return 1
    fi
    return 0
}

case "$1" in
    sync)
        generate > "$TOOL_VERSIONS"
        echo "wrote $TOOL_VERSIONS from opsm.toml [runtime]"
        ;;
    check)
        status=0

        tmp=$(mktemp)
        trap 'rm -f "$tmp"' EXIT
        generate > "$tmp"
        if ! diff -u "$TOOL_VERSIONS" "$tmp" >&2; then
            echo "DRIFT: .tool-versions does not match opsm.toml [runtime] — run: just toolchain-sync" >&2
            status=1
        fi

        elixir_v=$(pin_version elixir)
        rust_mm=$(pin_version rust | cut -d. -f1,2)
        check_gitlab_image elixir "$elixir_v" || status=1
        check_gitlab_image rust "$rust_mm" || status=1

        if [ "$status" -eq 0 ]; then
            echo "toolchain-check OK: .tool-versions and CI image pins match opsm.toml [runtime]"
        fi
        exit "$status"
        ;;
    *)
        usage
        ;;
esac
