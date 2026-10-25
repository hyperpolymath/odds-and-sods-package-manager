#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# check-yaml.sh — YAML policy gate (YAML-POLICY Y-1 / Y-3).
#
# Two jobs, deliberately separated by risk:
#
#  1. PARSE (blocking). Every tracked .yml/.yaml must parse with a real YAML
#     parser. This is not cosmetic: a workflow that does not parse produces a
#     run with no jobs, no log and no annotation, which is exactly how nine
#     dead workflows went unnoticed in another estate repo.
#
#  2. KYAML conformance (report-only by default). YAML-POLICY Y-3 targets KYAML
#     as the estate's authoring dialect but is explicitly SEQUENCED: the scope
#     is not yet decided (Y-3 §3.3) and the estate's own 9,261 workflow files
#     are written by bots (Dependabot, `gh actions-lock`), not by hand. This
#     repository therefore reports KYAML drift and only fails on it under
#     --enforce, once the owner has decided the scope. Reporting it early is
#     what makes that decision possible; enforcing it early would make the
#     repository unmergeable for a style the standard has not yet mandated.
#
# Reading YAML with grep/sed/awk in gate code is forbidden by Y-1 — hence yq,
# and hence a hard exit 2 when yq is absent rather than a silent pass.
#
# Usage: check-yaml.sh [--enforce] [PATH...]
#   exit 0  parsed, and (report mode) reported any KYAML drift
#   exit 1  a file did not parse, or --enforce and a file is not KYAML
#   exit 2  yq is missing / bad usage — the check could not run
set -uo pipefail

enforce=0
if [ "${1:-}" = "--enforce" ]; then
    enforce=1
    shift
fi
[ "$#" -gt 0 ] || set -- .

if ! command -v yq >/dev/null 2>&1; then
    echo "check-yaml: yq (mikefarah v4) is required — a gate that cannot look must not report a pass" >&2
    exit 2
fi

# KYAML output is a `yq` encoder; older builds do not have it. Probe once.
kyaml_supported=0
if printf 'a: 1\n' | yq -p yaml -o kyaml '.' >/dev/null 2>&1; then
    kyaml_supported=1
else
    echo "check-yaml: this yq has no kyaml encoder (need v4.45+); KYAML drift not measured." >&2
fi

parse_fail=0
kyaml_drift=0
total=0
drifted_list=""

while IFS= read -r -d '' file; do
    total=$((total + 1))

    if ! yq -p yaml '.' "$file" >/dev/null 2>&1; then
        echo "::error file=$file::does not parse as YAML"
        parse_fail=$((parse_fail + 1))
        continue
    fi

    # Workflows are bot-written (YAML-POLICY §0). Metric only, never enforced.
    case "$file" in
        ./.github/workflows/*|*/workflows/*) continue ;;
    esac

    [ "$kyaml_supported" -eq 1 ] || continue
    [ -s "$file" ] || continue

    if ! rendered=$(yq -p yaml -o kyaml '.' "$file" 2>/dev/null); then
        continue
    fi

    if [ "$rendered" != "$(cat "$file")" ]; then
        kyaml_drift=$((kyaml_drift + 1))
        drifted_list="${drifted_list}${file}
"
        echo "kyaml drift: $file"
    fi
done < <(find "$@" \( -name .git -o -name node_modules -o -name _build -o -name target \) -prune \
    -o -type f \( -name '*.yml' -o -name '*.yaml' \) -print0 | sort -z)

echo
echo "check-yaml: $total file(s) scanned; $parse_fail parse failure(s); $kyaml_drift not KYAML."

if [ "$parse_fail" -gt 0 ]; then
    exit 1
fi

if [ "$kyaml_drift" -gt 0 ]; then
    printf '%s' "$drifted_list" | sed 's/^/  /'
    if [ "$enforce" -eq 1 ]; then
        echo "check-yaml: --enforce and $kyaml_drift file(s) are not KYAML."
        exit 1
    fi
    echo "Report-only: Y-3 is sequenced (scope undecided). Rewrite any file with:"
    echo "  yq -p yaml -o kyaml '.' FILE > FILE.kyaml   # review, then replace"
fi

exit 0
