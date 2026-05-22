# SPDX-License-Identifier: MPL-2.0
defmodule Opsm.Clients.Oikos do
  @moduledoc """
  Client for Oikos ecosystem sustainability analysis service.
  """

  alias Opsm.Http
  alias Opsm.Types.{
    ServiceConfig,
    HttpConfig,
    OikosAnalysisRequest,
    OikosAnalysisResponse,
    OikosHealthResponse,
    SustainabilityScores
  }

  defstruct [:client]

  @type t :: %__MODULE__{client: Req.Request.t()}

  def new(%ServiceConfig{} = config, %HttpConfig{} = http_config) do
    client = Http.build_client(http_config, base_url: config.base_url, token: config.token)
    %__MODULE__{client: client}
  end

  @doc """
  Analyze a repository for sustainability.
  """
  def analyze_repository(%__MODULE__{client: client}, %OikosAnalysisRequest{} = request) do
    body = %{
      "repositoryUrl" => request.repository_url,
      "branch" => request.branch,
      "commitSha" => request.commit_sha
    }

    with :ok <- Http.post_json(client, "/analysis/repository", body),
         encoded_url = URI.encode_www_form(request.repository_url),
         {:ok, json} <- Http.get_json(client, "/analysis/repository/#{encoded_url}") do
      {:ok, decode_analysis_response(json)}
    end
  end

  @doc """
  Check service health.
  """
  def health(%__MODULE__{client: client}) do
    case Http.get_json(client, "/health") do
      {:ok, json} -> {:ok, decode_health_response(json)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Analyze a package for sustainability scoring.

  Attempts repository analysis if the package has a repository URL.
  Falls back to heuristic scoring based on package metadata.
  """
  def analyze_package(%__MODULE__{} = oikos, package_name, package_version, opts \\ []) do
    repo_url = Keyword.get(opts, :repository_url)
    forth = Keyword.get(opts, :forth, :unknown)

    cond do
      # If we have a repo URL, use full repository analysis
      repo_url != nil ->
        request = %OikosAnalysisRequest{
          repository_url: repo_url,
          branch: "main",
          commit_sha: nil
        }

        case analyze_repository(oikos, request) do
          {:ok, response} -> {:ok, response.overall_score}
          {:error, _} -> {:ok, heuristic_score(package_name, package_version, forth)}
        end

      # No repo URL — use heuristic scoring
      true ->
        {:ok, heuristic_score(package_name, package_version, forth)}
    end
  end

  @doc """
  Batch analyze multiple packages for sustainability.

  Returns a map of `"name@version" => score`.
  """
  def analyze_packages(%__MODULE__{} = oikos, packages) do
    packages
    |> Task.async_stream(fn {name, version, opts} ->
      {:ok, score} = analyze_package(oikos, name, version, opts)
      {"#{name}@#{version}", score}
    end, max_concurrency: 5, timeout: 10_000, on_timeout: :kill_task)
    |> Enum.reduce(%{}, fn
      {:ok, {key, score}}, acc -> Map.put(acc, key, score)
      {:exit, _}, acc -> acc
    end)
  end

  # Heuristic scoring based on package metadata when oikos service is unavailable
  defp heuristic_score(name, version, forth) do
    base = 50

    # Bonus for well-known ecosystems
    ecosystem_bonus = case forth do
      f when f in [:npm, :cargo, :hex, :pypi, :gem, :go] -> 10
      f when f in [:pub, :hackage, :nuget, :maven] -> 8
      _ -> 0
    end

    # Bonus for semver-compliant versions (indicates maturity)
    version_bonus = case Version.parse(version || "") do
      {:ok, %{major: m}} when m >= 1 -> 15
      {:ok, _} -> 5
      :error -> 0
    end

    # Penalty for very short names (potential typosquatting)
    name_penalty = if String.length(name || "") < 3, do: -10, else: 0

    min(100, max(0, base + ecosystem_bonus + version_bonus + name_penalty))
  end

  # Decoders

  defp decode_analysis_response(json) do
    %OikosAnalysisResponse{
      repository_url: json["repositoryUrl"] || "",
      analyzed_at: json["analyzedAt"] || "",
      overall_score: json["overallScore"] || 0,
      scores: decode_scores(json["scores"]),
      recommendations: json["recommendations"] || [],
      risks: []
    }
  end

  defp decode_scores(nil), do: %SustainabilityScores{}
  defp decode_scores(json) do
    %SustainabilityScores{
      maintainability: json["maintainability"] || 0,
      documentation: json["documentation"] || 0,
      test_coverage: json["testCoverage"] || 0,
      community_health: json["communityHealth"] || 0,
      security_posture: json["securityPosture"] || 0,
      dependency_health: json["dependencyHealth"] || 0,
      release_maturity: json["releaseMaturity"] || 0,
      code_quality: json["codeQuality"] || 0
    }
  end

  defp decode_health_response(json) do
    %OikosHealthResponse{
      status: decode_status(json["status"]),
      version: json["version"] || "unknown",
      uptime: json["uptime"] || 0
    }
  end

  defp decode_status("healthy"), do: :healthy
  defp decode_status("degraded"), do: :degraded
  defp decode_status(_), do: :unhealthy
end
