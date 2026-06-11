# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Clients.ClaimForge do
  @moduledoc """
  Client for Claim-Forge attestation generation service.
  Includes CLI fallback for spdx-tool.
  """

  alias Opsm.Http
  alias Opsm.Types.{
    ServiceConfig,
    HttpConfig,
    ClaimForgeRequest,
    ClaimForgeResponse,
    OikosHealthResponse
  }

  defstruct [:client, :base_url]

  @type t :: %__MODULE__{client: Req.Request.t(), base_url: String.t()}

  def new(%ServiceConfig{} = config, %HttpConfig{} = http_config) do
    client = Http.build_client(http_config, base_url: config.base_url, token: config.token)
    %__MODULE__{client: client, base_url: config.base_url}
  end

  @doc """
  Generate an attestation for an artifact.
  """
  def generate_attestation(%__MODULE__{client: client}, %ClaimForgeRequest{} = request) do
    body = %{
      "artifactPath" => request.artifact_path,
      "artifactDigest" => request.artifact_digest,
      "claimType" => encode_claim_type(request.claim_type),
      "metadata" => request.metadata
    }

    case Http.post_json(client, "/attestations/generate", body) do
      :ok ->
        case Http.get_json(client, "/attestations/latest/#{request.artifact_digest}") do
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
  Fallback to CLI spdx-tool for SPDX attestation generation.
  """
  def cli_generate_spdx(artifact_path) do
    case Opsm.SafeExec.cmd("spdx-tool", ["generate", "--format", "json", artifact_path], stderr_to_stdout: true) do
      {output, 0} ->
        case Jason.decode(output) do
          {:ok, json} -> {:ok, json}
          {:error, _} -> {:ok, %{"raw" => output}}
        end
      {error, _code} ->
        {:error, "spdx-tool failed: #{error}"}
    end
  rescue
    e in ErlangError ->
      {:error, "spdx-tool not found: #{inspect(e)}"}
  end

  # Encoders

  defp encode_claim_type(:build_provenance), do: "BuildProvenance"
  defp encode_claim_type(:source_attestation), do: "SourceAttestation"
  defp encode_claim_type(:vulnerability_scan), do: "VulnerabilityScan"
  defp encode_claim_type(:license_compliance), do: "LicenseCompliance"
  defp encode_claim_type(:code_review), do: "CodeReview"

  # Decoders

  defp decode_response(json) do
    %ClaimForgeResponse{
      attestation_id: json["attestationId"] || "",
      claim_type: decode_claim_type(json["claimType"]),
      created_at: json["createdAt"] || "",
      expires_at: json["expiresAt"],
      attestation_uri: json["attestationUri"] || "",
      signature: json["signature"] || "",
      public_key_id: json["publicKeyId"] || ""
    }
  end

  defp decode_claim_type("BuildProvenance"), do: :build_provenance
  defp decode_claim_type("SourceAttestation"), do: :source_attestation
  defp decode_claim_type("VulnerabilityScan"), do: :vulnerability_scan
  defp decode_claim_type("LicenseCompliance"), do: :license_compliance
  defp decode_claim_type("CodeReview"), do: :code_review
  defp decode_claim_type(_), do: :build_provenance

  defp decode_status("healthy"), do: :healthy
  defp decode_status("degraded"), do: :degraded
  defp decode_status(_), do: :unhealthy
end
