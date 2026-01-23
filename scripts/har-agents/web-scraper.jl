#!/usr/bin/env julia
# SPDX-License-Identifier: PMPL-1.0
# HAR Agent: Web Scraper
# Searches for package repositories using web search and scraping

using HTTP
using JSON3
using Dates

const QUEUE_DIR = "/tmp/opm-har-ingest"
const POLL_INTERVAL = 5
const SEARCH_ENGINE = "https://html.duckduckgo.com/html/"

function log_msg(msg::String)
    println(stderr, "[$(Dates.format(now(), "yyyy-mm-dd HH:MM:SS"))] $msg")
end

function search_web(package_name::String, language::String)
    log_msg("Searching web: $package_name ($language)")

    query = "$package_name $language package repository"

    try
        # Use DuckDuckGo HTML search (no API key required)
        response = HTTP.get(SEARCH_ENGINE, query=Dict("q" => query))
        body = String(response.body)

        # Extract URLs from HTML (simple regex approach)
        # This is a basic implementation - production would use proper HTML parsing
        urls = [m.match for m in eachmatch(r"https?://[^\s<>\"]+", body)]

        # Filter for common code hosting sites
        code_hosts = ["github.com", "gitlab.com", "codeberg.org", "sr.ht",
                     "bitbucket.org", "sourceforge.net"]

        relevant_urls = filter(url -> any(host -> occursin(host, url), code_hosts), urls)

        return relevant_urls[1:min(5, length(relevant_urls))]
    catch e
        log_msg("ERROR: Web search failed: $e")
        return String[]
    end
end

function try_known_locations(package_name::String, language::String)
    # Try common package repository patterns
    patterns = [
        "https://github.com/$language/$package_name",
        "https://github.com/$(lowercase(language))-$package_name/$package_name",
        "https://gitlab.com/$package_name/$package_name",
        "https://sr.ht/~$(lowercase(language))/$package_name"
    ]

    for url in patterns
        try
            response = HTTP.head(url, status_exception=false)
            if response.status < 400
                log_msg("Found at known location: $url")
                return url
            end
        catch
            continue
        end
    end

    return nothing
end

function process_task(task_file::String)
    task_id = replace(basename(task_file), ".imp.json" => "")
    log_msg("Processing task: $task_id")

    # Parse task JSON
    task = JSON3.read(read(task_file, String))

    package_name = get(get(task, :imp, Dict()), :package, get(task, :package, nothing))
    language = get(get(task, :imp, Dict()), :forth, get(task, :forth, "unknown"))
    callback_url = get(task, :callbackUrl, nothing)
    last_known_url = get(get(task, :imp, Dict()), :last_known_url, nothing)

    if isnothing(package_name)
        log_msg("ERROR: No package name in task $task_id")
        return false
    end

    # Try strategies in order:
    # 1. Last known URL (if provided)
    # 2. Known location patterns
    # 3. Web search

    found_url = nothing
    confidence = "low"
    source = "unknown"

    if !isnothing(last_known_url)
        try
            response = HTTP.head(last_known_url, status_exception=false)
            if response.status < 400
                found_url = last_known_url
                confidence = "high"
                source = "last_known_url"
                log_msg("Package still at last known URL: $last_known_url")
            end
        catch
            log_msg("Last known URL no longer valid: $last_known_url")
        end
    end

    if isnothing(found_url)
        found_url = try_known_locations(package_name, language)
        if !isnothing(found_url)
            confidence = "medium"
            source = "known_pattern"
        end
    end

    if isnothing(found_url)
        urls = search_web(package_name, language)
        if !isempty(urls)
            found_url = urls[1]
            confidence = "low"
            source = "web_search"
        end
    end

    # Construct result
    result = Dict(
        "taskId" => task_id,
        "agent" => "web-scraper",
        "package" => package_name,
        "found" => !isnothing(found_url),
        "repository" => something(found_url, ""),
        "confidence" => confidence,
        "metadata" => Dict(
            "source" => source,
            "language" => language
        )
    )

    log_msg("Result: found=$(result["found"]), confidence=$confidence")

    # Write result
    result_dir = joinpath(QUEUE_DIR, "results")
    mkpath(result_dir)
    result_file = joinpath(result_dir, "$(task_id).result.json")
    write(result_file, JSON3.write(result))

    # POST to callback URL if provided
    if !isnothing(callback_url)
        try
            log_msg("Posting result to $callback_url")
            HTTP.post(callback_url, ["Content-Type" => "application/json"], JSON3.write(result))
        catch e
            log_msg("WARN: Failed to post to callback URL: $e")
        end
    end

    # Mark task as processed
    processed_dir = joinpath(QUEUE_DIR, "processed")
    mkpath(processed_dir)
    mv(task_file, joinpath(processed_dir, basename(task_file)))

    log_msg("Task $task_id completed")
    return true
end

function watch_queue()
    log_msg("Web scraper agent started")
    log_msg("Watching: $QUEUE_DIR")

    mkpath(QUEUE_DIR)

    while true
        # Find all .imp.json files
        task_files = filter(f -> endswith(f, ".imp.json"), readdir(QUEUE_DIR, join=true))

        for task_file in task_files
            try
                process_task(task_file)
            catch e
                log_msg("ERROR: Failed to process $(basename(task_file)): $e")
            end
        end

        sleep(POLL_INTERVAL)
    end
end

function main()
    # Check dependencies
    try
        # Test that required packages are available
        using HTTP, JSON3
        log_msg("Dependencies OK")
    catch e
        log_msg("ERROR: Missing required Julia packages: $e")
        log_msg("Install with: julia -e 'using Pkg; Pkg.add([\"HTTP\", \"JSON3\"])'")
        exit(1)
    end

    watch_queue()
end

# Run if executed as script
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
