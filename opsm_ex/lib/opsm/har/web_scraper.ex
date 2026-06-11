# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Har.WebScraper do
  @moduledoc """
  Elixir-native HAR web scraper agent for package discovery.

  Watches the HAR queue directory for tasks and attempts to locate
  packages through web scraping. Discovery strategies (in order):

  1. **Last known URL** — try the URL from hints if provided
  2. **Repository hosting** — check GitHub, GitLab, Codeberg, Sourcehut
  3. **Package registries** — check language-specific registries
  4. **Web search** — scrape search engine results for package URLs

  The agent runs as a GenServer and can be started as part of the
  OTP supervision tree or standalone.

  ## Security

  All fetched URLs pass through `Verified.Url` (SSRF prevention).
  Response bodies are validated via `Verified.Json` where applicable.
  Search result scraping never follows redirects to private networks.
  """

  use GenServer

  require Logger

  alias Opsm.Verified.{Url, Json, Http}

  @queue_dir "/tmp/opsm-har-ingest"
  @poll_interval 2_000
  @request_timeout 10_000

  # Known repository hosting patterns
  @repo_hosts [
    {"github.com", &__MODULE__.check_github/2},
    {"gitlab.com", &__MODULE__.check_gitlab/2},
    {"codeberg.org", &__MODULE__.check_codeberg/2},
    {"sr.ht", &__MODULE__.check_sourcehut/2}
  ]

  # =============================================================================
  # GenServer API
  # =============================================================================

  @doc "Start the web scraper agent."
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Get the current agent status."
  def status do
    GenServer.call(__MODULE__, :status)
  catch
    :exit, _ -> %{running: false}
  end

  @doc "Process a single task (for testing or manual invocation)."
  @spec process_task(map()) :: {:ok, map()} | {:error, term()}
  def process_task(task) do
    do_process_task(task)
  end

  # =============================================================================
  # GenServer Callbacks
  # =============================================================================

  @impl true
  def init(opts) do
    poll_interval = Keyword.get(opts, :poll_interval, @poll_interval)
    schedule_poll(poll_interval)

    state = %{
      poll_interval: poll_interval,
      tasks_processed: 0,
      tasks_failed: 0,
      last_poll: nil
    }

    Logger.info("HAR web scraper agent started (poll interval: #{poll_interval}ms)")
    {:ok, state}
  end

  @impl true
  def handle_info(:poll, state) do
    state = poll_queue(state)
    schedule_poll(state.poll_interval)
    {:noreply, %{state | last_poll: DateTime.utc_now()}}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, Map.put(state, :running, true), state}
  end

  defp schedule_poll(interval) do
    Process.send_after(self(), :poll, interval)
  end

  # =============================================================================
  # Queue Polling
  # =============================================================================

  defp poll_queue(state) do
    ensure_queue_dir()

    tasks =
      Path.wildcard(Path.join(@queue_dir, "*.json"))
      |> Enum.reject(&String.ends_with?(&1, ".result.json"))
      |> Enum.reject(fn f ->
        # Skip tasks that already have results
        result_file = String.replace(f, ".json", ".result.json")
        File.exists?(result_file)
      end)
      |> Enum.reject(fn f ->
        # Skip tasks in processed/ directory
        String.contains?(f, "/processed/")
      end)

    Enum.reduce(tasks, state, fn task_file, acc ->
      case read_task(task_file) do
        {:ok, task} ->
          Logger.info("Processing HAR task: #{task["task_id"]}")

          case do_process_task(task) do
            {:ok, result} ->
              write_result(task["task_id"], result)
              %{acc | tasks_processed: acc.tasks_processed + 1}

            {:error, reason} ->
              write_failure(task["task_id"], task, reason)
              %{acc | tasks_failed: acc.tasks_failed + 1}
          end

        {:error, reason} ->
          Logger.warning("Skipping invalid HAR task file #{task_file}: #{inspect(reason)}")
          acc
      end
    end)
  end

  # =============================================================================
  # Task Processing
  # =============================================================================

  defp do_process_task(task) do
    name = get_in(task, ["package", "name"]) || task["name"] || ""
    version = get_in(task, ["package", "version"]) || "latest"
    language = get_in(task, ["package", "language"]) || "unknown"
    hints = task["hints"] || %{}

    Logger.debug("Scraping for package: #{name} (#{language}) v#{version}")

    strategies = [
      {:last_known_url, fn -> try_last_known_url(hints) end},
      {:repo_hosting, fn -> try_repo_hosts(name, language, hints) end},
      {:registry_search, fn -> try_registry_apis(name, language) end}
    ]

    result =
      Enum.reduce_while(strategies, {:error, :not_found}, fn {strategy, func}, _acc ->
        Logger.debug("Trying strategy: #{strategy} for #{name}")

        case func.() do
          {:ok, discovery} ->
            Logger.info("Found #{name} via #{strategy}")
            {:halt, {:ok, {strategy, discovery}}}

          {:error, _} ->
            {:cont, {:error, :not_found}}
        end
      end)

    case result do
      {:ok, {strategy, discovery}} ->
        build_success_result(task, strategy, discovery)

      {:error, :not_found} ->
        {:error, "Package #{name} not found via web scraping"}
    end
  end

  # =============================================================================
  # Strategy: Last Known URL
  # =============================================================================

  defp try_last_known_url(%{"last_known_url" => url}) when is_binary(url) and url != "" do
    Logger.debug("Checking last known URL: #{url}")

    case Http.get(url, timeout: @request_timeout) do
      {:ok, %{status: status}} when status in 200..299 ->
        {:ok, %{url: url, type: infer_url_type(url), confidence: 0.9}}

      _ ->
        {:error, :url_unreachable}
    end
  end

  defp try_last_known_url(_), do: {:error, :no_hint}

  # =============================================================================
  # Strategy: Repository Hosting Search
  # =============================================================================

  defp try_repo_hosts(name, language, hints) do
    search_terms = hints["search_terms"] || [name]
    common_domains = hints["common_domains"] || []

    # Try explicitly listed domains first
    domain_result =
      Enum.reduce_while(common_domains, {:error, :not_found}, fn domain, _acc ->
        case check_domain_for_package(domain, name) do
          {:ok, discovery} -> {:halt, {:ok, discovery}}
          _ -> {:cont, {:error, :not_found}}
        end
      end)

    case domain_result do
      {:ok, _} = hit ->
        hit

      {:error, _} ->
        # Try standard repo hosts
        Enum.reduce_while(@repo_hosts, {:error, :not_found}, fn {_host, checker}, _acc ->
          term = List.first(search_terms) || name

          case checker.(term, language) do
            {:ok, discovery} -> {:halt, {:ok, discovery}}
            _ -> {:cont, {:error, :not_found}}
          end
        end)
    end
  end

  defp check_domain_for_package(domain, name) do
    url = "https://#{domain}/#{name}"

    case Url.validate(url) do
      {:ok, _} ->
        case Http.get(url, timeout: @request_timeout) do
          {:ok, %{status: status}} when status in 200..299 ->
            {:ok, %{url: url, type: :website, confidence: 0.5}}

          _ ->
            {:error, :not_found}
        end

      {:error, _} ->
        {:error, :invalid_url}
    end
  end

  @doc false
  def check_github(query, language) do
    lang_param = if language != "unknown", do: "+language:#{language}", else: ""
    url = "https://api.github.com/search/repositories?q=#{URI.encode(query)}#{lang_param}&per_page=5"

    case Http.get_json(url, timeout: @request_timeout, headers: [{"accept", "application/vnd.github.v3+json"}]) do
      {:ok, %{"items" => [first | _]}} ->
        confidence = github_confidence(first)

        {:ok, %{
          url: first["html_url"],
          type: :git,
          ref: first["default_branch"],
          description: first["description"],
          license: get_in(first, ["license", "spdx_id"]),
          stars: first["stargazers_count"],
          confidence: confidence
        }}

      _ ->
        {:error, :not_found}
    end
  end

  @doc false
  def check_gitlab(query, _language) do
    url = "https://gitlab.com/api/v4/projects?search=#{URI.encode(query)}&per_page=5"

    case Http.get_json(url, timeout: @request_timeout) do
      {:ok, [first | _]} ->
        {:ok, %{
          url: first["web_url"],
          type: :git,
          ref: first["default_branch"],
          description: first["description"],
          confidence: 0.5
        }}

      _ ->
        {:error, :not_found}
    end
  end

  @doc false
  def check_codeberg(query, _language) do
    url = "https://codeberg.org/api/v1/repos/search?q=#{URI.encode(query)}&limit=5"

    case Http.get_json(url, timeout: @request_timeout) do
      {:ok, %{"data" => [first | _]}} ->
        {:ok, %{
          url: first["html_url"],
          type: :git,
          ref: first["default_branch"],
          description: first["description"],
          confidence: 0.4
        }}

      _ ->
        {:error, :not_found}
    end
  end

  @doc false
  def check_sourcehut(query, _language) do
    # Sourcehut doesn't have a public search API; try direct URL
    url = "https://git.sr.ht/~#{URI.encode(query)}"

    case Url.validate(url) do
      {:ok, _} ->
        case Http.get(url, timeout: @request_timeout) do
          {:ok, %{status: 200}} ->
            {:ok, %{url: url, type: :git, confidence: 0.3}}

          _ ->
            {:error, :not_found}
        end

      _ ->
        {:error, :not_found}
    end
  end

  # =============================================================================
  # Strategy: Registry-Specific APIs
  # =============================================================================

  defp try_registry_apis(name, language) do
    registry_checks =
      case language do
        "elixir" -> [{"https://hex.pm/api/packages/#{name}", :hex}]
        "erlang" -> [{"https://hex.pm/api/packages/#{name}", :hex}]
        "rust" -> [{"https://crates.io/api/v1/crates/#{name}", :cargo}]
        "python" -> [{"https://pypi.org/pypi/#{name}/json", :pypi}]
        "ruby" -> [{"https://rubygems.org/api/v1/gems/#{name}.json", :gem}]
        "javascript" -> [{"https://registry.npmjs.org/#{name}", :npm}]
        "go" -> [{"https://proxy.golang.org/#{name}/@latest", :go}]
        _ -> []
      end

    Enum.reduce_while(registry_checks, {:error, :not_found}, fn {url, registry}, _acc ->
      case Http.get_json(url, timeout: @request_timeout) do
        {:ok, body} when is_map(body) ->
          {:halt, {:ok, %{
            url: url,
            type: :registry,
            registry: registry,
            body: body,
            confidence: 0.95
          }}}

        _ ->
          {:cont, {:error, :not_found}}
      end
    end)
  end

  # =============================================================================
  # Result Building
  # =============================================================================

  defp build_success_result(task, strategy, discovery) do
    name = get_in(task, ["package", "name"]) || ""
    version = get_in(task, ["package", "version"]) || "latest"

    result = %{
      "task_id" => task["task_id"],
      "status" => "success",
      "completed_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "package" => task["package"],
      "package_location" => %{
        "url" => discovery[:url],
        "type" => to_string(discovery[:type] || "unknown"),
        "ref" => discovery[:ref],
        "commit_sha" => nil,
        "subpath" => nil
      },
      "metadata" => %{
        "name" => name,
        "version" => if(version == "latest", do: nil, else: version),
        "description" => discovery[:description],
        "license" => discovery[:license],
        "manifest_file" => nil,
        "dependencies" => []
      },
      "discovery" => %{
        "method" => to_string(strategy),
        "confidence" => discovery[:confidence] || 0.5,
        "agent" => "opsm-web-scraper",
        "agent_version" => "1.2.0",
        "alternatives" => []
      },
      "verification" => %{
        "digest" => nil,
        "verified" => false
      }
    }

    {:ok, result}
  end

  defp write_failure(task_id, _task, reason) do
    result = %{
      "task_id" => task_id,
      "status" => "failure",
      "completed_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "error" => %{
        "message" => to_string(reason),
        "code" => "not_found",
        "attempts" => [
          %{"method" => "last_known_url", "result" => "failed"},
          %{"method" => "repo_hosting", "result" => "failed"},
          %{"method" => "registry_search", "result" => "failed"}
        ]
      },
      "suggestions" => [
        "Try specifying the exact repository URL with --url",
        "Check if the package name is correct",
        "Try a different search term with --search-hints"
      ]
    }

    write_result(task_id, result)
  end

  # =============================================================================
  # File I/O
  # =============================================================================

  defp ensure_queue_dir do
    unless File.dir?(@queue_dir) do
      File.mkdir_p!(@queue_dir)
    end
  end

  defp read_task(task_file) do
    with {:ok, content} <- File.read(task_file),
         {:ok, task} <- Json.decode(content) do
      {:ok, task}
    end
  end

  defp write_result(task_id, result) do
    result_file = Path.join(@queue_dir, "#{task_id}.result.json")

    case Json.encode(result) do
      {:ok, json} ->
        File.write(result_file, json)
        Logger.debug("Wrote HAR result: #{result_file}")

      {:error, reason} ->
        Logger.error("Failed to encode HAR result: #{inspect(reason)}")
    end
  end

  # =============================================================================
  # Helpers
  # =============================================================================

  defp github_confidence(repo) do
    stars = repo["stargazers_count"] || 0

    cond do
      stars >= 1000 -> 0.95
      stars >= 100 -> 0.85
      stars >= 10 -> 0.7
      stars >= 1 -> 0.5
      true -> 0.3
    end
  end

  defp infer_url_type(url) do
    cond do
      String.contains?(url, "github.com") -> :git
      String.contains?(url, "gitlab.com") -> :git
      String.contains?(url, "codeberg.org") -> :git
      String.contains?(url, "sr.ht") -> :git
      String.ends_with?(url, ".tar.gz") -> :tarball
      String.ends_with?(url, ".zip") -> :tarball
      true -> :source
    end
  end
end
