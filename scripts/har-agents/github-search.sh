#!/usr/bin/env bash
# SPDX-License-Identifier: PMPL-1.0
# HAR Agent: GitHub Search
# Watches "$HYPATIA_TMPDIR/opsm-har-ingest"/ for discovery tasks and searches GitHub API

set -euo pipefail

readonly QUEUE_DIR="${OPSM_HAR_QUEUE_DIR:-"$HYPATIA_TMPDIR/opsm-har-ingest"}"
readonly POLL_INTERVAL=5
readonly GITHUB_API="https://api.github.com/search/repositories"
readonly CURL_CONNECT_TIMEOUT=10
readonly CURL_MAX_TIME=30

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
}

# Sanitize a string for safe use in file paths (alphanumeric, dash, underscore, dot only)
sanitize_path_component() {
    printf '%s' "$1" | tr -cd 'a-zA-Z0-9._-'
}

search_github() {
    local package_name="$1"
    local language="$2"
    local query="$package_name in:name,description language:$language"

    log "Searching GitHub: $query"

    # Search GitHub API (no auth required for public search, but rate-limited)
    local response
    response=$(curl -s --connect-timeout "$CURL_CONNECT_TIMEOUT" --max-time "$CURL_MAX_TIME" \
        -H "Accept: application/vnd.github.v3+json" \
        "$GITHUB_API?q=$(printf '%s' "$query" | jq -sRr @uri)&per_page=5")

    echo "$response"
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
    local package_name language callback_url
    package_name=$(jq -r '.imp.package // .package' "$task_file")
    language=$(jq -r '.imp.forth // .forth // "unknown"' "$task_file")
    callback_url=$(jq -r '.callbackUrl // empty' "$task_file")

    if [[ -z "$package_name" ]]; then
        log "ERROR: No package name in task $task_id"
        return 1
    fi

    # Search GitHub
    local results
    results=$(search_github "$package_name" "$language")

    # Extract first result
    local repo_url repo_description stars
    repo_url=$(echo "$results" | jq -r '.items[0].html_url // empty')
    repo_description=$(echo "$results" | jq -r '.items[0].description // empty')
    stars=$(echo "$results" | jq -r '.items[0].stargazers_count // 0')

    # Construct result
    local result
    result=$(jq -n \
        --arg task_id "$task_id" \
        --arg agent "github-search" \
        --arg package "$package_name" \
        --arg url "$repo_url" \
        --arg description "$repo_description" \
        --arg stars "$stars" \
        '{
            taskId: $task_id,
            agent: $agent,
            package: $package,
            found: ($url != ""),
            repository: $url,
            description: $description,
            confidence: (if ($stars | tonumber) > 100 then "high" elif ($stars | tonumber) > 10 then "medium" else "low" end),
            metadata: {
                stars: ($stars | tonumber)
            }
        }')

    log "Found: $repo_url (stars: $stars)"

    # Write result to results directory
    local result_dir="$QUEUE_DIR/results"
    mkdir -p "$result_dir"
    echo "$result" > "$result_dir/${task_id}.result.json"

    # POST to callback URL if provided (validate it starts with https://)
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

    # Mark task as processed (move to processed directory)
    local processed_dir="$QUEUE_DIR/processed"
    mkdir -p "$processed_dir"
    mv "$task_file" "$processed_dir/"

    log "Task $task_id completed"
}

watch_queue() {
    log "GitHub search agent started"
    log "Watching: $QUEUE_DIR"

    mkdir -p "$QUEUE_DIR"

    shopt -s nullglob
    while true; do
        # Find all .imp.json files in queue
        for task_file in "$QUEUE_DIR"/*.imp.json; do
            # Process task (ignore errors, continue with next)
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
