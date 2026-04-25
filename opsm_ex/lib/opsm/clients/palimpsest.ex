# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule Opsm.Clients.Palimpsest do
  @moduledoc """
  Client for Palimpsest license analysis service.
  Includes CLI fallback for license validation.
  """

  alias Opsm.Http
  alias Opsm.Types.{
    ServiceConfig,
    HttpConfig,
    PalimpsestRequest,
    PalimpsestResponse,
    LicenseCompatibility,
    LicenseConflict,
    DetectedLicense,
    OikosHealthResponse
  }

  defstruct [:client]

  @type t :: %__MODULE__{client: Req.Request.t()}

  def new(%ServiceConfig{} = config, %HttpConfig{} = http_config) do
    client = Http.build_client(http_config, base_url: config.base_url, token: config.token)
    %__MODULE__{client: client}
  end

  @doc """
  Analyze licenses for an artifact.
  """
  def analyze(%__MODULE__{client: client}, %PalimpsestRequest{} = request) do
    body = %{
      "artifactPath" => request.artifact_path,
      "includeTransitive" => request.include_transitive || false,
      "targetLicense" => request.target_license
    }

    case Http.post_json(client, "/licenses/analyze", body) do
      :ok ->
        encoded_path = URI.encode_www_form(request.artifact_path)
        case Http.get_json(client, "/licenses/analysis/#{encoded_path}") do
          {:ok, json} -> {:ok, decode_response(json)}
          {:error, reason} -> {:error, reason}
        end
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Check service health.
  """
  def health(%__MODULE__{client: client}) do
    case Http.get_json(client, "/health") do
      {:ok, json} ->
        {:ok, %OikosHealthResponse{
          status: decode_status(json["status"]),
          version: json["version"] || "unknown",
          uptime: json["uptime"] || 0
        }}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Fallback to CLI license-checker for basic license detection.
  """
  def cli_check_licenses(path) do
    case Opsm.SafeExec.cmd("license-checker", ["--json", "--start", path], stderr_to_stdout: true) do
      {output, 0} ->
        case Jason.decode(output) do
          {:ok, json} -> {:ok, json}
          {:error, _} -> {:ok, %{"raw" => output}}
        end
      {error, _code} ->
        {:error, "license-checker failed: #{error}"}
    end
  rescue
    e in ErlangError ->
      {:error, "license-checker not found: #{inspect(e)}"}
  end

  # Decoders

  defp decode_response(json) do
    %PalimpsestResponse{
      analyzed_at: json["analyzedAt"] || "",
      detected_licenses: decode_licenses(json["detectedLicenses"]),
      compatibility: decode_compatibility(json["compatibility"]),
      obligations: [],
      risks: []
    }
  end

  defp decode_licenses(nil), do: []
  defp decode_licenses(licenses) when is_list(licenses) do
    Enum.map(licenses, &decode_license/1)
  end
  defp decode_licenses(_), do: []

  defp decode_license(json) when is_map(json) do
    %DetectedLicense{
      spdx_id: json["spdxId"] || json["license"] || "UNKNOWN",
      confidence: json["confidence"] || 1.0,
      locations: json["locations"] || [],
      source: decode_license_source(json["source"])
    }
  end
  defp decode_license(_), do: nil

  defp decode_license_source("file_header"), do: :file_header
  defp decode_license_source("license_file"), do: :license_file
  defp decode_license_source("manifest"), do: :manifest
  defp decode_license_source("inferred"), do: :inferred
  defp decode_license_source(_), do: :inferred

  defp decode_compatibility(nil) do
    %LicenseCompatibility{compatible: true, target_license: nil, conflicts: []}
  end

  defp decode_compatibility(json) do
    %LicenseCompatibility{
      compatible: json["compatible"] || true,
      target_license: json["targetLicense"],
      conflicts: decode_conflicts(json["conflicts"])
    }
  end

  defp decode_conflicts(nil), do: []
  defp decode_conflicts(conflicts) when is_list(conflicts) do
    Enum.map(conflicts, &decode_conflict/1)
  end
  defp decode_conflicts(_), do: []

  defp decode_conflict(json) when is_map(json) do
    %LicenseConflict{
      license1: json["license1"] || "",
      license2: json["license2"] || "",
      reason: json["reason"] || "",
      severity: decode_conflict_severity(json["severity"])
    }
  end
  defp decode_conflict(_), do: nil

  defp decode_conflict_severity("error"), do: :error
  defp decode_conflict_severity("warning"), do: :warning
  defp decode_conflict_severity(_), do: :warning

  defp decode_status("healthy"), do: :healthy
  defp decode_status("degraded"), do: :degraded
  defp decode_status(_), do: :unhealthy
end
