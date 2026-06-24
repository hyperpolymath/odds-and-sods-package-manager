#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# HAR Agent: Mirror Finder
# Searches for package mirrors in Software Heritage, archive.org, and distro snapshots

set -euo pipefail

readonly QUEUE_DIR="${OPSM_HAR_QUEUE_DIR:-"$HYPATIA_TMPDIR/opsm-har-ingest"}"
readonly POLL_INTERVAL=5
readonly SWH_API="https://archive.softwareheritage.org/api/1"
readonly WAYBACK_API="https://archive.org/wayback/available"
readonly CURL_CONNECT_TIMEOUT=10
readonly CURL_MAX_TIME=30

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
}

# Sanitize a string for safe use in file paths
sanitize_path_component() {
    printf '%s' "$1" | tr -cd 'a-zA-Z0-9._-'
}

# URL-encode a string for safe inclusion in URLs
urlencode() {
    printf '%s' "$1" | jq -sRr @uri
}

check_software_heritage() {
    local url="$1"

    log "Checking Software Heritage: $url"

    # Try to find URL in SWH archive
    local encoded_url
    encoded_url=$(urlencode "$url")
    local response
    response=$(curl -s --connect-timeout "$CURL_CONNECT_TIMEOUT" --max-time "$CURL_MAX_TIME" \
        "${SWH_API}/origin/${encoded_url}/get/" || echo '{}')

    local found
    found=$(echo "$response" | jq -r '.url // empty')

    if [[ -n "$found" ]]; then
        log "Found in Software Heritage: $found"
        echo "$found"
        return 0
    fi

    return 1
}

check_wayback_machine() {
    local url="$1"

    log "Checking Wayback Machine: $url"

    # Check if URL is archived
    local response
    response=$(curl -s --connect-timeout "$CURL_CONNECT_TIMEOUT" --max-time "$CURL_MAX_TIME" \
        "${WAYBACK_API}?url=$(urlencode "$url")" || echo '{}')

    local snapshot
    snapshot=$(echo "$response" | jq -r '.archived_snapshots.closest.url // empty')

    if [[ -n "$snapshot" ]]; then
        log "Found in Wayback Machine: $snapshot"
        echo "$snapshot"
        return 0
    fi

    return 1
}

check_debian_snapshot() {
    local package_name="$1"

    log "Checking Debian snapshot: $package_name"

    # Try Debian snapshot service (URL-encode package name)
    local encoded_name
    encoded_name=$(urlencode "$package_name")
    local response
    response=$(curl -s --connect-timeout "$CURL_CONNECT_TIMEOUT" --max-time "$CURL_MAX_TIME" \
        "https://snapshot.debian.org/package/${encoded_name}/" || echo '')

    if echo "$response" | grep -qF "package ${package_name}"; then
        local url="https://snapshot.debian.org/package/${package_name}/"
        log "Found in Debian snapshot: $url"
        echo "$url"
        return 0
    fi

    return 1
}

check_fedora_archive() {
    local package_name="$1"

    log "Checking Fedora archives: $package_name"

    # Try Fedora archives (koji)
    local encoded_name
    encoded_name=$(urlencode "$package_name")
    local response
    response=$(curl -s --connect-timeout "$CURL_CONNECT_TIMEOUT" --max-time "$CURL_MAX_TIME" \
        "https://koji.fedoraproject.org/koji/search?match=glob&type=package&terms=${encoded_name}" || echo '')

    if echo "$response" | grep -qF "packageinfo"; then
        local url="https://koji.fedoraproject.org/koji/packageinfo?packageID=${encoded_name}"
        log "Found in Fedora archive: $url"
        echo "$url"
        return 0
    fi

    return 1
}

