#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# check-json.sh — J-1 / J-2 conformance gate for this repository.
#
# Policy: metadatastician/standards 3-practice/JSON-POLICY.adoc (owner ruling
# D306). Every authored `.json` file is I-JSON (RFC 7493) serialised by JCS
# (RFC 8785) and followed by exactly one line feed; every `.jsonl` file is one
# canonical record per line, no blank lines.
#
# The canonical implementation of this check lives in standards as
# `scripts/check-ijson-jcs.sh`. This is the repository-local copy so that a
# change upstream cannot silently weaken a gate we depend on, and so that the
# check runs identically on a laptop and in CI. Keep the two in step.
#
# Usage: check-json.sh [--enforce] [PATH...]
#   default      report only; always exit 0 unless the check could not run
#   --enforce    exit 1 when any file is not canonical or is invalid
#   exit 2       the check could not run (no ijson-jcs, missing path) — never
#                reported as a pass: a gate that cannot look has not looked.
#
# Tool: hyperpolymath/ijson-jcs — `check` (0 canonical / 1 not canonical /
# 2 invalid), `canon` (stdin -> stdout).
set -uo pipefail

IJSON_JCS="${IJSON_JCS:-ijson-jcs}"
enforce=0
if [ "${1:-}" = "--enforce" ]; then
    enforce=1
    shift
fi
[ "$#" -gt 0 ] || set -- .

if ! command -v "$IJSON_JCS" >/dev/null 2>&1; then
    echo "$IJSON_JCS: not found; install hyperpolymath/ijson-jcs or set IJSON_JCS" >&2
    exit 2
fi

for path in "$@"; do
    if [ ! -e "$path" ]; then
        echo "$path: scan path does not exist" >&2
        exit 2
    fi
done

bad=0
total=0

note() {
    printf '%s\n' "$*"
    bad=$((bad + 1))
}

# J-1 requires exactly one trailing LF. `ijson-jcs check` tolerates a missing
# one (it is a library-level acceptance), so the on-disk policy is checked here.
has_one_final_lf() {
    [ -s "$1" ] || return 1
    [ "$(tail -c1 "$1" | od -An -c | tr -d ' \n')" = '\n' ] || return 1
    # ... and not two.
    [ "$(tail -c2 "$1" | od -An -c | tr -d ' \n')" = '\n\n' ] && return 1
    return 0
}

while IFS= read -r -d '' file; do
    case "$file" in
        */devcontainer.json|devcontainer.json|*/.vscode/*.json|.vscode/*.json)
            # Tool-demanded JSONC: canonicalising deletes comments, including
            # the SPDX header. Carve-out per JSON-POLICY §4.
            continue
            ;;
    esac

    total=$((total + 1))
    case "$file" in
        *.jsonl)
            # J-2: no blank lines, one canonical record per line.
            lineno=0
            while IFS= read -r line || [ -n "$line" ]; do
                lineno=$((lineno + 1))
                if [ -z "$line" ]; then
                    note "NOT CANONICAL $file:$lineno blank line in JSON Lines"
                    continue
                fi
                if [ "$(printf '%s' "$line" | "$IJSON_JCS" canon 2>/dev/null)" != "$line" ]; then
                    note "NOT CANONICAL $file:$lineno"
                fi
            done < "$file"
            # A JSON Lines file is a sequence of lines, and the last one is only
            # a line if it ends with a line feed. Without this, a file whose
            # final record has no newline passes every per-line check above and
            # then breaks any reader that splits on "\n" — including the
            # per-line loop here, which silently accepts the same short input.
            has_one_final_lf "$file" ||
                note "NOT CANONICAL $file does not end with exactly one line feed"
            ;;
        *.json)
            rc=0
            "$IJSON_JCS" check "$file" >/dev/null 2>&1 || rc=$?
            case "$rc" in
                0)
                    has_one_final_lf "$file" ||
                        note "NOT CANONICAL $file does not end with exactly one line feed"
                    ;;
                1) note "NOT CANONICAL $file" ;;
                2) note "INVALID $file" ;;
                *) note "CHECK FAILED $file (ijson-jcs exit $rc)" ;;
            esac
            ;;
    esac
done < <(json_files "$@")

# json_files ROOT... — the files this gate is about.
#
# TRACKED files only, when inside a git work tree. `find` also returns ignored
# and untracked files: a developer's local build output, an editor's `.cache/`,
# a report a previous run dropped in the tree. Those are not the repository's
# canonical JSON, and failing a pull request over them would be a gate that
# punishes people for having run the tool.
json_files() {
    if git -C "${1:-.}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git -C "${1:-.}" ls-files -z -- '*.json' '*.jsonl'
    else
        find "$@" \( -name .git -o -name node_modules -o -name _build -o -name target \) -prune \
            -o -type f \( -name '*.json' -o -name '*.jsonl' \) -print0 | sort -z
    fi
}

if [ "$bad" -gt 0 ]; then
    printf '\n%s of %s file(s) are not I-JSON + JCS canonical (JSON-POLICY J-1/J-2).\n' "$bad" "$total"
    printf 'Fix: ijson-jcs fix <FILE>...   (JSON Lines: one `ijson-jcs canon` per line)\n'
    [ "$enforce" -eq 1 ] && exit 1
    printf 'Report-only mode: not failing the build.\n'
    exit 0
fi

printf 'OK: all %s JSON/JSON Lines file(s) are I-JSON + JCS canonical.\n' "$total"
exit 0
