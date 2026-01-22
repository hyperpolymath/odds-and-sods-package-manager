# SPDX-License-Identifier: PMPL-1.0
defmodule Opm.Clients.Oikos do
  @moduledoc """
  Client for Oikos ecosystem sustainability analysis service.
  """

  alias Opm.Http
  alias Opm.Types.{
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