process_task() {
    local task_file="$1"
    local task_id
    task_id=$(sanitize_path_component "$(basename "$task_file" .imp.json)")

    if [[ -z "$task_id" ]]; then
        log "ERROR: Empty task_id from $task_file"
        return 1
    fi

    log "Processing task: $task_id"

    # Parse task JSON
    local package_name repository_url
    package_name=$(jq -r '.imp.package // .package' "$task_file")
    repository_url=$(jq -r '.imp.repository // .repository // empty' "$task_file")

    if [[ -z "$package_name" ]]; then
        log "ERROR: No package name in task $task_id"
        return 1
    fi

    local mirrors=()
    local confidence="low"

    # Try different mirror sources
    if [[ -n "$repository_url" ]]; then
        # If we have a repository URL, check archives for it
        if mirror=$(check_software_heritage "$repository_url" 2>/dev/null); then
            mirrors+=("$mirror")
            confidence="high"
        fi

        if mirror=$(check_wayback_machine "$repository_url" 2>/dev/null); then
            mirrors+=("$mirror")
            [[ "$confidence" == "low" ]] && confidence="medium"
        fi
    fi

    # Check distro archives by package name
    if mirror=$(check_debian_snapshot "$package_name" 2>/dev/null); then
        mirrors+=("$mirror")
        [[ "$confidence" == "low" ]] && confidence="medium"
    fi

    if mirror=$(check_fedora_archive "$package_name" 2>/dev/null); then
        mirrors+=("$mirror")
        [[ "$confidence" == "low" ]] && confidence="medium"
    fi

    # Construct result
    local mirrors_json
    mirrors_json=$(printf '%s\n' "${mirrors[@]}" | jq -R . | jq -s .)

    local result
    result=$(jq -n \
        --arg task_id "$task_id" \
        --arg agent "mirror-finder" \
        --arg package "$package_name" \
        --argjson found "$(( ${#mirrors[@]} > 0 ))" \
        --argjson mirrors "$mirrors_json" \
        --arg confidence "$confidence" \
        '{
            taskId: $task_id,
            agent: $agent,
            package: $package,
            found: $found,
            mirrors: $mirrors,
            confidence: $confidence,
            metadata: {
                mirrorCount: ($mirrors | length)
            }
        }')

    log "Found ${#mirrors[@]} mirror(s)"

    # Write result
    local result_dir="$QUEUE_DIR/results"
    mkdir -p "$result_dir"
    echo "$result" > "$result_dir/${task_id}.result.json"

    # POST to callback URL if provided (validate HTTPS only)
    local callback_url
    callback_url=$(jq -r '.callbackUrl // empty' "$task_file")

    if [[ -n "$callback_url" ]]; then
        if [[ "$callback_url" =~ ^https:// ]]; then
            log "Posting result to $callback_url"
            curl -s --connect-timeout "$CURL_CONNECT_TIMEOUT" --max-time "$CURL_MAX_TIME" \
                -X POST \
                -H "Content-Type: application/json" \
                -d "$result" \
                "$callback_url" || log "WARN: Failed to post to callback URL"
        else
            log "WARN: Refusing callback to non-HTTPS URL: $callback_url"
        fi
    fi

    # Mark task as processed
    local processed_dir="$QUEUE_DIR/processed"
    mkdir -p "$processed_dir"
    mv "$task_file" "$processed_dir/"

    log "Task $task_id completed"
}

watch_queue() {
    log "Mirror finder agent started"
    log "Watching: $QUEUE_DIR"

    mkdir -p "$QUEUE_DIR"

    shopt -s nullglob
    while true; do
        for task_file in "$QUEUE_DIR"/*.imp.json; do
            process_task "$task_file" || log "ERROR: Failed to process $(basename "$task_file")"
        done

        sleep "$POLL_INTERVAL"
    done
}

main() {
    # Check dependencies
    if ! command -v jq &>/dev/null; then
        log "ERROR: jq is required but not installed"
        exit 1
    fi

    if ! command -v curl &>/dev/null; then
        log "ERROR: curl is required but not installed"
        exit 1
    fi

    watch_queue
}

main "$@"
